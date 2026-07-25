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
