## One debug panel behind F3, replacing the scatter of F-keys that each owned
## one trick. Adding a debug affordance is now a row here, not another global
## keybinding to remember and collide with.
##
## Only mob spawning keeps a key (F4): it needs the cursor to say *where*, and
## no button can express that.
##
## `is_open` is static and read by the Player, mirroring how `Perf` avoids an
## autoload slot. Gameplay input is polled from `Input` directly rather than
## routed through the UI, so without that flag every click on a button would
## also swing at the world behind it.
## Owning doc: docs/systems/ui.md
class_name DebugMenu
extends CanvasLayer

## True while the panel is showing. Gameplay reads this to ignore clicks that
## are meant for the panel.
static var is_open := false

## Above the HUD (0) and the game-over screen (10); below the perf readout
## (100), which must stay legible on top of everything.
const LAYER := 50
const PANEL_SIZE := Vector2(232.0, 0.0)
const MARGIN := Vector2(12.0, 96.0) ## Clears the HUD bars on the left.

## Test loot: one stack of every ordinary material. Deliberately more stacks
## than the 10-slot hotbar, so the overflow lands past it and a death actually
## has something to put in a loot bag ([player-combat.md](../../docs/systems/player-combat.md)).
const LOOT_STACK := 50

## One press of the XP button. Sized past the first level's cost so a single
## click always visibly does something — levelling is otherwise a long grind
## to reach by hand ([progression.md](../../docs/systems/progression.md)).
const XP_GRANT := 100.0

## Enough of whatever you picked to actually try something with it.
const GIVE_DEFAULT_COUNT := 20

## The factory test rig (3.3). A production chain needs a deposit, and deposits
## only generate underground — so checking one by hand means digging twenty rows
## and hoping. This carves a flat pocket beside the player, lays a short
## `copper_deposit` seam at one end and stocks the hotbar, which is the whole
## setup for `miner → inserter → belt → inserter → furnace` in one press.
##
## ❗️It exists because the WEB build has no other way in: there is no console in
## an exported build, so the browser check of the tick — the one place
## `MAX_CATCH_UP` and the deposit-exhaustion path are real — was otherwise a
## twenty-minute dig every time ([automation.md](../../docs/systems/automation.md)).
const RIG_ORE_MATERIAL := "copper_deposit"
const RIG_ORE_WIDTH := 3
const RIG_HEIGHT := 4
const RIG_WIDTH := 22
## Clear of the player's own body, so the pocket does not carve him out of the
## floor he is standing on.
const RIG_OFFSET := Vector2i(3, 1)
## Everything the chain is built from, at a count that leaves room to make
## mistakes.
const RIG_KIT: Array[String] = ["miner", "inserter", "conveyor_t1", "furnace"]
const RIG_KIT_COUNT := 10

## Injected by tests; fall back to the autoloads.
var game: Node = null
var waves: Node = null
var items: Node = null
var progression: Node = null
var terrain: Node = null
## Set by main.gd before add_child — the overlays this panel drives.
var flow_overlay: Node2D = null
var slot_overlay: Node2D = null
var perf_overlay: CanvasLayer = null
## The light grid's render pass. Hiding it IS full bright (terrain.md §Lighting).
var light_map: Node2D = null

var _rows: VBoxContainer = null
var _give_id: OptionButton = null
var _give_count: SpinBox = null


func _ready() -> void:
	if game == null:
		game = Game
	if waves == null:
		waves = Waves
	if items == null:
		items = Items
	if progression == null:
		progression = Progression
	if terrain == null:
		terrain = Terrain
	layer = LAYER
	# Usable while the tree is paused (the game-over screen pauses it).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_set_open(false)


func _exit_tree() -> void:
	is_open = false # Never leave the flag set for the next scene.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug_menu"):
		_set_open(not visible)


## Public so tests can drive it without synthesising input.
func toggle() -> void:
	_set_open(not visible)


func _set_open(open: bool) -> void:
	visible = open
	is_open = open

# --- Actions -----------------------------------------------------------------


## Enough stacks to overflow the hotbar, so the surplus sits in slots 10+ and
## dying leaves a bag worth walking back to.
func give_test_loot() -> void:
	for id in Materials.ORDER:
		var mat: Dictionary = Materials.MATERIALS[id]
		if mat.is_deposit or mat.min_tool_tier >= 99:
			continue # Deposits aren't items; bedrock never drops.
		items.player_inventory.add_item(id, LOOT_STACK)


## Carve the factory pocket beside the player and hand over the kit. Returns the
## pocket's top-left cell so a test can assert against it without re-deriving the
## geometry.
##
## The seam sits at the pocket's RIGHT end and is two rows tall, so a miner
## placed against it faces RIGHT and its harvest block lands on the ore — the
## placement the ghost is trying to teach. The floor under the pocket is stone,
## because a `support_dirs = 15` machine standing in a carved hole needs
## something solid to hold it up.
func build_factory_rig() -> Vector2i:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return Vector2i.ZERO
	var at := Vector2i((player.global_position / TileLayout.TILE_SIZE).floor()) + RIG_OFFSET
	for dx in RIG_WIDTH:
		for dy in RIG_HEIGHT:
			terrain.set_tile(at + Vector2i(dx, dy), "")
		terrain.set_tile(at + Vector2i(dx, RIG_HEIGHT), "stone")
	for dx in RIG_ORE_WIDTH:
		for dy in 2:
			var ore := at + Vector2i(RIG_WIDTH - 1 - dx, RIG_HEIGHT - 2 + dy)
			terrain.set_tile(ore, RIG_ORE_MATERIAL)
	for id: String in RIG_KIT:
		items.player_inventory.add_item(id, RIG_KIT_COUNT)
	return at


## Levelling by hand means mining hundreds of blocks; this is how the level-up
## path (stat grant, banner, bar rebase) gets exercised on demand.
func grant_xp() -> void:
	progression.grant_xp("debug", XP_GRANT)


func kill_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	# Clear the grace window first, or a recent hit silently eats this.
	player._invuln_left = 0.0
	player.take_damage(INF)


## Every item worth handing out by name: authored items first, then ordinary
## materials. Deposits are terrain features rather than items and bedrock never
## drops, so neither can end up in the inventory as an unplaceable id — the same
## rule give_test_loot uses.
static func giveable_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id: String in ItemDefs.STATS:
		ids.append(id)
	for id: String in Materials.ORDER:
		var mat: Dictionary = Materials.MATERIALS[id]
		if mat.is_deposit or mat.min_tool_tier >= 99:
			continue
		if not ids.has(id):
			ids.append(id)
	return ids


## Hand over an arbitrary stack. Kept ALONGSIDE give_test_loot rather than
## replacing it: that row is a one-click fixture that deliberately overflows the
## hotbar for the loot-bag flow, and reproducing it through this dropdown is 16
## interactions. Two rows, two purposes (ui.md).
func give_item(id: String, count: int) -> void:
	if id == "" or count <= 0:
		return
	items.player_inventory.add_item(id, count)


## Answers "is this dark because of the depth, or because my light is broken",
## and is how the itch screenshots get taken. Tolerates a missing light map so
## every row stays clickable in a stripped build or a test harness.
func _toggle_full_bright(pressed: bool) -> void:
	if light_map != null:
		light_map.visible = not pressed


func _give_pressed() -> void:
	if _give_id == null or _give_id.selected < 0:
		return
	give_item(_give_id.get_item_text(_give_id.selected), int(_give_count.value))


func _toggle_flow_overlay(pressed: bool) -> void:
	if flow_overlay != null:
		flow_overlay.visible = pressed


## Automation slot occupancy, counts, facings and cooldowns — the visible half of
## the tick-bug mitigation ([plan.md](../../docs/plan.md) names tick bugs the
## top-listed risk). A row rather than a hotkey, per this doc's own rule that
## debug overlays own no keybindings.
func _toggle_slot_overlay(pressed: bool) -> void:
	if slot_overlay != null:
		slot_overlay.visible = pressed


func _toggle_perf_overlay(pressed: bool) -> void:
	if perf_overlay == null:
		return
	perf_overlay.visible = pressed
	if pressed:
		perf_overlay.reset_stats() # Turning it on means "measure from here".

# --- Layout ------------------------------------------------------------------


func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = MARGIN
	panel.custom_minimum_size = PANEL_SIZE
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	_rows = VBoxContainer.new()
	margin.add_child(_rows)

	_title("Debug — F3")
	_check("Flow field overlay", _toggle_flow_overlay)
	_check("Automation slots", _toggle_slot_overlay)
	_check("Perf readout", _toggle_perf_overlay)
	_check("Full bright", _toggle_full_bright)
	_button("Skip countdown", func() -> void: game.skip_countdown())
	_button("Clear wave", func() -> void: waves.debug_clear_wave())
	_button("Poke nearest mob", func() -> void: waves.debug_poke_nearest())
	_button("Give test loot", give_test_loot)
	_button("Build factory rig", build_factory_rig)
	_give_row()
	_button("Grant %d XP" % roundi(XP_GRANT), grant_xp)
	_button("Kill player", kill_player)
	_title("F4 — spawn mob at cursor")


## Item dropdown + quantity + Give, on one line.
func _give_row() -> void:
	var row := HBoxContainer.new()
	_rows.add_child(row)

	_give_id = OptionButton.new()
	_give_id.fit_to_longest_item = false
	_give_id.custom_minimum_size = Vector2(96.0, 0.0)
	for id in giveable_ids():
		_give_id.add_item(id)
	row.add_child(_give_id)

	_give_count = SpinBox.new()
	_give_count.min_value = 1
	_give_count.max_value = 999
	_give_count.value = GIVE_DEFAULT_COUNT
	_give_count.custom_minimum_size = Vector2(56.0, 0.0)
	row.add_child(_give_count)

	var button := Button.new()
	button.text = "Give"
	button.pressed.connect(_give_pressed)
	row.add_child(button)


func _title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	_rows.add_child(label)


func _check(text: String, on_toggled: Callable) -> void:
	var check := CheckButton.new()
	check.text = text
	check.toggled.connect(on_toggled)
	_rows.add_child(check)


func _button(text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	_rows.add_child(button)
