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

## How often the crafting tab repaints while it is up (3.6b).
##
## ⚠️ **Nothing else would ever repaint a greyed row.** Rows are built once and
## affordability is a function of where you are STANDING and of what an inserter
## has put in a chest since — neither of which emits anything this node listens to.
## Walk toward a chest and a row that should have gone green stays grey, which
## reads as broken. A `Timer` scoped to this tab's visibility covers both cases,
## costs nothing while the tab is down, and keeps 3.6a's no-`_process` rule.
const CRAFT_REFRESH_SECONDS := 0.25

## Shift-clicking Craft makes up to this many, stopping on the first refusal.
## Shift already means "bulk" everywhere else in this screen.
const CRAFT_BULK_COUNT := 5

## The filter that shows everything — `All`, and the value `_category` holds for it.
const ALL_CATEGORIES := ""

## An input you cannot pay for. ⚠️ A theme colour override, not `modulate`: the
## label has to go back to the theme's own colour when the input becomes payable,
## and `remove_theme_color_override` is the only way to say that without hardcoding
## what the theme's colour was.
const MISSING_INPUT_COLOR := Color(0.95, 0.45, 0.4)

## Wide enough that the input costs line up down the list rather than starting at
## a different x per row.
const RECIPE_NAME_WIDTH := 150.0
const RECIPE_INPUT_FONT_SIZE := 12

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
## Injected by tests before add_child; falls back to the live autoload. The
## crafting tab's *only* model: `gather_available` / `consume_available` reach the
## player's bag plus every container in range through it
## ([progression.md](../../docs/systems/progression.md) §Crafting range).
##
## ⚠️ Inject it **together with `inventory`** (`screen.inventory = items.player_inventory`)
## or a craft drains one bag and pays into another.
var items: Node = null

var _tab := Tab.INVENTORY
var _player: Player = null

## The stack on the cursor, `{}` when empty.
##
## ❗️**It lives HERE, never on `Items`.** `Items.reset_run()` replaces the whole
## `Inventory` object, so a stack parked on the autoload would need its own line
## there and would survive a restart the day someone forgets it. This node is a
## child of `Main` and dies with the scene reload, so it needs no `reset_run` hook
## at all — the same argument the respawn beacon makes for a group over a static.
var _held: Dictionary = { }
## The cursor-following display of `_held`. ⚠️ **The OS cursor is NOT hidden** —
## that needs pointer lock on web — so this is offset from the pointer instead.
var _ghost: ItemSlot = null

## The container whose panel is open, or null.
##
## ⚠️ **Deliberately untyped, and never annotated on the way out of a loop or used
## as a `Dictionary` key.** Both are `tools/check_freed_safety.sh` failures: a type
## annotation is executable code that dereferences the value before any
## `is_instance_valid` guard on the next line can run, and this reference can
## outlive the chest by exactly one `queue_free()`. Every read goes through
## `_container_storage()`, which checks validity first.
var _container: Node = null

var _inventory_slots: Array[ItemSlot] = []
var _equipment_slots: Array[ItemSlot] = []
var _container_slots: Array[ItemSlot] = []
var _tab_buttons: Array[Button] = []

## One entry per hand recipe, in `RecipeDefs` table order:
## `{ recipe, root: HBoxContainer, button: Button, inputs: {item_id: Label} }`.
## ⚠️ Every node in here is a child built in `_ready` and never freed, which is
## what makes the `Dictionary` loop variable below safe.
var _recipe_rows: Array[Dictionary] = []
var _category_buttons: Array[Button] = []
## Which category the filter row is on; `ALL_CATEGORIES` shows every unlocked row.
var _category := ALL_CATEGORIES
var _craft_timer: Timer = null

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
@onready var _category_bar: HBoxContainer = %CategoryBar
@onready var _range_label: Label = %RangeLabel
@onready var _recipe_list: VBoxContainer = %RecipeList


func _ready() -> void:
	_instance = self
	add_to_group(GROUP)
	if inventory == null:
		inventory = Items.player_inventory
	if equipment == null:
		equipment = Items.equipment
	if game == null:
		game = Game
	if progression == null:
		progression = Progression
	if items == null:
		items = Items
	layer = LAYER
	# Usable while the tree is paused, so Esc still closes it under the game-over
	# screen (the `DebugMenu` precedent).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_tabs()
	# ⚠️ **All 68 widgets once, here** — never on open and never on tab switch.
	# ~272 Controls instantiated on a keypress is a visible hitch in a browser,
	# where flipping `visible` costs nothing.
	_build_slots()
	# Same argument, and it is the reason the crafting tab has no "build on open"
	# path either: 13 rows of ~6 Controls on a keypress is a hitch you can feel.
	_build_crafting()
	_build_ghost()
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
	# ❗️The death exploit's fix. `_die()` builds the loot bag BEFORE it emits this,
	# and a held stack is in neither the inventory nor the bag — so it would survive
	# death untouched. Hooked rather than reordering `_die`, which several things
	# already depend on ([player-combat.md](../../docs/systems/player-combat.md)
	# §Death & respawn).
	player.died.connect(_on_player_died)
	player.health_changed.connect(_on_player_vitals_changed)
	player.mana_changed.connect(_on_player_vitals_changed)
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
	_return_held()
	hide_container()
	_set_open(false)

# --- The container panel ------------------------------------------------------
#
# Reached through statics for the same reason `Hud.show_toast` is: the call sites
# (the player's `interact`, and a chest being swung down) own no path to this node,
# and both must be **inert with no screen in the tree** so headless tests are
# unaffected.

## The group a container reaches this screen through when it cannot name the class.
##
## ❗️`Chest.on_removed()` is exactly that case: `chest.gd → CharacterScreen →
## ItemSlot → Hud → ItemDefs → chest.tres → chest.tscn → chest.gd` is a real cycle
## — closed through a `place_scene` RESOURCE rather than through code — and Godot
## cannot resolve `ItemDefs.STATS` inside it. Every deployable an `ItemDefs` row can
## place is in that loop. The two statics below stay for callers outside it, like
## the player's `interact`.
const GROUP := &"character_screen"


## Open `node`'s panel alongside the window. Duck-typed all the way down: nothing
## here names `Chest`.
static func open_container(node: Node) -> void:
	if _instance != null:
		_instance.show_container(node)


## ❗️Reached from `Chest.on_removed()` (through `GROUP`, see above), which
## `pop_to_pickup` runs **before** the chest empties and **before** it is freed — so
## the panel closes while everything is still valid and a stack held on the cursor
## goes back to the PLAYER's inventory rather than into a dying container.
static func close_container(node: Node) -> void:
	if _instance != null:
		_instance.hide_container(node)


func show_container(node: Node) -> void:
	if node == null or not node.has_method(&"storage") or not can_open():
		return
	if not _is_current_container(node):
		_unbind_container()
	_container = node
	var storage: Inventory = node.storage()
	# ⚠️ **A named method, never a lambda.** A fresh `Callable` per open is
	# undetectable as a duplicate connection, so opening the same chest twice would
	# repaint every slot twice, forever.
	if not storage.slot_changed.is_connected(_on_container_slot_changed):
		storage.slot_changed.connect(_on_container_slot_changed)
	_container_title.text = container_title(node)
	_refresh_container()
	_container_panel.visible = true
	open(Tab.INVENTORY)


## `node` null closes whatever is open; a specific `node` closes only its own
## panel, so a chest destroyed across the map cannot shut the one you are using.
func hide_container(node: Node = null) -> void:
	if _container == null:
		return
	if node != null and is_instance_valid(_container) and not _is_current_container(node):
		return
	_return_held()
	_unbind_container()
	_container_panel.visible = false


## Names the container without knowing what it is: `item_id` is a `Deployable`
## property, so anything that has one introduces itself by its own display name.
static func container_title(node: Node) -> String:
	if node != null and &"item_id" in node:
		var named := Hud.item_name(node.item_id)
		if named != "":
			return named
	return "Container"


## Compared by instance id rather than by `==`, so a freed container is never
## dereferenced by the comparison itself.
func _is_current_container(node: Node) -> bool:
	if _container == null or not is_instance_valid(_container) or node == null:
		return false
	return _container.get_instance_id() == node.get_instance_id()


func _unbind_container() -> void:
	if _container != null and is_instance_valid(_container):
		var storage: Inventory = _container.storage()
		if storage.slot_changed.is_connected(_on_container_slot_changed):
			storage.slot_changed.disconnect(_on_container_slot_changed)
	_container = null
	for widget in _container_slots:
		widget.set_stack({ })
		widget.visible = false


## ⚠️ Every read of the container goes through here. `is_instance_valid` first,
## because the reference outlives the chest by one `queue_free()`.
func _container_storage() -> Inventory:
	if _container == null or not is_instance_valid(_container):
		return null
	return _container.storage()


## Shows `mini(slot_count, MAX_CONTAINER_SLOTS)` of the widgets built in `_ready`.
## ⚠️ The cap is a number here, not a reference to `Chest.CHEST_SLOTS`: this panel
## must not learn what kind of container it is drawing.
func _refresh_container() -> void:
	var storage := _container_storage()
	var shown := 0 if storage == null else mini(storage.slot_count(), MAX_CONTAINER_SLOTS)
	for i in _container_slots.size():
		_container_slots[i].visible = i < shown
		_container_slots[i].set_stack({ } if i >= shown else storage.get_slot(i))


func _on_container_slot_changed(index: int) -> void:
	var storage := _container_storage()
	if storage == null or index >= _container_slots.size():
		return
	_container_slots[index].set_stack(storage.get_slot(index))


## No player yet means world generation is still running, and `GAME_OVER` means a
## stats screen this one outranks on nothing is already up.
func can_open() -> bool:
	return _player != null and game.state != game.State.GAME_OVER


func current_tab() -> Tab:
	return _tab


func _set_open(open_now: bool) -> void:
	visible = open_now
	is_open = open_now
	_update_craft_timer()


func _show_tab(tab: Tab) -> void:
	_tab = tab
	for key: int in _pages:
		(_pages[key] as Control).visible = key == tab
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == tab
	if tab == Tab.INVENTORY:
		_refresh_stats()
	# ⚠️ Driven from BOTH here and `_set_open`, and it has to be: `open()` shows the
	# tab *before* it sets the flag, so neither call alone sees both halves true.
	_update_craft_timer()


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
	for widget in _inventory_slots:
		widget.slot_pressed.connect(_on_inventory_slot_pressed)

	for slot in equipment.slot_count():
		var widget := _make_slot(_equipment_grid, slot)
		widget.tooltip_text = equipment_slot_name(slot)
		widget.slot_pressed.connect(_on_equipment_slot_pressed)
		_equipment_slots.append(widget)

	for i in MAX_CONTAINER_SLOTS:
		var widget := _make_slot(_container_grid, i)
		widget.slot_pressed.connect(_on_container_slot_pressed)
		_container_slots.append(widget)


func _make_slot(parent: Node, index: int, key_label := "") -> ItemSlot:
	var slot := ItemSlot.new(index, key_label)
	parent.add_child(slot)
	return slot


## Added LAST, so it is the final child of the CanvasLayer and therefore drawn over
## every panel. `MOUSE_FILTER_IGNORE` because a ghost that ate the click it is
## following would make putting the stack down impossible.
func _build_ghost() -> void:
	_ghost = ItemSlot.new()
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.top_level = true
	# Explicit: outside a container nothing lays this out, so `size` would stay
	# zero and the edge clamping below would have nothing to measure.
	_ghost.size = ItemSlot.SLOT_SIZE
	_ghost.visible = false
	add_child(_ghost)

# --- The held stack -----------------------------------------------------------
#
# The interaction model is [ui.md](../../docs/systems/ui.md) §Character screen's:
# LMB picks up / puts down / swaps, RMB places one or splits half, shift-click
# quick-moves a stack to the other open inventory. One implementation serves the
# grid, the hotbar row, the equipment slots and the container panel, and splitting
# falls out of the model rather than needing a second mechanism.


## What is on the cursor. Public for the tests and for §9's container teardown.
func held() -> Dictionary:
	return _held


## ⚠️ Only `InputEventMouseMotion`, and there is deliberately **no `_process`**:
## the ghost costs nothing while the mouse is still.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion) or not _ghost.visible:
		return
	_move_ghost((event as InputEventMouseMotion).position)


func _set_held(stack: Dictionary) -> void:
	_held = stack
	_ghost.set_stack(stack)
	_ghost.visible = not stack.is_empty()
	if _ghost.visible:
		_move_ghost(get_viewport().get_mouse_position())


## Offset from the pointer rather than under it, and flipped ABOVE the pointer near
## the bottom edge rather than clamped down onto it — exactly what the HUD's inspect
## label does, and for the same reason: a clamped ghost lands squarely on the slot
## it is hovering, which is the one thing you are trying to see.
func _move_ghost(at: Vector2) -> void:
	var screen := get_viewport().get_visible_rect().size
	var box := _ghost.size
	var y := at.y + GHOST_OFFSET.y
	if y + box.y > screen.y - GHOST_MARGIN:
		y = at.y - box.y - GHOST_OFFSET.y
	_ghost.position = Vector2(
		clampf(at.x + GHOST_OFFSET.x, GHOST_MARGIN, screen.x - box.x - GHOST_MARGIN),
		clampf(y, GHOST_MARGIN, screen.y - box.y - GHOST_MARGIN),
	)


## ❗️**Every exit path comes through here, or the cursor stack is silently
## deleted.** There are four: the window closed (`I`/`C`/`K`/Esc), `died`, the open
## container destroyed, and `GAME_OVER`. What does not fit goes to the floor as a
## pickup carrying `grants_xp = false` — the same sink and the same flag as
## `Deployable.pop_to_pickup`, so there is one drop path and no second exit.
func _return_held() -> void:
	if _held.is_empty():
		return
	var stack := _held
	_set_held({ })
	_drop_to_world(stack.id, inventory.add_item(stack.id, stack.count))


## ❗️Death is the one exit that does NOT go back to the inventory. `_die()` builds
## the loot bag and only then emits `died`, so anything handed back to the bag's
## kept slots would be exactly the exploit this closes: open the screen, pick up
## your best haul, die, keep it while the rest drops. Straight to the floor,
## order-independent of `_die`'s internals.
func _on_player_died(_respawn_seconds: float) -> void:
	if _held.is_empty():
		return
	var stack := _held
	_set_held({ })
	_drop_to_world(stack.id, stack.count)


## Reached by GROUP, like every other drop in the game — this node owns no path to
## the spawner, and dying mobs do not either. A no-op with no spawner in the tree,
## so headless tests are unaffected.
func _drop_to_world(id: String, count: int) -> void:
	if count <= 0 or _player == null or not is_instance_valid(_player):
		return
	var spawner := get_tree().get_first_node_in_group(&"pickup_spawner")
	if spawner == null:
		return
	spawner.spawn_at(_player.global_position, id, count, false)

# --- Clicks -------------------------------------------------------------------


func _on_inventory_slot_pressed(index: int, button_index: int, shift: bool) -> void:
	# Shift only means quick-move with an EMPTY cursor: holding a stack, shift is
	# ignored and the click does what it always does. One rule, no modifier soup.
	if shift and _held.is_empty():
		_quick_move_from_inventory(index)
		return
	if button_index == MOUSE_BUTTON_RIGHT:
		_right_click(inventory, index)
		return
	_left_click(inventory, index)


## Pick up, put down, or swap — and all three are one call, because `put_in_slot`
## returns what the caller still holds.
func _left_click(inv: Inventory, index: int) -> void:
	if _held.is_empty():
		_set_held(inv.take_slot(index))
		return
	_set_held(inv.put_in_slot(index, _held))


## Empty cursor: take half. Holding: put one down.
func _right_click(inv: Inventory, index: int) -> void:
	if _held.is_empty():
		var stack := inv.get_slot(index)
		if stack.is_empty():
			return
		# ⚠️ `ceili(count / 2.0)`, not `count / 2`: integer division makes a right
		# click on a stack of ONE a silent no-op.
		_set_held(inv.take_from_slot(index, ceili(stack.count / 2.0)))
		return
	_place_one(inv, index)


## ⚠️ RMB never swaps. `put_in_slot` would happily displace a whole different stack
## for the sake of putting one item down, which is LMB's job and not this one's.
func _place_one(inv: Inventory, index: int) -> void:
	var target := inv.get_slot(index)
	if not target.is_empty() and target.id != _held.id:
		return
	var residue := inv.put_in_slot(index, { id = _held.id, count = 1 })
	if not residue.is_empty():
		return # A full slot took nothing; the cursor keeps everything.
	var left: int = _held.count - 1
	_set_held({ } if left <= 0 else { id = _held.id, count = left })


## Quick-move out of the player's own inventory. With a container open that is the
## container — the fast path, and what you actually use against a chest. Otherwise
## it is hotbar ⇄ the rest of the bag.
##
## ❗️**Offer first, consume second** — `Player.hand_feed`'s argument: the other
## order is one full destination away from eating the item.
##
## ⚠️ The destination never contains `index`, which is what stops the stack merging
## back into the slot it just left and then being removed from it.
func _quick_move_from_inventory(index: int) -> void:
	var stack := inventory.get_slot(index)
	if stack.is_empty():
		return
	var id: String = stack.id
	var count: int = stack.count
	var storage := _container_storage()
	if storage != null:
		_take_after_offering(inventory, index, count - storage.add_item(id, count))
		return
	var from := Inventory.HOTBAR_SIZE if index < Inventory.HOTBAR_SIZE else 0
	var to := inventory.slot_count() if index < Inventory.HOTBAR_SIZE else Inventory.HOTBAR_SIZE
	_take_after_offering(inventory, index, count - inventory.add_item_in_range(id, count, from, to))


## The other direction: a container stack straight into the player's bag.
func _quick_move_to_inventory(storage: Inventory, index: int) -> void:
	var stack := storage.get_slot(index)
	if stack.is_empty():
		return
	_take_after_offering(storage, index, stack.count - inventory.add_item(stack.id, stack.count))


## Consume exactly what the destination reported taking, and nothing when it took
## nothing — the second half of "offer first, consume second".
func _take_after_offering(source: Inventory, index: int, moved: int) -> void:
	if moved > 0:
		source.remove_from_slot(index, moved)


func _on_container_slot_pressed(index: int, button_index: int, shift: bool) -> void:
	var storage := _container_storage()
	if storage == null or index >= storage.slot_count():
		return
	if shift and _held.is_empty():
		_quick_move_to_inventory(storage, index)
		return
	if button_index == MOUSE_BUTTON_RIGHT:
		_right_click(storage, index)
		return
	_left_click(storage, index)

# --- The equipment panel ------------------------------------------------------


func _on_equipment_slot_pressed(slot: int, _button_index: int, shift: bool) -> void:
	# Neither button does anything different here: an equipment slot holds one
	# item, so there is no half to split and no single item to place.
	if shift and _held.is_empty():
		_unequip_to_inventory(slot)
		return
	if _held.is_empty():
		var worn := equipment.unequip(slot)
		if worn != "":
			_set_held({ id = worn, count = 1 })
		return
	# ❗️**Refused, and the cursor keeps its stack** — the `accept_item` bargain.
	# Nothing is consumed on a rejected click, which is what makes dropping a
	# pickaxe on the helmet slot a no-op rather than a lost pickaxe.
	if not Equipment.slot_accepts(slot, _held.id):
		return
	var displaced := equipment.equip(slot, _held.id)
	# ❗️Exactly ONE leaves the cursor however big the stack is: five helmets equip
	# one and hand four back.
	var left: int = _held.count - 1
	_set_held({ } if left <= 0 else { id = _held.id, count = left })
	# The piece that came off goes to the bag rather than onto a cursor that is
	# already holding something else, with the leftover to the floor — the same
	# conservation the inventory side keeps.
	if displaced != "":
		_drop_to_world(displaced, inventory.add_item(displaced, 1))


## ❗️Offer first, consume second again: with no room in the bag the piece stays
## WORN rather than being taken off and dropped at your feet mid-wave.
func _unequip_to_inventory(slot: int) -> void:
	var worn := equipment.get_item(slot)
	if worn == "":
		return
	if inventory.add_item(worn, 1) > 0:
		return
	equipment.unequip(slot)

# --- The crafting tab (3.6b) --------------------------------------------------
#
# A UI over `RecipeDefs`' `station = "hand"` rows, never a second table
# ([progression.md](../../docs/systems/progression.md) §Recipe tiers). Unlock
# filtering and the greyed/missing-input presentation are
# [ui.md](../../docs/systems/ui.md) §Character screen's.
#
# ⚠️ The category filter is a **button row, not a nested `TabContainer`**: a second
# tab bar inside this window's own tab bar is one too many, and the search box
# ("if time allows") drops in beside it later — which is why 3.6a put the `I`/`C`
# shortcuts in `_unhandled_input`, so a `LineEdit` can receive those letters.


func _build_crafting() -> void:
	_craft_timer = Timer.new()
	_craft_timer.wait_time = CRAFT_REFRESH_SECONDS
	_craft_timer.timeout.connect(_refresh_crafting)
	add_child(_craft_timer)

	var group := ButtonGroup.new()
	_add_category_button("All", ALL_CATEGORIES, group)
	for category in RecipeDefs.categories_for_station(RecipeDefs.HAND):
		_add_category_button(category.capitalize(), category, group)
	_category_buttons[0].button_pressed = true

	for recipe: Dictionary in RecipeDefs.for_station(RecipeDefs.HAND):
		_recipe_rows.append(_make_recipe_row(recipe, _recipe_rows.size()))
	_apply_recipe_filter()


func _add_category_button(text: String, category: String, group: ButtonGroup) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.pressed.connect(_on_category_pressed.bind(category))
	_category_bar.add_child(button)
	_category_buttons.append(button)


## An output `ItemSlot` (which buys the icon and the "Miner ×1" tooltip for free),
## the name, one label per input, and the Craft button.
func _make_recipe_row(recipe: Dictionary, index: int) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 8)

	var icon := ItemSlot.new()
	icon.set_stack(recipe.output)
	root.add_child(icon)

	var title := Label.new()
	title.text = recipe_title(recipe)
	title.custom_minimum_size = Vector2(RECIPE_NAME_WIDTH, 0.0)
	root.add_child(title)

	var input_labels: Dictionary = { }
	for id: String in recipe.inputs:
		var label := Label.new()
		label.text = input_text(id, recipe.inputs[id])
		label.add_theme_font_size_override("font_size", RECIPE_INPUT_FONT_SIZE)
		root.add_child(label)
		input_labels[id] = label

	# Pushes the button to the right edge so the column lines up down the list.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var button := Button.new()
	button.text = "Craft"
	# ⚠️ `Button.pressed` carries no modifier, so shift is read off `Input` here
	# rather than from the event — the same thing `_gui_input` hands the slots.
	button.pressed.connect(_on_craft_pressed.bind(index))
	root.add_child(button)

	_recipe_list.add_child(root)
	return { recipe = recipe, root = root, button = button, inputs = input_labels }


## "Miner", or "Torch ×4" when a craft yields more than one. Static so the wording
## unit-tests without a screen.
static func recipe_title(recipe: Dictionary) -> String:
	var named := Hud.item_name(recipe.output.id)
	if recipe.output.count <= 1:
		return named
	return "%s ×%d" % [named, recipe.output.count]


static func input_text(id: String, count: int) -> String:
	return "%s ×%d" % [Hud.item_name(id), count]


## ⚠️ **An invisible radius is a bug report.** A row greyed because the chest you
## are standing next to is one tile too far reads as broken, so the tab says out
## loud how many containers it can currently see.
static func containers_in_range_text(count: int) -> String:
	if count == 1:
		return "1 container in range"
	return "%d containers in range" % count


## Whether a row is LISTED at all, as opposed to merely unaffordable. Static and
## pure so both halves — the unlock branch and the category filter — test with a
## synthetic row, including the locked case the shipped table has no example of.
##
## ❗️`unlocked_by == ""` is the whole of unlock filtering until 3.7. The branch is
## written now so that step is data rather than a second edit here.
static func row_is_listed(recipe: Dictionary, category: String) -> bool:
	if recipe.unlocked_by != "":
		return false
	return category == ALL_CATEGORIES or recipe.category == category


func _on_category_pressed(category: String) -> void:
	_category = category
	_apply_recipe_filter()


func _apply_recipe_filter() -> void:
	for row: Dictionary in _recipe_rows:
		(row.root as Control).visible = row_is_listed(row.recipe, _category)


## Started when the crafting tab is up **and** the window is open, stopped
## otherwise, with one immediate repaint on show.
func _update_craft_timer() -> void:
	if _craft_timer == null:
		return
	if not (is_open and _tab == Tab.CRAFTING):
		_craft_timer.stop()
		return
	if _craft_timer.is_stopped():
		_craft_timer.start()
	_refresh_crafting()


## One `gather_available` call for the whole list: per row, the Craft button is
## disabled unless every input is payable, and each unpayable input goes red.
func _refresh_crafting() -> void:
	if _player == null or not is_instance_valid(_player):
		# No position to query from, so there is no honest answer to draw.
		_range_label.text = ""
		for row: Dictionary in _recipe_rows:
			(row.button as Button).disabled = true
		return
	var at := _player.global_position
	_range_label.text = containers_in_range_text(items.containers_near(at).size())
	var available: Dictionary = items.gather_available(at)
	for row: Dictionary in _recipe_rows:
		var affordable := true
		var recipe: Dictionary = row.recipe
		for id: String in recipe.inputs:
			var short: bool = available.get(id, 0) < recipe.inputs[id]
			affordable = affordable and not short
			_paint_input_label(row.inputs[id], short)
		(row.button as Button).disabled = not affordable


func _paint_input_label(label: Label, short: bool) -> void:
	if short:
		label.add_theme_color_override("font_color", MISSING_INPUT_COLOR)
	else:
		label.remove_theme_color_override("font_color")


func _on_craft_pressed(index: int) -> void:
	craft(index, Input.is_key_pressed(KEY_SHIFT))


## Make `index`'s recipe once, or up to `CRAFT_BULK_COUNT` times with `bulk`, and
## return how many were actually made. Public so a test drives it without
## synthesising a click and a modifier key.
##
## ❗️Each craft **verifies then consumes** through `consume_available`, and the loop
## stops on the first refusal — never "check once, craft five times".
##
## ⚠️ **Leftover goes to the floor, never deleted.** `add_item` returns what did not
## fit, and the loot bag's contract is that nothing vanishes silently
## ([player-combat.md](../../docs/systems/player-combat.md) §Death & respawn).
func craft(index: int, bulk := false) -> int:
	# Refused outright with no player: there is no position to query a range from,
	# and a craft that cannot see the containers would silently price itself wrong.
	if _player == null or not is_instance_valid(_player) or index >= _recipe_rows.size():
		return 0
	var recipe: Dictionary = _recipe_rows[index].recipe
	if not row_is_listed(recipe, _category):
		return 0
	var made := 0
	for _i in (CRAFT_BULK_COUNT if bulk else 1):
		if not items.consume_available(_player.global_position, recipe.inputs):
			break
		_drop_to_world(recipe.output.id, inventory.add_item(recipe.output.id, recipe.output.count))
		made += 1
	if made > 0:
		_refresh_crafting()
	return made

# --- Crafting-tab accessors, for the tests ------------------------------------
#
# Read-only, and the same bargain `ItemSlot.count_text` makes: a suite that
# reached into the row dictionaries would be pinning this file's internals rather
# than what the tab shows.


func crafting_row_count() -> int:
	return _recipe_rows.size()


func crafting_recipe(index: int) -> Dictionary:
	return _recipe_rows[index].recipe


func crafting_row_visible(index: int) -> bool:
	return (_recipe_rows[index].root as Control).visible


func crafting_row_enabled(index: int) -> bool:
	return not (_recipe_rows[index].button as Button).disabled


func crafting_input_is_missing(index: int, id: String) -> bool:
	var label: Label = _recipe_rows[index].inputs[id]
	return label.has_theme_color_override("font_color")


func crafting_range_text() -> String:
	return _range_label.text


func crafting_is_refreshing() -> bool:
	return _craft_timer != null and not _craft_timer.is_stopped()


## The index of the hand recipe that outputs `id`, or -1.
func crafting_row_for(id: String) -> int:
	for i in _recipe_rows.size():
		if _recipe_rows[i].recipe.output.id == id:
			return i
	return -1

# --- Repaint ------------------------------------------------------------------


func _on_inventory_slot_changed(index: int) -> void:
	if index < _inventory_slots.size():
		_inventory_slots[index].set_stack(inventory.get_slot(index))


func _on_equipment_slot_changed(slot: int) -> void:
	_paint_equipment_slot(slot)
	_refresh_stats()


## Signal-driven like the HUD's bars, so the readout follows a hit taken while the
## screen is open without this node growing a `_process`.
func _on_player_vitals_changed(_current: float, _max_value: float) -> void:
	if _tab == Tab.INVENTORY:
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
