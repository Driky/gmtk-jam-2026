## Unit tests for the chest (roadmap 3.5c) — the first N-slot container.
## Fresh Terrain + Automation per test, _process off, so the suite drives
## `step_tick()` itself.
##
## The cases here are the ones a plausible implementation gets wrong: the seam's
## RETURN CONTRACT in both directions (an `accept_item` that reports the count it
## was offered rather than the count it took is where items silently vanish), and
## the detachment of what `extract_item` hands back. A real `Inserter` drives the
## last two, because the seam is only correct if the one caller that exists agrees
## with it.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const ChestScene := preload("res://scenes/automation/chest.tscn")
const ConveyorScene := preload("res://scenes/automation/conveyor.tscn")
const InserterScene := preload("res://scenes/automation/inserter.tscn")

## Playable (x in [50, 150)) and far from world edges.
const ORIGIN := Vector2i(100, 100)

var _terrain: Node
var _automation: Node
var _spawner: SpawnerDouble


## Records what the real spawner would have dropped, without the autoload wiring
## or a Pickup in the tree.
class SpawnerDouble:
	extends Node

	var drops: Array = []


	func spawn_at(world_pos: Vector2, id: String, count: int, grants_xp := true) -> void:
		drops.append({ pos = world_pos, id = id, count = count, grants_xp = grants_xp })


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)
	_spawner = auto_free(SpawnerDouble.new())
	_spawner.add_to_group(&"pickup_spawner")
	add_child(_spawner)
	var game: Node = auto_free(GameScript.new()) # Out of the tree: only `state` is read.
	game.state = GameScript.State.BUILD_PHASE
	_automation = auto_free(AutomationScript.new())
	_automation.terrain = _terrain
	_automation.game = game
	add_child(_automation)
	_automation.set_process(false)


## ❗️No `Supply` double anywhere in this suite: a chest is unpowered, so it must
## work on a world with no generator in it at all.
func _chest(cell := ORIGIN) -> Chest:
	# A floor under it: unlike the belt and the inserter (`support_dirs = 0`), a
	# chest is held up by something, and the support queue pops one that is not.
	_terrain.set_tile(cell + Vector2i.DOWN, "dirt")
	var node: Chest = auto_free(ChestScene.instantiate())
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	return node


func _belt(cell: Vector2i, dir := Vector2i.RIGHT) -> Conveyor:
	var c: Conveyor = auto_free(ConveyorScene.instantiate())
	c.automation = _automation
	c.facing = dir
	c.setup(cell)
	add_child(c)
	assert_bool(c.register(_terrain)).is_true()
	c.on_placed()
	return c


func _inserter(cell: Vector2i, dir := Vector2i.RIGHT) -> Inserter:
	var i: Inserter = auto_free(InserterScene.instantiate())
	i.automation = _automation
	i.facing = dir
	i.setup(cell)
	add_child(i)
	assert_bool(i.register(_terrain)).is_true()
	i.on_placed()
	return i

# --- Authoring ----------------------------------------------------------------


## `support_dirs = 15` is the whole utility pitch: unlike a turret or a trap, a
## chest goes anywhere a cell touches solid — including hung off a wall in a
## mineshaft, which is exactly where you want the buffer.
func test_the_scene_authors_an_unpowered_one_by_one_supported_on_any_side() -> void:
	var live: Chest = auto_free(ChestScene.instantiate())
	assert_vector(live.size).is_equal(Vector2i.ONE)
	assert_float(live.power_demand).is_equal(0.0)
	assert_bool(live.directional).is_false()
	assert_str(live.item_id).is_equal("chest")
	assert_int(Deployable.scene_support_dirs(ChestScene)).is_equal(15)


## ❗️**No registry.** A chest does nothing on a tick, so joining one would put a
## node with an empty `on_tick` in the 10 Hz loop forever. It is reachable purely
## through `Terrain.get_entity` — the `Torch` shape.
func test_a_placed_chest_joins_no_tick_registry() -> void:
	var node := _chest()
	assert_int(_automation.machines().size()).is_equal(0)
	assert_object(_terrain.get_entity(ORIGIN)).is_same(node)
	_automation.step_tick()
	assert_int(_automation.tick_count).is_equal(1)


func test_it_owns_an_inventory_at_its_own_size() -> void:
	var node := _chest()
	assert_int(node.storage().slot_count()).is_equal(Chest.CHEST_SLOTS)
	assert_int(node.storage().slot_count()).is_not_equal(Inventory.SLOT_COUNT)

# --- The transfer seam --------------------------------------------------------


## The 3.6 seam. Handed out LIVE — a snapshot could not emit, and the container
## view binds `slot_changed` on this exactly as the HUD hotbar does.
func test_storage_is_the_live_inventory_and_its_signals_reach_the_caller() -> void:
	var node := _chest()
	var changed: Array[int] = []
	node.storage().slot_changed.connect(func(index: int) -> void: changed.append(index))

	node.accept_item("iron", 3)

	assert_int(node.storage().count_of("iron")).is_equal(3)
	assert_array(changed).contains_exactly([0])


## ❗️**Returns what it TOOK, not what it was offered.** A chest with one slot's
## worth of room left must report exactly that, or the inserter's give-back has
## nothing to give back and the remainder is gone.
func test_a_nearly_full_chest_takes_a_partial_stack_and_reports_it() -> void:
	var node := _chest()
	var capacity := Chest.CHEST_SLOTS * Inventory.STACK_SIZE
	node.accept_item("dirt", capacity - 4)

	assert_int(node.accept_item("dirt", 10)).is_equal(4)
	assert_int(node.storage().count_of("dirt")).is_equal(capacity)
	assert_int(node.accept_item("dirt", 1)).is_equal(0) # Full refuses cleanly.


## Unlike the turret and the furnace, a chest routes nothing by id — a buffer that
## only accepted what it already held would jam the first mixed belt it saw.
func test_it_refuses_nothing_by_id() -> void:
	var node := _chest()
	assert_int(node.accept_item("dirt", 1)).is_equal(1)
	assert_int(node.accept_item("copper_ammo", 1)).is_equal(1)
	assert_int(node.accept_item("pickaxe_t1", 1)).is_equal(1)


func test_extract_hands_back_the_first_non_empty_slot_in_slot_order() -> void:
	var node := _chest()
	node.accept_item("dirt", 2)
	node.accept_item("stone", 2)
	node.storage().remove_from_slot(0, 2) # Empty slot 0; slot 1 still holds stone.

	var taken := node.extract_item(1)

	assert_str(taken.id).is_equal("stone")
	assert_int(taken.count).is_equal(1)
	assert_int(node.storage().count_of("stone")).is_equal(1)


## ❗️Detached, like `take_range`'s copies: what comes out of the seam travels to
## a belt slot and gets mutated there. Handing out the chest's own dict would let
## a belt advance rewrite a slot the chest still thinks it owns.
func test_what_extract_returns_is_detached_from_the_slot() -> void:
	var node := _chest()
	node.accept_item("iron", 5)

	var taken := node.extract_item(2)
	taken.count = 99

	assert_int(node.storage().count_of("iron")).is_equal(3)


func test_an_empty_chest_gives_nothing() -> void:
	var node := _chest()
	assert_bool(node.extract_item(1).is_empty()).is_true()

# --- Popping ------------------------------------------------------------------


## Swinging a chest down must not delete what is in it. `take_cargo` is
## destructive by contract, and `pop_to_pickup` drops every stack through the
## same sink as the chest item itself.
func test_popping_it_drops_the_chest_and_every_stack_it_held() -> void:
	var node := _chest()
	node.accept_item("dirt", 150) # Two slots: 99 + 51.
	node.accept_item("iron", 4)

	node.pop_to_pickup()

	var dropped: Array = []
	for drop: Dictionary in _spawner.drops:
		dropped.append([drop.id, drop.count])
	assert_array(dropped).contains_exactly([["chest", 1], ["dirt", 99], ["dirt", 51], ["iron", 4]])


func test_take_cargo_leaves_it_empty() -> void:
	var node := _chest()
	node.accept_item("dirt", 3)

	assert_int(node.take_cargo().size()).is_equal(1)

	assert_array(node.take_cargo()).is_empty() # Destructive: no second helping.
	assert_int(node.storage().count_of("dirt")).is_equal(0)

# --- Through a real inserter ---------------------------------------------------


## The exit criterion, half one: an inserter fills a chest off a belt.
func test_an_inserter_moves_items_from_a_belt_into_a_chest() -> void:
	var chest := _chest(ORIGIN + Vector2i.RIGHT)
	var belt := _belt(ORIGIN + Vector2i.LEFT, Vector2i.RIGHT)
	_inserter(ORIGIN, Vector2i.RIGHT)
	belt.accept_item("iron", 1)

	_automation.step_tick()

	assert_bool(belt.slot_empty()).is_true()
	assert_int(chest.storage().count_of("iron")).is_equal(1)


## The exit criterion, half two — and the direction a `peek`-less seam could get
## wrong on its own: the chest is the SOURCE here, so `extract_item` runs before
## anyone knows the belt will take it.
func test_an_inserter_pulls_items_back_out_of_a_chest_onto_a_belt() -> void:
	var chest := _chest(ORIGIN + Vector2i.LEFT)
	var belt := _belt(ORIGIN + Vector2i.RIGHT, Vector2i.RIGHT)
	_inserter(ORIGIN, Vector2i.RIGHT)
	chest.accept_item("copper_bar", 2)

	_automation.step_tick()

	assert_int(chest.storage().count_of("copper_bar")).is_equal(1)
	assert_bool(belt.slot_empty()).is_false()


## Back-pressure through the give-back: a full destination must leave the chest's
## count untouched, not one short. This is the path where the item is in neither
## end if `accept_item` lies about what it took.
func test_a_refused_swing_hands_the_item_back_to_the_chest() -> void:
	var chest := _chest(ORIGIN + Vector2i.LEFT)
	var belt := _belt(ORIGIN + Vector2i.RIGHT, Vector2i.RIGHT)
	_inserter(ORIGIN, Vector2i.RIGHT)
	chest.accept_item("iron", 3)
	belt.accept_item("stone", 1) # One slot, now occupied.

	_automation.step_tick()

	assert_int(chest.storage().count_of("iron")).is_equal(3)
