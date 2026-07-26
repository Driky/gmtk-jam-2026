## 10 Hz tick: conveyors, inserters, machines, power. Also the deployable
## support re-check, which is where a mined tile turns into a popped machine.
## Owning doc: docs/systems/automation.md
extends Node

## Injected by tests; falls back to the autoload.
var terrain: Node = null

## Cells to re-check. Kept as an array plus a membership dict rather than a set,
## because the drain order does not matter but the dedupe does: 50 tile changes
## in one frame must not queue the same torch 50 times.
var _queue: Array[Vector2i] = []
var _queued: Dictionary[Vector2i, bool] = { }


func _ready() -> void:
	if terrain == null:
		terrain = Terrain
	# Both signals, following the Waves precedent (waves.gd): a deployable can
	# lose its support because the tile under it was mined OR because a
	# neighbouring entity went away.
	terrain.tile_changed.connect(_on_cell_changed)
	terrain.entity_changed.connect(_on_cell_changed)


func _process(_delta: float) -> void:
	drain_support_queue()


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
func reset_run() -> void:
	_queue.clear()
	_queued.clear()


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
