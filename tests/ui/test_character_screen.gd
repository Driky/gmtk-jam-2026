## Unit tests for the character window (roadmap 3.6a). Follows `test_hud.gd`'s
## shape: preload the scene *and* the script, inject the model between
## `instantiate()` and `add_child()`, never touch the live `Items`.
extends GdUnitTestSuite

const ScreenScene := preload("res://scenes/ui/character_screen.tscn")
const ScreenScript := preload("res://scripts/ui/character_screen.gd")
const GameScript := preload("res://scripts/game/game.gd")
const ProgressionScript := preload("res://scripts/progression/progression.gd")
const PlayerScene := preload("res://scenes/player.tscn")

var _inv: Inventory
var _eq: Equipment
var _game: Node
var _progression: Node
var _screen: CanvasLayer
var _player: Player


func before_test() -> void:
	_inv = Inventory.new()
	_eq = Equipment.new()
	_game = auto_free(GameScript.new())
	# A real Progression, just not the autoload one — the readout reads its curve,
	# so a stub would only re-implement it.
	_progression = auto_free(ProgressionScript.new())
	_player = auto_free(PlayerScene.instantiate())
	add_child(_player)
	# Not auto_free: one test frees the screen itself to prove `_exit_tree` clears
	# the static, and auto_free would then double-free it.
	_screen = ScreenScene.instantiate()
	_screen.inventory = _inv
	_screen.equipment = _eq
	_screen.game = _game
	_screen.progression = _progression
	add_child(_screen)
	_screen.bind_player(_player)


func after_test() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.free()
	_screen = null
	# The suite drove the static directly; never leave it set for the next test.
	CharacterScreen.is_open = false

# --- Open / close -------------------------------------------------------------


func test_it_starts_closed() -> void:
	assert_bool(_screen.visible).is_false()
	assert_bool(CharacterScreen.is_open).is_false()


func test_toggling_sets_and_clears_the_static() -> void:
	_screen.toggle_tab(ScreenScript.Tab.INVENTORY)
	assert_bool(CharacterScreen.is_open).is_true()
	assert_bool(_screen.visible).is_true()
	_screen.toggle_tab(ScreenScript.Tab.INVENTORY)
	assert_bool(CharacterScreen.is_open).is_false()
	assert_bool(_screen.visible).is_false()


## The direct shortcuts switch tab rather than closing when the window is already
## up on a different one.
func test_a_second_shortcut_switches_tab_instead_of_closing() -> void:
	_screen.toggle_tab(ScreenScript.Tab.INVENTORY)
	_screen.toggle_tab(ScreenScript.Tab.CRAFTING)
	assert_bool(CharacterScreen.is_open).is_true()
	assert_int(_screen.current_tab()).is_equal(ScreenScript.Tab.CRAFTING)
	_screen.toggle_tab(ScreenScript.Tab.CRAFTING)
	assert_bool(CharacterScreen.is_open).is_false()


## ❗️"Never leave the flag set for the next scene" — the same rule
## `DebugMenu._exit_tree` follows, and the reason a run restart does not come back
## with movement blocked by a screen that no longer exists.
func test_leaving_the_tree_clears_the_static() -> void:
	_screen.open()
	assert_bool(CharacterScreen.is_open).is_true()
	_screen.free()
	_screen = null
	assert_bool(CharacterScreen.is_open).is_false()


## Otherwise it draws under a stats screen it outranks on nothing.
func test_it_refuses_to_open_in_game_over() -> void:
	_game.set_state(GameScript.State.GAME_OVER)
	assert_bool(_screen.can_open()).is_false()
	_screen.open()
	assert_bool(CharacterScreen.is_open).is_false()


func test_game_over_closes_an_open_screen() -> void:
	_screen.open()
	_game.set_state(GameScript.State.GAME_OVER)
	assert_bool(CharacterScreen.is_open).is_false()
	assert_bool(_screen.visible).is_false()


## ❗️Refused before `bind_player`, so `I` during world generation cannot put an
## inventory over the loading bar.
func test_it_refuses_to_open_before_the_player_is_bound() -> void:
	var fresh: CanvasLayer = auto_free(ScreenScene.instantiate())
	fresh.inventory = Inventory.new()
	fresh.equipment = Equipment.new()
	fresh.game = _game
	fresh.progression = _progression
	add_child(fresh)
	assert_bool(fresh.can_open()).is_false()
	fresh.open()
	assert_bool(CharacterScreen.is_open).is_false()


## ❗️Esc marks the input handled, or which of this and 4.5's pause menu answers it
## is scene-order dependent.
##
## ⚠️ Driven through `push_input` rather than by calling `_unhandled_input`
## directly: the viewport's handled flag is only cleared when it starts dispatching
## an event, so a hand-called handler leaves a flag from the previous test standing
## and the closed-screen case below would pass for the wrong reason.
func test_esc_closes_and_marks_the_input_handled() -> void:
	_screen.open()
	get_viewport().push_input(_action(&"pause"))
	assert_bool(CharacterScreen.is_open).is_false()
	assert_bool(get_viewport().is_input_handled()).is_true()


## Closed already: the event falls through untouched so the pause menu can have it.
func test_esc_with_the_screen_closed_is_left_alone() -> void:
	get_viewport().push_input(_action(&"pause"))
	assert_bool(get_viewport().is_input_handled()).is_false()


## The direct shortcuts have to arrive through `_unhandled_input` too, or 3.6b's
## search box can never receive the letter `I`.
func test_the_inventory_shortcut_opens_the_window() -> void:
	get_viewport().push_input(_action(&"toggle_inventory"))
	assert_bool(CharacterScreen.is_open).is_true()
	assert_int(_screen.current_tab()).is_equal(ScreenScript.Tab.INVENTORY)


func _action(name: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	return event

# --- Tabs and layout ----------------------------------------------------------


func test_exactly_one_page_is_visible_at_a_time() -> void:
	for tab: int in [ScreenScript.Tab.INVENTORY, ScreenScript.Tab.CRAFTING, ScreenScript.Tab.SKILLS]:
		_screen._show_tab(tab)
		var shown := 0
		for key: int in _screen._pages:
			if (_screen._pages[key] as Control).visible:
				shown += 1
				assert_int(key).is_equal(tab)
		assert_int(shown).is_equal(1)


## ⚠️ All 68 widgets exist from `_ready`, never built on open or on tab switch —
## ~272 Controls instantiated on a keypress is a visible hitch in a browser.
func test_all_sixty_eight_widgets_exist_before_the_screen_is_ever_opened() -> void:
	assert_int(_screen._inventory_slots.size()).is_equal(Inventory.SLOT_COUNT)
	assert_int(_screen._equipment_slots.size()).is_equal(_eq.slot_count())
	assert_int(_screen._container_slots.size()).is_equal(ScreenScript.MAX_CONTAINER_SLOTS)
	assert_int(
		_screen._inventory_slots.size()
		+ _screen._equipment_slots.size()
		+ _screen._container_slots.size(),
	).is_equal(68)
	assert_bool(CharacterScreen.is_open).is_false()


## Slots 0–9 live in their own row under the grid, which is where the hotbar is on
## screen; everything past them is the grid.
func test_the_hotbar_row_holds_slots_zero_to_nine_and_the_grid_holds_the_rest() -> void:
	assert_int(_screen._hotbar.get_child_count()).is_equal(Inventory.HOTBAR_SIZE)
	assert_int(_screen._grid.get_child_count()).is_equal(
		Inventory.SLOT_COUNT - Inventory.HOTBAR_SIZE,
	)
	for i in Inventory.HOTBAR_SIZE:
		assert_object(_screen._inventory_slots[i].get_parent()).is_same(_screen._hotbar)
	assert_object(
		_screen._inventory_slots[Inventory.HOTBAR_SIZE].get_parent(),
	).is_same(_screen._grid)

# --- Repaint ------------------------------------------------------------------


## ❗️The whole point of the step: slot 27 is unreachable through the HUD, whose
## `_on_slot_changed` early-returns above `HOTBAR_SIZE`.
func test_a_change_in_a_slot_past_the_hotbar_repaints() -> void:
	_inv.put_in_slot(27, { id = "dirt", count = 6 })
	assert_str(_screen._inventory_slots[27].count_text()).is_equal("6")
	_inv.take_slot(27)
	assert_str(_screen._inventory_slots[27].count_text()).is_equal("")


## Seeded in `_ready` rather than on the first change, like the HUD's XP bar: a run
## resumed with a full bag must not show an empty grid until something moves.
func test_the_grid_is_seeded_from_an_inventory_that_already_had_items() -> void:
	var inv := Inventory.new()
	inv.add_item("stone", 5)
	var fresh: CanvasLayer = auto_free(ScreenScene.instantiate())
	fresh.inventory = inv
	fresh.equipment = Equipment.new()
	fresh.game = _game
	fresh.progression = _progression
	add_child(fresh)
	assert_str(fresh._inventory_slots[0].count_text()).is_equal("5")


func test_equipping_repaints_the_panel_slot() -> void:
	_eq.equip(Equipment.Slot.HELMET, "copper_helmet")
	var widget: ItemSlot = _screen._equipment_slots[Equipment.Slot.HELMET]
	assert_object(widget.icon_texture()).is_not_null()
	_eq.unequip(Equipment.Slot.HELMET)
	assert_object(widget.icon_texture()).is_null()


## An empty equipment slot has to keep naming itself, or the panel is eight
## identical squares.
func test_an_empty_equipment_slot_still_names_which_slot_it_is() -> void:
	var widget: ItemSlot = _screen._equipment_slots[Equipment.Slot.FEET]
	assert_str(widget.tooltip_text).is_equal(ScreenScript.equipment_slot_name(Equipment.Slot.FEET))
	_eq.equip(Equipment.Slot.FEET, "copper_boots")
	assert_str(widget.tooltip_text).is_equal("Copper Boots ×1")
	_eq.unequip(Equipment.Slot.FEET)
	assert_str(widget.tooltip_text).is_equal(ScreenScript.equipment_slot_name(Equipment.Slot.FEET))

# --- Stats readout ------------------------------------------------------------


## ⚠️ Move speed is NOT a player member — it is read from `Progression`, which is
## where `_move` reads it every frame.
func test_the_stats_readout_names_hp_mana_speed_and_armor() -> void:
	var text := ScreenScript.stats_text(30.0, 100.0, 12.5, 50.0, 110.0, 16.0)
	assert_str(text).contains("HP    30 / 100")
	assert_str(text).contains("Mana  13 / 50")
	assert_str(text).contains("Speed 110")
	assert_str(text).contains("Armor 16")


func test_the_readout_follows_an_equipment_change() -> void:
	assert_str(_screen._stats_label.text).contains("Armor 0")
	_eq.equip(Equipment.Slot.CHEST, "copper_chestplate")
	assert_str(_screen._stats_label.text).contains("Armor 4")
