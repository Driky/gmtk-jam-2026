## Unit tests for the extracted slot widget (roadmap 3.6a). Built with no HUD in
## the tree at all, which is the point of `Hud.icon_for` / `Hud.item_name` being
## static: 68 of these have to work headless.
extends GdUnitTestSuite

var _slot: ItemSlot


func before_test() -> void:
	_slot = auto_free(ItemSlot.new(0))
	add_child(_slot)


func test_a_fresh_slot_is_empty_and_unselected() -> void:
	assert_str(_slot.count_text()).is_equal("")
	assert_object(_slot.icon_texture()).is_null()
	assert_that(_slot.color).is_equal(ItemSlot.NORMAL_BG)


func test_a_stack_shows_an_icon_and_its_count() -> void:
	_slot.set_stack({ id = "dirt", count = 7 })
	assert_object(_slot.icon_texture()).is_same(Hud.icon_for("dirt"))
	assert_str(_slot.count_text()).is_equal("7")


## An emptied slot that kept a stale icon is the bug the one `set_stack` entry
## point exists to make impossible.
func test_emptying_a_slot_clears_the_icon_and_the_count() -> void:
	_slot.set_stack({ id = "dirt", count = 7 })
	_slot.set_stack({ })
	assert_object(_slot.icon_texture()).is_null()
	assert_str(_slot.count_text()).is_equal("")
	assert_str(_slot.tooltip_text).is_equal("")


## The readout the cursor inspector cannot give over the grid, since 3.6a gates
## it off while the screen is open — same wording, so the two cannot drift.
func test_the_tooltip_names_the_item_and_the_count() -> void:
	_slot.set_stack({ id = "copper_deposit", count = 3 })
	assert_str(_slot.tooltip_text).is_equal("Copper Deposit ×3")


func test_selection_changes_the_background_both_ways() -> void:
	_slot.set_selected(true)
	assert_that(_slot.color).is_equal(ItemSlot.SELECTED_BG)
	_slot.set_selected(false)
	assert_that(_slot.color).is_equal(ItemSlot.NORMAL_BG)


## Opt-in, so a grid slot and a hotbar slot are one widget. ⚠️ Child order is
## icon → key → count and `test_hud.gd` asserts the key at child index 1.
func test_the_key_label_is_opt_in() -> void:
	assert_int(_slot.get_child_count()).is_equal(2) # Icon, count. No key.
	var keyed: ItemSlot = auto_free(ItemSlot.new(9, "0"))
	assert_int(keyed.get_child_count()).is_equal(3)
	assert_str((keyed.get_child(1) as Label).text).is_equal("0")


## The index is echoed back rather than re-derived by the listener: the equipment
## panel hands in an `Equipment.Slot`, which is not an inventory index at all.
func test_a_click_reports_the_index_the_button_and_the_shift_state() -> void:
	var slot: ItemSlot = auto_free(ItemSlot.new(27))
	add_child(slot)
	var seen: Array = []
	slot.slot_pressed.connect(
		func(index: int, button: int, shift: bool) -> void:
			seen.append([index, button, shift]),
	)
	slot._gui_input(_click(MOUSE_BUTTON_RIGHT, true))
	assert_array(seen).contains_exactly([[27, MOUSE_BUTTON_RIGHT, true]])


## Only on press, and only the two buttons the interaction model uses — a middle
## click or a release must not fire a second time through the same handler.
func test_releases_and_other_buttons_are_ignored() -> void:
	var seen: Array = []
	_slot.slot_pressed.connect(func(_i: int, _b: int, _s: bool) -> void: seen.append(true))
	_slot._gui_input(_click(MOUSE_BUTTON_LEFT, false, false))
	_slot._gui_input(_click(MOUSE_BUTTON_MIDDLE, false))
	assert_array(seen).is_empty()
	_slot._gui_input(_click(MOUSE_BUTTON_LEFT, false))
	assert_int(seen.size()).is_equal(1)


func _click(button_index: int, shift: bool, pressed := true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.shift_pressed = shift
	return event
