## Waves-side flow-field lifecycle (roadmap 2.2): init + baseline, debounced
## recompute, reset. Fresh instances + doubles, never the live autoloads.
extends GdUnitTestSuite

const GameScript := preload("res://scripts/game/game.gd")
const WavesScript := preload("res://scripts/waves/waves.gd")
const StubEnemyScene := preload("res://tests/waves/stub_enemy.tscn")

const DEEP_ROW := FlowField.REGION_ROWS + 10


## Terrain double: the change signals Waves connects + the three reads the
## FlowField snapshot performs. Empty world (all air) is fine for these tests.
class TerrainDouble:
	extends Node

	signal tile_changed(pos: Vector2i)
	signal entity_changed(pos: Vector2i)

	## -1 = all air, which reaches only a handful of cells (nothing is
	## "supported", so the solve is a thin falling column). Set it to the row
	## under the goal to get a solve big enough to span multiple frame slices.
	var floor_row := -1


	func get_cell_source_id(pos: Vector2i) -> int:
		return Materials.ORDER.find("dirt") if pos.y == floor_row else -1


	func get_entity(_pos: Vector2i) -> Node:
		return null


	func get_entity_cells() -> Array[Vector2i]:
		return []


	func is_solid(pos: Vector2i) -> bool:
		return pos.y == floor_row


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
	# Spawn seams: this suite only exercises the field, but _waves is in the
	# tree, so the engine ticks its real _process and may trickle mobs out.
	_waves.enemy_scene = StubEnemyScene
	_waves.spawn_parent = auto_free(Node2D.new())
	add_child(_waves.spawn_parent)
	# Solve in one slice: these tests assert on update counts, not on pacing.
	# The amortized pacing itself is covered below and in test_flow_field.gd.
	_waves.step_budget_usec = 1 << 30
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
	assert_int(_waves.remaining()).is_equal(0)
	assert_float(_waves.baseline_cost_at(Vector2i(100, 20))).is_equal(INF)
	# Post-reset terrain signals are ignored again.
	_terrain.touch_tile(Vector2i(100, 20))
	assert_float(_waves._recompute_left).is_equal(0.0)

# --- Amortized solve pacing ----------------------------------------------------


## The frame-budget guarantee: arming the debounce must not solve the whole
## field in one _process — it starts a build that later frames finish.
func test_recompute_is_spread_across_frames() -> void:
	_terrain.floor_row = 21 # Goal stands on it -> a wide, many-pop solve.
	_waves.initialize_flow_field(_core)
	_waves.step_budget_usec = 1 # One tiny slice per frame.
	_terrain.touch_tile(Vector2i(100, 20))
	_waves._process(WavesScript.RECOMPUTE_DEBOUNCE + 0.1)
	assert_bool(_waves.flow_field.is_building()).is_true()
	assert_int(_updates).is_equal(1) # Still only the init compute.
	var frames := 0
	while _waves.flow_field.is_building():
		frames += 1
		assert_int(frames).is_less(100000)
		_waves._process(0.016)
	assert_int(frames).is_greater(1) # Genuinely took multiple frames.
	assert_int(_updates).is_equal(2) # Announced exactly once, on publish.


## A change landing mid-solve must not cancel the one in flight — under
## continuous chewing that would leave the front buffer stale forever.
func test_change_during_a_solve_queues_a_rebuild() -> void:
	_terrain.floor_row = 21 # Goal stands on it -> a wide, many-pop solve.
	_waves.initialize_flow_field(_core)
	_waves.step_budget_usec = 1
	_terrain.touch_tile(Vector2i(100, 20))
	_waves._process(WavesScript.RECOMPUTE_DEBOUNCE + 0.1)
	assert_bool(_waves.flow_field.is_building()).is_true()
	_terrain.touch_tile(Vector2i(101, 20)) # Arrives mid-solve.
	_waves._process(WavesScript.RECOMPUTE_DEBOUNCE + 0.1)
	assert_bool(_waves._rebuild_pending).is_true()
	_waves.step_budget_usec = 1 << 30
	_waves._process(0.016) # First solve publishes, second begins.
	assert_int(_updates).is_equal(2)
	assert_bool(_waves._rebuild_pending).is_false()
	_waves._process(0.016) # Second publishes.
	assert_int(_updates).is_equal(3)
	assert_bool(_waves.flow_field.is_building()).is_false()


## Spawning against a stale field is the one case worth a synchronous hitch.
func test_wave_start_flushes_an_in_flight_solve() -> void:
	_terrain.floor_row = 21 # Goal stands on it -> a wide, many-pop solve.
	_waves.initialize_flow_field(_core)
	_waves.step_budget_usec = 1
	_terrain.touch_tile(Vector2i(100, 20))
	_waves._process(WavesScript.RECOMPUTE_DEBOUNCE + 0.1)
	assert_bool(_waves.flow_field.is_building()).is_true()
	_enter_wave_phase()
	assert_bool(_waves.flow_field.is_building()).is_false()
	assert_int(_updates).is_equal(2)
