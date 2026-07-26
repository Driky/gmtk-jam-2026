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

## Injected by tests; fall back to the autoloads.
var game: Node = null
var waves: Node = null
var items: Node = null
var progression: Node = null
## Set by main.gd before add_child — the overlays this panel drives.
var flow_overlay: Node2D = null
var perf_overlay: CanvasLayer = null

var _rows: VBoxContainer = null


func _ready() -> void:
	if game == null:
		game = Game
	if waves == null:
		waves = Waves
	if items == null:
		items = Items
	if progression == null:
		progression = Progression
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


func _toggle_flow_overlay(pressed: bool) -> void:
	if flow_overlay != null:
		flow_overlay.visible = pressed


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
	_check("Perf readout", _toggle_perf_overlay)
	_button("Skip countdown", func() -> void: game.skip_countdown())
	_button("Clear wave", func() -> void: waves.debug_clear_wave())
	_button("Poke nearest mob", func() -> void: waves.debug_poke_nearest())
	_button("Give test loot", give_test_loot)
	_button("Grant %d XP" % roundi(XP_GRANT), grant_xp)
	_button("Kill player", kill_player)
	_title("F4 — spawn mob at cursor")


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
