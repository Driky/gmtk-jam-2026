## Pure locomotion decisions for ground mobs: given the terrain, the mob's
## cell, and an intent direction, resolve walk / jump / chew / fall against
## capabilities. Free of node state so the never-cut stair-digging logic is
## unit-testable without physics frames (same decision/actuation split as
## FlowField). Owning doc: docs/systems/enemies.md
class_name EnemyLocomotion
extends RefCounted

enum Action { NONE, WALK, JUMP, CHEW, FALL }


## Returns { action: Action, target: Vector2i, jump_tiles: int }. `target` is
## the cell moved into (WALK/FALL) or chewed (CHEW); NONE keeps the mob still
## and tells the caller to try the direct-to-Core fallback.
static func decide(terrain: Node, cell: Vector2i, dir: Vector2i, _stats: EnemyStats) -> Dictionary:
	if dir.x != 0:
		var ahead := cell + Vector2i(dir.x, 0)
		if not terrain.is_solid(ahead):
			return _make(Action.WALK, ahead)
		return _make(Action.NONE, cell) # Jump/chew resolution lands next chunk.
	if dir == Vector2i.DOWN:
		if not terrain.is_solid(cell + Vector2i.DOWN):
			return _make(Action.FALL, cell + Vector2i.DOWN)
		return _make(Action.NONE, cell)
	return _make(Action.NONE, cell)


static func _make(action: Action, target: Vector2i, jump_tiles := 0) -> Dictionary:
	return { "action": action, "target": target, "jump_tiles": jump_tiles }
