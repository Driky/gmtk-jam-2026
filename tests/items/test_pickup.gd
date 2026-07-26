## Unit tests for the looting XP channel (roadmap 2.6).
## Uses the scene but never adds it to the tree: collect() is called directly,
## so no player has to be staged at the right distance and _physics_process
## can't collect out from under a test.
extends GdUnitTestSuite

const PickupScene := preload("res://scenes/pickup.tscn")


func before_test() -> void:
	# Fresh inventory per test — leftovers from another test would change what
	# a collection is able to accept, and accepted count is what XP scales on.
	Items.reset_run()


## Lifetime looting XP on the live autoload; asserted as a DELTA, since other
## suites in the same run have already moved the number.
func _loot_xp() -> float:
	return Progression.xp_by_source.get("looting", 0.0)


func _pickup(id: String, count: int, grants_xp := true) -> Node2D:
	var pickup: Node2D = auto_free(PickupScene.instantiate())
	pickup.setup(id, count, grants_xp)
	return pickup


func test_collecting_grants_the_material_rate_per_unit() -> void:
	var before := _loot_xp()
	_pickup("stone", 3).collect()
	assert_float(_loot_xp() - before).is_equal_approx(3.0 * Materials.loot_xp("stone"), 0.001)


## The whole point of the channel: depth pays. Gold has to dwarf stone, or
## there's no reason to leave the Core.
func test_rarer_ore_is_worth_dramatically_more() -> void:
	assert_float(Materials.loot_xp("gold")).is_greater(Materials.loot_xp("copper"))
	assert_float(Materials.loot_xp("copper")).is_greater(Materials.loot_xp("stone"))
	assert_float(Materials.loot_xp("magmatite")).is_greater(Materials.loot_xp("gold"))


## The drop of a block the player placed themselves: carried all the way from
## the tile's player_placed flag (terrain.md).
func test_a_vetoed_drop_pays_nothing() -> void:
	var before := _loot_xp()
	_pickup("gold", 5, false).collect()
	assert_float(_loot_xp() - before).is_equal_approx(0.0, 0.001)


func test_items_with_no_entry_are_worth_nothing() -> void:
	var before := _loot_xp()
	_pickup("pickaxe_t1", 1).collect()
	assert_float(_loot_xp() - before).is_equal_approx(0.0, 0.001)


## Only what the inventory actually took is paid for; the remainder stays on
## the ground and pays when it's picked up later.
func test_a_partial_collection_pays_only_for_what_fit() -> void:
	# 39 full stacks + one at 95, leaving room for exactly 4 more dirt.
	Items.player_inventory.add_item("dirt", 39 * Inventory.STACK_SIZE + 95)
	var pickup := _pickup("dirt", 10)
	var before := _loot_xp()
	pickup.collect()
	assert_int(pickup.count).is_equal(6) # Rejected remainder stays in the world.
	assert_float(_loot_xp() - before).is_equal_approx(4.0 * Materials.loot_xp("dirt"), 0.001)


func test_a_fully_rejected_collection_pays_nothing() -> void:
	Items.player_inventory.add_item("dirt", Inventory.SLOT_COUNT * Inventory.STACK_SIZE)
	var pickup := _pickup("dirt", 10)
	var before := _loot_xp()
	pickup.collect()
	assert_int(pickup.count).is_equal(10)
	assert_float(_loot_xp() - before).is_equal_approx(0.0, 0.001)
