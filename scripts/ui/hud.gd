## HUD: HP/mana bars, hotbar display, elevation readout. Bars and hotbar are
## purely signal-driven; only the elevation label polls, and only repaints on
## row change. Owning doc: docs/systems/ui.md
extends CanvasLayer

const _TILESET: TileSet = preload("res://assets/generated/terrain_tileset.tres")

const ICON_SIZE := 16
const SLOT_SIZE := Vector2(44, 44)
const SLOT_MARGIN := 6.0
const NORMAL_BG := Color(0, 0, 0, 0.45)
const SELECTED_BG := Color(0.95, 0.85, 0.3, 0.55)
const FALLBACK_COLOR := Color(0.6, 0.6, 0.6)

static var _icon_cache: Dictionary = { }

## Injected by tests before add_child; falls back to the live autoload.
var inventory: Inventory = null

var _player: Player = null
var _last_row := -(1 << 30)

var _slot_bgs: Array[ColorRect] = []
var _slot_icons: Array[TextureRect] = []
var _slot_counts: Array[Label] = []

@onready var _hp_bar: ProgressBar = %HPBar
@onready var _hp_label: Label = %HPLabel
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _mana_label: Label = %ManaLabel
@onready var _elevation_label: Label = %ElevationLabel
@onready var _hotbar: HBoxContainer = %Hotbar


func _ready() -> void:
	if inventory == null:
		inventory = Items.player_inventory
	for i in Inventory.HOTBAR_SIZE:
		_make_slot(i)
	inventory.slot_changed.connect(_on_slot_changed)
	inventory.selected_changed.connect(_on_selected_changed)
	for i in Inventory.HOTBAR_SIZE:
		_refresh_slot(i)
	_on_selected_changed(inventory.selected_slot)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var row := floori(_player.global_position.y / TileLayout.TILE_SIZE)
	if row == _last_row:
		return
	_last_row = row
	_elevation_label.text = elevation_text(_player.global_position.y)


## Called by main.gd once the player exists — its _ready (which seeds hp/mana)
## has already run, so the bars are seeded here instead of via the signals.
func bind_player(player: Player) -> void:
	_player = player
	player.health_changed.connect(_on_health_changed)
	player.mana_changed.connect(_on_mana_changed)
	_on_health_changed(player.current_hp, Progression.get_stat("max_hp"))
	_on_mana_changed(player.current_mana, Progression.get_stat("max_mana"))


## Icon = fully-surrounded autotile frame (mask 15, variant 0) of the id's
## atlas source; ids without tile art get a base_color swatch (gray if unknown).
static func icon_for(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var icon: Texture2D
	var source_id := Materials.ORDER.find(id)
	if source_id != -1:
		var src: TileSetAtlasSource = _TILESET.get_source(source_id)
		var atlas := AtlasTexture.new()
		atlas.atlas = src.texture
		atlas.region = Rect2(src.get_tile_texture_region(TileLayout.LAYOUT[15][0], 0))
		icon = atlas
	else:
		var mat: Dictionary = Materials.MATERIALS.get(id, { })
		var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(mat.get("base_color", FALLBACK_COLOR))
		icon = ImageTexture.create_from_image(image)
	_icon_cache[id] = icon
	return icon


static func biome_name(row: int) -> String:
	var clamped := clampi(row, 0, WorldConfig.WORLD_HEIGHT - 1)
	for band: Dictionary in Biomes.BANDS:
		if clamped >= band.row_begin and clamped < band.row_end:
			return band.name
	return "?" # Unreachable while BANDS covers [0, WORLD_HEIGHT).


static func elevation_text(global_y: float) -> String:
	var row := floori(global_y / TileLayout.TILE_SIZE)
	return "Elevation: %d — %s" % [row, biome_name(row)]


func _on_health_changed(current: float, max_value: float) -> void:
	_hp_bar.max_value = max_value
	_hp_bar.value = current
	_hp_label.text = "%d / %d" % [roundi(current), roundi(max_value)]


func _on_mana_changed(current: float, max_value: float) -> void:
	_mana_bar.max_value = max_value
	_mana_bar.value = current
	_mana_label.text = "%d / %d" % [roundi(current), roundi(max_value)]


func _on_slot_changed(index: int) -> void:
	if index < Inventory.HOTBAR_SIZE:
		_refresh_slot(index)


func _on_selected_changed(index: int) -> void:
	for i in Inventory.HOTBAR_SIZE:
		_slot_bgs[i].color = SELECTED_BG if i == index else NORMAL_BG


func _refresh_slot(index: int) -> void:
	var slot := inventory.get_slot(index)
	if slot.is_empty():
		_slot_icons[index].texture = null
		_slot_counts[index].text = ""
	else:
		_slot_icons[index].texture = icon_for(slot.id)
		_slot_counts[index].text = str(slot.count)


func _make_slot(index: int) -> void:
	var bg := ColorRect.new()
	bg.custom_minimum_size = SLOT_SIZE
	bg.color = NORMAL_BG
	_hotbar.add_child(bg)
	_slot_bgs.append(bg)

	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = SLOT_MARGIN
	icon.offset_top = SLOT_MARGIN
	icon.offset_right = -SLOT_MARGIN
	icon.offset_bottom = -SLOT_MARGIN
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.add_child(icon)
	_slot_icons.append(icon)

	var key := Label.new()
	key.text = str((index + 1) % 10) # Action hotbar_10 = key "0" = slot 9.
	key.add_theme_font_size_override("font_size", 10)
	key.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 3)
	bg.add_child(key)

	var count := Label.new()
	count.add_theme_font_size_override("font_size", 12)
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 3)
	count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bg.add_child(count)
	_slot_counts.append(count)
