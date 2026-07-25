## Unit tests for the Inventory model (roadmap 1.6).
## Runs against a fresh instance per test — never the live Items autoload.
extends GdUnitTestSuite

var _inv: Inventory
var _slot_events: Array = []
var _selected_events: Array = []


func before_test() -> void:
	_inv = Inventory.new()
	_slot_events = []
	_selected_events = []
	_inv.slot_changed.connect(
		func(index: int) -> void:
			_slot_events.append(index),
	)
	_inv.selected_changed.connect(
		func(index: int) -> void:
			_selected_events.append(index),
	)


func test_add_fills_existing_stack_before_new_slot() -> void:
	assert_int(_inv.add_item("dirt", 10)).is_equal(0)
	assert_int(_inv.add_item("dirt", 10)).is_equal(0)
	assert_int(_inv.get_slot(0).count).is_equal(20)
	assert_bool(_inv.get_slot(1).is_empty()).is_true()


func test_add_splits_across_stack_boundary() -> void:
	assert_int(_inv.add_item("stone", 150)).is_equal(0)
	assert_int(_inv.get_slot(0).count).is_equal(99)
	assert_int(_inv.get_slot(1).count).is_equal(51)
	assert_int(_inv.count_of("stone")).is_equal(150)


func test_add_returns_leftover_when_full() -> void:
	for i in Inventory.SLOT_COUNT:
		_inv.add_item("dirt", 99)
	assert_int(_inv.add_item("dirt", 5)).is_equal(5)
	assert_int(_inv.count_of("dirt")).is_equal(Inventory.SLOT_COUNT * 99)


func test_different_ids_use_separate_slots() -> void:
	_inv.add_item("dirt", 1)
	_inv.add_item("stone", 1)
	assert_str(_inv.get_slot(0).id).is_equal("dirt")
	assert_str(_inv.get_slot(1).id).is_equal("stone")


func test_remove_clears_slot_at_zero() -> void:
	_inv.add_item("dirt", 3)
	assert_int(_inv.remove_from_slot(0, 3)).is_equal(3)
	assert_bool(_inv.get_slot(0).is_empty()).is_true()
	assert_int(_inv.remove_from_slot(0, 1)).is_equal(0)


func test_consume_selected_success_and_failure() -> void:
	_inv.add_item("wood", 2)
	assert_bool(_inv.consume_selected()).is_true()
	assert_bool(_inv.consume_selected(5)).is_false() # only 1 left
	assert_bool(_inv.consume_selected()).is_true()
	assert_bool(_inv.consume_selected()).is_false() # empty slot


func test_selected_slot_clamped_to_hotbar_and_signals() -> void:
	_inv.selected_slot = 4
	_inv.selected_slot = 4 # no re-emit on same value
	_inv.selected_slot = 99 # clamped to last hotbar slot
	assert_int(_inv.selected_slot).is_equal(Inventory.HOTBAR_SIZE - 1)
	assert_array(_selected_events).contains_exactly([4, Inventory.HOTBAR_SIZE - 1])


func test_slot_changed_payloads() -> void:
	_inv.add_item("dirt", 150) # slots 0 (99) + 1 (51)
	_inv.remove_from_slot(1, 51)
	assert_array(_slot_events).contains_exactly([0, 1, 1])

# --- take_range (death drop, 2.5) --------------------------------------------


## The death-drop split: the hotbar survives, everything past it goes to the bag.
func test_take_range_empties_only_the_requested_span() -> void:
	_inv.add_item("dirt", 99 * Inventory.HOTBAR_SIZE + 5) # fills 0-9, spills into 10
	var taken := _inv.take_range(Inventory.HOTBAR_SIZE, Inventory.SLOT_COUNT)
	assert_int(taken.size()).is_equal(1)
	assert_int(taken[0].count).is_equal(5)
	assert_bool(_inv.get_slot(Inventory.HOTBAR_SIZE).is_empty()).is_true()
	assert_int(_inv.get_slot(0).count).is_equal(99) # hotbar untouched


func test_take_range_skips_empty_slots_and_emits_per_slot() -> void:
	_inv.add_item("dirt", 1)
	_inv.add_item("wood", 1)
	_slot_events.clear()
	var taken := _inv.take_range(0, Inventory.SLOT_COUNT)
	assert_int(taken.size()).is_equal(2) # not 40 — empties are skipped
	assert_array(_slot_events).contains_exactly([0, 1])


## The returned dicts are detached copies: mutating a bag's contents must not
## reach back into the (now empty) inventory slot.
func test_take_range_returns_detached_copies() -> void:
	_inv.add_item("dirt", 4)
	var taken := _inv.take_range(0, 1)
	taken[0].count = 99
	assert_bool(_inv.get_slot(0).is_empty()).is_true()


func test_take_range_clamps_out_of_bounds() -> void:
	_inv.add_item("dirt", 4)
	assert_int(_inv.take_range(-10, Inventory.SLOT_COUNT + 10).size()).is_equal(1)
