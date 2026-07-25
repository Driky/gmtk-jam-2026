## Wave composition, spawning, aggro helpers. Owning doc: docs/systems/enemies.md
##
## 2.1 stub: no enemies exist yet, so a wave "clears" on a fixed timer (or
## the F9 debug action). The real manager (2.4) replaces the timer but keeps
## the same clear contract: call game.notify_wave_cleared() when all spawned
## mobs are dead.
extends Node

## Placeholder wave length until enemies land in 2.3/2.4.
const STUB_WAVE_DURATION := 15.0

## Injected by tests; falls back to the Game autoload (loads before us).
var game: Node = null

var _time_left := 0.0


func _ready() -> void:
	if game == null:
		game = Game
	game.wave_started.connect(_on_wave_started)


func _process(delta: float) -> void:
	if _time_left <= 0.0 or game.state != game.State.WAVE_PHASE:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		game.notify_wave_cleared()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_clear_wave") and game.state == game.State.WAVE_PHASE:
		_time_left = 0.0
		game.notify_wave_cleared()


func _on_wave_started(_wave_number: int) -> void:
	_time_left = STUB_WAVE_DURATION
