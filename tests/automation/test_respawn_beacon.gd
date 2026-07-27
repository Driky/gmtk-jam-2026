## Unit tests for the respawn beacon (roadmap 3.5c). Fresh Terrain + Automation
## per test, _process off, so the suite drives `step_tick()` itself.
##
## The beacon has no behaviour — the respawn RULE is tested in
## `tests/player/test_player.gd`. What is worth pinning here is its authoring,
## because every one of those numbers is a silent failure: the group is what the
## player queries (a typo makes beacons simply never work, with no error), and
## `support_dirs = 4` is what keeps the respawn formula's "feet on top of the
## anchor cell, ground below" true.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const BeaconScene := preload("res://scenes/automation/respawn_beacon.tscn")

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


## ❗️No `Supply` double anywhere in this suite: a beacon is unpowered, so it must
## work on a world with no generator in it at all.
func _beacon(cell := ORIGIN) -> RespawnBeacon:
	_terrain.set_tile(cell + Vector2i.DOWN, "dirt")
	var node: RespawnBeacon = auto_free(BeaconScene.instantiate())
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	return node

# --- Authoring ----------------------------------------------------------------


## ❗️**`support_dirs = 4` is DOWN, and it is not cosmetic.** The respawn formula
## puts the player's feet at the TOP EDGE of the anchor cell and assumes ground
## below it; a wall- or ceiling-mounted beacon would drop you into mid-air or
## inside solid rock. Same argument that moved 3.5a's turret from 1 to 4, so this
## asserts the predicate rather than the number alone.
func test_a_beacon_needs_a_floor_under_it_and_not_a_ceiling_over_it() -> void:
	var dirs := Deployable.scene_support_dirs(BeaconScene)
	assert_int(dirs).is_equal(4)

	_terrain.set_tile(ORIGIN + Vector2i.DOWN, "dirt")
	assert_bool(Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, dirs)).is_true()

	_terrain.set_tile(ORIGIN + Vector2i.DOWN, "")
	_terrain.set_tile(ORIGIN + Vector2i.UP, "dirt")
	assert_bool(Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, dirs)).is_false()


func test_the_scene_authors_an_unpowered_one_by_one() -> void:
	var live: RespawnBeacon = auto_free(BeaconScene.instantiate())
	assert_vector(live.size).is_equal(Vector2i.ONE)
	assert_float(live.power_demand).is_equal(0.0)
	assert_bool(live.directional).is_false()
	assert_str(live.item_id).is_equal("beacon")

# --- The group ----------------------------------------------------------------


## ❗️The whole interface. `Player._respawn_anchor` queries this group by name and
## nothing else — a beacon outside it is invisible with no error anywhere. It is
## declared on the SCENE ROOT (the core.tscn / torch.tscn convention), so it is
## joined before `_ready` and left on the `.tscn` where the rest of the authoring
## lives.
func test_a_beacon_is_in_the_respawn_group_from_the_moment_it_enters_the_tree() -> void:
	var node := _beacon()
	assert_array(get_tree().get_nodes_in_group(&"respawn_beacon")).contains([node])


## The anchor contract, shared with `core.gd` by NAME so `_tick_respawn` has one
## code path: for a 1×1 beacon the anchor cell is simply the cell it stands on.
func test_base_cell_is_the_cell_it_occupies() -> void:
	var node := _beacon()
	assert_vector(node.base_cell()).is_equal(ORIGIN)

# --- Registration -------------------------------------------------------------


## No tick registry — a beacon does nothing per tick, so joining one would put a
## node with an empty `on_tick` in the 10 Hz loop forever.
func test_a_placed_beacon_joins_no_tick_registry() -> void:
	var node := _beacon()
	assert_int(_automation.machines().size()).is_equal(0)
	assert_object(_terrain.get_entity(ORIGIN)).is_same(node)
	_automation.step_tick()
	assert_int(_automation.tick_count).is_equal(1)


## It gives the item back like any deployable, and — once the deferred free lands
## — it is out of the group, which is what makes the anchor query fall back to the
## Core. Godot drops a node from its groups when it actually DELETES it, so this
## has to await the frame; until then `Turret.pick_target`'s `is_instance_valid`
## filter is what covers the gap.
func test_popping_it_gives_the_beacon_back_and_leaves_the_group() -> void:
	var node := _beacon()

	node.pop_to_pickup()

	assert_int(_spawner.drops.size()).is_equal(1)
	assert_str(_spawner.drops[0].id).is_equal("beacon")
	await get_tree().process_frame
	assert_array(get_tree().get_nodes_in_group(&"respawn_beacon")).is_empty()
