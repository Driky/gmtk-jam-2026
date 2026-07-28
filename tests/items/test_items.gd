## Unit tests for the crafting-range queries (roadmap 3.6b) — `containers_near`,
## `gather_available` and `consume_available` on `scripts/items/items.gd`.
##
## A FRESH `Items` instance per test, never the autoload: the queries read
## `player_inventory` off `self`, so a second instance in the tree is a complete
## fixture and the live run's bag is never touched.
##
## The cases here are the ones a plausible implementation gets wrong. `consume` is
## the one that matters most: a per-id loop that runs short on the LAST input has
## already eaten the first ones and produces nothing, which is an item sink with no
## error message anywhere.
extends GdUnitTestSuite

const ItemsScript := preload("res://scripts/items/items.gd")
const ChestScene := preload("res://scenes/automation/chest.tscn")

## The player, for every case below. Chests are placed relative to it.
const HERE := Vector2.ZERO

var _items: Node


func before_test() -> void:
	_items = auto_free(ItemsScript.new())
	add_child(_items)


## A chest in the tree at `at`, already carrying `stacks`. Its `&"container"`
## group membership comes from the scene root, which is the whole discovery
## mechanism under test.
func _chest(at: Vector2, stacks := { }) -> Node2D:
	var chest: Node2D = auto_free(ChestScene.instantiate())
	add_child(chest)
	chest.global_position = at
	for id: String in stacks:
		chest.storage().add_item(id, stacks[id])
	return chest

# --- Discovery ----------------------------------------------------------------


func test_it_is_inert_with_no_container_in_the_tree() -> void:
	_items.player_inventory.add_item("stone", 7)
	assert_array(_items.containers_near(HERE)).is_empty()
	assert_dict(_items.gather_available(HERE)).is_equal({ stone = 7 })


## ⚠️ The radius is 12 tiles, not the player's 4.5-tile reach — but it is still a
## radius, and a chest across the room must not pay for a craft.
func test_a_container_out_of_range_is_excluded() -> void:
	_chest(Vector2(0.0, 100.0), { stone = 10 })
	_chest(Vector2(0.0, ItemsScript.CRAFTING_RANGE_PX + 8.0), { stone = 99 })
	assert_int(_items.containers_near(HERE).size()).is_equal(1)
	assert_dict(_items.gather_available(HERE)).is_equal({ stone = 10 })


## ❗️The order is STATED — row-major by `global_position`, y then x — so which
## chest a craft drains cannot drift across a save round-trip, where
## `get_nodes_in_group`'s scene-tree order would.
func test_containers_come_back_row_major() -> void:
	var third := _chest(Vector2(100.0, 100.0))
	var first := _chest(Vector2(50.0, 0.0))
	var second := _chest(Vector2(0.0, 100.0))
	assert_array(_items.containers_near(HERE)).contains_exactly([first, second, third])


## ⚠️ The group is duck-typed on `Node2D` + `storage()`, never on `Chest`: the
## radius filter already needs the position, and `storage()` is what makes
## something a container everywhere else. Anything else in the group is skipped
## rather than crashing the tab that calls this every 0.25 s.
func test_a_group_member_that_is_not_a_container_is_skipped() -> void:
	var impostor: Node2D = auto_free(Node2D.new())
	impostor.add_to_group(&"container")
	add_child(impostor)
	var plain: Node = auto_free(Node.new())
	plain.add_to_group(&"container")
	add_child(plain)
	_chest(Vector2(0.0, 32.0), { stone = 4 })
	assert_int(_items.containers_near(HERE).size()).is_equal(1)
	assert_dict(_items.gather_available(HERE)).is_equal({ stone = 4 })


## A container freed mid-scan cannot be dereferenced. ⚠️ Godot drops a node from
## its groups when it *actually* deletes it, so the corpse this guards against is
## not constructible from a test — what is testable is that a chest still alive on
## a pending `queue_free()` is handled rather than raising, which is the shape the
## untyped loop and the `is_instance_valid` filter exist for.
func test_a_container_pending_free_does_not_raise() -> void:
	var chest := _chest(Vector2(0.0, 32.0), { stone = 4 })
	chest.queue_free()
	assert_array(_items.containers_near(HERE)).is_not_null()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(_items.containers_near(HERE)).is_empty()
	assert_dict(_items.gather_available(HERE)).is_empty()

# --- The tally ----------------------------------------------------------------


func test_the_tally_sums_the_bag_and_every_container_in_range() -> void:
	_items.player_inventory.add_item("stone", 5)
	_items.player_inventory.add_item("copper", 2)
	_chest(Vector2(0.0, 32.0), { stone = 10 })
	_chest(Vector2(32.0, 0.0), { copper = 3, coal = 1 })
	assert_dict(_items.gather_available(HERE)).is_equal({ stone = 15, copper = 5, coal = 1 })


## Split stacks of the same id across slots must add up, not overwrite.
func test_the_tally_sums_across_slots() -> void:
	_items.player_inventory.add_item("stone", Inventory.STACK_SIZE + 20)
	assert_dict(_items.gather_available(HERE)).is_equal({ stone = Inventory.STACK_SIZE + 20 })


## ❗️**Equipment is excluded by construction** — `equipment` is a separate object
## and nothing in the queries reads it. Pinned because the consume step would
## otherwise be able to silently un-equip you, and "why did my armor vanish" is a
## bug report rather than a feature.
func test_equipment_is_excluded_from_the_tally() -> void:
	_items.equipment.equip(Equipment.Slot.HELMET, "copper_helmet")
	_items.player_inventory.add_item("stone", 1)
	assert_dict(_items.gather_available(HERE)).is_equal({ stone = 1 })


func test_equipment_is_not_reachable_by_a_craft() -> void:
	_items.equipment.equip(Equipment.Slot.HELMET, "copper_helmet")
	assert_bool(_items.consume_available(HERE, { copper_helmet = 1 })).is_false()
	assert_str(_items.equipment.get_item(Equipment.Slot.HELMET)).is_equal("copper_helmet")

# --- Consuming ----------------------------------------------------------------


func test_consume_pays_the_whole_cost_out_of_the_bag() -> void:
	_items.player_inventory.add_item("stone", 12)
	_items.player_inventory.add_item("copper", 6)
	assert_bool(_items.consume_available(HERE, { stone = 10, copper = 5 })).is_true()
	assert_int(_items.player_inventory.count_of("stone")).is_equal(2)
	assert_int(_items.player_inventory.count_of("copper")).is_equal(1)


## ❗️**All-or-nothing, and this is the case the two-phase shape exists for.** The
## cost iterates `stone` first (dictionaries keep insertion order), so a naive
## per-id loop removes the ten stone and only then discovers the copper is short —
## eating the inputs and producing nothing.
func test_consume_short_by_one_input_removes_nothing() -> void:
	_items.player_inventory.add_item("stone", 10)
	assert_bool(_items.consume_available(HERE, { stone = 10, copper = 1 })).is_false()
	assert_int(_items.player_inventory.count_of("stone")).is_equal(10)


## Short by one of a SINGLE input, across the whole pool.
func test_consume_short_across_the_pool_removes_nothing() -> void:
	_items.player_inventory.add_item("stone", 4)
	var chest := _chest(Vector2(0.0, 32.0), { stone = 5 })
	assert_bool(_items.consume_available(HERE, { stone = 10 })).is_false()
	assert_int(_items.player_inventory.count_of("stone")).is_equal(4)
	assert_int(chest.storage().count_of("stone")).is_equal(5)


## The bag first, then containers — so a craft you can afford by hand never
## reaches into a chest you were using as a buffer.
func test_consume_drains_the_bag_before_any_container() -> void:
	_items.player_inventory.add_item("stone", 3)
	var chest := _chest(Vector2(0.0, 32.0), { stone = 10 })
	assert_bool(_items.consume_available(HERE, { stone = 5 })).is_true()
	assert_int(_items.player_inventory.count_of("stone")).is_equal(0)
	assert_int(chest.storage().count_of("stone")).is_equal(8)


func test_consume_drains_containers_in_row_major_order() -> void:
	var second := _chest(Vector2(100.0, 100.0), { stone = 4 })
	var first := _chest(Vector2(0.0, 100.0), { stone = 4 })
	assert_bool(_items.consume_available(HERE, { stone = 6 })).is_true()
	assert_int(first.storage().count_of("stone")).is_equal(0)
	assert_int(second.storage().count_of("stone")).is_equal(2)


## An out-of-range chest cannot pay, and must not be drained on the way past.
func test_consume_never_reaches_a_container_out_of_range() -> void:
	var far := _chest(Vector2(0.0, ItemsScript.CRAFTING_RANGE_PX + 8.0), { stone = 99 })
	assert_bool(_items.consume_available(HERE, { stone = 1 })).is_false()
	assert_int(far.storage().count_of("stone")).is_equal(99)


## ⚠️ A recipe with no inputs is refused rather than trivially granted: no row in
## the table has one, and treating it as payable makes a malformed row an infinite
## tap on the crafting tab.
func test_an_empty_cost_is_refused() -> void:
	assert_bool(_items.consume_available(HERE, { })).is_false()
