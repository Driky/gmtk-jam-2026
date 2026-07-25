## Music crossfade, pooled SFX. Owning doc: docs/systems/pipeline.md
##
## 2.1 footprint: the countdown-presentation stings (never-cut, plan.md) —
## last-FINAL_WINDOW-seconds tick + wave-start sting, driven by Game's
## signals. Streams load behind exists() guards so missing assets degrade
## to silence, never errors. Music crossfade lands in 4.4. Web autoplay is
## safe here: the first sting fires minutes after the first user input.
extends Node

const TICK_STREAM_PATH := "res://assets/audio/countdown_tick.wav"
const WAVE_START_STREAM_PATH := "res://assets/audio/wave_start.wav"

var _tick_player: AudioStreamPlayer
var _wave_start_player: AudioStreamPlayer


func _ready() -> void:
	_tick_player = _make_player(TICK_STREAM_PATH)
	_wave_start_player = _make_player(WAVE_START_STREAM_PATH)
	Game.countdown_tick.connect(_on_countdown_tick)
	Game.wave_started.connect(_on_wave_started)


func play_countdown_tick() -> void:
	if _tick_player.stream != null:
		_tick_player.play()


func play_wave_start() -> void:
	if _wave_start_player.stream != null:
		_wave_start_player.play()


func _make_player(stream_path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	if ResourceLoader.exists(stream_path):
		player.stream = load(stream_path)
	add_child(player)
	return player


func _on_countdown_tick(seconds_left: int) -> void:
	if seconds_left <= Game.FINAL_WINDOW and seconds_left > 0:
		play_countdown_tick()


func _on_wave_started(_wave_number: int) -> void:
	play_wave_start()
