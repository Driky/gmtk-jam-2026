## Boot driver: amortized world generation behind the loading bar, then the
## player spawns on the flat center column. Owning doc: docs/roadmap.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
const PlayerScene := preload("res://scenes/player.tscn")
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
	var surface_row: int = _gen.surface_height(cx)
	_camera.enabled = false # Static view during GENERATING; player camera takes over.
	var player: CharacterBody2D = PlayerScene.instantiate()
	# Feet on the surface tile top (center is 11 px up), 1 px slack against overlap.
	player.position = Vector2((cx + 0.5) * TILE, surface_row * TILE - 12)
	add_child(player)
	Game.set_state(Game.State.BUILD_PHASE)
	_gen = null
