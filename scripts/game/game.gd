## Phase state machine + countdown timer. Owning doc: docs/plan.md
##
## Signal hub for the phase flow: Waves/HUD/AudioBus/SaveSystem listen here
## and never wire to each other. Contract: state_changed always emits BEFORE
## the phase-specific signal, so listeners reading Game.state inside a phase
## signal handler see a consistent value.
##
## Autoload-order note: Game loads FIRST — it must not touch other autoloads
## in _ready; the Terrain hookup is deferred (and injectable for tests).
extends Node

signal state_changed(state: State)
## Build phase began; payload is the UPCOMING wave number. SaveSystem
## autosaves here (4.3).
signal build_phase_started(wave_number: int)
## Countdown display/sting driver — emitted on integer-second boundaries
## only (including one immediately at build-phase start).
signal countdown_tick(seconds_left: int)
## Wave n is live — Waves (2.4) spawns off this; HUD announces.
signal wave_started(wave_number: int)
## All spawned mobs dead — the loot/XP settle moment; grace beat follows.
signal wave_cleared(wave_number: int)

enum State { BOOT, MENU, GENERATING, BUILD_PHASE, WAVE_PHASE, GAME_OVER }

const TerrainScript := preload("res://scripts/terrain/terrain.gd")

const BUILD_PHASE_DURATION := 240.0
## Last-N-seconds window: audio sting + screen pulse (never-cut, plan.md).
const FINAL_WINDOW := 10
## Beat between wave cleared and the next build phase.
const GRACE_BEAT := 2.0
## Debug: short build phase for browser smoke tests, where no input is
## available. The menu's "Skip countdown" is the interactive equivalent.
const DEBUG_FAST_PHASES := false
const DEBUG_BUILD_PHASE_DURATION := 15.0
## Debug (F8): how much countdown skip_countdown leaves on the clock. Inside
## FINAL_WINDOW on purpose, so the skip still shows the last-10s presentation.
const DEBUG_SKIP_TO_SECONDS := 5.0

var state := State.BOOT
## The run's world seed — world gen consumes it, the save system persists it.
var world_seed := 0
## Waves completed count during WAVE_PHASE; the upcoming wave is +1.
var wave_number := 0
var time_left := 0.0
# Run stats for the game-over screen (plan.md: waves, depth, blocks mined).
var waves_survived := 0
var max_depth_row := 0
var blocks_mined := 0
## Injected by tests; resolved to the Terrain autoload otherwise.
var terrain: Node = null

var _grace_left := 0.0
var _last_tick := -1
var _player: Node2D = null


func _ready() -> void:
	_connect_terrain.call_deferred()


func _process(delta: float) -> void:
	match state:
		State.BUILD_PHASE:
			_tick_countdown(delta)
			_poll_depth()
		State.WAVE_PHASE:
			_tick_grace(delta)
			_poll_depth()


## Debug: cut a running build countdown short so a wave can be reached without
## waiting out four minutes. Only ever shortens — repeat presses can't push the
## clock back up. Driven from the F3 debug menu ([ui.md](../systems/ui.md)).
func skip_countdown() -> void:
	if state != State.BUILD_PHASE:
		return
	time_left = minf(time_left, DEBUG_SKIP_TO_SECONDS)
	_emit_tick()


func set_state(next: State) -> void:
	if next == state:
		return
	state = next
	state_changed.emit(next)

# --- Phase flow ----------------------------------------------------------------


func build_phase_duration() -> float:
	return DEBUG_BUILD_PHASE_DURATION if DEBUG_FAST_PHASES else BUILD_PHASE_DURATION


func start_build_phase() -> void:
	time_left = build_phase_duration()
	_last_tick = -1
	set_state(State.BUILD_PHASE)
	build_phase_started.emit(wave_number + 1)
	_emit_tick()


## Public wave-clear contract: Waves calls this once its spawn queue is empty
## and every mob it spawned is dead (2.4).
func notify_wave_cleared() -> void:
	if state != State.WAVE_PHASE or _grace_left > 0.0:
		return
	waves_survived += 1
	wave_cleared.emit(wave_number)
	_grace_left = GRACE_BEAT


func game_over() -> void:
	if state == State.GAME_OVER:
		return
	set_state(State.GAME_OVER)

# --- Run stats -----------------------------------------------------------------


## Watermark the deepest row reached (raw tile row, matches the HUD readout).
func note_depth(row: int) -> void:
	max_depth_row = maxi(max_depth_row, row)


func get_run_stats() -> Dictionary:
	return {
		waves_survived = waves_survived,
		max_depth_row = max_depth_row,
		blocks_mined = blocks_mined,
	}


## Zero all run state before a scene reload. Direct state assignment (no
## emit) — the reload re-drives the real transitions from BOOT.
func reset_run() -> void:
	wave_number = 0
	time_left = 0.0
	waves_survived = 0
	max_depth_row = 0
	blocks_mined = 0
	_grace_left = 0.0
	_last_tick = -1
	_player = null
	state = State.BOOT

# --- Internals -----------------------------------------------------------------


func _tick_countdown(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_start_wave()
		return
	_emit_tick()


## Emit countdown_tick only when the displayed (ceiled) second changes.
func _emit_tick() -> void:
	var seconds := ceili(time_left)
	if seconds != _last_tick:
		_last_tick = seconds
		countdown_tick.emit(seconds)


func _start_wave() -> void:
	wave_number += 1
	set_state(State.WAVE_PHASE)
	wave_started.emit(wave_number)


func _tick_grace(delta: float) -> void:
	if _grace_left <= 0.0:
		return
	_grace_left -= delta
	if _grace_left <= 0.0:
		_grace_left = 0.0
		start_build_phase()


func _poll_depth() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	note_depth(floori(_player.global_position.y / TileLayout.TILE_SIZE))


func _connect_terrain() -> void:
	if terrain == null:
		terrain = get_node_or_null("/root/Terrain")
	if terrain != null:
		terrain.tile_broken.connect(_on_tile_broken)


func _on_tile_broken(_pos: Vector2i, _material_id: String, source: int) -> void:
	if source == TerrainScript.Source.PLAYER:
		blocks_mined += 1
