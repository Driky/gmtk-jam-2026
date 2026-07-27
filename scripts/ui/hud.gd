## HUD: HP/mana/XP bars, hotbar display, elevation readout, phase label
## (countdown, then "Wave n — X remaining"), Core HP bar, rejection toasts. Bars, hotbar, and
## phase widgets are purely
## signal-driven; only the elevation label polls, and only repaints on row
## change. The countdown presentation (big timer, last-10s red pulse, wave
## announce) is a never-cut item — docs/plan.md. Owning doc: docs/systems/ui.md
class_name Hud
extends CanvasLayer

const _TILESET: TileSet = preload("res://assets/generated/terrain_tileset.tres")

## The fallback swatch's pixel size. ⚠️ Stays here rather than moving to
## `ItemSlot` with the layout constants: `icon_for` below is its only reader, and
## parking it on the widget would leave this script reaching back into the class
## it constructs, which is the cycle the extraction exists to avoid.
const ICON_SIZE := 16
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

## Cursor inspector: offset from the pointer, and the margin it keeps from the
## screen edge. Below-right of the cursor, because that is the quadrant the
## arrow itself does not cover.
const INSPECT_OFFSET := Vector2(18.0, 14.0)
const INSPECT_MARGIN := 6.0

## Set in _ready, cleared in _exit_tree — the ProjectilePool.fire trick, so
## call sites need no node path and the fixed autoload map in tech-design.md
## stays untouched. Inert with no HUD in the tree, so tests are unaffected.
static var _instance: Hud = null

static var _icon_cache: Dictionary = { }

## Is the cursor inspector showing? Static and driven through the F3 row, the
## same shape `DebugMenu.is_open` uses — so the toggle needs no node path and
## survives the HUD not being in the tree at all.
static var inspector_enabled := true

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

## The hotbar row. ONE array of `ItemSlot`s since 3.6a, replacing the three
## parallel arrays this used to keep — the character screen needs 68 more of these
## widgets, and a fourth set of parallel arrays was the copy that would drift.
var _slots: Array[ItemSlot] = []

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
@onready var _selected_label: Label = %SelectedLabel
@onready var _inspect_label: Label = %InspectLabel


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
	_refresh_inspector()
	var row := floori(_player.global_position.y / TileLayout.TILE_SIZE)
	if row == _last_row:
		return
	_last_row = row
	_elevation_label.text = elevation_text(_player.global_position.y)

# --- Cursor inspector --------------------------------------------------------


## Toggled from the F3 row. Static and inert without a HUD, mirroring
## `show_toast` — the debug menu owns no path to this node.
static func set_inspector_enabled(enabled: bool) -> void:
	inspector_enabled = enabled
	if _instance != null and not enabled:
		_instance._inspect_label.visible = false


## Name whatever the pointer is over, once per frame. Polled rather than
## signal-driven because the *cursor* is what changes, and nothing emits when a
## mouse moves over a tile.
##
## Precedence mirrors what a click would actually do, so the label can never
## name something other than what you are about to act on: a hotbar slot (a UI
## element, and the only screen-space case) → a mob → a deployable → the tile.
func _refresh_inspector() -> void:
	if not inspector_enabled:
		return
	# ⚠️ Gated at 3.6a, and it is not just tidiness. `_hovered_slot` hit-tests only
	# the ten hotbar rects, so hovering the character screen's grid falls through to
	# a `Terrain.get_entity` probe plus a full enemies-group loop every frame — and
	# names the tile *behind* the window, invisible under layer 5 and still costing.
	# The slot tooltips are the readout over the grid.
	if UiState.blocks_gameplay_actions():
		_inspect_label.visible = false
		return
	var at := get_viewport().get_mouse_position()
	var text := _inspect_text(at)
	_inspect_label.visible = text != ""
	if text == "":
		return
	_inspect_label.text = text
	# Placed after the text is set: the label has to have resized before it can
	# be kept on screen, or a long name runs off the right edge for one frame.
	_inspect_label.reset_size()
	var screen := get_viewport().get_visible_rect().size
	var box := _inspect_label.size
	# ❗️Flipped ABOVE the cursor near the bottom edge rather than clamped down
	# onto it — hovering a hotbar slot is the common case, and a clamped label
	# lands squarely on the slots either side of the one it is naming.
	var y := at.y + INSPECT_OFFSET.y
	if y + box.y > screen.y - INSPECT_MARGIN:
		y = at.y - box.y - INSPECT_OFFSET.y
	_inspect_label.position = Vector2(
		clampf(at.x + INSPECT_OFFSET.x, INSPECT_MARGIN, screen.x - box.x - INSPECT_MARGIN),
		clampf(y, INSPECT_MARGIN, screen.y - box.y - INSPECT_MARGIN),
	)


func _inspect_text(at: Vector2) -> String:
	var slot := _hovered_slot(at)
	if slot >= 0:
		var stack := inventory.get_slot(slot)
		return "" if stack.is_empty() else "%s ×%d" % [item_name(stack.id), stack.count]
	var cell: Vector2i = _player.target_tile()
	var enemy := _enemy_at(cell)
	if enemy != null:
		return "%s — %d/%d HP" % [
			item_name(enemy.stats.display_name),
			roundi(enemy.current_hp),
			roundi(enemy.stats.max_hp),
		]
	# `as Deployable`, so the Core stays anonymous exactly as it stays
	# un-removable — it is deliberately not one of these.
	var deployable := Terrain.get_entity(cell) as Deployable
	if deployable != null:
		return item_name(deployable.item_id)
	return tile_text(Terrain.get_tile_data(cell))


## An empty cell reads as nothing at all rather than "Air": naming the absence
## of a tile is noise on every second pixel of the screen. A deposit carries its
## remaining ore, which is the one number that decides where a miner goes.
static func tile_text(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	var name := item_name(data.material_id)
	if data.is_deposit:
		return "%s — %d ore left" % [name, data.reserve]
	return name


## Which hotbar slot the pointer is over, or -1. Hit-tested against the slot
## backgrounds themselves, so it cannot drift from where they were laid out.
func _hovered_slot(at: Vector2) -> int:
	for i in _slots.size():
		if _slots[i].get_global_rect().has_point(at):
			return i
	return -1


## Mobs are roughly a tile, so "same cell as the hovered tile" is both accurate
## enough and free — no physics query, no per-frame distance sort.
func _enemy_at(cell: Vector2i) -> Enemy:
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		if Vector2i((enemy.global_position / TileLayout.TILE_SIZE).floor()) == cell:
			return enemy
	return null


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


## THE display name for any item or tile id, and the one place that question is
## answered — the hotbar readout, the cursor inspector and anything later that
## needs to say "Copper Deposit" out loud all come here.
##
## ❗️It cannot just read `Items.stats_for(id).display_name`: every plain block
## resolves to the shared `BLOCK_DEFAULT`, whose name is the literal word
## "Block", so a hundred materials would all introduce themselves identically.
## Authored items win; everything else is its own id, title-cased — Godot's
## `capitalize()` already turns `copper_deposit` into `Copper Deposit`, so
## materials need no second name table to drift from `materials.gd`.
static func item_name(id: String) -> String:
	if id == "":
		return ""
	if ItemDefs.STATS.has(id):
		var authored: String = (ItemDefs.STATS[id] as ItemStats).display_name
		if authored != "":
			return authored
	return id.capitalize()


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


## Names where you actually woke up. The player hands over the FACT and the HUD
## picks the words — a beacon (3.5c) can be halfway across the map, so a fixed
## "at the Core" would be the banner lying about the one thing it reports.
func _on_player_respawned(at_beacon: bool) -> void:
	_announce("Respawned at a beacon" if at_beacon else "Respawned at the Core")


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
	# Mining the last of a stack changes what is in hand without the selection
	# moving, so the name has to follow the slot edit as well as the selection.
	if index == inventory.selected_slot:
		_refresh_selected_label()


func _on_selected_changed(index: int) -> void:
	for i in Inventory.HOTBAR_SIZE:
		_slots[i].set_selected(i == index)
	_refresh_selected_label()


## What is actually in your hand, above the hotbar. An empty slot names **bare
## hands** rather than going blank, because that is what LMB will swing with —
## the same resolution `Items.selected_stats()` does, said out loud.
func _refresh_selected_label() -> void:
	var stack := inventory.selected_item()
	var id: String = stack.get("id", "")
	_selected_label.text = ItemDefs.BARE_HAND.display_name if id == "" else item_name(id)


func _refresh_slot(index: int) -> void:
	_slots[index].set_stack(inventory.get_slot(index))


## The hotbar's ten widgets, key-labelled — the one thing that distinguishes them
## from the character screen's grid slots (action hotbar_10 = key "0" = slot 9).
func _make_slot(index: int) -> void:
	var slot := ItemSlot.new(index, str((index + 1) % 10))
	_hotbar.add_child(slot)
	_slots.append(slot)
