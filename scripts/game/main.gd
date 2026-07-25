## Boot driver: amortized world generation behind the loading bar, then the
## player spawns on the flat center column. Owning doc: docs/roadmap.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
const PlayerScene := preload("res://scenes/player.tscn")
const CoreScene := preload("res://scenes/core.tscn")
## The Core owns the exact center column (flow-field origin, 2.2); the
## player spawns beside it, still on the guaranteed-flat span.
const PLAYER_SPAWN_OFFSET_X := 3
## Debug: set non-zero to force a seed (menu seed entry is a Day-4 stretch).
const FORCED_SEED := 0

var _gen: WorldGen

@onready var _loading_ui: CanvasLayer = %LoadingUI
@onready var _loading_bar: ProgressBar = %LoadingBar
@onready var _hud: CanvasLayer = %HUD
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	Game.world_seed = FORCED_SEED if FORCED_SEED != 0 else randi()
	# MENU is an instant pass-through until the real main menu lands (4.5).
	Game.set_state(Game.State.MENU)
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
	var core: Node2D = CoreScene.instantiate()
	core.setup(cx, surface_row)
	add_child(core)
	var registered: bool = core.register_footprint(Terrain)
	assert(registered) # The flat spawn area guarantees air cells.
	core.died.connect(Game.game_over)
	var player: CharacterBody2D = PlayerScene.instantiate()
	# Feet on the surface tile top (center is 11 px up), 1 px slack against overlap.
	player.position = Vector2((cx + PLAYER_SPAWN_OFFSET_X + 0.5) * TILE, surface_row * TILE - 12)
	add_child(player)
	_hud.bind_player(player)
	_hud.bind_core(core)
	_hud.visible = true
	Game.start_build_phase()
	_gen = null
