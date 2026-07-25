## Unit tests for EnemyLocomotion (roadmap 2.3) on a synthetic terrain —
## never touches the live autoloads.
extends GdUnitTestSuite

## Minimal stand-in for the Terrain autoload: the reads EnemyLocomotion uses.
class TerrainDouble:
	extends Node

	var solids: Dictionary[Vector2i, bool] = { }


	func is_solid(pos: Vector2i) -> bool:
		return solids.get(pos, false)


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


func test_down_over_air_falls() -> void:
	var d := _decide(Vector2i(5, 9), Vector2i.DOWN)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.FALL)


func test_zero_dir_is_none() -> void:
	_lay_floor(0, 10)
	var d := _decide(Vector2i(5, 9), Vector2i.ZERO)
	assert_int(d.action).is_equal(EnemyLocomotion.Action.NONE)
