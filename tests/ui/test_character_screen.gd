## Unit tests for the character window (roadmap 3.6a). Follows `test_hud.gd`'s
## shape: preload the scene *and* the script, inject the model between
## `instantiate()` and `add_child()`, never touch the live `Items`.
extends GdUnitTestSuite

const ScreenScene := preload("res://scenes/ui/character_screen.tscn")
const ScreenScript := preload("res://scripts/ui/character_screen.gd")
const GameScript := preload("res://scripts/game/game.gd")
const ProgressionScript := preload("res://scripts/progression/progression.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const PickupSpawnerScript := preload("res://scripts/items/pickup_spawner.gd")

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

# --- The held stack (3.6a) ----------------------------------------------------
#
# Clicks are driven through `ItemSlot._gui_input`, so the widget's own button and
# shift decoding is part of what is under test rather than bypassed.


func _click_slot(widget: ItemSlot, button_index := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.shift_pressed = shift
	widget._gui_input(event)


func _bag(widget_index: int) -> ItemSlot:
	return _screen._inventory_slots[widget_index]


## Total over every slot plus the cursor — the invariant every click preserves.
func _total() -> int:
	var total: int = _screen.held().get("count", 0)
	for i in _inv.slot_count():
		total += _inv.get_slot(i).get("count", 0)
	return total


func test_left_click_picks_a_stack_up_and_puts_it_down() -> void:
	_inv.put_in_slot(27, { id = "dirt", count = 12 })
	_click_slot(_bag(27))
	assert_int(_screen.held().count).is_equal(12)
	assert_bool(_inv.get_slot(27).is_empty()).is_true()
	assert_int(_total()).is_equal(12)

	_click_slot(_bag(3)) # A hotbar slot: this is what "hotbar assignment" means.
	assert_bool(_screen.held().is_empty()).is_true()
	assert_int(_inv.get_slot(3).count).is_equal(12)
	assert_int(_total()).is_equal(12)


func test_left_click_onto_a_different_id_swaps_onto_the_cursor() -> void:
	_inv.put_in_slot(0, { id = "dirt", count = 4 })
	_inv.put_in_slot(1, { id = "stone", count = 7 })
	_click_slot(_bag(0))
	_click_slot(_bag(1))
	assert_str(_screen.held().id).is_equal("stone")
	assert_int(_screen.held().count).is_equal(7)
	assert_str(_inv.get_slot(1).id).is_equal("dirt")
	assert_int(_total()).is_equal(11)


func test_left_click_onto_the_same_id_merges_and_keeps_the_overflow() -> void:
	_inv.put_in_slot(0, { id = "dirt", count = 95 })
	_inv.put_in_slot(1, { id = "dirt", count = 10 })
	_click_slot(_bag(1)) # Hold 10.
	_click_slot(_bag(0)) # 4 fit, 6 stay on the cursor.
	assert_int(_inv.get_slot(0).count).is_equal(Inventory.STACK_SIZE)
	assert_int(_screen.held().count).is_equal(6)
	assert_int(_total()).is_equal(105)


## ⚠️ `ceili(count / 2.0)`: integer division would make this a silent no-op on a
## stack of one, which is the click most likely to be tried first.
func test_right_click_splits_half_and_rounds_up() -> void:
	_inv.put_in_slot(0, { id = "dirt", count = 7 })
	_click_slot(_bag(0), MOUSE_BUTTON_RIGHT)
	assert_int(_screen.held().count).is_equal(4)
	assert_int(_inv.get_slot(0).count).is_equal(3)
	assert_int(_total()).is_equal(7)


func test_right_click_on_a_stack_of_one_takes_it() -> void:
	_inv.put_in_slot(0, { id = "dirt", count = 1 })
	_click_slot(_bag(0), MOUSE_BUTTON_RIGHT)
	assert_int(_screen.held().count).is_equal(1)
	assert_bool(_inv.get_slot(0).is_empty()).is_true()


func test_right_click_while_holding_puts_exactly_one_down() -> void:
	_inv.put_in_slot(0, { id = "dirt", count = 5 })
	_click_slot(_bag(0)) # Hold 5.
	_click_slot(_bag(9), MOUSE_BUTTON_RIGHT)
	assert_int(_screen.held().count).is_equal(4)
	assert_int(_inv.get_slot(9).count).is_equal(1)
	_click_slot(_bag(9), MOUSE_BUTTON_RIGHT)
	assert_int(_inv.get_slot(9).count).is_equal(2)
	assert_int(_total()).is_equal(5)


## ⚠️ RMB never swaps — that is LMB's job. Putting one item down must not displace
## a whole different stack.
func test_right_click_onto_a_different_id_does_nothing() -> void:
	_inv.put_in_slot(0, { id = "dirt", count = 5 })
	_inv.put_in_slot(1, { id = "stone", count = 3 })
	_click_slot(_bag(0)) # Hold dirt.
	_click_slot(_bag(1), MOUSE_BUTTON_RIGHT)
	assert_int(_screen.held().count).is_equal(5)
	assert_str(_inv.get_slot(1).id).is_equal("stone")
	assert_int(_inv.get_slot(1).count).is_equal(3)


func test_right_click_onto_a_full_slot_keeps_the_whole_cursor_stack() -> void:
	_inv.put_in_slot(0, { id = "dirt", count = Inventory.STACK_SIZE })
	_inv.put_in_slot(1, { id = "dirt", count = 5 })
	_click_slot(_bag(1)) # Hold 5.
	_click_slot(_bag(0), MOUSE_BUTTON_RIGHT)
	assert_int(_screen.held().count).is_equal(5)
	assert_int(_total()).is_equal(Inventory.STACK_SIZE + 5)

# --- Shift-click quick-move ---------------------------------------------------


## ⚠️ Out of the hotbar goes to the BAG. Without `add_item_in_range` this would
## merge straight back into a hotbar stack and then be removed from the source.
func test_shift_click_moves_a_hotbar_stack_into_the_bag() -> void:
	_inv.put_in_slot(2, { id = "dirt", count = 8 })
	_click_slot(_bag(2), MOUSE_BUTTON_LEFT, true)
	assert_bool(_inv.get_slot(2).is_empty()).is_true()
	assert_int(_inv.get_slot(Inventory.HOTBAR_SIZE).count).is_equal(8)
	assert_int(_total()).is_equal(8)


func test_shift_click_moves_a_bag_stack_into_the_hotbar() -> void:
	_inv.put_in_slot(27, { id = "dirt", count = 8 })
	_click_slot(_bag(27), MOUSE_BUTTON_LEFT, true)
	assert_bool(_inv.get_slot(27).is_empty()).is_true()
	assert_int(_inv.get_slot(0).count).is_equal(8)


## ❗️Offer first, consume second: a destination with no room must leave the source
## untouched rather than eating the stack.
func test_shift_click_with_nowhere_to_go_leaves_the_stack_alone() -> void:
	for i in range(Inventory.HOTBAR_SIZE, Inventory.SLOT_COUNT):
		_inv.put_in_slot(i, { id = "stone", count = Inventory.STACK_SIZE })
	_inv.put_in_slot(0, { id = "dirt", count = 8 })
	_click_slot(_bag(0), MOUSE_BUTTON_LEFT, true)
	assert_int(_inv.get_slot(0).count).is_equal(8)


## A partial move takes exactly what fit and no more.
func test_shift_click_moves_only_what_fits() -> void:
	for i in range(Inventory.HOTBAR_SIZE + 1, Inventory.SLOT_COUNT):
		_inv.put_in_slot(i, { id = "stone", count = Inventory.STACK_SIZE })
	_inv.put_in_slot(Inventory.HOTBAR_SIZE, { id = "dirt", count = 90 })
	_inv.put_in_slot(0, { id = "dirt", count = 20 })
	_click_slot(_bag(0), MOUSE_BUTTON_LEFT, true)
	assert_int(_inv.get_slot(Inventory.HOTBAR_SIZE).count).is_equal(Inventory.STACK_SIZE)
	assert_int(_inv.get_slot(0).count).is_equal(11) # 20 offered, 9 fit.


## Shift with a stack already on the cursor is an ordinary click, not a third mode.
func test_shift_is_ignored_while_holding_a_stack() -> void:
	_inv.put_in_slot(0, { id = "dirt", count = 5 })
	_click_slot(_bag(0))
	_click_slot(_bag(20), MOUSE_BUTTON_LEFT, true)
	assert_bool(_screen.held().is_empty()).is_true()
	assert_int(_inv.get_slot(20).count).is_equal(5)

# --- Conservation -------------------------------------------------------------


## A long randomized click sequence over the grid, the hotbar and both buttons. The
## only assertion that matters is that nothing was created or destroyed — which is
## the whole contract, and the one no individual case can prove.
func test_a_randomized_click_sequence_conserves_the_total() -> void:
	_inv.add_item("dirt", 140)
	_inv.add_item("stone", 60)
	_inv.add_item("coal", 7)
	var expected := _total()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260727
	for step in 400:
		var index := rng.randi_range(0, Inventory.SLOT_COUNT - 1)
		var button: int = (
			MOUSE_BUTTON_RIGHT if rng.randf() < 0.4 else MOUSE_BUTTON_LEFT
		)
		_click_slot(_bag(index), button, rng.randf() < 0.2)
		assert_int(_total()).override_failure_message(
			"step %d (slot %d, button %d) changed the total" % [step, index, button],
		).is_equal(expected)


## ❗️Closing the window is the commonest exit, and without the return the cursor
## stack is silently deleted.
func test_closing_the_window_returns_the_held_stack() -> void:
	_inv.put_in_slot(27, { id = "dirt", count = 9 })
	_screen.open()
	_click_slot(_bag(27))
	assert_int(_screen.held().count).is_equal(9)
	_screen.close()
	assert_bool(_screen.held().is_empty()).is_true()
	assert_int(_inv.count_of("dirt")).is_equal(9)


func test_game_over_returns_the_held_stack_too() -> void:
	_inv.put_in_slot(27, { id = "dirt", count = 9 })
	_screen.open()
	_click_slot(_bag(27))
	_game.set_state(GameScript.State.GAME_OVER)
	assert_bool(_screen.held().is_empty()).is_true()
	assert_int(_inv.count_of("dirt")).is_equal(9)


## ❗️**The death exploit.** `_die()` builds the loot bag BEFORE it emits `died`, so
## a held stack is in neither the inventory nor the bag and would survive death
## untouched. It has to leave the cursor, and it must NOT go back into the kept
## hotbar slots — so it goes to the floor.
func test_the_held_stack_leaves_the_cursor_on_death_without_going_back_in_the_bag() -> void:
	_inv.put_in_slot(27, { id = "magmatite", count = 99 })
	_screen.open()
	_click_slot(_bag(27))
	assert_int(_screen.held().count).is_equal(99)

	_player.died.emit(Player.RESPAWN_TIME)
	assert_bool(_screen.held().is_empty()).is_true()
	# Not handed back to the inventory: that is the half that made it an exploit.
	assert_int(_inv.count_of("magmatite")).is_equal(0)


## The drop path is reached by GROUP, so it has to be inert with no spawner in the
## tree — every headless test would crash otherwise.
func test_the_death_drop_is_inert_without_a_pickup_spawner() -> void:
	_inv.put_in_slot(0, { id = "dirt", count = 3 })
	_click_slot(_bag(0))
	_player.died.emit(Player.RESPAWN_TIME)
	assert_bool(_screen.held().is_empty()).is_true()


## What does not fit goes to the floor rather than being deleted — asserted against
## a real `PickupSpawner`, so the `grants_xp = false` flag travels with it.
func test_a_return_that_does_not_fit_lands_on_the_floor() -> void:
	var spawner: Node2D = auto_free(PickupSpawnerScript.new())
	add_child(spawner)
	_inv.put_in_slot(0, { id = "dirt", count = 20 })
	_click_slot(_bag(0)) # Hold 20, slot 0 now empty.
	# Fill every slot with something else, so the return has nowhere to go.
	for i in _inv.slot_count():
		_inv.put_in_slot(i, { id = "stone", count = Inventory.STACK_SIZE })
	_screen.open()
	_screen.close()
	assert_bool(_screen.held().is_empty()).is_true()
	assert_int(_inv.count_of("dirt")).is_equal(0)
	var pickups := spawner.get_children()
	assert_int(pickups.size()).is_equal(1)
	assert_int(_total()).is_equal(Inventory.SLOT_COUNT * Inventory.STACK_SIZE)

# --- The ghost ----------------------------------------------------------------


func test_the_ghost_only_shows_while_something_is_held() -> void:
	assert_bool(_screen._ghost.visible).is_false()
	_inv.put_in_slot(0, { id = "dirt", count = 2 })
	_click_slot(_bag(0))
	assert_bool(_screen._ghost.visible).is_true()
	assert_str(_screen._ghost.count_text()).is_equal("2")
	_click_slot(_bag(1))
	assert_bool(_screen._ghost.visible).is_false()


## ⚠️ It must never eat the click it is following, or the stack can never be put
## down. And the OS cursor stays visible — hiding it needs pointer lock on web.
func test_the_ghost_ignores_the_mouse() -> void:
	assert_int(_screen._ghost.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)


## Offset below-right of the pointer in the ordinary case.
func test_the_ghost_sits_below_right_of_the_pointer() -> void:
	_screen._move_ghost(Vector2(300.0, 200.0))
	assert_float(_screen._ghost.position.x).is_greater(300.0)
	assert_float(_screen._ghost.position.y).is_greater(200.0)


## ❗️Flipped ABOVE the pointer near the bottom edge rather than clamped down onto
## it — a clamped ghost lands on the slot you are hovering, which is the one thing
## you are trying to see. The HUD's inspect label does exactly this.
func test_the_ghost_flips_above_the_pointer_near_the_bottom_edge() -> void:
	var height: float = get_viewport().get_visible_rect().size.y
	_screen._move_ghost(Vector2(300.0, height - 2.0))
	assert_float(_screen._ghost.position.y).is_less(height - 2.0)
