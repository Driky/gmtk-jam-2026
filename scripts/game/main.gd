## Boot driver: amortized world generation behind the loading bar, then a
## static surface view until the player lands (1.6). Owning doc: docs/roadmap.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
## Debug: set non-zero to force a seed (menu seed entry is a Day-4 stretch).
const FORCED_SEED := 0

var _gen: WorldGen

@onready var _loading_ui: CanvasLayer = %LoadingUI
@onready var _loading_bar: ProgressBar = %LoadingBar
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	Game.world_seed = FORCED_SEED if FORCED_SEED != 0 else randi()
	Game.set_state(Game.State.GENERATING)
	_gen = WorldGen.new(Terrain, Game.world_seed)


func _process(_delta: float) -> void:
	if _gen == null:
		return
	_loading_bar.value = _gen.step()
	if _gen.is_complete():
		_finish_generation()


func _finish_generation() -> void:
	_loading_ui.visible = false
	var cx := int(WorldConfig.WORLD_WIDTH / 2.0)
	_camera.position = Vector2((cx + 0.5) * TILE, (_gen.surface_height(cx) - 4) * TILE)
	Game.set_state(Game.State.BUILD_PHASE)
	_gen = null
