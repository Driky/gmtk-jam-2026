## Unit tests for what the player is wearing (roadmap 3.6a). A fresh `Equipment`
## per test; `slot_accepts` is static and pure, so the sweeps below run against the
## real `ItemDefs` table without touching the `Items` autoload.
extends GdUnitTestSuite

## Every panel slot, for the sweeps that have to hold for all of them.
const ALL_SLOTS: Array[int] = [
	Equipment.Slot.HELMET,
	Equipment.Slot.CHEST,
	Equipment.Slot.LEGS,
	Equipment.Slot.FEET,
	Equipment.Slot.BACK,
	Equipment.Slot.RING_1,
	Equipment.Slot.RING_2,
	Equipment.Slot.NECKLACE,
]

## The seven authored pieces and the ONE slot each belongs in.
const AUTHORED: Dictionary = {
	"copper_helmet": Equipment.Slot.HELMET,
	"copper_chestplate": Equipment.Slot.CHEST,
	"copper_greaves": Equipment.Slot.LEGS,
	"copper_boots": Equipment.Slot.FEET,
	"copper_cloak": Equipment.Slot.BACK,
	"copper_amulet": Equipment.Slot.NECKLACE,
}

var _eq: Equipment
var _events: Array = []


func before_test() -> void:
	_eq = Equipment.new()
	_events = []
	_eq.slot_changed.connect(func(slot: int) -> void: _events.append(slot))


func test_eight_slots_all_empty() -> void:
	assert_int(_eq.slot_count()).is_equal(8)
	assert_int(ALL_SLOTS.size()).is_equal(_eq.slot_count())
	for slot in ALL_SLOTS:
		assert_str(_eq.get_item(slot)).is_equal("")
	assert_float(_eq.armor_total()).is_equal(0.0)

# --- slot_accepts -------------------------------------------------------------


## ❗️The zero-migration claim, pinned. `ItemDefs.stats_for` never returns null and
## both fallbacks default to `NONE`, so nothing that existed before 3.6a became
## wearable — and a `.tres` authored later with a stray slot fails here rather
## than by being worn.
func test_every_non_equippable_authored_item_is_rejected_by_every_slot() -> void:
	for id: String in ItemDefs.STATS:
		if ItemDefs.stats_for(id).equip_slot != ItemStats.EquipSlot.NONE:
			continue
		for slot in ALL_SLOTS:
			assert_bool(Equipment.slot_accepts(slot, id)).override_failure_message(
				"%s must not be equippable in slot %d" % [id, slot],
			).is_false()


func test_every_material_is_rejected_by_every_slot() -> void:
	for id: String in Materials.ORDER:
		for slot in ALL_SLOTS:
			assert_bool(Equipment.slot_accepts(slot, id)).override_failure_message(
				"material %s must not be equippable in slot %d" % [id, slot],
			).is_false()


func test_nothing_and_an_unknown_id_are_rejected() -> void:
	for slot in ALL_SLOTS:
		assert_bool(Equipment.slot_accepts(slot, "")).is_false()
		assert_bool(Equipment.slot_accepts(slot, "not_a_thing")).is_false()


## Each of the six single-slot pieces fits EXACTLY its own slot — the plausible
## wrong answer is an off-by-one enum mapping that puts greaves on your head.
func test_each_authored_piece_is_accepted_by_exactly_its_own_slot() -> void:
	for id: String in AUTHORED:
		var wanted: int = AUTHORED[id]
		for slot in ALL_SLOTS:
			assert_bool(Equipment.slot_accepts(slot, id)).override_failure_message(
				"%s in slot %d (expected only %d)" % [id, slot, wanted],
			).is_equal(slot == wanted)


## ❗️`RING` is one authored value that fits TWO slots, and `ItemStats` must not
## know there are two.
func test_a_ring_is_accepted_by_both_ring_slots_and_nothing_else() -> void:
	for slot in ALL_SLOTS:
		var is_ring: bool = slot == Equipment.Slot.RING_1 or slot == Equipment.Slot.RING_2
		assert_bool(Equipment.slot_accepts(slot, "copper_ring")).is_equal(is_ring)


## The whole set is authored, so there is no slot the panel can offer with nothing
## to put in it.
func test_every_slot_has_at_least_one_authored_piece() -> void:
	for slot in ALL_SLOTS:
		var found := false
		for id: String in ItemDefs.STATS:
			if Equipment.slot_accepts(slot, id):
				found = true
				break
		assert_bool(found).override_failure_message(
			"slot %d has no authored piece" % slot,
		).is_true()

# --- equip / unequip ----------------------------------------------------------


func test_equipping_an_empty_slot_displaces_nothing_and_emits_once() -> void:
	assert_str(_eq.equip(Equipment.Slot.HELMET, "copper_helmet")).is_equal("")
	assert_str(_eq.get_item(Equipment.Slot.HELMET)).is_equal("copper_helmet")
	assert_array(_events).contains_exactly([Equipment.Slot.HELMET])


## The displaced id is how the screen knows what to hand back to the cursor.
##
## ❗️Asserted with the SAME id, and that is the whole point: exactly one piece per
## slot is authored, so identical is the only displacement that exists — and a
## shortcut returning "" for it would look exactly like an empty slot to the
## screen, which would consume one from the cursor for a swap that never happened.
func test_equip_always_goes_in_and_returns_the_displaced_id() -> void:
	assert_str(_eq.equip(Equipment.Slot.HELMET, "copper_helmet")).is_equal("")
	_events.clear()
	assert_str(_eq.equip(Equipment.Slot.HELMET, "copper_helmet")).is_equal("copper_helmet")
	assert_str(_eq.get_item(Equipment.Slot.HELMET)).is_equal("copper_helmet")
	assert_array(_events).contains_exactly([Equipment.Slot.HELMET])


## An id the slot refuses changes nothing and emits nothing — the screen asks
## `slot_accepts` first, and this is the belt to that brace.
func test_equipping_something_the_slot_refuses_is_a_no_op() -> void:
	_eq.equip(Equipment.Slot.HELMET, "copper_helmet")
	_events.clear()
	assert_str(_eq.equip(Equipment.Slot.HELMET, "copper_boots")).is_equal("")
	assert_str(_eq.get_item(Equipment.Slot.HELMET)).is_equal("copper_helmet")
	assert_array(_events).is_empty()


## Both ring slots hold one each rather than the second evicting the first.
func test_the_two_ring_slots_are_independent() -> void:
	_eq.equip(Equipment.Slot.RING_1, "copper_ring")
	assert_str(_eq.equip(Equipment.Slot.RING_2, "copper_ring")).is_equal("")
	assert_str(_eq.get_item(Equipment.Slot.RING_1)).is_equal("copper_ring")
	assert_str(_eq.get_item(Equipment.Slot.RING_2)).is_equal("copper_ring")
	assert_float(_eq.armor_total()).is_equal_approx(2.0, 0.001)


func test_unequip_returns_what_was_worn_and_empties_the_slot() -> void:
	_eq.equip(Equipment.Slot.FEET, "copper_boots")
	_events.clear()
	assert_str(_eq.unequip(Equipment.Slot.FEET)).is_equal("copper_boots")
	assert_str(_eq.get_item(Equipment.Slot.FEET)).is_equal("")
	assert_array(_events).contains_exactly([Equipment.Slot.FEET])


func test_unequipping_an_empty_slot_is_nothing_and_emits_nothing() -> void:
	assert_str(_eq.unequip(Equipment.Slot.FEET)).is_equal("")
	assert_array(_events).is_empty()

# --- armor_total --------------------------------------------------------------


func test_armor_total_sums_filled_slots_only() -> void:
	_eq.equip(Equipment.Slot.HELMET, "copper_helmet")
	assert_float(_eq.armor_total()).is_equal_approx(3.0, 0.001)
	_eq.equip(Equipment.Slot.CHEST, "copper_chestplate")
	assert_float(_eq.armor_total()).is_equal_approx(7.0, 0.001)
	_eq.unequip(Equipment.Slot.HELMET)
	assert_float(_eq.armor_total()).is_equal_approx(4.0, 0.001)


## The figure the mitigation curve is read against.
##
## ⚠️ **16, not the 15 the seven `.tres` files sum to.** A fully-equipped player
## wears EIGHT items, because `copper_ring` fills both ring slots — the same one
## authored id twice. Worth pinning precisely because the two numbers look like
## each other's typo.
func test_the_full_authored_set_totals_sixteen() -> void:
	_eq.equip(Equipment.Slot.HELMET, "copper_helmet")
	_eq.equip(Equipment.Slot.CHEST, "copper_chestplate")
	_eq.equip(Equipment.Slot.LEGS, "copper_greaves")
	_eq.equip(Equipment.Slot.FEET, "copper_boots")
	_eq.equip(Equipment.Slot.BACK, "copper_cloak")
	_eq.equip(Equipment.Slot.RING_1, "copper_ring")
	_eq.equip(Equipment.Slot.RING_2, "copper_ring")
	_eq.equip(Equipment.Slot.NECKLACE, "copper_amulet")
	assert_float(_eq.armor_total()).is_equal_approx(16.0, 0.001)

# --- slot_for -----------------------------------------------------------------


func test_slot_for_names_the_one_slot_a_piece_belongs_in() -> void:
	for id: String in AUTHORED:
		assert_int(_eq.slot_for(id)).is_equal(AUTHORED[id])


func test_slot_for_is_minus_one_for_anything_unwearable() -> void:
	assert_int(_eq.slot_for("")).is_equal(-1)
	assert_int(_eq.slot_for("dirt")).is_equal(-1)
	assert_int(_eq.slot_for("miner")).is_equal(-1)


## A second ring must not evict the first — the auto-target is the free slot.
func test_slot_for_a_ring_prefers_the_free_ring_slot() -> void:
	assert_int(_eq.slot_for("copper_ring")).is_equal(Equipment.Slot.RING_1)
	_eq.equip(Equipment.Slot.RING_1, "copper_ring")
	assert_int(_eq.slot_for("copper_ring")).is_equal(Equipment.Slot.RING_2)

# --- Items.reset_run ----------------------------------------------------------


## ❗️`reset_run` replaces the inventory; it has to replace this too. Forget it and
## you keep last run's armor — invisible until run two.
func test_reset_run_clears_equipment() -> void:
	Items.equipment.equip(Equipment.Slot.HELMET, "copper_helmet")
	assert_float(Items.equipment.armor_total()).is_greater(0.0)
	Items.reset_run()
	assert_float(Items.equipment.armor_total()).is_equal(0.0)
	assert_str(Items.equipment.get_item(Equipment.Slot.HELMET)).is_equal("")
