## The character window: one screen, three tabs, on layer 5. This commit is the
## shell — the tabs, the 68 slot widgets and the open/close rules; the interaction
## model lands on top of it.
##
## ❗️**A PANEL, not a modal.** No full-screen dim and it never touches
## `SceneTree.paused`: the countdown keeps running and the factory keeps ticking
## while you sort your bag, which is the cost of opening a screen mid-wave and the
## reason it is worth blocking movement at all
## ([ui.md](../../docs/systems/ui.md) §Character screen). A dim would also hide the
## countdown, the wave banner and the Core HP bar — precisely the moment the HUD
## matters most.
##
## Owning doc: docs/systems/ui.md
class_name CharacterScreen
extends CanvasLayer

## The three tabs. CRAFTING is 3.6b's and SKILLS is 3.7's; both are placeholders
## here so the tab bar and the `C`/`K` shortcuts are complete from the start
## rather than growing a fourth code path later.
enum Tab { INVENTORY, CRAFTING, SKILLS }

## Above the HUD (1), below the game-over screen (10), far below the debug menu
## (50). Set from here rather than in the scene so there is one source for it.
const LAYER := 5

## Slots 0–9 are laid out as their own row under the grid, which is where the
## hotbar is on screen. ⚠️ "Hotbar assignment" means moving items INTO 0–9 —
## `Inventory.selected_slot` clamps to the hotbar, so there is deliberately no
## selection affordance over the grid.
const HOTBAR_COLUMNS := 10
const GRID_COLUMNS := 10

## The widest container the panel will ever draw, matching `Chest.CHEST_SLOTS`.
## ⚠️ Not a reference to `Chest`: the panel is duck-typed on `storage()`, so 4.x's
## next container needs no edit here.
const MAX_CONTAINER_SLOTS := 20

## Held-stack ghost offset from the pointer and the margin it keeps from the screen
## edge — the same numbers and the same bottom-edge flip as the HUD's cursor
## inspector, for the same reason: a clamped ghost lands on the slot it is naming.
const GHOST_OFFSET := Vector2(14.0, 12.0)
const GHOST_MARGIN := 6.0

## True while the window is showing. Mirrors `DebugMenu.is_open` — gameplay polls
## `Input` directly rather than routing through the UI, so a screen that blocks
## anything has to be readable from the player without a node path
## ([ui.md](../../docs/systems/ui.md) §An open gameplay screen).
static var is_open := false

## Set in `_ready`, cleared in `_exit_tree` — the `Hud.show_toast` idiom, so the
## container statics need no node path and are **inert with no screen in the
## tree**. Headless tests are unaffected.
static var _instance: CharacterScreen = null

## Injected by tests before add_child; falls back to the live autoload. The only
## way a suite drives this screen without the live `Items`.
var inventory: Inventory = null
## Injected by tests before add_child; falls back to the live autoload.
var equipment: Equipment = null
## Injected by tests before add_child; falls back to the live autoload.
var game: Node = null
## Injected by tests before add_child; falls back to the live autoload — the sink
## the held stack falls into when it cannot go back in the bag.
var progression: Node = null

var _tab := Tab.INVENTORY
var _player: Player = null

var _inventory_slots: Array[ItemSlot] = []
var _equipment_slots: Array[ItemSlot] = []
var _container_slots: Array[ItemSlot] = []
var _tab_buttons: Array[Button] = []

@onready var _window: PanelContainer = %Window
@onready var _tab_bar: HBoxContainer = %TabBar
@onready var _grid: GridContainer = %Grid
@onready var _hotbar: GridContainer = %Hotbar
@onready var _equipment_grid: GridContainer = %EquipmentGrid
@onready var _stats_label: Label = %StatsLabel
@onready var _pages: Dictionary = {
	Tab.INVENTORY: %InventoryPage,
	Tab.CRAFTING: %CraftingPage,
	Tab.SKILLS: %SkillsPage,
}
@onready var _container_panel: PanelContainer = %ContainerPanel
@onready var _container_title: Label = %ContainerTitle
@onready var _container_grid: GridContainer = %ContainerGrid


func _ready() -> void:
	_instance = self
	if inventory == null:
		inventory = Items.player_inventory
	if equipment == null:
		equipment = Items.equipment
	if game == null:
		game = Game
	if progression == null:
		progression = Progression
	layer = LAYER
	# Usable while the tree is paused, so Esc still closes it under the game-over
	# screen (the `DebugMenu` precedent).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_tabs()
	# ⚠️ **All 68 widgets once, here** — never on open and never on tab switch.
	# ~272 Controls instantiated on a keypress is a visible hitch in a browser,
	# where flipping `visible` costs nothing.
	_build_slots()
	inventory.slot_changed.connect(_on_inventory_slot_changed)
	equipment.slot_changed.connect(_on_equipment_slot_changed)
	game.state_changed.connect(_on_state_changed)
	_refresh_inventory()
	_refresh_equipment()
	_show_tab(Tab.INVENTORY)
	_set_open(false)


func _exit_tree() -> void:
	is_open = false # Never leave the flag set for the next scene.
	if _instance == self:
		_instance = null


## Called by main.gd once the player exists — the same ownership moment
## `Hud.bind_player` uses, and what makes the screen openable at all.
##
## ❗️The screen refuses to open before this lands rather than being made *visible*
## by it: `I` during world generation would otherwise put an inventory over the
## loading bar.
func bind_player(player: Player) -> void:
	_player = player
	_refresh_stats()

# --- Open / close -------------------------------------------------------------


## ⚠️ In `_unhandled_input`, never `_input`: 3.6b's crafting search box has to be
## able to receive the letters `I` and `C` while it has focus.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_inventory"):
		toggle_tab(Tab.INVENTORY)
	elif event.is_action_pressed(&"toggle_crafting"):
		toggle_tab(Tab.CRAFTING)
	elif event.is_action_pressed(&"toggle_skill_tree"):
		toggle_tab(Tab.SKILLS)
	elif event.is_action_pressed(&"pause"):
		if not is_open:
			return # 4.5's pause menu takes the else-branch.
		close()
		# ❗️Not optional: without marking it handled, which of the two screens
		# answers Esc is scene-order dependent.
		get_viewport().set_input_as_handled()


## The direct shortcuts' behaviour: open on that tab, switch to it if the window
## is already up on another, close if it is already up on this one.
func toggle_tab(tab: Tab) -> void:
	if not is_open:
		open(tab)
		return
	if _tab == tab:
		close()
		return
	_show_tab(tab)


## Public so a test drives it without synthesising input.
func open(tab := Tab.INVENTORY) -> void:
	if not can_open():
		return
	_show_tab(tab)
	_set_open(true)


func close() -> void:
	if not is_open:
		return
	_set_open(false)


## No player yet means world generation is still running, and `GAME_OVER` means a
## stats screen this one outranks on nothing is already up.
func can_open() -> bool:
	return _player != null and game.state != game.State.GAME_OVER


func current_tab() -> Tab:
	return _tab


func _set_open(open_now: bool) -> void:
	visible = open_now
	is_open = open_now


func _show_tab(tab: Tab) -> void:
	_tab = tab
	for key: int in _pages:
		(_pages[key] as Control).visible = key == tab
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == tab
	if tab == Tab.INVENTORY:
		_refresh_stats()


## Closed on `GAME_OVER`, and `can_open` refuses to reopen there. Without both it
## draws under a screen it outranks on nothing.
func _on_state_changed(state: int) -> void:
	if state == game.State.GAME_OVER:
		close()

# --- Layout -------------------------------------------------------------------


func _build_tabs() -> void:
	for tab: int in [Tab.INVENTORY, Tab.CRAFTING, Tab.SKILLS]:
		var button := Button.new()
		button.text = tab_name(tab)
		button.toggle_mode = true
		button.pressed.connect(_show_tab.bind(tab))
		_tab_bar.add_child(button)
		_tab_buttons.append(button)


## The tab's label, and the one place those words live.
static func tab_name(tab: int) -> String:
	match tab:
		Tab.INVENTORY:
			return "Inventory (I)"
		Tab.CRAFTING:
			return "Crafting (C)"
		Tab.SKILLS:
			return "Skills (K)"
	return "?"


## The label under an equipment slot. Spelled out rather than derived from the
## enum name, so "Ring 1" does not read as "RING_1" on screen.
static func equipment_slot_name(slot: int) -> String:
	match slot:
		Equipment.Slot.HELMET:
			return "Helmet"
		Equipment.Slot.CHEST:
			return "Chest"
		Equipment.Slot.LEGS:
			return "Legs"
		Equipment.Slot.FEET:
			return "Feet"
		Equipment.Slot.BACK:
			return "Back"
		Equipment.Slot.RING_1:
			return "Ring 1"
		Equipment.Slot.RING_2:
			return "Ring 2"
		Equipment.Slot.NECKLACE:
			return "Necklace"
	return "?"


func _build_slots() -> void:
	_grid.columns = GRID_COLUMNS
	_hotbar.columns = HOTBAR_COLUMNS
	# The grid holds everything PAST the hotbar; slots 0–9 get their own row under
	# it, which is where they are on screen.
	_inventory_slots.resize(inventory.slot_count())
	for i in range(Inventory.HOTBAR_SIZE, inventory.slot_count()):
		_inventory_slots[i] = _make_slot(_grid, i)
	for i in mini(Inventory.HOTBAR_SIZE, inventory.slot_count()):
		_inventory_slots[i] = _make_slot(_hotbar, i, str((i + 1) % 10))

	for slot in equipment.slot_count():
		var widget := _make_slot(_equipment_grid, slot)
		widget.tooltip_text = equipment_slot_name(slot)
		_equipment_slots.append(widget)

	for i in MAX_CONTAINER_SLOTS:
		_container_slots.append(_make_slot(_container_grid, i))


func _make_slot(parent: Node, index: int, key_label := "") -> ItemSlot:
	var slot := ItemSlot.new(index, key_label)
	parent.add_child(slot)
	return slot

# --- Repaint ------------------------------------------------------------------


func _on_inventory_slot_changed(index: int) -> void:
	if index < _inventory_slots.size():
		_inventory_slots[index].set_stack(inventory.get_slot(index))


func _on_equipment_slot_changed(slot: int) -> void:
	_paint_equipment_slot(slot)
	_refresh_stats()


func _refresh_inventory() -> void:
	for i in _inventory_slots.size():
		_inventory_slots[i].set_stack(inventory.get_slot(i))


func _refresh_equipment() -> void:
	for slot in _equipment_slots.size():
		_paint_equipment_slot(slot)


## An equipment slot holds ONE item, so the widget is handed a count of 1 rather
## than a stack — the same widget, told the truth about what it is showing.
func _paint_equipment_slot(slot: int) -> void:
	var id := equipment.get_item(slot)
	var widget := _equipment_slots[slot]
	widget.set_stack({ } if id == "" else { id = id, count = 1 })
	# Restored after `set_stack` overwrote it: an empty slot has to keep saying
	# which slot it is, or the panel is eight identical squares.
	if id == "":
		widget.tooltip_text = equipment_slot_name(slot)


## HP, mana, move speed and armor. ⚠️ Move speed is NOT a player member — it is
## read from `Progression` every frame in `_move`, so it is read from there here.
func _refresh_stats() -> void:
	if _player == null:
		_stats_label.text = ""
		return
	_stats_label.text = stats_text(
		_player.current_hp,
		progression.get_stat("max_hp"),
		_player.current_mana,
		progression.get_stat("max_mana"),
		progression.get_stat("move_speed"),
		equipment.armor_total(),
	)


## Static so the wording unit-tests without a player, a `Progression` or a tree.
static func stats_text(
		hp: float,
		max_hp: float,
		mana: float,
		max_mana: float,
		move_speed: float,
		armor: float,
) -> String:
	return "\n".join(
		[
			"HP    %d / %d" % [roundi(hp), roundi(max_hp)],
			"Mana  %d / %d" % [roundi(mana), roundi(max_mana)],
			"Speed %d" % roundi(move_speed),
			"Armor %d" % roundi(armor),
		],
	)
