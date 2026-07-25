## Player-following world camera, clamped to the playable band.
## Zoom-cycle decision owned by docs/systems/ui.md; constants by player-combat.md.
extends Camera2D

const ZOOM_STEPS: Array[float] = [1.0, 1.5, 2.0]
const SMOOTHING_SPEED := 8.0

var _zoom_index := 0


func _ready() -> void:
	var tile := TileLayout.TILE_SIZE
	limit_left = WorldConfig.PLAYABLE_X_BEGIN * tile
	limit_right = WorldConfig.PLAYABLE_X_END * tile
	limit_top = 0
	limit_bottom = WorldConfig.WORLD_HEIGHT * tile
	position_smoothing_enabled = true
	position_smoothing_speed = SMOOTHING_SPEED
	make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_zoom"):
		_zoom_index = (_zoom_index + 1) % ZOOM_STEPS.size()
		zoom = Vector2.ONE * ZOOM_STEPS[_zoom_index]
