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

# --- A non-default size (3.5c's chest) ----------------------------------------


## ❗️Every loop must walk the INSTANCE's size, not `SLOT_COUNT`. A missed site
## has no error to show for it: `add_item` would silently write past slot 2 into
## a resized array, or `take_range` would clamp a 2-slot store to 40 and read
## out of bounds.
func test_a_smaller_inventory_fills_spills_and_empties_at_its_own_size() -> void:
	var small := Inventory.new(2)
	assert_int(small.slot_count()).is_equal(2)

	assert_int(small.add_item("dirt", Inventory.STACK_SIZE * 2)).is_equal(0)
	assert_int(small.add_item("stone", 7)).is_equal(7) # No slot 3 to spill into.
	assert_int(small.count_of("dirt")).is_equal(Inventory.STACK_SIZE * 2)

	var taken := small.take_range(0, small.slot_count())
	assert_int(taken.size()).is_equal(2)
	assert_int(small.count_of("dirt")).is_equal(0)

# --- The held-stack API (3.6a) ------------------------------------------------


## Total sum of `count` over every slot plus whatever is being held. ❗️Every call
## in the held-stack API preserves it, and that is the whole contract.
func _total(held := { }) -> int:
	var total: int = held.get("count", 0)
	for i in _inv.slot_count():
		total += _inv.get_slot(i).get("count", 0)
	return total


func test_take_slot_takes_the_whole_stack_and_leaves_it_empty() -> void:
	_inv.add_item("dirt", 12)
	var held := _inv.take_slot(0)
	assert_int(held.count).is_equal(12)
	assert_str(held.id).is_equal("dirt")
	assert_bool(_inv.get_slot(0).is_empty()).is_true()
	assert_int(_total(held)).is_equal(12)


func test_take_slot_of_an_empty_slot_is_nothing_and_emits_nothing() -> void:
	_slot_events.clear()
	assert_bool(_inv.take_slot(3).is_empty()).is_true()
	assert_array(_slot_events).is_empty()


## ❗️The dupe bug this API exists to close: `get_slot` hands back the live dict,
## so a cursor stack built from it would grow every time a pickup magnets in.
func test_take_slots_result_is_not_aliased_to_the_slot() -> void:
	_inv.add_item("dirt", 4)
	var held := _inv.take_slot(0)
	held.count = 99
	assert_bool(_inv.get_slot(0).is_empty()).is_true()
	_inv.add_item("dirt", 4)
	assert_int(_inv.get_slot(0).count).is_equal(4) # Not 103.
	assert_int(held.count).is_equal(99) # And the held stack did not shrink.


func test_take_from_slot_splits_and_detaches_the_remainder() -> void:
	_inv.add_item("stone", 10)
	var held := _inv.take_from_slot(0, 4)
	assert_int(held.count).is_equal(4)
	assert_int(_inv.get_slot(0).count).is_equal(6)
	assert_int(_total(held)).is_equal(10)
	held.count = 50
	assert_int(_inv.get_slot(0).count).is_equal(6)


func test_take_from_slot_clamps_to_what_is_there_and_clears_at_zero() -> void:
	_inv.add_item("stone", 3)
	var held := _inv.take_from_slot(0, 99)
	assert_int(held.count).is_equal(3)
	assert_bool(_inv.get_slot(0).is_empty()).is_true()


func test_take_from_slot_of_nothing_or_zero_is_nothing() -> void:
	_inv.add_item("stone", 3)
	assert_bool(_inv.take_from_slot(0, 0).is_empty()).is_true()
	assert_bool(_inv.take_from_slot(5, 1).is_empty()).is_true()
	assert_int(_inv.get_slot(0).count).is_equal(3)


func test_put_in_an_empty_slot_consumes_the_whole_stack() -> void:
	assert_bool(_inv.put_in_slot(7, { id = "wood", count = 5 }).is_empty()).is_true()
	assert_int(_inv.get_slot(7).count).is_equal(5)
	assert_int(_total()).is_equal(5)


## Detached on the way IN as well: the caller's dict must not become the slot.
func test_put_does_not_alias_the_callers_stack_into_the_slot() -> void:
	var held := { id = "wood", count = 5 }
	_inv.put_in_slot(7, held)
	held.count = 99
	assert_int(_inv.get_slot(7).count).is_equal(5)


func test_a_merge_clamps_to_the_stack_size_and_returns_the_overflow() -> void:
	_inv.add_item("dirt", 95)
	var residue := _inv.put_in_slot(0, { id = "dirt", count = 10 })
	assert_int(_inv.get_slot(0).count).is_equal(Inventory.STACK_SIZE)
	assert_int(residue.count).is_equal(6)
	assert_int(_total(residue)).is_equal(105)


## Nothing moved, nothing emitted, and the caller keeps every last item — the
## plausible wrong answer here is silently eating the stack.
func test_a_put_onto_a_full_same_id_slot_returns_it_untouched() -> void:
	_inv.add_item("dirt", Inventory.STACK_SIZE)
	_slot_events.clear()
	var residue := _inv.put_in_slot(0, { id = "dirt", count = 7 })
	assert_int(residue.count).is_equal(7)
	assert_int(_inv.get_slot(0).count).is_equal(Inventory.STACK_SIZE)
	assert_array(_slot_events).is_empty()


func test_a_put_of_a_different_id_swaps_and_returns_the_displaced_stack() -> void:
	_inv.add_item("dirt", 8)
	var displaced := _inv.put_in_slot(0, { id = "stone", count = 3 })
	assert_str(displaced.id).is_equal("dirt")
	assert_int(displaced.count).is_equal(8)
	assert_str(_inv.get_slot(0).id).is_equal("stone")
	assert_int(_inv.get_slot(0).count).is_equal(3)
	assert_int(_total(displaced)).is_equal(11)


## The displaced stack is detached too, or mutating what you now hold reaches
## back into the slot you just filled.
func test_the_displaced_stack_is_detached() -> void:
	_inv.add_item("dirt", 8)
	var displaced := _inv.put_in_slot(0, { id = "stone", count = 3 })
	displaced.count = 99
	_inv.add_item("dirt", 1)
	assert_int(_inv.count_of("dirt")).is_equal(1)


## An oversized held stack cannot exist through the UI, but the API stays total
## under one anyway rather than silently parking 150 in a 99 slot.
func test_an_oversized_put_clamps_and_hands_back_the_rest() -> void:
	var residue := _inv.put_in_slot(0, { id = "dirt", count = 150 })
	assert_int(_inv.get_slot(0).count).is_equal(Inventory.STACK_SIZE)
	assert_int(residue.count).is_equal(150 - Inventory.STACK_SIZE)


## Round trip: take then put back, every pairing, and the total never moves.
func test_conservation_across_every_take_and_put_pairing() -> void:
	_inv.add_item("dirt", 40)
	_inv.add_item("stone", 40)
	assert_int(_total()).is_equal(80)

	var held := _inv.take_slot(0)
	assert_int(_total(held)).is_equal(80)
	held = _inv.put_in_slot(1, held) # Swap onto the stone.
	assert_int(_total(held)).is_equal(80)
	held = _inv.put_in_slot(5, held) # Into an empty slot.
	assert_int(_total(held)).is_equal(80)
	assert_bool(held.is_empty()).is_true()

	held = _inv.take_from_slot(1, 20) # Half of the dirt now in slot 1.
	assert_int(_total(held)).is_equal(80)
	held = _inv.put_in_slot(1, held) # Merged straight back.
	assert_int(_total(held)).is_equal(80)
	assert_int(_inv.get_slot(1).count).is_equal(40)


## ❗️Fires AFTER the write, not during it: `Player._on_slot_changed` frees and
## re-instantiates the swing hitbox off this signal, so a listener must never see
## a half-finished swap.
func test_slot_changed_fires_once_per_touched_index_and_after_the_write() -> void:
	_inv.add_item("dirt", 8)
	var seen: Array = []
	var inv := _inv
	_inv.slot_changed.connect(
		func(index: int) -> void:
			seen.append([index, inv.get_slot(index).duplicate()]),
	)

	_inv.take_from_slot(0, 3)
	assert_int(seen.size()).is_equal(1)
	assert_int(seen[0][0]).is_equal(0)
	assert_int(seen[0][1].count).is_equal(5) # The POST-write value.

	seen.clear()
	_inv.put_in_slot(0, { id = "stone", count = 1 })
	assert_int(seen.size()).is_equal(1)
	assert_str(seen[0][1].id).is_equal("stone")

# --- add_item_in_range --------------------------------------------------------


## ⚠️ Without the range a shift-click out of the hotbar merges straight back into
## the hotbar stack it just left.
func test_add_item_in_range_never_touches_a_slot_outside_the_span() -> void:
	_inv.add_item("dirt", 10) # Slot 0.
	_slot_events.clear()
	assert_int(_inv.add_item_in_range("dirt", 5, Inventory.HOTBAR_SIZE, Inventory.SLOT_COUNT)).is_equal(0)
	assert_int(_inv.get_slot(0).count).is_equal(10) # Not merged back down.
	assert_int(_inv.get_slot(Inventory.HOTBAR_SIZE).count).is_equal(5)
	assert_array(_slot_events).contains_exactly([Inventory.HOTBAR_SIZE])


func test_add_item_in_range_reports_what_did_not_fit_in_the_span() -> void:
	# One slot of room: 99 fits, the rest comes back even though slot 1 is free.
	assert_int(_inv.add_item_in_range("dirt", 150, 0, 1)).is_equal(150 - Inventory.STACK_SIZE)
	assert_bool(_inv.get_slot(1).is_empty()).is_true()


func test_add_item_in_range_clamps_out_of_bounds_like_take_range() -> void:
	assert_int(_inv.add_item_in_range("dirt", 5, -10, Inventory.SLOT_COUNT + 10)).is_equal(0)
	assert_int(_inv.get_slot(0).count).is_equal(5)


## `add_item` IS this call over the whole array — one stacking implementation, so
## the fill-then-spill order cannot drift between them.
func test_add_item_still_fills_then_spills_through_the_ranged_path() -> void:
	_inv.add_item("stone", 150)
	assert_int(_inv.get_slot(0).count).is_equal(99)
	assert_int(_inv.get_slot(1).count).is_equal(51)
