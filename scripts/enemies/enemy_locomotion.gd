## Pure locomotion decisions for ground mobs: given the terrain, the mob's
## cell, and an intent direction, resolve walk / jump / chew / fall against
## capabilities. Free of node state so the never-cut stair-digging logic is
## unit-testable without physics frames (same decision/actuation split as
## FlowField). Owning doc: docs/systems/enemies.md
class_name EnemyLocomotion
extends RefCounted

enum Action { NONE, WALK, JUMP, CHEW, FALL, CLIMB }

## Drops deeper than this scan read as "unsafe" (bottomless as far as the
## mob knows).
const DROP_SCAN_MAX := 24


## Returns { action: Action, target: Vector2i, jump_tiles: int }. `target` is
## the cell moved into (WALK/FALL/JUMP landing) or chewed (CHEW); NONE keeps
## the mob still and tells the caller to try the direct-to-Core fallback.
## Resolution order (owning doc): walk -> jump -> chew; capabilities are
## speed, digging is correctness. CLIMB (3.5b) joins the two VERTICAL branches
## only, and it is the single site that reads `EnemyStats.is_biped`.
static func decide(terrain: Node, cell: Vector2i, dir: Vector2i, stats: EnemyStats) -> Dictionary:
	if dir.x != 0:
		var ahead := cell + Vector2i(dir.x, 0)
		if not terrain.is_solid(ahead):
			if drop_tiles(terrain, ahead) <= stats.max_safe_fall:
				return _make(Action.WALK, ahead)
			# Unsafe drop ahead: stair-dig — chew the block under own feet,
			# descend, re-measure next frame; the shaft down the cliff face
			# is emergent. (A diagonal stair is geometrically impossible: an
			# unsafe drop ahead means the down-and-forward cell is air.)
			var feet := cell + Vector2i.DOWN
			if terrain.is_solid(feet):
				return _make(Action.CHEW, feet)
			return _make(Action.WALK, ahead) # Nothing to chew: already airborne.
		var h := wall_height(terrain, cell, dir.x, stats.jump_height)
		if h <= stats.jump_height:
			return _make(Action.JUMP, Vector2i(cell.x + dir.x, cell.y - h), h)
		return _make(Action.CHEW, ahead)
	if dir == Vector2i.DOWN:
		var below := cell + Vector2i.DOWN
		if terrain.is_solid(below):
			return _make(Action.CHEW, below)
		if drop_tiles(terrain, cell) <= stats.max_safe_fall:
			return _make(Action.FALL, below)
		# A ladder makes the unsafe drop safe: ride it down rather than jumping.
		if stats.is_biped and Deployable.climbable_at(terrain, below):
			return _make(Action.CLIMB, below)
		# Below is air yet the drop is unsafe (straddling a neighbor column):
		# nothing diggable below — let the direct fallback pick a side.
		return _make(Action.NONE, cell)
	if dir == Vector2i.UP:
		var above := cell + Vector2i.UP
		if terrain.is_solid(above):
			return _make(Action.CHEW, above)
		# ❗️Before the NONE fall-through, and gated on the mob's ONE remaining
		# read of `is_biped`: the player's ladders are biped highways during a
		# wave, which is deliberate emergent texture rather than an oversight
		# ([enemies.md](../../docs/systems/enemies.md) §Climbables). Only the
		# DESTINATION has to be climbable, which is what lets a mob step up into
		# rung 0 from the ground beside it — the field's edge asks the same.
		if stats.is_biped and Deployable.climbable_at(terrain, above):
			return _make(Action.CLIMB, above)
		# Air above: the field routed a wall-climb the walker can't do
		# (climb_speed 0) — the caller's direct fallback absorbs it.
		return _make(Action.NONE, cell)
	return _make(Action.NONE, cell)


## Air cells strictly below `cell` before the first solid; max_scan + 1 when
## no floor is found within the scan (reads as unsafe).
static func drop_tiles(terrain: Node, cell: Vector2i, max_scan := DROP_SCAN_MAX) -> int:
	for d in range(1, max_scan + 1):
		if terrain.is_solid(cell + Vector2i(0, d)):
			return d - 1
	return max_scan + 1


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
