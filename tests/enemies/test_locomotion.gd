## Unit tests for EnemyLocomotion (roadmap 2.3) on a synthetic terrain —
## never touches the live autoloads.
extends GdUnitTestSuite

## Minimal stand-in for the Terrain autoload: the reads EnemyLocomotion uses.
## `get_entity` joined at 3.5b — `Deployable.climbable_at` asks the entity dict,
## so a double with only `is_solid` can no longer drive `decide`.
class TerrainDouble:
	extends Node

	var solids: Dictionary[Vector2i, bool] = { }
	var entities: Dictionary[Vector2i, Node] = { }


	func is_solid(pos: Vector2i) -> bool:
		return solids.get(pos, false)


	func get_entity(pos: Vector2i) -> Node:
		return entities.get(pos)


	func set_solid(pos: Vector2i) -> void:
		solids[pos] = true


var _terrain: TerrainDouble
var _stats: EnemyStats


func before_test() -> void:
	_terrain = auto_free(TerrainDouble.new())
	_stats = EnemyStats.new()


## Flat floor at y = 10, mob standing on it at (5, 9).
func _lay_floor(from_x: int, to_x: int, y := 10) -> void:
	for x in range(from_x, to_x + 1):
		_terrain.set_solid(Vector2i(x, y))


func _decide(cell: Vector2i, dir: Vector2i) -> Dictionary:
	return EnemyLocomotion.decide(_terrain, cell, dir, _stats)


## A registered climbable in `cell`. A bare `Deployable` rather than the ladder
## scene: `climbable_at` reads the export, and the rule under test is the export's.
func _rung(cell: Vector2i) -> void:
	var node: Deployable = auto_free(Deployable.new())
	node.is_climbable = true
	node.setup(cell)
	_terrain.entities[cell] = node

# --- Walk / fall basics ------------------------------------------------------


func test_flat_ground_walks_ahead() -> void:
	_lay_floor(0, 10)
	var d := _decide(Vector2i(5, 9), Vector2i.RIGHT)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.WALK)
	assert_that(d.target).is_equal(Vector2i(6, 9))


func test_walks_left_too() -> void:
	_lay_floor(0, 10)
	var d := _decide(Vector2i(5, 9), Vector2i.LEFT)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.WALK)
	assert_that(d.target).is_equal(Vector2i(4, 9))


func test_down_over_safe_air_falls() -> void:
	_terrain.set_solid(Vector2i(5, 12)) # Floor 2 below: a safe drop.
	var d := _decide(Vector2i(5, 9), Vector2i.DOWN)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.FALL)


func test_zero_dir_is_none() -> void:
	_lay_floor(0, 10)
	var d := _decide(Vector2i(5, 9), Vector2i.ZERO)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.NONE)

# --- Jump / chew resolution --------------------------------------------------


func test_one_high_step_jumps() -> void:
	_lay_floor(0, 10)
	_terrain.set_solid(Vector2i(6, 9)) # 1-high step ahead.
	var d := _decide(Vector2i(5, 9), Vector2i.RIGHT)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.JUMP)
	assert_that(d.target).is_equal(Vector2i(6, 8))
	assert_int(d.jump_tiles).is_equal(1)


func test_two_high_wall_chews_the_blocker() -> void:
	_lay_floor(0, 10)
	_terrain.set_solid(Vector2i(6, 9))
	_terrain.set_solid(Vector2i(6, 8))
	var d := _decide(Vector2i(5, 9), Vector2i.RIGHT)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.CHEW)
	assert_that(d.target).is_equal(Vector2i(6, 9))


func test_step_without_headroom_chews() -> void:
	_lay_floor(0, 10)
	_terrain.set_solid(Vector2i(6, 9)) # Jumpable step...
	_terrain.set_solid(Vector2i(5, 8)) # ...under a ceiling over the mob.
	var d := _decide(Vector2i(5, 9), Vector2i.RIGHT)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.CHEW)
	assert_that(d.target).is_equal(Vector2i(6, 9))


func test_taller_jumper_clears_two_high_wall() -> void:
	_lay_floor(0, 10)
	_terrain.set_solid(Vector2i(6, 9))
	_terrain.set_solid(Vector2i(6, 8))
	_stats.jump_height = 2
	var d := _decide(Vector2i(5, 9), Vector2i.RIGHT)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.JUMP)
	assert_that(d.target).is_equal(Vector2i(6, 7))
	assert_int(d.jump_tiles).is_equal(2)


func test_down_over_solid_chews_below() -> void:
	_lay_floor(0, 10)
	var d := _decide(Vector2i(5, 9), Vector2i.DOWN)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.CHEW)
	assert_that(d.target).is_equal(Vector2i(5, 10))


func test_up_through_solid_chews_above() -> void:
	_terrain.set_solid(Vector2i(5, 8))
	var d := _decide(Vector2i(5, 9), Vector2i.UP)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.CHEW)
	assert_that(d.target).is_equal(Vector2i(5, 8))


func test_up_through_air_is_none() -> void:
	# The field routed a wall-climb this mob can't do — caller falls back.
	var d := _decide(Vector2i(5, 9), Vector2i.UP)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.NONE)

# --- Climbables (3.5b) -------------------------------------------------------


## The feature: a biped routed up into a ladder rung climbs it instead of
## falling through to NONE. Only the DESTINATION is climbable here — the mob is
## standing on the ground beside the column, which is how it gets on.
func test_up_into_a_rung_climbs_it() -> void:
	_lay_floor(0, 10)
	_rung(Vector2i(5, 8))
	var d := _decide(Vector2i(5, 9), Vector2i.UP)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.CLIMB)
	assert_that(d.target).is_equal(Vector2i(5, 8))


## Down a column too deep to jump: ride it rather than taking the drop. A SAFE
## drop still just falls — the climb is the answer to an unsafe one.
func test_down_a_rung_over_an_unsafe_drop_climbs() -> void:
	_rung(Vector2i(5, 10))
	var d := _decide(Vector2i(5, 9), Vector2i.DOWN)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.CLIMB)
	assert_that(d.target).is_equal(Vector2i(5, 10))


func test_a_safe_drop_beside_a_rung_still_just_falls() -> void:
	_terrain.set_solid(Vector2i(5, 12)) # Floor 2 below: a safe drop.
	_rung(Vector2i(5, 10))
	assert_int(_decide(Vector2i(5, 9), Vector2i.DOWN).action).is_equal(
		EnemyLocomotion.Action.FALL,
	)


## ❗️`is_biped` gates ASCENDING and nothing else. A crawler facing a ladder
## returns neither CLIMB nor CHEW — nothing chews a climbable (the skip lives in
## `Enemy._attackable_entity`) — so it falls through to NONE and the caller's
## direct fallback picks another way round. That over-connectivity is the
## documented accepted error, backed by the stuck watchdog.
func test_a_non_biped_neither_climbs_a_rung_nor_chews_it() -> void:
	_lay_floor(0, 10)
	_rung(Vector2i(5, 8))
	_stats.is_biped = false
	var d := _decide(Vector2i(5, 9), Vector2i.UP)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.NONE)


## A solid above still wins: a rung does not make rock passable, and the mob
## chews through the ceiling exactly as it did at 2.3.
func test_solid_above_still_chews_even_with_a_rung_beyond_it() -> void:
	_terrain.set_solid(Vector2i(5, 8))
	_rung(Vector2i(5, 8))
	var d := _decide(Vector2i(5, 9), Vector2i.UP)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.CHEW)

# --- Stair-digging (2.3, never-cut) ------------------------------------------


func test_drop_tiles_counts_air_below() -> void:
	_terrain.set_solid(Vector2i(5, 14))
	assert_int(EnemyLocomotion.drop_tiles(_terrain, Vector2i(5, 9))).is_equal(4)


func test_drop_tiles_scan_cap_reads_unsafe() -> void:
	var depth := EnemyLocomotion.drop_tiles(_terrain, Vector2i(5, 9), 8)
	assert_int(depth).is_equal(9)


func test_safe_drop_walks_off() -> void:
	# Floor at y = 10 up to x = 5; landing 3 below ahead.
	_lay_floor(0, 5)
	_lay_floor(6, 12, 13)
	var d := _decide(Vector2i(5, 9), Vector2i.RIGHT)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.WALK)


func test_unsafe_drop_at_lip_digs_own_feet() -> void:
	# Sheer cliff: columns >= 6 are air down to y = 18.
	_lay_floor(0, 5)
	_lay_floor(6, 12, 18)
	var d := _decide(Vector2i(5, 9), Vector2i.RIGHT)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.CHEW)
	assert_that(d.target).is_equal(Vector2i(5, 10))


func test_down_over_unsafe_air_is_none() -> void:
	# Straddling: below is air, drop is deep, nothing diggable below.
	var d := _decide(Vector2i(5, 9), Vector2i.DOWN)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.NONE)


## Simulate the emergent stair-dig loop against a sheer 8-deep cliff: apply
## each chew to the terrain, let the mob descend, re-decide — it must reach a
## safe remaining drop in bounded steps, never soft-locking.
func test_stair_sequence_terminates_at_safe_drop() -> void:
	_lay_floor(0, 5) # High ground at y = 10.
	_lay_floor(6, 12, 18) # Valley floor 8 below.
	# Solid fill between the two levels under the high ground, like real
	# world gen (the mob digs through this).
	for y in range(11, 18):
		for x in range(0, 6):
			_terrain.set_solid(Vector2i(x, y))
	var cell := Vector2i(5, 9)
	for step in 32:
		var d := _decide(cell, Vector2i.RIGHT)
		match d.action:
			EnemyLocomotion.Action.CHEW:
				_terrain.solids.erase(d.target)
				# Descend once the chew opened the floor under the mob.
				if not _terrain.is_solid(cell + Vector2i.DOWN):
					cell += Vector2i.DOWN
			EnemyLocomotion.Action.WALK:
				var ahead: Vector2i = d.target
				assert_int(EnemyLocomotion.drop_tiles(_terrain, ahead)).is_less_equal(3)
				return # Reached a safe walk-off — loop terminated correctly.
			_:
				fail("unexpected action %d at %s" % [d.action, cell])
				return
	fail("stair-dig never reached a safe drop")
