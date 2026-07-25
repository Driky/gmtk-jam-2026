## Unit tests for the Waves stub (roadmap 2.1) — timer-cleared waves until
## the real manager lands in 2.4. Uses fresh Game/Waves instances, never
## the live autoloads.
extends GdUnitTestSuite

const GameScript := preload("res://scripts/game/game.gd")
const WavesScript := preload("res://scripts/waves/waves.gd")

var _game: Node
var _waves: Node


func before_test() -> void:
	_game = auto_free(GameScript.new())
	_waves = auto_free(WavesScript.new())
	_waves.game = _game # Inject before add_child (_ready connects signals).
	add_child(_waves)


func _enter_wave_phase() -> void:
	_game.start_build_phase()
	_game._tick_countdown(_game.build_phase_duration() + 0.1)


func test_wave_started_arms_stub_timer() -> void:
	assert_float(_waves._time_left).is_equal(0.0)
	_enter_wave_phase()
	assert_float(_waves._time_left).is_equal(WavesScript.STUB_WAVE_DURATION)


func test_stub_clears_wave_after_duration() -> void:
	_enter_wave_phase()
	_waves._process(WavesScript.STUB_WAVE_DURATION + 0.1)
	assert_int(_game.waves_survived).is_equal(1)


func test_clear_fires_exactly_once() -> void:
	_enter_wave_phase()
	for i in 3:
		_waves._process(WavesScript.STUB_WAVE_DURATION + 0.1)
	assert_int(_game.waves_survived).is_equal(1)


func test_no_ticking_outside_wave_phase() -> void:
	_enter_wave_phase()
	_game.set_state(GameScript.State.GAME_OVER)
	_waves._process(WavesScript.STUB_WAVE_DURATION + 0.1)
	assert_float(_waves._time_left).is_equal(WavesScript.STUB_WAVE_DURATION)
	assert_int(_game.waves_survived).is_equal(0)


func test_partial_deltas_accumulate() -> void:
	_enter_wave_phase()
	var half := WavesScript.STUB_WAVE_DURATION / 2.0
	_waves._process(half)
	assert_int(_game.waves_survived).is_equal(0)
	_waves._process(half + 0.1)
	assert_int(_game.waves_survived).is_equal(1)
