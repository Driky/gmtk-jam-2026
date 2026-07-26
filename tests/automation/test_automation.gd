## Unit tests for the deployable support re-check (roadmap 3.1). Runs a fresh
## Automation against a fresh Terrain — never the live autoloads — with
## _process disabled so the drain happens exactly when a test says so.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const DeployableScript := preload("res://scripts/automation/deployable.gd")
const TorchScene := preload("res://scenes/torch.tscn")

## Playable (x in [50, 150)) and far from world edges.
const CELL := Vector2i(100, 100)
## Directly under CELL — the tile a wall-mounted torch is standing on.
const ANCHOR := CELL + Vector2i.DOWN

var _terrain: Node
var _automation: Node
var _spawner: SpawnerDouble


## Records what the real spawner would have dropped, without the autoload
## wiring or a Pickup in the tree.
class SpawnerDouble:
	extends Node

	var drops: Array = []


	func spawn_at(world_pos: Vector2, id: String, count: int, grants_xp := true) -> void:
		drops.append({ pos = world_pos, id = id, count = count, grants_xp = grants_xp })


## Support that also accepts a live Deployable ABOVE. Deliberately NOT the
## shipped rule (a deployable never holds another one up) — it exists to build a
## chain deep enough that a recursive drain would blow the stack, which is the
## only way to prove the shipped drain is iterative. One-directional, or a row
## would hold itself up circularly and never pop at all. Hung downward rather
## than sideways because the world is only 200 columns wide but 1200 rows deep.
class Linked:
	extends Deployable

	func is_supported(t: Node) -> bool:
		if super.is_supported(t):
			return true
		return t.get_entity(cell() + Vector2i.UP) is Deployable


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)
	_spawner = auto_free(SpawnerDouble.new())
	_spawner.add_to_group(&"pickup_spawner")
	add_child(_spawner)
	_automation = auto_free(AutomationScript.new())
	_automation.terrain = _terrain
	add_child(_automation) # _ready wires the two Terrain signals.
	# The drain is a test's own business here; a stray frame must not do it first.
	_automation.set_process(false)


func _torch_at(cell: Vector2i) -> Torch:
	var torch: Torch = auto_free(TorchScene.instantiate())
	torch.setup(cell)
	add_child(torch)
	torch.register(_terrain)
	return torch


func _deployable_at(cell: Vector2i, dirs := Deployable.SUPPORT_ALL) -> Deployable:
	var node: Deployable = auto_free(DeployableScript.new())
	node.support_dirs = dirs
	node.item_id = "torch"
	node.setup(cell)
	add_child(node)
	node.register(_terrain)
	return node

# --- Losing support ----------------------------------------------------------


## The visible proof of the whole feature: mine the tile a torch is mounted on
## and it drops as a pickup instead of hanging in mid-air.
func test_mining_the_tile_a_torch_is_mounted_on_pops_it() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	var torch := _torch_at(CELL)
	_automation.drain_support_queue() # Settle the registration's own signals.

	_terrain.damage_tile(ANCHOR, 999.0, 99, TerrainScript.Source.PLAYER)
	_automation.drain_support_queue()

	assert_object(_terrain.get_entity(CELL)).is_null()
	assert_int(_spawner.drops.size()).is_equal(1)
	assert_str(_spawner.drops[0].id).is_equal("torch")
	assert_bool(torch.is_queued_for_deletion()).is_true()
	_terrain.debug_validate()


## A torch with a second wall behind it is still mounted — the check asks the
## whole bitmask, not just the neighbour that happened to change.
func test_a_torch_with_a_second_neighbour_survives_the_same_mine() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	_terrain.set_tile(CELL + Vector2i.LEFT, "dirt")
	var torch := _torch_at(CELL)
	_automation.drain_support_queue()

	_terrain.damage_tile(ANCHOR, 999.0, 99, TerrainScript.Source.PLAYER)
	_automation.drain_support_queue()

	assert_object(_terrain.get_entity(CELL)).is_same(torch)
	assert_array(_spawner.drops).is_empty()


## `0` is the opt-out, and it has to hold under the re-check too — a free-
## floating machine must never pop just because a tile near it changed.
func test_a_zero_support_deployable_never_pops() -> void:
	var node := _deployable_at(CELL, Deployable.SUPPORT_NONE)
	_automation.queue_support_check(CELL)
	_automation.drain_support_queue()
	assert_object(_terrain.get_entity(CELL)).is_same(node)


## O(1) per mined tile is the whole budget argument: only the five cells a
## change can touch are probed, so digging across the map costs nothing.
func test_a_distant_tile_change_queues_nothing() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	_torch_at(CELL)
	_automation.drain_support_queue()

	_terrain.set_tile(CELL + Vector2i(3, 0), "dirt")
	assert_int(_automation.pending_checks()).is_equal(0)


## Registration emits one entity_changed per occupied cell, and a change beside
## a big machine can touch several of them — but a pop is one machine and one
## item on the floor, however many times it was queued.
func test_a_multi_cell_deployable_pops_once_however_many_cells_are_queued() -> void:
	var floor_cell := CELL + Vector2i(0, 2)
	_terrain.set_tile(floor_cell, "dirt")
	var big: Deployable = auto_free(DeployableScript.new())
	big.size = Vector2i(2, 2)
	big.item_id = "torch"
	big.setup(CELL)
	add_child(big)
	assert_bool(big.register(_terrain)).is_true()
	_automation.drain_support_queue() # Standing on the floor.

	_terrain.damage_tile(floor_cell, 999.0, 99, TerrainScript.Source.PLAYER)
	for cell: Vector2i in big.footprint():
		_automation.queue_support_check(cell) # As several nearby changes would.
	assert_int(_automation.pending_checks()).is_equal(4)
	_automation.drain_support_queue()

	assert_int(_spawner.drops.size()).is_equal(1)
	for cell: Vector2i in Deployable.footprint_at(CELL, Vector2i(2, 2)):
		assert_object(_terrain.get_entity(cell)).is_null()
	_terrain.debug_validate()

# --- Coalescing & iteration --------------------------------------------------


## Fifty changes around one torch must cost one check, not fifty. The dedupe is
## the entire reason this needs no timer.
func test_fifty_changes_around_one_torch_coalesce_into_one_check() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	_torch_at(CELL)
	_automation.drain_support_queue()

	for i in 50:
		_automation.queue_support_check(CELL)
	assert_int(_automation.pending_checks()).is_equal(1)
	_automation.drain_support_queue()
	assert_int(_automation.pending_checks()).is_equal(0)


## ❗️The test that fails under a recursive implementation. A 200-long chain,
## anchored by one tile: mining it has to unwind the whole row inside a single
## drain, each link popping exactly once and nothing running out of stack.
func test_one_drain_unwinds_a_two_hundred_long_chain() -> void:
	const CHAIN := 200
	var ceiling := CELL + Vector2i.UP
	_terrain.set_tile(ceiling, "dirt") # The only real support in the column.
	for i in CHAIN:
		var link: Deployable = auto_free(Linked.new())
		link.item_id = "torch"
		link.setup(CELL + Vector2i(0, i))
		add_child(link)
		assert_bool(link.register(_terrain)).is_true()
	_automation.drain_support_queue()
	assert_int(_spawner.drops.size()).is_equal(0) # The chain is standing.

	_terrain.damage_tile(ceiling, 999.0, 99, TerrainScript.Source.PLAYER)
	_automation.drain_support_queue()

	assert_int(_spawner.drops.size()).is_equal(CHAIN) # Each popped exactly once.
	for i in CHAIN:
		assert_object(_terrain.get_entity(CELL + Vector2i(0, i))).is_null()
	assert_int(_automation.pending_checks()).is_equal(0)
	_terrain.debug_validate()

# --- Run state ---------------------------------------------------------------


## ❗️A cell surviving a restart re-checks something else entirely in the new
## world. Easy to forget, invisible when wrong.
func test_reset_run_clears_the_queue() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	_torch_at(CELL)
	_automation.queue_support_check(CELL)
	assert_int(_automation.pending_checks()).is_greater(0)
	_automation.reset_run()
	assert_int(_automation.pending_checks()).is_equal(0)


## The dedupe dict has to be cleared alongside the array, or every cell queued
## before the restart is silently un-queueable afterwards.
func test_a_cell_queued_before_reset_can_be_queued_again() -> void:
	_automation.queue_support_check(CELL)
	_automation.reset_run()
	_automation.queue_support_check(CELL)
	assert_int(_automation.pending_checks()).is_equal(1)
