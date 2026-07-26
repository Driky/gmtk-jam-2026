## Unit tests for the F4 perf overlay: stat accumulation and formatting.
## Fresh instances + doubles, never the live autoloads.
extends GdUnitTestSuite

const GameScript := preload("res://scripts/game/game.gd")
const PerfOverlayScript := preload("res://scripts/debug/perf_overlay.gd")


class WavesDouble:
	extends Node

	signal flow_field_updated

	var flow_field: FlowField = null


## Just the two perf counters the overlay diffs.
class TerrainDouble:
	extends Node

	var cell_writes := 0
	var cell_write_usec := 0
	var cell_write_peak_usec := 0


	func write(count: int, usec: int) -> void:
		cell_writes += count
		cell_write_usec += usec
		cell_write_peak_usec = maxi(cell_write_peak_usec, usec)


var _game: Node
var _waves: WavesDouble
var _terrain: TerrainDouble
var _overlay: CanvasLayer


func before_test() -> void:
	_game = auto_free(GameScript.new())
	_waves = auto_free(WavesDouble.new())
	_overlay = auto_free(PerfOverlayScript.new())
	_terrain = auto_free(TerrainDouble.new())
	_overlay.game = _game
	_overlay.terrain = _terrain
	_overlay.waves = _waves # Inject before add_child (_ready connects).
	add_child(_overlay)
	_game.set_state(GameScript.State.BUILD_PHASE)


func _field_with_solve(msec: float) -> FlowField:
	var field := FlowField.new()
	field.last_solve_msec = msec
	return field

# --- Formatting ----------------------------------------------------------------


func test_format_stats_shape() -> void:
	var text := PerfOverlayScript.format_stats(
		58,
		17.2,
		214.6,
		231.0,
		83.2,
		121.4,
		14,
		6,
		40,
		0.4,
		22.5,
		116.7,
		17.2,
	)
	assert_str(text).contains("fps 58")
	assert_str(text).contains("frame 17.2")
	assert_str(text).contains("peak 231.0 ms")
	assert_str(text).contains("field last 83.2")
	assert_str(text).contains("solves 14")
	assert_str(text).contains("mobs 6")
	assert_str(text).contains("cells 40 in 0.4 ms in-call | worst one 22.5 ms")
	assert_str(text).contains("dirty 116.7")
	assert_str(text).contains("clean 17.2")

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

# --- Cell-write attribution ----------------------------------------------------


## The discriminator: a slow frame next to a cell write lands in "dirty", a
## slow frame with no write nearby lands in "clean".
func test_frames_split_by_whether_a_cell_was_written() -> void:
	_overlay._process(0.016) # Clean.
	_terrain.write(5, 400)
	_overlay._process(0.120) # Dirty: writes happened during it.
	assert_float(_overlay._worst_dirty).is_equal_approx(120.0, 0.1)
	assert_float(_overlay._worst_clean).is_equal_approx(16.0, 0.1)
	assert_int(_overlay._writes).is_equal(5)


## The engine defers its quadrant rebuild, so the frames just after a write
## must stay attributed to it.
func test_dirty_window_outlives_the_writing_frame() -> void:
	_terrain.write(1, 100)
	_overlay._process(0.016)
	for i in PerfOverlayScript.DIRTY_FRAMES:
		_overlay._process(0.120) # No new writes, but still within the window.
	assert_float(_overlay._worst_dirty).is_equal_approx(120.0, 0.1)
	assert_float(_overlay._worst_clean).is_equal(0.0)


func test_clean_frames_after_the_window_are_not_blamed_on_writes() -> void:
	_terrain.write(1, 100)
	_overlay._process(0.016)
	for i in PerfOverlayScript.DIRTY_FRAMES + 1:
		_overlay._process(0.016)
	_overlay._process(0.120) # Well clear of the write.
	assert_float(_overlay._worst_clean).is_equal_approx(120.0, 0.1)


func test_reset_baselines_against_world_gen_writes() -> void:
	_terrain.write(240000, 90000) # World gen.
	_overlay.reset_stats()
	_overlay._process(0.016)
	assert_int(_overlay._writes).is_equal(0)
	assert_float(_overlay._worst_dirty).is_equal(0.0)


## Regression: world gen writes ~240k cells before a run starts, and folding
## their time into the readout made the in-call total read ~10x high.
func test_reset_baselines_the_in_call_total_too() -> void:
	_terrain.write(240000, 120000) # World gen: 120 ms of cheap writes.
	_overlay.reset_stats()
	_terrain.write(5, 400) # One tile break during play.
	_overlay._process(0.016)
	assert_int(_overlay._write_usec).is_equal(400)
	assert_int(_overlay._writes).is_equal(5)

# --- Light readout (2.7) -----------------------------------------------------


## Just the surface the readout reads: a Node2D carrying a LightGrid.
class LightMapDouble:
	extends Node2D

	var grid := LightGrid.new()


## No light COUNT is reported on purpose: the grid costs the same whether one
## torch is lit or a hundred. What moves is the region, and the fallback ladder
## in terrain.md is written in those terms.
func test_light_text_reports_the_grid_region() -> void:
	var light_map: LightMapDouble = auto_free(LightMapDouble.new())
	light_map.grid.resize(112, 77)
	var text := PerfOverlayScript.light_text(light_map)
	assert_str(text).contains("112x77")
	assert_str(text).contains("8624 cells")


func test_light_text_calls_out_full_bright() -> void:
	var light_map: LightMapDouble = auto_free(LightMapDouble.new())
	light_map.visible = false
	assert_str(PerfOverlayScript.light_text(light_map)).contains("FULL BRIGHT")


## The overlay must survive a build with no light map rather than taking the
## whole readout down with it.
func test_light_text_tolerates_a_missing_light_map() -> void:
	assert_str(PerfOverlayScript.light_text(null)).contains("light off")
