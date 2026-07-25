## Unit tests for the Game state machine (roadmap 2.1).
## Runs against a fresh instance per test — never mutates the live autoload.
## Instances are NOT added to the tree: _ready's deferred Terrain hookup and
## _process never run; tick methods are driven directly.
extends GdUnitTestSuite

const GameScript := preload("res://scripts/game/game.gd")
const TerrainScript := preload("res://scripts/terrain/terrain.gd")

var _game: Node
var _states: Array = []
var _ticks: Array = []
var _build_starts: Array = []
var _wave_starts: Array = []
var _wave_clears: Array = []


func before_test() -> void:
	_game = auto_free(GameScript.new())
	_states = []
	_ticks = []
	_build_starts = []
	_wave_starts = []
	_wave_clears = []
	_game.state_changed.connect(func(state: int) -> void: _states.append(state))
	_game.countdown_tick.connect(func(seconds: int) -> void: _ticks.append(seconds))
	_game.build_phase_started.connect(func(wave: int) -> void: _build_starts.append(wave))
	_game.wave_started.connect(func(wave: int) -> void: _wave_starts.append(wave))
	_game.wave_cleared.connect(func(wave: int) -> void: _wave_clears.append(wave))

# --- Transitions ---------------------------------------------------------------


func test_boot_to_build_transition_path() -> void:
	_game.set_state(GameScript.State.MENU)
	_game.set_state(GameScript.State.GENERATING)
	_game.start_build_phase()
	assert_array(_states).contains_exactly(
		[
			GameScript.State.MENU,
			GameScript.State.GENERATING,
			GameScript.State.BUILD_PHASE,
		],
	)


func test_set_state_is_idempotent() -> void:
	_game.set_state(GameScript.State.MENU)
	_game.set_state(GameScript.State.MENU)
	assert_array(_states).has_size(1)


func test_state_changed_emits_before_phase_signal() -> void:
	var state_at_build_start := [-1]
	_game.build_phase_started.connect(
		func(_wave: int) -> void: state_at_build_start[0] = _game.state,
	)
	_game.start_build_phase()
	assert_int(state_at_build_start[0]).is_equal(GameScript.State.BUILD_PHASE)

# --- Countdown -----------------------------------------------------------------


func test_build_phase_start_resets_timer_and_ticks() -> void:
	_game.start_build_phase()
	assert_float(_game.time_left).is_equal(_game.build_phase_duration())
	assert_array(_build_starts).contains_exactly([1])
	assert_array(_ticks).contains_exactly([ceili(_game.build_phase_duration())])


func test_countdown_ticks_once_per_second_boundary() -> void:
	_game.start_build_phase()
	_ticks.clear()
	for i in 5:
		_game._tick_countdown(1.0)
	var first := ceili(_game.build_phase_duration()) - 1
	assert_array(_ticks).contains_exactly([first, first - 1, first - 2, first - 3, first - 4])


func test_fractional_deltas_do_not_double_tick() -> void:
	_game.start_build_phase()
	_ticks.clear()
	_game._tick_countdown(0.25) # 239.75 → still displays 240
	_game._tick_countdown(0.5) # 239.25
	assert_array(_ticks).is_empty()
	_game._tick_countdown(0.25) # 239.0 → 239
	assert_array(_ticks).contains_exactly([ceili(_game.build_phase_duration()) - 1])


func test_countdown_zero_starts_wave() -> void:
	_game.start_build_phase()
	_game._tick_countdown(_game.build_phase_duration() + 0.1)
	assert_int(_game.state).is_equal(GameScript.State.WAVE_PHASE)
	assert_int(_game.wave_number).is_equal(1)
	assert_array(_wave_starts).contains_exactly([1])

# --- Wave clear + grace beat ---------------------------------------------------


func test_wave_cleared_then_grace_returns_to_build() -> void:
	_game.start_build_phase()
	_game._tick_countdown(_game.build_phase_duration() + 0.1)
	_game.notify_wave_cleared()
	assert_array(_wave_clears).contains_exactly([1])
	assert_int(_game.waves_survived).is_equal(1)
	# Still in WAVE_PHASE during the grace beat.
	assert_int(_game.state).is_equal(GameScript.State.WAVE_PHASE)
	_game._tick_grace(GameScript.GRACE_BEAT + 0.1)
	assert_int(_game.state).is_equal(GameScript.State.BUILD_PHASE)
	assert_float(_game.time_left).is_equal(_game.build_phase_duration())
	assert_array(_build_starts).contains_exactly([1, 2])


func test_wave_cleared_ignored_outside_wave_phase() -> void:
	_game.start_build_phase()
	_game.notify_wave_cleared()
	assert_array(_wave_clears).is_empty()
	assert_int(_game.waves_survived).is_equal(0)


func test_wave_cleared_ignored_during_grace() -> void:
	_game.start_build_phase()
	_game._tick_countdown(_game.build_phase_duration() + 0.1)
	_game.notify_wave_cleared()
	_game.notify_wave_cleared()
	assert_array(_wave_clears).has_size(1)
	assert_int(_game.waves_survived).is_equal(1)

# --- Game over + stats ---------------------------------------------------------


func test_game_over_is_guarded() -> void:
	_game.game_over()
	_game.game_over()
	assert_array(_states).contains_exactly([GameScript.State.GAME_OVER])


func test_blocks_mined_counts_player_source_only() -> void:
	_game._on_tile_broken(Vector2i.ZERO, "dirt", TerrainScript.Source.PLAYER)
	_game._on_tile_broken(Vector2i.ZERO, "dirt", TerrainScript.Source.MONSTER)
	_game._on_tile_broken(Vector2i.ZERO, "dirt", TerrainScript.Source.MACHINE)
	assert_int(_game.blocks_mined).is_equal(1)


func test_depth_watermark_is_monotonic() -> void:
	_game.note_depth(40)
	_game.note_depth(25)
	assert_int(_game.max_depth_row).is_equal(40)
	_game.note_depth(90)
	assert_int(_game.max_depth_row).is_equal(90)


func test_run_stats_shape() -> void:
	_game.notify_wave_cleared() # ignored — not in wave phase
	_game.note_depth(33)
	_game._on_tile_broken(Vector2i.ZERO, "dirt", TerrainScript.Source.PLAYER)
	var stats: Dictionary = _game.get_run_stats()
	assert_int(stats.waves_survived).is_equal(0)
	assert_int(stats.max_depth_row).is_equal(33)
	assert_int(stats.blocks_mined).is_equal(1)


func test_reset_run_zeroes_everything_without_emitting() -> void:
	_game.start_build_phase()
	_game._tick_countdown(_game.build_phase_duration() + 0.1)
	_game.note_depth(50)
	_game._on_tile_broken(Vector2i.ZERO, "dirt", TerrainScript.Source.PLAYER)
	_states.clear()
	_game.reset_run()
	assert_int(_game.state).is_equal(GameScript.State.BOOT)
	assert_array(_states).is_empty()
	assert_int(_game.wave_number).is_equal(0)
	assert_int(_game.waves_survived).is_equal(0)
	assert_int(_game.max_depth_row).is_equal(0)
	assert_int(_game.blocks_mined).is_equal(0)
	assert_float(_game.time_left).is_equal(0.0)
