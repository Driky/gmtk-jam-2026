## Pure locomotion decisions for ground mobs: given the terrain, the mob's
## cell, and an intent direction, resolve walk / jump / chew / fall against
## capabilities. Free of node state so the never-cut stair-digging logic is
## unit-testable without physics frames (same decision/actuation split as
## FlowField). Owning doc: docs/systems/enemies.md
class_name EnemyLocomotion
extends RefCounted

enum Action { NONE, WALK, JUMP, CHEW, FALL }


## Returns { action: Action, target: Vector2i, jump_tiles: int }. `target` is
## the cell moved into (WALK/FALL/JUMP landing) or chewed (CHEW); NONE keeps
## the mob still and tells the caller to try the direct-to-Core fallback.
## Resolution order (owning doc): walk -> jump -> chew; capabilities are
## speed, digging is correctness.
static func decide(terrain: Node, cell: Vector2i, dir: Vector2i, stats: EnemyStats) -> Dictionary:
	if dir.x != 0:
		var ahead := cell + Vector2i(dir.x, 0)
		if not terrain.is_solid(ahead):
			return _make(Action.WALK, ahead)
		var h := wall_height(terrain, cell, dir.x, stats.jump_height)
		if h <= stats.jump_height:
			return _make(Action.JUMP, Vector2i(cell.x + dir.x, cell.y - h), h)
		return _make(Action.CHEW, ahead)
	if dir == Vector2i.DOWN:
		var below := cell + Vector2i.DOWN
		if not terrain.is_solid(below):
			return _make(Action.FALL, below)
		return _make(Action.CHEW, below)
	if dir == Vector2i.UP:
		var above := cell + Vector2i.UP
		if terrain.is_solid(above):
			return _make(Action.CHEW, above)
		# Air above: the field routed a wall-climb the walker can't do
		# (climb_speed 0) — the caller's direct fallback absorbs it.
		return _make(Action.NONE, cell)
	return _make(Action.NONE, cell)


## Height of the solid stack ahead of `cell` toward dir_x, counting up from
## the feet row; max_h + 1 when taller than max_h or when the mob lacks the
## headroom in its own column to rise alongside it.
static func wall_height(terrain: Node, cell: Vector2i, dir_x: int, max_h: int) -> int:
	for h in range(1, max_h + 1):
		if terrain.is_solid(Vector2i(cell.x, cell.y - h)):
			return max_h + 1
		if not terrain.is_solid(Vector2i(cell.x + dir_x, cell.y - h)):
			return h
	return max_h + 1


static func _make(action: Action, target: Vector2i, jump_tiles := 0) -> Dictionary:
	return { "action": action, "target": target, "jump_tiles": jump_tiles }
