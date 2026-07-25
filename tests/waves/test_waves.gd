## Unit tests for the wave manager (roadmap 2.4): budget pre-roll, trickle
## pacing, alternating buffer spawns, the alive cap, and the clear contract.
## Uses fresh Game/Waves instances and a stub enemy scene — never the live
## autoloads, never the real physics enemy.
extends GdUnitTestSuite

const GameScript := preload("res://scripts/game/game.gd")
const WavesScript := preload("res://scripts/waves/waves.gd")
const StubEnemyScene := preload("res://tests/waves/stub_enemy.tscn")
const Roster := preload("res://data/wave_roster.gd")

## Surface row the stub terrain reports for every column.
const SOLID_ROW := 20


## The two signals _ready connects plus the is_solid probe _spawn_position
## needs — keeps tests off the live Terrain.
class TerrainStub:
	extends Node

	signal tile_changed(pos: Vector2i)
	signal entity_changed(pos: Vector2i)


	## Row 0 is the world's bedrock border — solid everywhere, including above
	## the buffer surface. Spawn placement must skip it, not stand on it.
	func is_solid(pos: Vector2i) -> bool:
		return pos.y == 0 or pos.y >= SOLID_ROW


	func touch(pos: Vector2i) -> void:
		tile_changed.emit(pos)
		entity_changed.emit(pos)


var _game: Node
var _waves: Node
var _spawn_root: Node2D


func before_test() -> void:
	_game = auto_free(GameScript.new())
	_spawn_root = auto_free(Node2D.new())
	add_child(_spawn_root)
	_waves = auto_free(WavesScript.new())
	_waves.game = _game # Inject before add_child (_ready connects signals).
	_waves.terrain = auto_free(TerrainStub.new())
	_waves.enemy_scene = StubEnemyScene
	_waves.spawn_parent = _spawn_root
	add_child(_waves)


func _enter_wave_phase() -> void:
	_game.start_build_phase()
	_game._tick_countdown(_game.build_phase_duration() + 0.1)


## Advance far enough to spawn `count` mobs (the first lands on the first tick).
func _pump_spawns(count: int) -> void:
	for i in count:
		_waves._process(WavesScript.SPAWN_INTERVAL)


func _kill(enemy: Node) -> void:
	enemy.take_damage(INF)

# --- Budget pre-roll ---------------------------------------------------------


func test_no_wave_queued_before_the_wave_starts() -> void:
	assert_int(_waves.remaining()).is_equal(0)


func test_wave_start_prerolls_the_whole_budget() -> void:
	_enter_wave_phase()
	assert_int(_waves.remaining()).is_equal(Roster.budget_for(1))
	assert_int(_waves.alive_count()).is_equal(0) # Pre-rolled, not pre-spawned.


func test_wave_start_emits_progress() -> void:
	var seen: Array[int] = []
	_waves.wave_progress_changed.connect(func(left: int) -> void: seen.append(left))
	_enter_wave_phase()
	assert_array(seen).contains([Roster.budget_for(1)])

# --- Trickle -----------------------------------------------------------------


func test_first_tick_spawns_exactly_one() -> void:
	_enter_wave_phase()
	_waves._process(0.016)
	assert_int(_waves.alive_count()).is_equal(1)
	# The mob moved from queue to alive — the wave total is unchanged.
	assert_int(_waves.remaining()).is_equal(Roster.budget_for(1))


func test_trickle_paces_the_queue() -> void:
	_enter_wave_phase()
	_waves._process(0.016)
	_waves._process(WavesScript.SPAWN_INTERVAL / 2.0)
	assert_int(_waves.alive_count()).is_equal(1) # Interval not elapsed yet.
	_waves._process(WavesScript.SPAWN_INTERVAL / 2.0)
	assert_int(_waves.alive_count()).is_equal(2)


func test_no_spawning_outside_wave_phase() -> void:
	_enter_wave_phase()
	_game.set_state(GameScript.State.BUILD_PHASE)
	_pump_spawns(3)
	assert_int(_waves.alive_count()).is_equal(0)


func test_alive_cap_stalls_the_trickle() -> void:
	_enter_wave_phase()
	_waves._on_wave_started(20) # Re-roll a budget far past the cap.
	assert_int(_waves.remaining()).is_greater(WavesScript.MAX_ALIVE)
	_pump_spawns(WavesScript.MAX_ALIVE + 10)
	assert_int(_waves.alive_count()).is_equal(WavesScript.MAX_ALIVE)
	# The cap stalls the trickle; it never drops mobs from the wave.
	assert_int(_waves.remaining()).is_greater(WavesScript.MAX_ALIVE)

# --- Spawn placement ---------------------------------------------------------


func test_spawns_land_on_the_buffer_surface() -> void:
	_enter_wave_phase()
	_pump_spawns(4)
	for enemy: Node2D in _waves._alive:
		var cell := Vector2i((enemy.position / WavesScript.TILE).floor())
		var margin: int = mini(cell.x, WorldConfig.WORLD_WIDTH - 1 - cell.x)
		assert_int(margin).is_between(
			WavesScript.SPAWN_MARGIN_MIN,
			WavesScript.SPAWN_MARGIN_MAX,
		)
		assert_bool(WorldConfig.is_in_buffer(cell)).is_true()
		assert_float(enemy.position.y).is_equal(
			SOLID_ROW * WavesScript.TILE - WavesScript.SPAWN_FEET_OFFSET,
		)


func test_spawns_alternate_buffers() -> void:
	_enter_wave_phase()
	_pump_spawns(3)
	var centre := WorldConfig.WORLD_WIDTH * WavesScript.TILE / 2.0
	var sides: Array[bool] = []
	for enemy: Node2D in _waves._alive:
		sides.append(enemy.position.x < centre)
	assert_array(sides).has_size(3)
	assert_bool(sides[0] == sides[1]).is_false()
	assert_bool(sides[1] == sides[2]).is_false()

# --- Clear contract ----------------------------------------------------------


func test_wave_holds_while_the_queue_still_has_mobs() -> void:
	_enter_wave_phase()
	_waves._process(0.016)
	_kill(_waves._alive[0])
	assert_int(_game.waves_survived).is_equal(0) # Queue isn't drained yet.


func test_wave_holds_while_mobs_are_alive() -> void:
	_enter_wave_phase()
	_pump_spawns(Roster.budget_for(1))
	# Queue fully drained, every mob still alive.
	assert_int(_waves.alive_count()).is_equal(Roster.budget_for(1))
	assert_int(_game.waves_survived).is_equal(0)


func test_wave_clears_once_every_spawned_mob_is_dead() -> void:
	_enter_wave_phase()
	_pump_spawns(Roster.budget_for(1))
	for enemy in _waves._alive.duplicate():
		_kill(enemy)
	assert_int(_waves.remaining()).is_equal(0)
	assert_int(_game.waves_survived).is_equal(1)


func test_clear_fires_exactly_once() -> void:
	_enter_wave_phase()
	_pump_spawns(Roster.budget_for(1))
	for enemy in _waves._alive.duplicate():
		_kill(enemy)
	for i in 3:
		_waves._check_cleared()
	assert_int(_game.waves_survived).is_equal(1)


func test_debug_clear_wave_empties_the_wave() -> void:
	_enter_wave_phase()
	_pump_spawns(2)
	var event := InputEventAction.new()
	event.action = &"debug_clear_wave"
	event.pressed = true
	_waves._unhandled_input(event)
	assert_int(_waves.remaining()).is_equal(0)
	assert_int(_game.waves_survived).is_equal(1)

# --- Run reset ---------------------------------------------------------------


func test_reset_run_clears_wave_state() -> void:
	_enter_wave_phase()
	_pump_spawns(2)
	_waves.reset_run()
	assert_int(_waves.remaining()).is_equal(0)
