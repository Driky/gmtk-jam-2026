## 10 Hz tick: conveyors, inserters, machines, power. Also the deployable
## support re-check, which is where a mined tile turns into a popped machine.
## Owning doc: docs/systems/automation.md
extends Node

## How many registered machines have nothing to do (a miner whose deposit ran
## out, today). Emitted **only on change** rather than every tick, and read by
## the HUD's idle counter ([ui.md](../../docs/systems/ui.md) §HUD).
signal idle_machines_changed(count: int)

const GameScript := preload("res://scripts/game/game.gd")

const TILE := TileLayout.TILE_SIZE

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

## The fourth registry (3.4): generators and relays, the only things that emit a
## coverage disc. Kept apart from `_machines` because it is walked for a
## different reason — supply, not work.
var _emitters: Array[PowerEmitter] = []
## Same deferral as `_order_dirty`, for the same reason: the graph is rebuilt on
## place/remove only, never per tick
## ([automation.md](../../docs/systems/automation.md) §Power).
var _power_dirty := false
var _grid: PowerGrid = null
## Component per machine, parallel to `_machines`, filled by the demand pass and
## read by the stamping pass — so the disc walk happens once per machine per
## tick rather than twice.
var _machine_grids: PackedInt32Array = PackedInt32Array()
## Last count emitted, so `idle_machines_changed` fires on a transition rather
## than 10×/second.
var _idle_machines := 0

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
## Power resolves BEFORE all three (3.4): a machine's tick asks what its ratio
## is, so the answer has to already be stamped on it.
##
## Public so tests can drive it without waiting a frame, mirroring
## `drain_support_queue()`.
func step_tick() -> void:
	Perf.begin(&"automation.tick")
	tick_count += 1
	_ensure_order()
	_refresh_power()
	# freed-safe: the tick registries are pruned EAGERLY — `pop_to_pickup` calls
	# `on_removed()` -> `unregister_*` before `queue_free()`, so a corpse never survives
	# a frame in one. `test_*` asserts it: "Must not touch the freed node".
	for machine: Deployable in _machines:
		machine.on_tick(terrain)
	# freed-safe: the tick registries are pruned EAGERLY — `pop_to_pickup` calls
	# `on_removed()` -> `unregister_*` before `queue_free()`, so a corpse never survives
	# a frame in one. `test_*` asserts it: "Must not touch the freed node".
	for inserter: Deployable in _inserters:
		inserter.on_tick(terrain)
	_advance_conveyors()
	_refresh_idle_count()
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


## ❗️Marks the graph dirty rather than rebuilding: twenty relays placed in one
## frame cost one rebuild, exactly as twenty placements cost one sort.
func register_emitter(emitter: PowerEmitter) -> void:
	if _emitters.has(emitter):
		return
	_emitters.append(emitter)
	_power_dirty = true


func unregister_emitter(emitter: PowerEmitter) -> void:
	_emitters.erase(emitter)
	_power_dirty = true


## Read-only views for the item renderer and the debug slot overlay. Handed out
## rather than copied: both are per-frame readers of a list of a few hundred.
func conveyors() -> Array[Deployable]:
	return _conveyors


func inserters() -> Array[Deployable]:
	return _inserters


func machines() -> Array[Deployable]:
	return _machines


func emitters() -> Array[PowerEmitter]:
	return _emitters


## The live graph, for the power overlay. Never null once a tick has run; null
## before the first one, which is exactly when there is nothing to draw.
func power_grid() -> PowerGrid:
	return _grid


func idle_machines() -> int:
	return _idle_machines


## Cheap "is anything on a belt" probe, so the item layer can skip a redraw on an
## idle factory. Early-outs on the first occupied slot, so the full scan only
## happens in the case whose answer is "nothing to draw".
func has_items_in_transit() -> bool:
	# freed-safe: the tick registries are pruned EAGERLY — `pop_to_pickup` calls
	# `on_removed()` -> `unregister_*` before `queue_free()`, so a corpse never survives
	# a frame in one. `test_*` asserts it: "Must not touch the freed node".
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
	# Same argument as the other three, plus one more: the grid is DERIVED from
	# these nodes' positions, so a surviving graph would hand out coverage from
	# generators that no longer exist.
	_emitters.clear()
	_grid = null
	_power_dirty = false
	_order_dirty = false
	_idle_machines = 0
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

# --- Power (3.4) --------------------------------------------------------------


## The power pass, at the TOP of the tick: rebuild the graph if it moved, burn
## fuel, then supply → demand → ratio.
##
## ❗️**Two machine passes, and they cannot be folded into one.** A grid's ratio
## is `supply / total demand`, so no machine's ratio exists until every machine
## on that grid has declared what it draws. Stamping as we go would give the
## first machine walked a ratio computed from a partial denominator — the whole
## factory would then run at a rate that depends on row-major order.
##
## Its own `Perf` section inside `automation.tick`: the disc walk is the one part
## of the tick whose cost scales with emitters × machines rather than with either.
func _refresh_power() -> void:
	Perf.begin(&"automation.power")
	if _grid == null or _power_dirty:
		_rebuild_power_grid()
	# Before supply is read, so a generator running dry stops powering on this
	# tick rather than one tick late.
	# freed-safe: the tick registries are pruned EAGERLY — `pop_to_pickup` calls
	# `on_removed()` -> `unregister_*` before `queue_free()`, so a corpse never survives
	# a frame in one. `test_*` asserts it: "Must not touch the freed node".
	for emitter: PowerEmitter in _emitters:
		emitter.burn_tick()
	_grid.begin_tick()
	for i in _emitters.size():
		_grid.add_supply(_grid.component_of(i), _emitters[i].power_supply())
	_machine_grids.resize(_machines.size())
	for i in _machines.size():
		var machine := _machines[i]
		# A machine that draws nothing is skipped in BOTH passes, so its ratio
		# stays at the base's 1.0 and no overlay reports a free machine as
		# browned out.
		if machine.power_demand <= 0.0:
			_machine_grids[i] = PowerGrid.NO_GRID
			continue
		var component := _grid_of_machine(machine)
		_machine_grids[i] = component
		_grid.add_demand(component, machine.power_demand)
	_grid.resolve()
	for i in _machines.size():
		if _machines[i].power_demand <= 0.0:
			continue
		_machines[i].set_power_ratio(_grid.ratio_of(_machine_grids[i]))
	Perf.end()


## ❗️Sorted row-major first, so component NUMBERING is derived from the world
## rather than from placement order — the same argument `_ensure_order` makes for
## the tick. It changes no ratio, but the overlay colours a grid by its index,
## and a save/load that restored emitters in file order would otherwise repaint
## the whole factory for no reason ([save.md](../../docs/systems/save.md)).
func _rebuild_power_grid() -> void:
	_power_dirty = false
	_emitters.sort_custom(_row_major)
	var centres := PackedVector2Array()
	var radii := PackedFloat32Array()
	centres.resize(_emitters.size())
	radii.resize(_emitters.size())
	for i in _emitters.size():
		# The node's own anchor, which `setup()` puts at the footprint centre —
		# the same point the overlay draws the circle around.
		centres[i] = _emitters[i].global_position
		radii[i] = _emitters[i].power_radius * TILE
	if _grid == null:
		_grid = PowerGrid.new()
	_grid.build(centres, radii)


## ❗️**ANY footprint cell inside a disc powers the whole machine.** A 3×2 miner
## with one corner in the circle is fair — the alternative (its centre only) puts
## a machine's power on a point the player cannot see, and a big machine that is
## visibly half-covered but dead reads as a bug.
func _grid_of_machine(machine: Deployable) -> int:
	for cell: Vector2i in machine.footprint():
		var component := _grid.grid_of_point((Vector2(cell) + Vector2(0.5, 0.5)) * TILE)
		if component != PowerGrid.NO_GRID:
			return component
	return PowerGrid.NO_GRID


## Tally machines with nothing to do, at the tail of the tick. Free in practice:
## it walks a list the tick has just walked anyway, and `is_idle()` is a flag the
## machine recomputed a few microseconds ago rather than a fresh terrain probe.
##
## ❗️**Emitters are tallied too**, though they are not machines: a generator with
## no fuel is the same "come and feed me" signal as a miner over bare rock, and
## it is the one that stops the whole factory rather than one machine.
##
## Emitted only on CHANGE, so the HUD repaints on a transition instead of ten
## times a second.
func _refresh_idle_count() -> void:
	var idle := 0
	# freed-safe: the tick registries are pruned EAGERLY — `pop_to_pickup` calls
	# `on_removed()` -> `unregister_*` before `queue_free()`, so a corpse never survives
	# a frame in one. `test_*` asserts it: "Must not touch the freed node".
	for machine: Deployable in _machines:
		if machine.is_idle():
			idle += 1
	# freed-safe: the tick registries are pruned EAGERLY — `pop_to_pickup` calls
	# `on_removed()` -> `unregister_*` before `queue_free()`, so a corpse never survives
	# a frame in one. `test_*` asserts it: "Must not touch the freed node".
	for emitter: PowerEmitter in _emitters:
		if emitter.is_idle():
			idle += 1
	if idle == _idle_machines:
		return
	_idle_machines = idle
	idle_machines_changed.emit(idle)


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
