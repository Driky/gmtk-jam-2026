## Unit tests for the death loot bag (roadmap 2.5). Collection is driven
## directly rather than through physics — the fall/settle half is the same
## manual integration pickup.gd already uses.
extends GdUnitTestSuite

const LootBagScene := preload("res://scenes/loot_bag.tscn")


func before_test() -> void:
	Items.reset_run() # Never leak inventory state between tests.


func after_test() -> void:
	Items.reset_run()


func _bag_with(slots: Array[Dictionary]) -> LootBag:
	var bag: LootBag = auto_free(LootBagScene.instantiate())
	bag.setup(slots)
	return bag


func test_setup_carries_the_slots() -> void:
	var bag := _bag_with([{ id = "dirt", count = 4 }])
	assert_int(bag.contents.size()).is_equal(1)
	assert_str(bag.contents[0].id).is_equal("dirt")


func test_collect_returns_everything_to_the_inventory() -> void:
	var bag := _bag_with([{ id = "dirt", count = 4 }, { id = "stone", count = 7 }])
	add_child(bag)
	var player: Node2D = auto_free(Node2D.new())
	player.add_to_group(&"player")
	add_child(player)
	bag._try_collect()
	assert_int(Items.player_inventory.count_of("dirt")).is_equal(4)
	assert_int(Items.player_inventory.count_of("stone")).is_equal(7)
	assert_bool(bag.contents.is_empty()).is_true()


## Same contract as pickup.gd: a full inventory must not silently delete the
## rest of the haul — recovering a bag twice has to be possible.
func test_leftovers_stay_in_the_bag_when_the_inventory_is_full() -> void:
	var inventory := Items.player_inventory
	for i in Inventory.SLOT_COUNT:
		inventory.add_item("stone", Inventory.STACK_SIZE)
	var bag := _bag_with([{ id = "dirt", count = 4 }])
	add_child(bag)
	var player: Node2D = auto_free(Node2D.new())
	player.add_to_group(&"player")
	add_child(player)
	bag._try_collect()
	assert_int(bag.contents.size()).is_equal(1)
	assert_int(bag.contents[0].count).is_equal(4)
	assert_bool(is_instance_valid(bag)).is_true() # Not freed — still recoverable.


## Regression: the bag drops at the player's own feet and the body stays there
## for the whole respawn timer, so a corpse that could collect would hand the
## haul straight back on the next physics frame and dying would cost nothing.
func test_a_dead_player_cannot_collect() -> void:
	var bag := _bag_with([{ id = "dirt", count = 4 }])
	add_child(bag)
	var player: DeadPlayerDouble = auto_free(DeadPlayerDouble.new())
	player.add_to_group(&"player")
	add_child(player)
	bag._try_collect()
	assert_int(Items.player_inventory.count_of("dirt")).is_equal(0)
	assert_int(bag.contents.size()).is_equal(1)
	# ...and it is collectable the moment they're back on their feet.
	player.dead = false
	bag._try_collect()
	assert_int(Items.player_inventory.count_of("dirt")).is_equal(4)


## Stands in for a downed player sitting on top of its own bag.
class DeadPlayerDouble:
	extends Node2D

	var dead := true


	func is_dead() -> bool:
		return dead


## Out of range it must do nothing at all; a bag that emptied itself from
## across the map would make the walk-back pointless.
func test_no_collection_out_of_range() -> void:
	var bag := _bag_with([{ id = "dirt", count = 4 }])
	add_child(bag)
	bag.global_position = Vector2(1000.0, 0.0)
	var player: Node2D = auto_free(Node2D.new())
	player.add_to_group(&"player")
	add_child(player)
	bag._try_collect()
	assert_int(Items.player_inventory.count_of("dirt")).is_equal(0)
	assert_int(bag.contents.size()).is_equal(1)
