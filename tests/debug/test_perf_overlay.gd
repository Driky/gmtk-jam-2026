## Unit tests for the F4 perf overlay: stat accumulation and formatting.
## Fresh instances + doubles, never the live autoloads.
extends GdUnitTestSuite

const GameScript := preload("res://scripts/game/game.gd")
const PerfOverlayScript := preload("res://scripts/debug/perf_overlay.gd")


class WavesDouble:
	extends Node

	signal flow_field_updated

	var flow_field: FlowField = null


var _game: Node
var _waves: WavesDouble
var _overlay: CanvasLayer


func before_test() -> void:
	_game = auto_free(GameScript.new())
	_waves = auto_free(WavesDouble.new())
	_overlay = auto_free(PerfOverlayScript.new())
	_overlay.game = _game
	_overlay.waves = _waves # Inject before add_child (_ready connects).
	add_child(_overlay)
	_game.set_state(GameScript.State.BUILD_PHASE)


func _field_with_solve(msec: float) -> FlowField:
	var field := FlowField.new()
	field.last_solve_msec = msec
	return field

# --- Formatting ----------------------------------------------------------------


func test_format_stats_shape() -> void:
	var text := PerfOverlayScript.format_stats(58, 17.2, 214.6, 231.0, 83.2, 121.4, 14, 6)
	assert_str(text).contains("fps 58")
	assert_str(text).contains("frame 17.2")
	assert_str(text).contains("peak 231.0 ms")
	assert_str(text).contains("field last 83.2")
	assert_str(text).contains("solves 14")
	assert_str(text).contains("mobs 6")

# --- Frame sampling ------------------------------------------------------------


func test_peak_tracks_the_worst_frame() -> void:
	_overlay._process(0.016)
	_overlay._process(0.220) # A 220 ms hitch.
	_overlay._process(0.016)
	assert_float(_overlay._peak).is_equal_approx(220.0, 0.1)


## The whole point of the overlay: a hitch every half second barely moves an
## FPS average, so the peak must survive a sea of good frames.
func test_peak_survives_many_good_frames() -> void:
	_overlay._process(0.200)
	for i in 200:
		_overlay._process(0.016)
	assert_float(_overlay._peak).is_equal_approx(200.0, 0.1)


func test_generating_frames_are_not_sampled() -> void:
	_game.set_state(GameScript.State.GENERATING)
	_overlay._process(2.0) # World-gen row sweep, legitimately huge.
	assert_float(_overlay._peak).is_equal(0.0)


func test_worst_window_rolls_over() -> void:
	_overlay._process(0.150)
	# Push past the window so the spike leaves the rolling figure...
	for i in int(PerfOverlayScript.WINDOW / 0.016) + 2:
		_overlay._process(0.016)
	for i in int(PerfOverlayScript.WINDOW / 0.016) + 2:
		_overlay._process(0.016)
	assert_float(_overlay._worst_shown).is_less(150.0)
	assert_float(_overlay._peak).is_equal_approx(150.0, 0.1) # ...but never the peak.

# --- Flow-field solve sampling -------------------------------------------------


func test_field_updates_record_solve_cost() -> void:
	_waves.flow_field = _field_with_solve(83.2)
	_waves.flow_field_updated.emit()
	assert_float(_overlay._solve_last).is_equal_approx(83.2, 0.01)
	assert_int(_overlay._solves).is_equal(1)


func test_solve_peak_is_the_worst_not_the_last() -> void:
	_waves.flow_field = _field_with_solve(120.0)
	_waves.flow_field_updated.emit()
	_waves.flow_field = _field_with_solve(80.0)
	_waves.flow_field_updated.emit()
	assert_float(_overlay._solve_last).is_equal_approx(80.0, 0.01)
	assert_float(_overlay._solve_peak).is_equal_approx(120.0, 0.01)
	assert_int(_overlay._solves).is_equal(2)


func test_reset_stats_zeroes_everything() -> void:
	_overlay._process(0.200)
	_waves.flow_field = _field_with_solve(120.0)
	_waves.flow_field_updated.emit()
	_overlay.reset_stats()
	assert_float(_overlay._peak).is_equal(0.0)
	assert_float(_overlay._solve_peak).is_equal(0.0)
	assert_int(_overlay._solves).is_equal(0)
