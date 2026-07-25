## Unit tests for FlowField (roadmap 2.2) on a small synthetic terrain —
## never touches the live autoloads.
extends GdUnitTestSuite

const W := 20
const ROWS := 15
const FLOOR_Y := 10


## Minimal stand-in for the Terrain autoload: the three reads FlowField uses.
class TerrainDouble:
	extends Node

	var tiles: Dictionary[Vector2i, String] = { }
	var entities: Dictionary[Vector2i, Node] = { }


	func get_cell_source_id(pos: Vector2i) -> int:
		return Materials.ORDER.find(tiles.get(pos, ""))


	func get_entity(pos: Vector2i) -> Node:
		return entities.get(pos)


	func get_entity_cells() -> Array[Vector2i]:
		var cells: Array[Vector2i] = []
		for pos: Vector2i in entities:
			cells.append(pos)
		return cells


## A deployable stand-in: FlowField duck-types on a current_hp property.
class EntityDouble:
	extends Node2D

	var current_hp := 100.0


var _terrain: TerrainDouble
var _field: FlowField


func before_test() -> void:
	_terrain = auto_free(TerrainDouble.new())
	_field = FlowField.new()
	_field.terrain = _terrain
	_field.region_width = W
	_field.region_rows = ROWS


## Flat dirt floor at FLOOR_Y across the whole width.
func _lay_floor(material_id := "dirt") -> void:
	for x in W:
		_terrain.tiles[Vector2i(x, FLOOR_Y)] = material_id


func _goal() -> Array[Vector2i]:
	return [Vector2i(10, FLOOR_Y - 1)]

# --- Field basics ------------------------------------------------------------


func test_goal_is_zero_and_neighbors_flow_into_it() -> void:
	_lay_floor()
	_field.recompute(_goal())
	assert_bool(_field.is_computed()).is_true()
	assert_float(_field.cost_at(Vector2i(10, 9))).is_equal_approx(0.0, 0.0001)
	assert_vector(_field.get_flow_dir(Vector2i(10, 9))).is_equal(Vector2i.ZERO)
	assert_float(_field.cost_at(Vector2i(9, 9))).is_equal_approx(FlowField.MOVE_COST, 0.0001)
	assert_vector(_field.get_flow_dir(Vector2i(9, 9))).is_equal(Vector2i.RIGHT)
	assert_vector(_field.get_flow_dir(Vector2i(11, 9))).is_equal(Vector2i.LEFT)


func test_falling_into_goal_is_near_free_and_monotone() -> void:
	_lay_floor()
	_field.recompute(_goal())
	assert_float(_field.cost_at(Vector2i(10, 8))).is_equal_approx(FlowField.FALL_COST, 0.0001)
	assert_float(_field.cost_at(Vector2i(10, 6))).is_equal_approx(3 * FlowField.FALL_COST, 0.0001)
	# Follow the flow from a far cell: strictly decreasing cost, ends at the goal.
	var cell := Vector2i(3, 9)
	var cost := _field.cost_at(cell)
	for i in 40:
		var dir := _field.get_flow_dir(cell)
		if dir == Vector2i.ZERO:
			break
		cell += dir
		var next_cost := _field.cost_at(cell)
		assert_bool(next_cost < cost).is_true()
		cost = next_cost
	assert_vector(cell).is_equal(_goal()[0])


func test_ascending_needs_support() -> void:
	# Goal floats at (5, 3); the only approach from the floor is straight up
	# through open air — unsupported above the first cell, so unreachable.
	_lay_floor()
	_field.recompute([Vector2i(5, 3)] as Array[Vector2i])
	assert_float(_field.cost_at(Vector2i(5, 9))).is_equal(INF)
	# Cells ABOVE the goal still fall in.
	assert_float(_field.cost_at(Vector2i(5, 1))).is_less(INF)
	# A wall column beside the shaft supports every cell -> climbable.
	for y in range(3, FLOOR_Y):
		_terrain.tiles[Vector2i(4, y)] = "dirt"
	_field.recompute([Vector2i(5, 3)] as Array[Vector2i])
	var climb_cost := _field.cost_at(Vector2i(5, 9))
	assert_float(climb_cost).is_less(INF)
	assert_float(climb_cost).is_equal_approx(6 * FlowField.MOVE_COST, 0.0001)


func test_gradient_points_off_a_ledge() -> void:
	# Floor only over x 0..10; goal at the bottom of the open pit to the right.
	for x in 11:
		_terrain.tiles[Vector2i(x, FLOOR_Y)] = "dirt"
	var goal := Vector2i(11, ROWS - 1)
	_field.recompute([goal] as Array[Vector2i])
	# Mob on the ledge edge: stepping off into unsupported air must be finite
	# (support at `from`) so the gradient can point over the drop.
	var edge := Vector2i(10, 9)
	assert_float(_field.cost_at(edge)).is_less(INF)
	assert_vector(_field.get_flow_dir(edge)).is_equal(Vector2i.RIGHT)
	var expected: float = FlowField.MOVE_COST + 5 * FlowField.FALL_COST
	assert_float(_field.cost_at(edge)).is_equal_approx(expected, 0.0001)


func test_dig_weighting_prefers_soft_walls() -> void:
	_lay_floor()
	# Full-height wall column at x = 7 (a lone 1-tile wall would just be
	# hopped over — cheaper than digging, and correctly so).
	for y in FLOOR_Y:
		_terrain.tiles[Vector2i(7, y)] = "dirt" # hardness 1 -> enter cost 2
	_field.recompute(_goal())
	var through_dirt := _field.cost_at(Vector2i(5, 9))
	for y in FLOOR_Y:
		_terrain.tiles[Vector2i(7, y)] = "stone" # hardness 2 -> enter cost 3
	_field.recompute(_goal())
	var through_stone := _field.cost_at(Vector2i(5, 9))
	assert_float(through_dirt).is_less(through_stone)
	assert_float(through_stone - through_dirt).is_equal_approx(1.0, 0.0001)


func test_bedrock_seals_the_goal() -> void:
	_lay_floor()
	var goal := _goal()[0]
	for offset: Vector2i in FlowField.DIRS:
		_terrain.tiles[goal + offset] = "bedrock"
	_field.recompute(_goal())
	assert_float(_field.cost_at(Vector2i(5, 9))).is_equal(INF)
	assert_float(_field.cost_at(Vector2i(10, 5))).is_equal(INF)

# --- Sentinels ---------------------------------------------------------------


func test_sentinels_before_compute_and_out_of_region() -> void:
	assert_bool(_field.is_computed()).is_false()
	assert_float(_field.cost_at(Vector2i(5, 5))).is_equal(INF)
	assert_vector(_field.get_flow_dir(Vector2i(5, 5))).is_equal(Vector2i.ZERO)
	_lay_floor()
	_field.recompute(_goal())
	for pos: Vector2i in [Vector2i(5, ROWS), Vector2i(-1, 5), Vector2i(W, 5)]:
		assert_float(_field.cost_at(pos)).is_equal(INF)
		assert_vector(_field.get_flow_dir(pos)).is_equal(Vector2i.ZERO)

# --- Entities ----------------------------------------------------------------


func test_entity_hp_surcharge_and_core_exemption() -> void:
	_lay_floor()
	_field.recompute(_goal())
	var open_cost := _field.cost_at(Vector2i(7, 9))
	var blocker: EntityDouble = auto_free(EntityDouble.new())
	_terrain.entities[Vector2i(8, 9)] = blocker
	_field.recompute(_goal())
	var blocked_cost := _field.cost_at(Vector2i(7, 9))
	var surcharge: float = 100.0 * FlowField.ENTITY_HP_COST_FACTOR
	assert_float(blocked_cost).is_equal_approx(open_cost + surcharge, 0.0001)
	# A "core"-group entity adds nothing.
	blocker.add_to_group("core")
	_field.recompute(_goal())
	assert_float(_field.cost_at(Vector2i(7, 9))).is_equal_approx(open_cost, 0.0001)


func test_snapshot_costs_is_independent_copy() -> void:
	_lay_floor()
	_field.recompute(_goal())
	var baseline := _field.snapshot_costs()
	assert_int(baseline.size()).is_equal(W * ROWS)
	var probe := Vector2i(5, 9)
	var before := _field.cost_at(probe)
	_terrain.tiles[Vector2i(7, 9)] = "stone" # Wall up the walking row.
	_field.recompute(_goal())
	assert_float(_field.cost_at(probe)).is_not_equal(before)
	assert_float(baseline[probe.y * W + probe.x]).is_equal_approx(before, 0.0001)

# --- cost_of_entering reference (reversal-sensitive pairs) -------------------


func test_cost_of_entering_cases() -> void:
	_lay_floor()
	_terrain.tiles[Vector2i(3, 9)] = "dirt" # A solid on the walking row.
	_terrain.tiles[Vector2i(4, 9)] = "bedrock"
	_field.recompute(_goal())
	var down := _field.cost_of_entering(Vector2i(8, 8), Vector2i(8, 9))
	assert_float(down).is_equal_approx(FlowField.FALL_COST, 0.0001)
	# Up along a supported column (above the floor cell's neighbor).
	var up_supported := _field.cost_of_entering(Vector2i(8, 9), Vector2i(8, 8))
	assert_float(up_supported).is_equal_approx(FlowField.MOVE_COST, 0.0001)
	# Up in open sky: both ends unsupported.
	assert_float(_field.cost_of_entering(Vector2i(8, 4), Vector2i(8, 3))).is_equal(INF)
	# Into solids: dig cost / impassable bedrock.
	var into_dirt := _field.cost_of_entering(Vector2i(2, 9), Vector2i(3, 9))
	assert_float(into_dirt).is_equal_approx(1.0 + 1.0 / FlowField.REFERENCE_DIG_POWER, 0.0001)
	assert_float(_field.cost_of_entering(Vector2i(5, 9), Vector2i(4, 9))).is_equal(INF)
