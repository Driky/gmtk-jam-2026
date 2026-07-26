## 10 Hz tick: conveyors, inserters, machines, power. Also the deployable
## support re-check, which is where a mined tile turns into a popped machine.
## Owning doc: docs/systems/automation.md
extends Node

const GameScript := preload("res://scripts/game/game.gd")

const TICK_HZ := 10
const TICK_INTERVAL := 1.0 / TICK_HZ
## Frames longer than a tick are caught up, but only this many at once.
##
## ❗️Not optional, and not a tuning knob. Chrome throttles a backgrounded tab
## hard, so the first `delta` after a tab-out comes back as one enormous value —
## without this clamp a 30-second tab-out runs 300 ticks inside a single frame
## and hangs the page. With it the factory loses that time instead, which is the
## correct trade: nobody is watching a belt they cannot see. Do not "fix" it.
const MAX_CATCH_UP := 3

## Injected by tests; fall back to the autoloads (both load before us).
var terrain: Node = null
var game: Node = null

## Ticks run this run. Public: the debug overlay reads it, and a test asserting
## "N ticks happened" needs it more than any internal does.
var tick_count := 0

## Cells to re-check. Kept as an array plus a membership dict rather than a set,
## because the drain order does not matter but the dedupe does: 50 tile changes
## in one frame must not queue the same torch 50 times.
var _queue: Array[Vector2i] = []
var _queued: Dictionary[Vector2i, bool] = { }

## The three tick phases, in the locked order. Every entry is a Deployable that
## joined through `on_placed()` and leaves through `on_removed()`, so a popped
## machine is never ticked after it stops existing.
var _machines: Array[Deployable] = []
var _inserters: Array[Deployable] = []
var _conveyors: Array[Deployable] = []
## A placement or removal invalidates the row-major order; the sort is deferred
## to the next tick so twenty placements in one frame cost one sort.
var _order_dirty := false

var _tick_accum := 0.0


func _ready() -> void:
	if terrain == null:
		terrain = Terrain
	if game == null:
		game = Game
	# Both signals, following the Waves precedent (waves.gd): a deployable can
	# lose its support because the tile under it was mined OR because a
	# neighbouring entity went away.
	terrain.tile_changed.connect(_on_cell_changed)
	terrain.entity_changed.connect(_on_cell_changed)


func _process(delta: float) -> void:
	drain_support_queue()
	advance(delta)


## Feed the tick accumulator one frame's worth of time. Public for the same
## reason `drain_support_queue()` is: a test drives the clock itself rather than
## waiting on real frames, and the catch-up clamp is only observable from here.
func advance(delta: float) -> void:
	# House idiom for phase gating: an early return on the Game state rather
	# than set_process, so there is one place to read and nothing to re-enable.
	# ❗️WAVE_PHASE is in the list on purpose — the factory running *during* the
	# fight is the fantasy (plan.md), so this gate is what would break it.
	if game.state != GameScript.State.BUILD_PHASE and game.state != GameScript.State.WAVE_PHASE:
		return
	_tick_accum += delta
	var steps := 0
	# ❗️Subtracts the interval, never resets to zero: terrain.gd's `_sweep_accum`
	# takes the other shape (reset + at most one iteration per frame) and both
	# drifts and silently drops ticks on a long frame. A conveyor line that loses
	# ticks under load is a factory that quietly runs slow.
	while _tick_accum >= TICK_INTERVAL and steps < MAX_CATCH_UP:
		_tick_accum -= TICK_INTERVAL
		steps += 1
		step_tick()
	if _tick_accum >= TICK_INTERVAL:
		_tick_accum = fmod(_tick_accum, TICK_INTERVAL) # Drop the backlog.


## One 10 Hz step of the whole logistics sim, in the LOCKED phase order
## `machines → inserters → conveyors` — a crafted item can leave the same tick,
## and the inserter's give-back-on-refusal is only safe because conveyors have
## not advanced yet ([automation.md](../../docs/systems/automation.md)).
##
## Public so tests can drive it without waiting a frame, mirroring
## `drain_support_queue()`.
func step_tick() -> void:
	Perf.begin(&"automation.tick")
	tick_count += 1
	_ensure_order()
	for machine: Deployable in _machines:
		machine.on_tick(terrain)
	for inserter: Deployable in _inserters:
		inserter.on_tick(terrain)
	_advance_conveyors()
	Perf.end()


## How far into the current tick interval we are, 0→1. The item renderer's only
## input: it interpolates each slot between its previous and current cell, so it
## reads the sim directly and cannot desync from it.
func tick_alpha() -> float:
	return clampf(_tick_accum / TICK_INTERVAL, 0.0, 1.0)

# --- Registration ------------------------------------------------------------

## Joined and left through the `Deployable.on_placed()` / `on_removed()`
## virtuals, so nothing in the player or the placement path knows these lists
## exist.


func register_machine(machine: Deployable) -> void:
	_register(_machines, machine)


func unregister_machine(machine: Deployable) -> void:
	_machines.erase(machine)


func register_inserter(inserter: Deployable) -> void:
	_register(_inserters, inserter)


func unregister_inserter(inserter: Deployable) -> void:
	_inserters.erase(inserter)


func register_conveyor(conveyor: Deployable) -> void:
	_register(_conveyors, conveyor)


func unregister_conveyor(conveyor: Deployable) -> void:
	_conveyors.erase(conveyor)


## Read-only views for the item renderer and the debug slot overlay. Handed out
## rather than copied: both are per-frame readers of a list of a few hundred.
func conveyors() -> Array[Deployable]:
	return _conveyors


func inserters() -> Array[Deployable]:
	return _inserters


## Cheap "is anything on a belt" probe, so the item layer can skip a redraw on an
## idle factory. Early-outs on the first occupied slot, so the full scan only
## happens in the case whose answer is "nothing to draw".
func has_items_in_transit() -> bool:
	for node: Deployable in _conveyors:
		if not (node as Conveyor).slot_empty():
			return true
	return false


## Enqueue a cell for a support re-check. Idempotent within a drain window.
func queue_support_check(cell: Vector2i) -> void:
	if _queued.has(cell):
		return
	_queued[cell] = true
	_queue.append(cell)


## Pop everything that lost its footing.
##
## ❗️This is a WORK QUEUE, not a debounce timer. A support check is four
## `is_solid` calls, not a 57 ms field solve, so there is nothing to amortize —
## what needs taming is **re-entrancy**. `pop_to_pickup` calls `remove_entity`
## per cell, which emits `entity_changed`, which lands right back in the handler
## below. So the handler only ever *enqueues*, and pops that happen mid-drain
## append to the very array being drained — that append *is* the cascade.
## Recursion would blow the stack on a long chain and is never used.
##
## Termination is provable: every step either does nothing or permanently
## removes one deployable, and only a removal can enqueue more. The assert is a
## debug-only backstop against a future predicate that breaks that argument.
##
## Public so tests can drive it without waiting a frame.
func drain_support_queue() -> void:
	var guard := 0
	while not _queue.is_empty():
		guard += 1
		assert(guard < Deployable.MAX_DRAIN_STEPS)
		var cell: Vector2i = _queue.pop_back()
		_queued.erase(cell)
		var deployable := terrain.get_entity(cell) as Deployable
		if deployable == null or deployable.is_supported(terrain):
			continue
		deployable.pop_to_pickup()


func pending_checks() -> int:
	return _queue.size()


## Wipe all run state ahead of a scene reload (restart flow, 2.1). Every autoload
## holding run state exposes reset_run() — tech-design.md. A cell surviving a
## restart would re-check something else entirely in the new world.
##
## ❗️The registries have to be cleared here, not left to `on_removed()`.
## Deployables are children of Main and die with the scene reload without ever
## being popped, so a surviving array would hold freed references and the first
## tick of the new run would fault on them.
func reset_run() -> void:
	_queue.clear()
	_queued.clear()
	_machines.clear()
	_inserters.clear()
	_conveyors.clear()
	_order_dirty = false
	tick_count = 0
	_tick_accum = 0.0


## A deployable is only affected by a tile it TOUCHES, and it is registered per
## occupied cell — so five `get_entity` probes cover every candidate, O(1) per
## mined tile. `get_entity_cells()` is deliberately never called here, and world
## gen costs nothing at all because `set_cell_raw` emits no signal.
func _on_cell_changed(pos: Vector2i) -> void:
	_probe(pos)
	for offset: Vector2i in Deployable.SUPPORT_OFFSETS:
		_probe(pos + offset)


func _probe(cell: Vector2i) -> void:
	if terrain.get_entity(cell) is Deployable:
		queue_support_check(cell)

# --- Tick internals ----------------------------------------------------------


## The conveyor phase. The two-phase mark-then-commit pass itself belongs to the
## Conveyor — it is a property of the group, not of the tick driver.
func _advance_conveyors() -> void:
	Conveyor.advance_all(terrain, _conveyors)


func _register(registry: Array[Deployable], node: Deployable) -> void:
	if registry.has(node):
		return
	registry.append(node)
	_order_dirty = true


## ❗️Iteration order is ROW-MAJOR BY CELL (y, then x), not insertion order, and
## that is what makes the tick deterministic at all. Conveyor advance is
## order-independent by construction, but two inserters pulling from the same
## conveyor slot are not, and neither is the tie-break when two conveyors face
## the same cell.
##
## Insertion order is reproducible within a session but NOT across 4.3's
## save/load, which restores entities in file order and would silently change
## tick behaviour. Row-major is derived from the world itself, so any restore
## order ticks identically — and it makes the debug overlay read in sim order.
##
## Cost: one sort of a few hundred elements after a placement, at human
## placement rates.
func _ensure_order() -> void:
	if not _order_dirty:
		return
	_order_dirty = false
	_machines.sort_custom(_row_major)
	_inserters.sort_custom(_row_major)
	_conveyors.sort_custom(_row_major)


static func _row_major(a: Deployable, b: Deployable) -> bool:
	var ca := a.cell()
	var cb := b.cell()
	if ca.y != cb.y:
		return ca.y < cb.y
	return ca.x < cb.x
