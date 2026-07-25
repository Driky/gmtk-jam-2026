## Waves-side flow-field lifecycle (roadmap 2.2): init + baseline, debounced
## recompute, reset. Fresh instances + doubles, never the live autoloads.
extends GdUnitTestSuite

const GameScript := preload("res://scripts/game/game.gd")
const WavesScript := preload("res://scripts/waves/waves.gd")

const DEEP_ROW := FlowField.REGION_ROWS + 10


## Terrain double: the change signals Waves connects + the three reads the
## FlowField snapshot performs. Empty world (all air) is fine for these tests.
class TerrainDouble:
	extends Node

	signal tile_changed(pos: Vector2i)
	signal entity_changed(pos: Vector2i)


	func get_cell_source_id(_pos: Vector2i) -> int:
		return -1


	func get_entity(_pos: Vector2i) -> Node:
		return null


	func get_entity_cells() -> Array[Vector2i]:
		return []


	func touch_tile(pos: Vector2i) -> void:
		tile_changed.emit(pos)


	func touch_entity(pos: Vector2i) -> void:
		entity_changed.emit(pos)


class CoreDouble:
	extends Node2D

	func footprint() -> Array[Vector2i]:
		return [Vector2i(100, 20), Vector2i(101, 20)]


var _game: Node
var _terrain: TerrainDouble
var _waves: Node
var _core: CoreDouble
var _updates := 0


func before_test() -> void:
	_game = auto_free(GameScript.new())
	_terrain = auto_free(TerrainDouble.new())
	_waves = auto_free(WavesScript.new())
	_waves.game = _game
	_waves.terrain = _terrain # Inject before add_child (_ready connects).
	add_child(_waves)
	_core = auto_free(CoreDouble.new())
	_updates = 0
	_waves.flow_field_updated.connect(
		func() -> void:
			_updates += 1,
	)


func _enter_wave_phase() -> void:
	_game.start_build_phase()
	_game._tick_countdown(_game.build_phase_duration() + 0.1)

# --- Init & baseline ---------------------------------------------------------


func test_signals_before_init_are_ignored() -> void:
	_terrain.touch_tile(Vector2i(100, 20))
	assert_float(_waves._recompute_left).is_equal(0.0)
	assert_int(_updates).is_equal(0)


func test_initialize_computes_field_and_baseline() -> void:
	_waves.initialize_flow_field(_core)
	assert_bool(_waves.flow_field.is_computed()).is_true()
	assert_int(_updates).is_equal(1)
	assert_float(_waves.baseline_cost_at(Vector2i(100, 20))).is_equal(0.0)
	# Out-of-region baseline queries are INF, not out-of-bounds reads.
	assert_float(_waves.baseline_cost_at(Vector2i(100, DEEP_ROW))).is_equal(INF)


func test_baseline_survives_recomputes() -> void:
	_waves.initialize_flow_field(_core)
	var initial: float = _waves.baseline_cost_at(Vector2i(100, 19))
	_terrain.touch_tile(Vector2i(100, 20))
	_waves._process(WavesScript.RECOMPUTE_DEBOUNCE + 0.1)
	assert_float(_waves.baseline_cost_at(Vector2i(100, 19))).is_equal(initial)

# --- Debounce ----------------------------------------------------------------


func test_recompute_debounced_half_second() -> void:
	_waves.initialize_flow_field(_core)
	_terrain.touch_tile(Vector2i(100, 20))
	_waves._process(0.3)
	assert_int(_updates).is_equal(1) # Still only the init compute.
	_waves._process(0.3)
	assert_int(_updates).is_equal(2)
	assert_float(_waves._recompute_left).is_equal(0.0)


func test_change_burst_coalesces_into_one_recompute() -> void:
	_waves.initialize_flow_field(_core)
	for i in 5:
		_terrain.touch_tile(Vector2i(100 + i, 20))
	_waves._process(WavesScript.RECOMPUTE_DEBOUNCE + 0.1)
	assert_int(_updates).is_equal(2)


func test_leading_edge_never_rearms() -> void:
	_waves.initialize_flow_field(_core)
	_terrain.touch_tile(Vector2i(100, 20))
	_waves._process(0.4)
	_terrain.touch_tile(Vector2i(101, 20)) # Must NOT push the deadline back.
	_waves._process(0.15)
	assert_int(_updates).is_equal(2)


func test_deep_changes_never_trigger() -> void:
	_waves.initialize_flow_field(_core)
	_terrain.touch_tile(Vector2i(100, DEEP_ROW))
	assert_float(_waves._recompute_left).is_equal(0.0)
	_waves._process(WavesScript.RECOMPUTE_DEBOUNCE + 0.1)
	assert_int(_updates).is_equal(1)


func test_entity_changes_trigger_too() -> void:
	_waves.initialize_flow_field(_core)
	_terrain.touch_entity(Vector2i(100, 20))
	_waves._process(WavesScript.RECOMPUTE_DEBOUNCE + 0.1)
	assert_int(_updates).is_equal(2)


func test_wave_start_flushes_pending_recompute() -> void:
	_waves.initialize_flow_field(_core)
	_terrain.touch_tile(Vector2i(100, 20))
	_enter_wave_phase() # wave_started must not leave mobs a stale field.
	assert_int(_updates).is_equal(2)
	assert_float(_waves._recompute_left).is_equal(0.0)

# --- Reset -------------------------------------------------------------------


func test_reset_run_clears_everything() -> void:
	_waves.initialize_flow_field(_core)
	_terrain.touch_tile(Vector2i(100, 20))
	_enter_wave_phase()
	_waves.reset_run()
	assert_object(_waves.flow_field).is_null()
	assert_float(_waves._recompute_left).is_equal(0.0)
	assert_float(_waves._time_left).is_equal(0.0)
	assert_float(_waves.baseline_cost_at(Vector2i(100, 20))).is_equal(INF)
	# Post-reset terrain signals are ignored again.
	_terrain.touch_tile(Vector2i(100, 20))
	assert_float(_waves._recompute_left).is_equal(0.0)
