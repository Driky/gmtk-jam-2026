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
const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const ChestScene := preload("res://scenes/automation/chest.tscn")
const TorchScene := preload("res://scenes/torch.tscn")
const ItemsScript := preload("res://scripts/items/items.gd")

var _inv: Inventory
var _eq: Equipment
var _game: Node
var _progression: Node
var _screen: CanvasLayer
var _player: Player
## A second `Items` in the tree, never the autoload. ⚠️ `_inv` and `_eq` are ITS
## models rather than free-standing ones (3.6b): the crafting tab drains through
## `consume_available` and pays into `inventory`, so a suite where those are two
## different bags would test a screen the game never runs.
var _items: Node
## Built on demand by `_chest()` — only the container cases need a world.
var _screen_terrain: Node


func before_test() -> void:
	_screen_terrain = null
	_items = auto_free(ItemsScript.new())
	add_child(_items)
	_inv = _items.player_inventory
	_eq = _items.equipment
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
	_screen.items = _items
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

# --- The equipment panel (3.6a) ----------------------------------------------


func _gear(slot: int) -> ItemSlot:
	return _screen._equipment_slots[slot]


## Total across the bag, the cursor AND what is worn — the panel is not an exit.
func _total_with_gear() -> int:
	var total := _total()
	for slot in _eq.slot_count():
		if _eq.get_item(slot) != "":
			total += 1
	return total


func test_dropping_a_piece_on_its_slot_wears_it() -> void:
	_inv.put_in_slot(0, { id = "copper_helmet", count = 1 })
	_click_slot(_bag(0))
	_click_slot(_gear(Equipment.Slot.HELMET))
	assert_str(_eq.get_item(Equipment.Slot.HELMET)).is_equal("copper_helmet")
	assert_bool(_screen.held().is_empty()).is_true()
	assert_float(_eq.armor_total()).is_equal_approx(3.0, 0.001)
	assert_int(_total_with_gear()).is_equal(1)


## ❗️**Refused, and the cursor keeps its stack** — nothing is consumed on a
## rejected click. Dropping a pickaxe on the helmet slot must not eat the pickaxe.
func test_a_wrong_type_drop_is_refused_and_the_cursor_keeps_its_stack() -> void:
	_inv.put_in_slot(0, { id = "pickaxe_t1", count = 1 })
	_click_slot(_bag(0))
	_click_slot(_gear(Equipment.Slot.HELMET))
	assert_str(_screen.held().id).is_equal("pickaxe_t1")
	assert_int(_screen.held().count).is_equal(1)
	assert_str(_eq.get_item(Equipment.Slot.HELMET)).is_equal("")


## The right piece in the wrong slot is refused just as firmly.
func test_boots_are_refused_by_the_helmet_slot() -> void:
	_inv.put_in_slot(0, { id = "copper_boots", count = 1 })
	_click_slot(_bag(0))
	_click_slot(_gear(Equipment.Slot.HELMET))
	assert_str(_screen.held().id).is_equal("copper_boots")
	assert_str(_eq.get_item(Equipment.Slot.HELMET)).is_equal("")
	_click_slot(_gear(Equipment.Slot.FEET))
	assert_bool(_screen.held().is_empty()).is_true()
	assert_str(_eq.get_item(Equipment.Slot.FEET)).is_equal("copper_boots")


## ❗️Exactly one leaves the cursor however big the stack is.
func test_a_stack_of_five_helmets_equips_one_and_hands_four_back() -> void:
	_inv.put_in_slot(0, { id = "copper_helmet", count = 5 })
	_click_slot(_bag(0))
	_click_slot(_gear(Equipment.Slot.HELMET))
	assert_int(_screen.held().count).is_equal(4)
	assert_str(_eq.get_item(Equipment.Slot.HELMET)).is_equal("copper_helmet")
	assert_int(_total_with_gear()).is_equal(5)


## The displaced piece goes to the bag rather than onto a cursor already holding
## something — and the total does not move either way.
func test_the_displaced_piece_goes_back_into_the_bag() -> void:
	_inv.put_in_slot(0, { id = "copper_helmet", count = 2 })
	_click_slot(_bag(0))
	_click_slot(_gear(Equipment.Slot.HELMET)) # Wear one, hold one.
	_click_slot(_gear(Equipment.Slot.HELMET)) # Wear the other; the first comes off.
	assert_bool(_screen.held().is_empty()).is_true()
	assert_str(_eq.get_item(Equipment.Slot.HELMET)).is_equal("copper_helmet")
	assert_int(_inv.count_of("copper_helmet")).is_equal(1)
	assert_int(_total_with_gear()).is_equal(2)


func test_clicking_a_worn_piece_takes_it_onto_the_cursor() -> void:
	_eq.equip(Equipment.Slot.CHEST, "copper_chestplate")
	_click_slot(_gear(Equipment.Slot.CHEST))
	assert_str(_screen.held().id).is_equal("copper_chestplate")
	assert_int(_screen.held().count).is_equal(1)
	assert_str(_eq.get_item(Equipment.Slot.CHEST)).is_equal("")
	assert_float(_eq.armor_total()).is_equal(0.0)


func test_clicking_an_empty_equipment_slot_with_an_empty_cursor_does_nothing() -> void:
	_click_slot(_gear(Equipment.Slot.BACK))
	assert_bool(_screen.held().is_empty()).is_true()


func test_shift_click_takes_a_worn_piece_straight_to_the_bag() -> void:
	_eq.equip(Equipment.Slot.FEET, "copper_boots")
	_click_slot(_gear(Equipment.Slot.FEET), MOUSE_BUTTON_LEFT, true)
	assert_str(_eq.get_item(Equipment.Slot.FEET)).is_equal("")
	assert_int(_inv.count_of("copper_boots")).is_equal(1)
	assert_bool(_screen.held().is_empty()).is_true()


## ❗️Offer first, consume second: with no room in the bag the piece stays WORN
## rather than being taken off and dropped at your feet mid-wave.
func test_shift_click_with_a_full_bag_leaves_the_piece_worn() -> void:
	_eq.equip(Equipment.Slot.FEET, "copper_boots")
	for i in _inv.slot_count():
		_inv.put_in_slot(i, { id = "stone", count = Inventory.STACK_SIZE })
	_click_slot(_gear(Equipment.Slot.FEET), MOUSE_BUTTON_LEFT, true)
	assert_str(_eq.get_item(Equipment.Slot.FEET)).is_equal("copper_boots")


## Both ring slots take the same authored id, independently.
func test_a_ring_goes_in_either_ring_slot() -> void:
	_inv.put_in_slot(0, { id = "copper_ring", count = 2 })
	_click_slot(_bag(0))
	_click_slot(_gear(Equipment.Slot.RING_2))
	_click_slot(_gear(Equipment.Slot.RING_1))
	assert_str(_eq.get_item(Equipment.Slot.RING_1)).is_equal("copper_ring")
	assert_str(_eq.get_item(Equipment.Slot.RING_2)).is_equal("copper_ring")
	assert_int(_total_with_gear()).is_equal(2)


## The panel is not an exit for items either — a randomized sweep across the bag
## AND the eight equipment slots, asserting only that nothing appears or vanishes.
func test_a_randomized_sequence_over_both_panels_conserves_the_total() -> void:
	_inv.add_item("copper_helmet", 3)
	_inv.add_item("copper_ring", 4)
	_inv.add_item("copper_boots", 2)
	_inv.add_item("dirt", 120)
	var expected := _total_with_gear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654321
	for step in 400:
		var button: int = MOUSE_BUTTON_RIGHT if rng.randf() < 0.3 else MOUSE_BUTTON_LEFT
		var shift: bool = rng.randf() < 0.2
		if rng.randf() < 0.4:
			_click_slot(_gear(rng.randi_range(0, _eq.slot_count() - 1)), button, shift)
		else:
			_click_slot(_bag(rng.randi_range(0, Inventory.SLOT_COUNT - 1)), button, shift)
		assert_int(_total_with_gear()).override_failure_message(
			"step %d changed the total" % step,
		).is_equal(expected)

# --- The container panel (3.6a) ----------------------------------------------


## A registered chest on a floor tile, in a Terrain of this suite's own.
func _chest(cell := Vector2i(100, 100)) -> Chest:
	if _screen_terrain == null:
		_screen_terrain = auto_free(TerrainScript.new())
		add_child(_screen_terrain)
	_screen_terrain.set_tile(cell + Vector2i.DOWN, "dirt")
	var node: Chest = auto_free(ChestScene.instantiate())
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_screen_terrain)).is_true()
	node.on_placed()
	return node


func _box(index: int) -> ItemSlot:
	return _screen._container_slots[index]


func test_opening_a_container_shows_its_panel_on_the_inventory_tab() -> void:
	var chest := _chest()
	chest.accept_item("copper", 12)
	CharacterScreen.open_container(chest)
	assert_bool(CharacterScreen.is_open).is_true()
	assert_int(_screen.current_tab()).is_equal(ScreenScript.Tab.INVENTORY)
	assert_bool(_screen._container_panel.visible).is_true()
	assert_str(_box(0).count_text()).is_equal("12")
	assert_str(_screen._container_title.text).is_equal(Hud.item_name("chest"))


## Shows only as many widgets as the container has slots, capped at the 20 built in
## `_ready`. ⚠️ The cap is a number, not a reference to `Chest.CHEST_SLOTS`.
func test_the_panel_shows_one_widget_per_container_slot() -> void:
	var chest := _chest()
	CharacterScreen.open_container(chest)
	var expected := mini(chest.storage().slot_count(), ScreenScript.MAX_CONTAINER_SLOTS)
	var shown := 0
	for widget in _screen._container_slots:
		if widget.visible:
			shown += 1
	assert_int(shown).is_equal(expected)


## ⚠️ **A named method, not a lambda.** A fresh `Callable` per open is undetectable
## as a duplicate, so opening the same chest twice would repaint every slot twice,
## forever.
func test_opening_the_same_container_twice_binds_slot_changed_once() -> void:
	var chest := _chest()
	CharacterScreen.open_container(chest)
	CharacterScreen.open_container(chest)
	CharacterScreen.open_container(chest)
	assert_int(chest.storage().slot_changed.get_connections().size()).is_equal(1)


## And closing disconnects, so a chest left alone stops repainting a panel that is
## no longer showing it.
func test_closing_the_panel_disconnects_the_container() -> void:
	var chest := _chest()
	CharacterScreen.open_container(chest)
	_screen.close()
	assert_int(chest.storage().slot_changed.get_connections().size()).is_equal(0)
	assert_bool(_screen._container_panel.visible).is_false()


func test_a_chest_filled_by_an_inserter_repaints_live() -> void:
	var chest := _chest()
	CharacterScreen.open_container(chest)
	chest.accept_item("iron", 4)
	assert_str(_box(0).count_text()).is_equal("4")


## The two directions of the thing you actually open a chest for.
func test_shift_click_moves_a_stack_into_the_container_and_back() -> void:
	var chest := _chest()
	CharacterScreen.open_container(chest)
	_inv.put_in_slot(27, { id = "copper", count = 30 })
	_click_slot(_bag(27), MOUSE_BUTTON_LEFT, true)
	assert_bool(_inv.get_slot(27).is_empty()).is_true()
	assert_int(chest.storage().count_of("copper")).is_equal(30)

	_click_slot(_box(0), MOUSE_BUTTON_LEFT, true)
	assert_int(chest.storage().count_of("copper")).is_equal(0)
	assert_int(_inv.count_of("copper")).is_equal(30)


## ❗️Offer first, consume second across the boundary too: a full chest must leave
## the player's stack untouched.
func test_shift_click_into_a_full_container_leaves_the_stack_alone() -> void:
	var chest := _chest()
	var storage := chest.storage()
	for i in storage.slot_count():
		storage.put_in_slot(i, { id = "stone", count = Inventory.STACK_SIZE })
	CharacterScreen.open_container(chest)
	_inv.put_in_slot(0, { id = "copper", count = 5 })
	_click_slot(_bag(0), MOUSE_BUTTON_LEFT, true)
	assert_int(_inv.get_slot(0).count).is_equal(5)


## With a container open, shift-click goes to the container rather than hotbar⇄bag.
func test_a_container_takes_precedence_over_the_hotbar_swap() -> void:
	var chest := _chest()
	CharacterScreen.open_container(chest)
	_inv.put_in_slot(0, { id = "copper", count = 5 })
	_click_slot(_bag(0), MOUSE_BUTTON_LEFT, true)
	assert_int(chest.storage().count_of("copper")).is_equal(5)
	assert_int(_inv.count_of("copper")).is_equal(0)


func test_clicks_move_stacks_between_the_bag_and_the_container() -> void:
	var chest := _chest()
	chest.accept_item("coal", 9)
	CharacterScreen.open_container(chest)
	_click_slot(_box(0))
	assert_int(_screen.held().count).is_equal(9)
	_click_slot(_bag(5))
	assert_int(_inv.get_slot(5).count).is_equal(9)
	assert_int(chest.storage().count_of("coal")).is_equal(0)


## ❗️**The container destroyed while its panel is open.** `pop_to_pickup`'s order
## puts `on_removed()` before `take_cargo()` and before `queue_free()`, so the panel
## closes while everything is still valid and the cursor stack lands in the
## PLAYER's inventory rather than in a dying chest.
func test_popping_the_open_chest_closes_the_panel_and_saves_the_held_stack() -> void:
	var spawner: Node2D = auto_free(PickupSpawnerScript.new())
	add_child(spawner)
	var chest := _chest()
	chest.accept_item("magmatite", 40)
	CharacterScreen.open_container(chest)
	_click_slot(_box(0)) # 40 magmatite on the cursor.
	assert_int(_screen.held().count).is_equal(40)

	chest.pop_to_pickup()
	assert_bool(_screen._container_panel.visible).is_false()
	assert_bool(_screen.held().is_empty()).is_true()
	assert_int(_inv.count_of("magmatite")).is_equal(40)
	assert_object(_screen._container).is_null()


## A chest destroyed across the map must not shut the panel you are using.
func test_another_container_being_removed_leaves_this_panel_open() -> void:
	var mine := _chest(Vector2i(100, 100))
	var theirs := _chest(Vector2i(110, 100))
	CharacterScreen.open_container(mine)
	theirs.pop_to_pickup()
	assert_bool(_screen._container_panel.visible).is_true()
	assert_object(_screen._container).is_same(mine)


## Both statics are inert with no screen in the tree, like `Hud.show_toast` — every
## headless test that pops a chest would crash otherwise.
func test_the_container_statics_are_inert_without_a_screen() -> void:
	var chest := _chest()
	_screen.free()
	_screen = null
	CharacterScreen.open_container(chest)
	CharacterScreen.close_container(chest)
	assert_bool(CharacterScreen.is_open).is_false()

# --- Player.interact (3.6a) ---------------------------------------------------


## ❗️Duck-typed on `has_method(&"storage")`, not `as Chest`, so 4.x's next
## container needs no edit in the player.
func test_interact_opens_the_container_under_the_cursor() -> void:
	var chest := _chest()
	_player.global_position = (Vector2(100, 100) + Vector2(0.5, 0.5)) * TileLayout.TILE_SIZE
	assert_bool(_player.interact(_screen_terrain, Vector2i(100, 100))).is_true()
	assert_bool(CharacterScreen.is_open).is_true()
	assert_object(_screen._container).is_same(chest)


func test_interact_on_an_empty_cell_finds_nothing() -> void:
	_chest() # A Terrain exists, but not at this cell.
	_player.global_position = (Vector2(100, 100) + Vector2(0.5, 0.5)) * TileLayout.TILE_SIZE
	assert_bool(_player.interact(_screen_terrain, Vector2i(101, 100))).is_false()
	assert_bool(CharacterScreen.is_open).is_false()


## A deployable that is not a container has no `storage()`, so it is not one.
func test_interact_on_a_non_container_deployable_finds_nothing() -> void:
	if _screen_terrain == null:
		_screen_terrain = auto_free(TerrainScript.new())
		add_child(_screen_terrain)
	var cell := Vector2i(100, 100)
	_screen_terrain.set_tile(cell + Vector2i.DOWN, "dirt")
	var torch: Deployable = auto_free(TorchScene.instantiate())
	torch.setup(cell)
	add_child(torch)
	assert_bool(torch.register(_screen_terrain)).is_true()
	_player.global_position = (Vector2(cell) + Vector2(0.5, 0.5)) * TileLayout.TILE_SIZE
	assert_bool(_player.interact(_screen_terrain, cell)).is_false()
	assert_bool(CharacterScreen.is_open).is_false()


## Out of reach is out of reach, the same rule mining and placement use.
func test_interact_refuses_a_chest_out_of_reach() -> void:
	_chest(Vector2i(100, 100))
	_player.global_position = Vector2(0.0, 0.0)
	assert_bool(_player.interact(_screen_terrain, Vector2i(100, 100))).is_false()
	assert_bool(CharacterScreen.is_open).is_false()


## ❗️Regression pin on a bug no other test could see and every one of them missed:
## the container panel shipped with `anchors_preset = 15`, so its `anchor_left` was
## 0 and `offset_left = -400` placed it at x = **-400** — fully off the left edge of
## the screen, while `visible` was cheerfully true. Only a screenshot found it.
func test_both_panels_are_inside_the_viewport_and_do_not_overlap() -> void:
	var chest := _chest()
	CharacterScreen.open_container(chest)
	await get_tree().process_frame

	var screen_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var window: Control = _screen._window
	var panel: Control = _screen._container_panel
	for control: Control in [window, panel]:
		var rect := control.get_global_rect()
		assert_bool(screen_rect.encloses(rect)).override_failure_message(
			"%s is at %s, outside the %s viewport" % [control.name, rect, screen_rect.size],
		).is_true()
		assert_float(rect.size.x).is_greater(0.0)
		assert_float(rect.size.y).is_greater(0.0)
	# Alongside, not on top of: the container view must not cover the bag.
	assert_bool(window.get_global_rect().intersects(panel.get_global_rect())).is_false()

# --- The crafting tab (3.6b) --------------------------------------------------
#
# The tab is a UI over `RecipeDefs`' hand rows, so nothing below authors a recipe:
# the cases pin what the shipped table makes the screen DO. `craft(index, bulk)` is
# driven directly rather than through a synthesised click, because `Button.pressed`
# carries no modifier and shift is read off `Input`.


## A chest beside the player, positioned rather than placed: the crafting query
## finds it by its scene-root `&"container"` group, not through `Terrain`.
func _near_chest(offset: Vector2, stacks := { }) -> Node2D:
	var chest: Node2D = auto_free(ChestScene.instantiate())
	add_child(chest)
	chest.global_position = _player.global_position + offset
	for id: String in stacks:
		chest.storage().add_item(id, stacks[id])
	return chest


## ⚠️ **The torch, not the miner — since 3.7 the miner is behind a skill node.**
## The craft mechanics below (consume, bulk, floor, chest) do not care WHICH row
## they run, but they do need one a fresh run can actually list, and the torch is
## the only free row with more than one input — which is what the
## only-the-missing-input case needs.
func _torch_row() -> int:
	return _screen.crafting_row_for("torch")


## Whatever the table prices a miner at, paid into the bag.
func _afford(id: String, times := 1) -> void:
	var recipe := RecipeDefs.RECIPES[0]
	for row: Dictionary in RecipeDefs.for_station(RecipeDefs.HAND):
		if row.output.id == id:
			recipe = row
	for input_id: String in recipe.inputs:
		_inv.add_item(input_id, recipe.inputs[input_id] * times)


## Built in `_ready` with the rest of the window — never on open, never on tab
## switch. 13 rows of ~6 Controls on a keypress is a hitch you can feel in a browser.
func test_every_hand_recipe_gets_a_row_up_front() -> void:
	var rows := RecipeDefs.for_station(RecipeDefs.HAND)
	assert_int(rows.size()).is_greater(0)
	assert_int(_screen.crafting_row_count()).is_equal(rows.size())
	for i in rows.size():
		assert_str(_screen.crafting_recipe(i).output.id).is_equal(rows[i].output.id)


## ❗️The whole readable state of a row: enabled exactly when every input is
## payable, and each unpayable input marked so the greying has a reason on screen.
func test_a_row_is_enabled_only_when_its_inputs_are_affordable() -> void:
	var row := _torch_row()
	var needs: Dictionary = _screen.crafting_recipe(row).inputs
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_bool(_screen.crafting_row_enabled(row)).is_false()
	for id: String in needs:
		assert_bool(_screen.crafting_input_is_missing(row, id)).is_true()

	_afford("torch")
	_screen.close()
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_bool(_screen.crafting_row_enabled(row)).is_true()
	for id: String in needs:
		assert_bool(_screen.crafting_input_is_missing(row, id)).is_false()


## One short input is enough to grey the row, and only that input is marked.
func test_only_the_missing_input_is_marked() -> void:
	var row := _torch_row()
	var needs: Dictionary = _screen.crafting_recipe(row).inputs
	_afford("torch")
	_inv.remove_item("coal", 1)
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_bool(_screen.crafting_row_enabled(row)).is_false()
	assert_bool(_screen.crafting_input_is_missing(row, "coal")).is_true()
	assert_bool(_screen.crafting_input_is_missing(row, "stone")).is_false()
	assert_int(needs.size()).is_greater(1) # or this case proves nothing


func test_crafting_consumes_and_yields_exactly_once() -> void:
	var row := _torch_row()
	var needs: Dictionary = _screen.crafting_recipe(row).inputs
	_afford("torch", 2)
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_int(_screen.craft(row)).is_equal(1)
	var made: Dictionary = _screen.crafting_recipe(row).output
	assert_int(_inv.count_of(made.id)).is_equal(made.count)
	for id: String in needs:
		assert_int(_inv.count_of(id)).is_equal(needs[id])


## Shift is bulk everywhere else in this screen, and it verifies-then-consumes per
## craft rather than checking once and making five.
func test_shift_crafting_stops_at_the_first_refusal() -> void:
	var row := _torch_row()
	_afford("torch", 3)
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_int(_screen.craft(row, true)).is_equal(3)
	assert_int(_inv.count_of("torch")).is_equal(_screen.crafting_recipe(row).output.count * 3)
	assert_bool(_screen.crafting_row_enabled(row)).is_false()


func test_shift_crafting_is_capped() -> void:
	var row := _torch_row()
	_afford("torch", 20)
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_int(_screen.craft(row, true)).is_equal(ScreenScript.CRAFT_BULK_COUNT)


func test_crafting_an_unaffordable_row_takes_nothing() -> void:
	var row := _torch_row()
	_afford("torch")
	_inv.remove_item("coal", 1)
	var before := _inv.count_of("stone")
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_int(_screen.craft(row)).is_equal(0)
	assert_int(_inv.count_of("stone")).is_equal(before)
	assert_int(_inv.count_of("torch")).is_equal(0)


## ⚠️ **The output must not vanish into a full bag** — `add_item` returns what did
## not fit and it goes to the floor, the same contract pickups and loot bags keep.
func test_a_full_inventory_sends_the_output_to_the_floor() -> void:
	var spawner: Node2D = auto_free(PickupSpawnerScript.new())
	add_child(spawner)
	var row := _torch_row()
	var needs: Dictionary = _screen.crafting_recipe(row).inputs
	var chest := _near_chest(Vector2(32.0, 0.0))
	for id: String in needs:
		chest.storage().add_item(id, needs[id])
	for i in _inv.slot_count():
		_inv.put_in_slot(i, { id = "dirt", count = Inventory.STACK_SIZE })

	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_int(_screen.craft(row)).is_equal(1)
	assert_int(_inv.count_of("torch")).is_equal(0)
	assert_int(spawner.get_children().size()).is_equal(1)

# --- Crafting range -----------------------------------------------------------


## ❗️The exit criterion of 3.6b: with the ore in a chest beside you, the row is
## craftable — the bag is not the only pool a cost draws from.
func test_a_chest_in_range_pays_for_a_craft() -> void:
	var row := _torch_row()
	var needs: Dictionary = _screen.crafting_recipe(row).inputs
	var chest := _near_chest(Vector2(32.0, 0.0))
	for id: String in needs:
		chest.storage().add_item(id, needs[id])
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_bool(_screen.crafting_row_enabled(row)).is_true()
	assert_int(_screen.craft(row)).is_equal(1)
	assert_int(_inv.count_of("torch")).is_equal(_screen.crafting_recipe(row).output.count)
	for id: String in needs:
		assert_int(chest.storage().count_of(id)).is_equal(0)


## ⚠️ An invisible radius is a bug report: a row greyed because the chest is one
## tile too far has to say so.
func test_the_range_label_counts_containers_in_range() -> void:
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_str(_screen.crafting_range_text()).is_equal(
		ScreenScript.containers_in_range_text(0),
	)
	_near_chest(Vector2(32.0, 0.0))
	_near_chest(Vector2(0.0, 48.0))
	_near_chest(Vector2(0.0, ItemsScript.CRAFTING_RANGE_PX + 8.0))
	_screen.close()
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_str(_screen.crafting_range_text()).is_equal(
		ScreenScript.containers_in_range_text(2),
	)


## ⚠️ **The 3.6b finding: nothing else would ever repaint a greyed row.** Rows are
## built once and affordability depends on where you are standing and on what an
## inserter has put in a chest since — neither emits anything this node listens to.
func test_the_repaint_timer_runs_only_while_the_crafting_tab_is_up() -> void:
	assert_bool(_screen.crafting_is_refreshing()).is_false()
	_screen.open(ScreenScript.Tab.INVENTORY)
	assert_bool(_screen.crafting_is_refreshing()).is_false()
	_screen.toggle_tab(ScreenScript.Tab.CRAFTING)
	assert_bool(_screen.crafting_is_refreshing()).is_true()
	_screen.toggle_tab(ScreenScript.Tab.SKILLS)
	assert_bool(_screen.crafting_is_refreshing()).is_false()
	_screen.toggle_tab(ScreenScript.Tab.CRAFTING)
	assert_bool(_screen.crafting_is_refreshing()).is_true()
	_screen.close()
	assert_bool(_screen.crafting_is_refreshing()).is_false()


## Opening straight onto the tab starts it too — `open()` shows the tab BEFORE it
## sets the flag, so neither half alone sees both.
func test_opening_onto_the_crafting_tab_starts_the_timer() -> void:
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_bool(_screen.crafting_is_refreshing()).is_true()


## The timer's own tick is what makes a row go green while you walk toward a chest,
## without reopening the tab.
func test_the_timer_tick_repaints_a_row_that_became_affordable() -> void:
	var row := _torch_row()
	var needs: Dictionary = _screen.crafting_recipe(row).inputs
	_screen.open(ScreenScript.Tab.CRAFTING)
	assert_bool(_screen.crafting_row_enabled(row)).is_false()
	var chest := _near_chest(Vector2(32.0, 0.0))
	for id: String in needs:
		chest.storage().add_item(id, needs[id])
	assert_bool(_screen.crafting_row_enabled(row)).is_false() # nothing has ticked yet
	_screen._craft_timer.timeout.emit()
	assert_bool(_screen.crafting_row_enabled(row)).is_true()

# --- Filtering ----------------------------------------------------------------


## ❗️`unlocked_by == ""` is the whole of unlock filtering until 3.7. No shipped row
## is locked yet, so the branch is pinned on the pure predicate — which is the only
## way to prove it before that data exists.
func test_a_locked_row_is_hidden_whatever_the_filter() -> void:
	var locked := { category = "automation", unlocked_by = "some_skill_node" }
	var open_row := { category = "automation", unlocked_by = "" }
	assert_bool(ScreenScript.row_is_listed(locked, ScreenScript.ALL_CATEGORIES)).is_false()
	assert_bool(ScreenScript.row_is_listed(locked, "automation")).is_false()
	assert_bool(ScreenScript.row_is_listed(open_row, ScreenScript.ALL_CATEGORIES)).is_true()
	assert_bool(ScreenScript.row_is_listed(open_row, "automation")).is_true()
	assert_bool(ScreenScript.row_is_listed(open_row, "defense")).is_false()


## ❗️**Since 3.7 this is the shape of a FRESH RUN's crafting tab**: every row is
## built, and exactly the ungated ones are listed. A gated row showing up here is
## a machine handed over for free.
func test_only_the_ungated_rows_are_visible_under_the_all_filter() -> void:
	var listed := 0
	for i in _screen.crafting_row_count():
		var free: bool = _screen.crafting_recipe(i).unlocked_by == ""
		assert_bool(_screen.crafting_row_visible(i)).is_equal(free)
		listed += 1 if free else 0
	# Not zero, or a new run opens a tab with nothing in it at all.
	assert_int(listed).is_greater(0)


## The filter flips `visible` on rows already built — it never rebuilds the list.
## ⚠️ Run against `utility`, the one category with an ungated row in it: the gate
## and the category filter are two conditions on one predicate, so a category with
## nothing free in it would pass this whichever way the AND was written.
func test_a_category_filter_hides_the_other_rows() -> void:
	_screen._on_category_pressed("utility")
	var shown := 0
	for i in _screen.crafting_row_count():
		var recipe: Dictionary = _screen.crafting_recipe(i)
		var listed: bool = recipe.category == "utility" and recipe.unlocked_by == ""
		assert_bool(_screen.crafting_row_visible(i)).is_equal(listed)
		shown += 1 if listed else 0
	assert_int(shown).is_greater(0)
	_screen._on_category_pressed(ScreenScript.ALL_CATEGORIES)
	for i in _screen.crafting_row_count():
		assert_bool(_screen.crafting_row_visible(i)).is_equal(
			_screen.crafting_recipe(i).unlocked_by == "",
		)


## A filtered-out row cannot be crafted even if something reached its button —
## the filter is what is on screen, so it has to be what is craftable too.
func test_a_filtered_out_row_refuses_to_craft() -> void:
	var row := _torch_row()
	_afford("torch")
	_screen.open(ScreenScript.Tab.CRAFTING)
	_screen._on_category_pressed("defense")
	assert_int(_screen.craft(row)).is_equal(0)
	assert_int(_inv.count_of("torch")).is_equal(0)


## `All` plus one button per category, in table order.
func test_the_category_bar_is_all_plus_one_button_per_category() -> void:
	var categories := RecipeDefs.categories_for_station(RecipeDefs.HAND)
	assert_int(_screen._category_bar.get_child_count()).is_equal(categories.size() + 1)
	assert_str((_screen._category_bar.get_child(0) as Button).text).is_equal("All")
	for i in categories.size():
		var button := _screen._category_bar.get_child(i + 1) as Button
		assert_str(button.text).is_equal(categories[i].capitalize())

# --- Refusals -----------------------------------------------------------------


## ❗️Refused outright with no player: there is no position to query a range from,
## so a craft would silently price itself against the bag alone.
func test_crafting_is_refused_before_the_player_is_bound() -> void:
	var unbound: CanvasLayer = ScreenScene.instantiate()
	var their_items: Node = auto_free(ItemsScript.new())
	add_child(their_items)
	unbound.inventory = their_items.player_inventory
	unbound.equipment = their_items.equipment
	unbound.game = _game
	unbound.progression = _progression
	unbound.items = their_items
	add_child(unbound)
	their_items.player_inventory.add_item("stone", 99)
	their_items.player_inventory.add_item("coal", 99)
	assert_int(unbound.craft(unbound.crafting_row_for("torch"))).is_equal(0)
	assert_str(unbound.crafting_range_text()).is_equal("")
	# ⚠️ Freed here rather than `auto_free`d: it claimed `_instance` on `_ready`, and
	# `_exit_tree` clears the static only while it is still the one holding it.
	unbound.free()


## ⚠️ **Layout, asserted rather than eyeballed** — the sibling case below this one
## exists because the container panel shipped fully off-screen with `visible` true
## and only a screenshot found it. The crafting tab is the same risk: 13 rows of
## six Controls inside a `ScrollContainer`, and a row that overflows the window
## horizontally puts its Craft button somewhere unclickable.
func test_the_crafting_page_and_every_row_stay_inside_the_window() -> void:
	_screen.open(ScreenScript.Tab.CRAFTING)
	await get_tree().process_frame
	await get_tree().process_frame

	var window: Control = _screen._window
	var page: Control = _screen._pages[ScreenScript.Tab.CRAFTING]
	var window_rect := window.get_global_rect()
	assert_bool(
		Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(window_rect),
	).is_true()
	assert_bool(window_rect.encloses(page.get_global_rect())).override_failure_message(
		"CraftingPage at %s escapes the window at %s" % [page.get_global_rect(), window_rect],
	).is_true()

	# The list scrolls vertically, so only the horizontal fit is asserted: a row
	# wider than the window is a Craft button pushed out of reach.
	for i in _screen.crafting_row_count():
		var row := _screen._recipe_rows[i].root as Control
		var rect := row.get_global_rect()
		assert_float(rect.size.x).override_failure_message(
			"Recipe row %d has no width" % i,
		).is_greater(0.0)
		assert_bool(rect.end.x <= window_rect.end.x + 1.0).override_failure_message(
			"Recipe row %d ends at x=%.1f, past the window's %.1f" % [
				i,
				rect.end.x,
				window_rect.end.x,
			],
		).is_true()
