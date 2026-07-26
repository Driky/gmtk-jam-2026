## HUD: HP/mana/XP bars, hotbar display, elevation readout, phase label
## (countdown, then "Wave n — X remaining"), Core HP bar, rejection toasts. Bars, hotbar, and
## phase widgets are purely
## signal-driven; only the elevation label polls, and only repaints on row
## change. The countdown presentation (big timer, last-10s red pulse, wave
## announce) is a never-cut item — docs/plan.md. Owning doc: docs/systems/ui.md
class_name Hud
extends CanvasLayer

const _TILESET: TileSet = preload("res://assets/generated/terrain_tileset.tres")

const ICON_SIZE := 16
const SLOT_SIZE := Vector2(44, 44)
const SLOT_MARGIN := 6.0
const NORMAL_BG := Color(0, 0, 0, 0.45)
const SELECTED_BG := Color(0.95, 0.85, 0.3, 0.55)
const FALLBACK_COLOR := Color(0.6, 0.6, 0.6)

const FINAL_COLOR := Color(1.0, 0.35, 0.3)
const PULSE_ALPHA := 0.18
const PULSE_FADE := 0.5
const BANNER_HOLD := 1.5
const BANNER_FADE := 0.5

## Shorter than the banner: a rejected click is a nudge, not an announcement,
## and it must be gone before you have finished re-aiming.
const TOAST_HOLD := 1.2
const TOAST_FADE := 0.4

## Set in _ready, cleared in _exit_tree — the ProjectilePool.fire trick, so
## call sites need no node path and the fixed autoload map in tech-design.md
## stays untouched. Inert with no HUD in the tree, so tests are unaffected.
static var _instance: Hud = null

static var _icon_cache: Dictionary = { }

## Injected by tests before add_child; falls back to the live autoload.
var inventory: Inventory = null
## Injected by tests before add_child; falls back to the live autoload.
var game: Node = null
## Injected by tests before add_child; falls back to the live autoload. The
## remaining-mob count is Waves' own data, not phase flow, so it doesn't route
## through Game (signal-hub note in game.gd).
var waves: Node = null
## Injected by tests before add_child; falls back to the live autoload.
var progression: Node = null
## Injected by tests before add_child; falls back to the live autoload. Drives
## the idle-machine counter, same test seam as `game`/`waves`/`progression`.
var automation: Node = null

var _player: Player = null
var _last_row := -(1 << 30)
var _banner_tween: Tween = null
var _toast_tween: Tween = null
var _toast_message := ""
var _wave_number := 0

var _slot_bgs: Array[ColorRect] = []
var _slot_icons: Array[TextureRect] = []
var _slot_counts: Array[Label] = []

@onready var _hp_bar: ProgressBar = %HPBar
@onready var _hp_label: Label = %HPLabel
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _mana_label: Label = %ManaLabel
@onready var _elevation_label: Label = %ElevationLabel
@onready var _hotbar: HBoxContainer = %Hotbar
@onready var _phase_label: Label = %PhaseLabel
@onready var _core_bar: ProgressBar = %CoreBar
@onready var _wave_banner: Label = %WaveBanner
@onready var _pulse_overlay: ColorRect = %PulseOverlay
@onready var _xp_bar: ProgressBar = %XPBar
@onready var _xp_label: Label = %XPLabel
@onready var _toast: Label = %Toast
@onready var _idle_alert: Label = %IdleAlert


func _ready() -> void:
	_instance = self
	if inventory == null:
		inventory = Items.player_inventory
	if game == null:
		game = Game
	if waves == null:
		waves = Waves
	if progression == null:
		progression = Progression
	if automation == null:
		automation = Automation
	for i in Inventory.HOTBAR_SIZE:
		_make_slot(i)
	inventory.slot_changed.connect(_on_slot_changed)
	inventory.selected_changed.connect(_on_selected_changed)
	for i in Inventory.HOTBAR_SIZE:
		_refresh_slot(i)
	_on_selected_changed(inventory.selected_slot)
	game.countdown_tick.connect(_on_countdown_tick)
	game.wave_started.connect(_on_wave_started)
	game.wave_cleared.connect(_on_wave_cleared)
	waves.wave_progress_changed.connect(_on_wave_progress_changed)
	progression.xp_changed.connect(_on_xp_changed)
	progression.leveled_up.connect(_on_leveled_up)
	automation.idle_machines_changed.connect(_on_idle_machines_changed)
	# Seeded like the XP bar rather than waiting for a transition: a run resumed
	# with an already-exhausted miner (4.3) must show the alert immediately.
	_on_idle_machines_changed(automation.idle_machines())
	# Seeded here rather than waiting for the first grant: a run that starts
	# mid-level (a reload, 4.3) must not show an empty bar until something dies.
	_on_xp_changed(progression.xp, progression.xp_needed(), progression.level)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## The one entry point for rejection feedback. Static because the call sites are
## many and unrelated (buffer-zone placement today; 3.1 alone adds buffer,
## validity, power coverage and the exhausted-deposit miner alert), and none of
## them should own a path to this node. No-ops without a HUD in the tree.
static func show_toast(message: String) -> void:
	if _instance != null:
		_instance.toast(message)


## Its own widget and its own tween, NOT a reuse of the wave banner: a rejected
## click must never blot out a fight.
##
## ❗️The repeat guard is not optional. Placement polls input every physics
## frame, so a held RMB against a buffer fires this 60x/second — without
## absorbing identical repeats the tween restarts every frame and the toast
## never fades. It would ship visibly broken.
func toast(message: String) -> void:
	if message == _toast_message and _toast_tween != null and _toast_tween.is_valid():
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_message = message
	_toast.text = message
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE)
	_toast_tween.tween_callback(
		func() -> void:
			_toast.visible = false
			# Cleared so the SAME message can toast again later; the guard only
			# ever absorbs repeats while one is still on screen.
			_toast_message = "",
	)


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
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)
	_on_health_changed(player.current_hp, Progression.get_stat("max_hp"))
	_on_mana_changed(player.current_mana, Progression.get_stat("max_mana"))


## Called by main.gd once the Core exists; seeds the bar like bind_player.
func bind_core(core: Node) -> void:
	core.health_changed.connect(_on_core_health_changed)
	_on_core_health_changed(core.current_hp, core.MAX_HP)


## Icon = fully-surrounded autotile frame (mask 15, variant 0) of the id's
## atlas source; ids without tile art get a flat swatch — an authored item's
## icon_color, else the material's base_color, else gray.
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
		var color: Color = mat.get("base_color", FALLBACK_COLOR)
		if ItemDefs.STATS.has(id):
			color = (ItemDefs.STATS[id] as ItemStats).icon_color
		var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(color)
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


## ❗️ASCII on purpose. The bundled Open Sans has no U+26A0 warning sign, and a
## missing glyph renders as a blank box — a "warning" that looks like a bug.
static func idle_text(count: int) -> String:
	return "[!] %d idle machine%s" % [count, "" if count == 1 else "s"]


static func format_time(seconds_left: int) -> String:
	return "%d:%02d" % [floori(seconds_left / 60.0), seconds_left % 60]


static func wave_text(wave_number: int, remaining: int) -> String:
	return "Wave %d — %d remaining" % [wave_number, remaining]


## Level first: it's the number worth reading at a glance, and the raw XP
## behind it is only interesting while you're watching the bar fill.
static func xp_text(level: int, current: float, needed: float) -> String:
	return "Lv %d — %d / %d" % [level, floori(current), roundi(needed)]


func _on_health_changed(current: float, max_value: float) -> void:
	_hp_bar.max_value = max_value
	_hp_bar.value = current
	_hp_label.text = "%d / %d" % [roundi(current), roundi(max_value)]


func _on_mana_changed(current: float, max_value: float) -> void:
	_mana_bar.max_value = max_value
	_mana_bar.value = current
	_mana_label.text = "%d / %d" % [roundi(current), roundi(max_value)]


func _on_core_health_changed(current: float, max_value: float) -> void:
	_core_bar.max_value = max_value
	_core_bar.value = current


func _on_xp_changed(current: float, needed: float, level: int) -> void:
	_xp_bar.max_value = needed
	_xp_bar.value = current
	_xp_label.text = xp_text(level, current, needed)


## Reuses the wave banner rather than growing a screen: a level-up is worth
## announcing, not worth interrupting a fight for. The upgrade point it grants
## has nowhere to be spent until the skill tree (3.7), so it isn't advertised.
func _on_leveled_up(level: int, _points: int) -> void:
	_announce("Level %d!" % level)


## Reuses the wave banner rather than growing a screen — a run continues
## through a player death (the Core is the loss condition), so this is an
## announcement, not an interruption. The real death screen is 4.5.
func _on_player_died(respawn_seconds: float) -> void:
	_announce("You died — respawning in %ds" % roundi(respawn_seconds))


func _on_player_respawned() -> void:
	_announce("Respawned at the Core")


## A PERSISTENT count, not a toast. A miner runs its deposit dry while you are
## somewhere else entirely — a toast that fires the moment it happens is a
## notification you were never looking at, where a count is still there when you
## come back. Hidden at zero, so a factory with nothing wrong shows nothing.
func _on_idle_machines_changed(count: int) -> void:
	_idle_alert.visible = count > 0
	if count > 0:
		_idle_alert.text = idle_text(count)


func _on_countdown_tick(seconds_left: int) -> void:
	_phase_label.text = format_time(seconds_left)
	var final_window: bool = seconds_left <= game.FINAL_WINDOW
	_phase_label.modulate = FINAL_COLOR if final_window else Color.WHITE
	if final_window and seconds_left > 0:
		_pulse()


func _on_wave_started(wave_number: int) -> void:
	_wave_number = wave_number
	_phase_label.modulate = Color.WHITE
	_phase_label.scale = Vector2.ONE
	_refresh_wave_label()
	_announce("Wave %d" % wave_number)


func _on_wave_progress_changed(_remaining: int) -> void:
	_refresh_wave_label()


## Reads waves.remaining() rather than trusting the signal payload: Waves is an
## autoload, so its wave_started handler runs before this node's — a
## payload-driven label would be written before the queue exists. Skipped
## outside WAVE_PHASE so a death during the grace beat can't overwrite the
## countdown that _on_countdown_tick just put there.
func _refresh_wave_label() -> void:
	if game.state != game.State.WAVE_PHASE:
		return
	_phase_label.text = wave_text(_wave_number, waves.remaining())


func _on_wave_cleared(wave_number: int) -> void:
	_announce("Wave %d cleared!" % wave_number)


## Screen pulse + label pop for the last-10s countdown (Compatibility-safe:
## plain alpha/scale tweens, no shaders).
func _pulse() -> void:
	_pulse_overlay.color.a = PULSE_ALPHA
	_phase_label.pivot_offset = _phase_label.size / 2.0
	_phase_label.scale = Vector2(1.2, 1.2)
	var tween := create_tween()
	tween.tween_property(_pulse_overlay, "color:a", 0.0, PULSE_FADE)
	tween.parallel().tween_property(_phase_label, "scale", Vector2.ONE, PULSE_FADE)


func _announce(message: String) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_wave_banner.text = message
	_wave_banner.visible = true
	_wave_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(BANNER_HOLD)
	_banner_tween.tween_property(_wave_banner, "modulate:a", 0.0, BANNER_FADE)
	_banner_tween.tween_callback(func() -> void: _wave_banner.visible = false)


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
