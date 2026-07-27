## Boot driver: amortized world generation behind the loading bar, then the
## player spawns on the flat center column. Owning doc: docs/roadmap.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
const PlayerScene := preload("res://scenes/player.tscn")
const CoreScene := preload("res://scenes/core.tscn")
const FlowFieldOverlay := preload("res://scripts/waves/flow_field_overlay.gd")
const ConveyorItemLayer := preload("res://scripts/automation/conveyor_item_layer.gd")
const SlotOverlay := preload("res://scripts/automation/slot_overlay.gd")
const PowerOverlay := preload("res://scripts/automation/power_overlay.gd")
const PerfOverlay := preload("res://scripts/debug/perf_overlay.gd")
const DebugMenuScript := preload("res://scripts/debug/debug_menu.gd")
## The Core owns the exact center column (flow-field origin, 2.2); the
## player spawns beside it, still on the guaranteed-flat span.
const PLAYER_SPAWN_OFFSET_X := 3
## Debug: set non-zero to force a seed (menu seed entry is a Day-4 stretch).
const FORCED_SEED := 0

var _gen: WorldGen

@onready var _loading_ui: CanvasLayer = %LoadingUI
@onready var _loading_bar: ProgressBar = %LoadingBar
@onready var _hud: CanvasLayer = %HUD
@onready var _game_over_ui: CanvasLayer = %GameOverUI
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	Game.state_changed.connect(_on_state_changed)
	_game_over_ui.restart_requested.connect(_restart)
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
	# Field + untouched-terrain baseline: Core registered, zero player edits.
	Waves.initialize_flow_field(core)
	# Items on belts: a world-space layer like the tilemap, under the light map so
	# they are lit rather than glowing ([automation.md](../../docs/systems/automation.md)).
	add_child(ConveyorItemLayer.new())
	# Debug overlays own no keybindings — the F3 menu drives their visibility.
	var flow_overlay := FlowFieldOverlay.new()
	add_child(flow_overlay)
	var slot_overlay := SlotOverlay.new()
	add_child(slot_overlay)
	# ❗️NOT a debug overlay and deliberately not handed to the F3 panel: the bolt
	# layer is always on, and `P` toggles its coverage circles
	# ([ui.md](../../docs/systems/ui.md) — the one sanctioned keybinding exception).
	add_child(PowerOverlay.new())
	var perf_overlay := PerfOverlay.new()
	add_child(perf_overlay)
	var debug_menu: CanvasLayer = DebugMenuScript.new()
	debug_menu.flow_overlay = flow_overlay
	debug_menu.slot_overlay = slot_overlay
	debug_menu.perf_overlay = perf_overlay
	debug_menu.light_map = %LightMap
	perf_overlay.light_map = %LightMap
	add_child(debug_menu)
	_seed_starting_kit()
	var player: CharacterBody2D = PlayerScene.instantiate()
	# Feet on the surface tile top (center is 11 px up), 1 px slack against overlap.
	player.position = Vector2((cx + PLAYER_SPAWN_OFFSET_X + 0.5) * TILE, surface_row * TILE - 12)
	add_child(player)
	_hud.bind_player(player)
	_hud.bind_core(core)
	_hud.visible = true
	Game.start_build_phase()
	_gen = null

## Placeholder starting inventory. Bare hands mine at 2.0 hardness/s, so a run
## has to open with a tool or the first minute is a slog; torches because depth
## is where the good ore is and depth is dark, so a run that opens without light
## cannot descend at all ([terrain.md](../../docs/systems/terrain.md) §Lighting).
## Crafting (4.2) is what eventually replaces the hand-out.
##
## Data rather than a sequence of calls so a test can assert what a run opens
## with — this list was silently emptied of its torches once by a stray
## `git checkout` and nothing caught it but a screenshot.
##
## ❗️**Every entry costs a HOTBAR slot, and there are only ten.** The kit is
## added first, so anything handed over later — the F3 rig's machines, a wave's
## loot — lands behind it, and past slot ten it is unreachable until 3.6 builds
## the inventory UI. 3.5a hit exactly that: the rig's kit overflowed and the coal
## fell off the end, leaving a chain that could never be fuelled
## ([ui.md](../../docs/systems/ui.md)). Keep this list as short as a run needs.
##
## ⚠️ `bolt_caster` was dropped at 3.5a. `data/item_defs.gd` had always said it
## existed only "before 3.5's turrets depend on it" — the turret is a live
## consumer of the pooled projectile system now, so the placeholder no longer
## earns a permanent slot. It is still an authored item and still in the F3
## give-item dropdown, so the player's ranged path stays one click away.
const STARTING_KIT: Array[Array] = [
	["pickaxe_t1", 1],
	["torch", 20],
]


## Seeded BEFORE the player exists so its _ready equips slot 0 straight away.
func _seed_starting_kit() -> void:
	for entry: Array in STARTING_KIT:
		Items.player_inventory.add_item(entry[0], entry[1])


func _on_state_changed(state: Game.State) -> void:
	if state != Game.State.GAME_OVER:
		return
	# Freeze gameplay under the stats screen (GameOverUI runs ALWAYS).
	get_tree().paused = true
	_game_over_ui.open(Game.get_run_stats())


func _restart() -> void:
	get_tree().paused = false # A reload does NOT unpause — clear it first.
	Terrain.reset_run()
	Automation.reset_run()
	Items.reset_run()
	Waves.reset_run()
	Game.reset_run()
	get_tree().reload_current_scene() # Fresh seed via _ready's randi().
