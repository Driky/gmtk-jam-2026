## Phase state machine + countdown timer. Owning doc: docs/plan.md
##
## 1.5 footprint: states + world_seed so generation runs behind GENERATING.
## Transitions, the countdown timer, and wave hand-off land in 2.1.
extends Node

signal state_changed(state: State)

enum State { BOOT, MENU, GENERATING, BUILD_PHASE, WAVE_PHASE, GAME_OVER }

var state := State.BOOT
## The run's world seed — world gen consumes it, the save system persists it.
var world_seed := 0


func set_state(next: State) -> void:
	if next == state:
		return
	state = next
	state_changed.emit(next)
