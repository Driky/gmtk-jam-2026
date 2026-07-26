## Unit tests for the Deployable base (roadmap 3.1) — footprint, registration,
## the support predicate and the single drop path. Runs against a fresh Terrain
## instance per test, never the live autoload.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const DeployableScript := preload("res://scripts/automation/deployable.gd")

## Playable (x in [50, 150)) and far from world edges.
const CELL := Vector2i(100, 100)

var _terrain: Node


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)


## Records what the real spawner would have dropped, without the autoload
## wiring or a Pickup in the tree.
class SpawnerDouble:
	extends Node

	var drops: Array = []


	func spawn_at(world_pos: Vector2, id: String, count: int, grants_xp := true) -> void:
		drops.append({ pos = world_pos, id = id, count = count, grants_xp = grants_xp })


## Reports which virtuals fired, and what the world looked like when they did.
class Observed:
	extends Deployable

	var placed_calls := 0
	var removed_calls := 0
	## Whether the origin cell was already free when on_removed ran — the
	## documented contract, and the reason on_removed is called after the cells
	## are given back rather than before.
	var cell_free_on_removed := false
	var observed_terrain: Node = null


	func on_placed() -> void:
		placed_calls += 1


	func on_removed() -> void:
		removed_calls += 1
		if observed_terrain != null:
			cell_free_on_removed = observed_terrain.get_entity(cell()) == null


func _deployable(origin: Vector2i, area := Vector2i.ONE, dirs := Deployable.SUPPORT_ALL) -> Deployable:
	var node: Deployable = auto_free(DeployableScript.new())
	node.size = area
	node.support_dirs = dirs
	node.item_id = "torch"
	node.setup(origin)
	return node


func _spawner() -> SpawnerDouble:
	var spawner: SpawnerDouble = auto_free(SpawnerDouble.new())
	# The group is how a deployable that was never handed a spawner finds one —
	# take_damage has no caller to pass it.
	spawner.add_to_group(&"pickup_spawner")
	add_child(spawner)
	return spawner

# --- Footprint ---------------------------------------------------------------


func test_a_one_by_one_footprint_is_its_own_cell() -> void:
	assert_array(Deployable.footprint_at(CELL, Vector2i.ONE)).contains_exactly([CELL])


## Origin is the TOP-LEFT cell, so the footprint grows right and down. Getting
## this backwards puts a machine's cells somewhere its ghost never drew.
func test_a_two_by_three_footprint_grows_right_and_down() -> void:
	assert_array(Deployable.footprint_at(CELL, Vector2i(2, 3))).contains_exactly(
		[
			CELL,
			CELL + Vector2i(1, 0),
			CELL + Vector2i(0, 1),
			CELL + Vector2i(1, 1),
			CELL + Vector2i(0, 2),
			CELL + Vector2i(1, 2),
		],
	)


## Byte-identical to the 2.7 torch's anchor: the light grid floors a world
## position back to a cell, and an origin-anchored source lights the wrong one
## at negative coordinates.
func test_setup_centres_a_one_by_one_on_its_cell() -> void:
	var node := _deployable(CELL)
	assert_vector(node.position).is_equal(Vector2(100.5, 100.5) * TileLayout.TILE_SIZE)
	assert_vector(node.cell()).is_equal(CELL)


func test_setup_centres_a_multi_cell_on_its_whole_footprint() -> void:
	var node := _deployable(CELL, Vector2i(2, 3))
	assert_vector(node.position).is_equal(Vector2(101.0, 101.5) * TileLayout.TILE_SIZE)

# --- HP ----------------------------------------------------------------------


## ❗️Risk 1. `var current_hp := max_hp` runs BEFORE the scene loader applies the
## authored export, so a scene saying 40 would silently ship a 20 HP machine —
## invisible until a mob takes four hits too long to chew it. Packing a scene is
## the only way to exercise the real ordering.
func test_current_hp_starts_at_the_scene_authored_max_hp() -> void:
	var template := DeployableScript.new()
	template.max_hp = 40.0
	var scene := PackedScene.new()
	scene.pack(template)
	template.free()

	var node: Deployable = auto_free(scene.instantiate())
	node.setup(CELL)
	assert_float(node.max_hp).is_equal(40.0)
	assert_float(node.current_hp).is_equal(40.0)


## Damage taken before the node enters the tree must not be undone by _ready
## re-seeding HP from max.
func test_ready_does_not_re_seed_hp_after_damage() -> void:
	var node := _deployable(CELL)
	node.take_damage(5.0)
	add_child(node)
	assert_float(node.current_hp).is_equal(node.max_hp - 5.0)

# --- Registration ------------------------------------------------------------


func test_register_claims_every_footprint_cell() -> void:
	var node := _deployable(CELL, Vector2i(2, 2))
	assert_bool(node.register(_terrain)).is_true()
	for cell: Vector2i in node.footprint():
		assert_object(_terrain.get_entity(cell)).is_same(node)
	_terrain.debug_validate()


## All-or-nothing, mirroring Core.register_footprint: a partial claim leaves
## cells nothing can ever occupy again.
func test_register_rolls_back_every_cell_on_a_mid_footprint_collision() -> void:
	var blocker: Node2D = auto_free(Node2D.new())
	_terrain.place_entity(CELL + Vector2i(1, 1), blocker)
	var node := _deployable(CELL, Vector2i(2, 2))
	assert_bool(node.register(_terrain)).is_false()
	assert_object(_terrain.get_entity(CELL)).is_null()
	assert_object(_terrain.get_entity(CELL + Vector2i(1, 0))).is_null()
	assert_object(_terrain.get_entity(CELL + Vector2i(0, 1))).is_null()
	assert_object(_terrain.get_entity(CELL + Vector2i(1, 1))).is_same(blocker)
	_terrain.debug_validate()


func test_unregister_gives_every_cell_back() -> void:
	var node := _deployable(CELL, Vector2i(2, 2))
	node.register(_terrain)
	node.unregister(_terrain)
	for cell: Vector2i in node.footprint():
		assert_object(_terrain.get_entity(cell)).is_null()

# --- Support -----------------------------------------------------------------


## ❗️Risk 2. @export_flags hands out 1/2/4/8 = Up/Right/Down/Left. Inverting
## Up and Down gives a game that mostly works — torches mount on floors instead
## of ceilings — with no error anywhere, so the orientation is pinned directly.
func test_the_up_bit_means_a_solid_above() -> void:
	_terrain.set_tile(CELL + Vector2i.UP, "dirt")
	assert_bool(Deployable.is_supported_at(_terrain, CELL, Vector2i.ONE, 1)).is_true()


func test_the_up_bit_is_not_satisfied_by_a_solid_below() -> void:
	_terrain.set_tile(CELL + Vector2i.DOWN, "dirt")
	assert_bool(Deployable.is_supported_at(_terrain, CELL, Vector2i.ONE, 1)).is_false()


func test_all_four_bits_accept_a_floor() -> void:
	_terrain.set_tile(CELL + Vector2i.DOWN, "dirt")
	assert_bool(
		Deployable.is_supported_at(_terrain, CELL, Vector2i.ONE, Deployable.SUPPORT_ALL),
	).is_true()


func test_no_neighbour_is_no_support() -> void:
	assert_bool(
		Deployable.is_supported_at(_terrain, CELL, Vector2i.ONE, Deployable.SUPPORT_ALL),
	).is_false()


## Zero is the opt-out: a machine that never pops, floating in a void.
func test_zero_dirs_is_supported_anywhere() -> void:
	assert_bool(
		Deployable.is_supported_at(_terrain, CELL, Vector2i.ONE, Deployable.SUPPORT_NONE),
	).is_true()


## Support means a solid TILE. A deployable never holds another one up, which is
## what keeps chain depth at 1 and cascades rare.
func test_a_neighbouring_deployable_is_not_support() -> void:
	var neighbour := _deployable(CELL + Vector2i.DOWN)
	assert_bool(neighbour.register(_terrain)).is_true()
	assert_bool(
		Deployable.is_supported_at(_terrain, CELL, Vector2i.ONE, Deployable.SUPPORT_ALL),
	).is_false()


## One supported cell holds the whole machine up — a 2×2 resting a single corner
## on a ledge is standing, not floating.
func test_one_supported_cell_holds_a_two_by_two_up() -> void:
	_terrain.set_tile(CELL + Vector2i(1, 2), "dirt")
	assert_bool(
		Deployable.is_supported_at(_terrain, CELL, Vector2i(2, 2), Deployable.SUPPORT_ALL),
	).is_true()


func test_is_supported_reads_the_nodes_own_exports() -> void:
	var node := _deployable(CELL, Vector2i.ONE, 1)
	assert_bool(node.is_supported(_terrain)).is_false()
	_terrain.set_tile(CELL + Vector2i.UP, "dirt")
	assert_bool(node.is_supported(_terrain)).is_true()

# --- Removal hits ------------------------------------------------------------


func test_a_one_hit_deployable_comes_off_in_one_swing() -> void:
	var node := _deployable(CELL)
	assert_bool(node.take_removal_hit()).is_true()
	assert_float(node.removal_ratio()).is_equal(1.0)


func test_removal_ratio_climbs_across_a_multi_hit_removal() -> void:
	var node := _deployable(CELL)
	node.removal_hits = 3
	assert_bool(node.take_removal_hit()).is_false()
	assert_float(node.removal_ratio()).is_equal_approx(1.0 / 3.0, 0.001)
	assert_bool(node.take_removal_hit()).is_false()
	assert_float(node.removal_ratio()).is_equal_approx(2.0 / 3.0, 0.001)
	assert_bool(node.take_removal_hit()).is_true()
	assert_float(node.removal_ratio()).is_equal(1.0)

# --- The one drop path -------------------------------------------------------


## The deferred-free trap: queue_free runs at end of frame, so cells cleared
## only by _exit_tree would still be claimed when the player re-places into them
## on the very next tick.
func test_pop_frees_every_cell_before_any_frame_boundary() -> void:
	var node := _deployable(CELL, Vector2i(2, 2))
	add_child(node)
	node.register(_terrain)
	var cells := node.footprint()
	node.pop_to_pickup()
	for cell: Vector2i in cells:
		assert_object(_terrain.get_entity(cell)).is_null()


## Whatever its footprint, a deployable is ONE item on the floor.
func test_pop_spawns_exactly_one_pickup_that_pays_no_xp() -> void:
	var spawner := _spawner()
	var node := _deployable(CELL, Vector2i(2, 2))
	add_child(node)
	node.register(_terrain)
	node.pop_to_pickup(spawner)
	assert_int(spawner.drops.size()).is_equal(1)
	assert_str(spawner.drops[0].id).is_equal("torch")
	assert_int(spawner.drops[0].count).is_equal(1)
	# place → remove → place must not be an infinite looting-XP loop.
	assert_bool(spawner.drops[0].grants_xp).is_false()


## Three callers reach this path and the support re-check re-enters it through
## entity_changed, so a second call has to be inert rather than a second pickup.
func test_a_second_pop_is_a_no_op() -> void:
	var spawner := _spawner()
	var node := _deployable(CELL)
	add_child(node)
	node.register(_terrain)
	node.pop_to_pickup(spawner)
	node.pop_to_pickup(spawner)
	assert_int(spawner.drops.size()).is_equal(1)


## A missing spawner must not crash the pop — the cells still have to be freed,
## or a failed drop leaves an un-placeable hole in the world.
func test_pop_without_a_spawner_still_frees_the_cells() -> void:
	var node := _deployable(CELL)
	add_child(node)
	node.register(_terrain)
	node.pop_to_pickup()
	assert_object(_terrain.get_entity(CELL)).is_null()


## A node that never claimed anything (a rejected placement) still has to be
## poppable without dereferencing a terrain it was never given.
func test_popping_a_never_registered_deployable_is_safe() -> void:
	var node := _deployable(CELL)
	add_child(node)
	node.pop_to_pickup()
	assert_bool(node.is_queued_for_deletion()).is_true()


## Nothing the player built is destroyed outright: a mob that kills a torch
## knocks it onto the floor, so a wave through your lighting costs a walk.
func test_damage_to_zero_pops_it_instead_of_destroying_it() -> void:
	var spawner := _spawner()
	var node := _deployable(CELL)
	add_child(node)
	node.register(_terrain)
	node.take_damage(node.max_hp)
	assert_object(_terrain.get_entity(CELL)).is_null()
	assert_int(spawner.drops.size()).is_equal(1)
	assert_bool(node.is_queued_for_deletion()).is_true()


func test_partial_damage_leaves_it_standing() -> void:
	var node := _deployable(CELL)
	add_child(node)
	node.register(_terrain)
	node.take_damage(node.max_hp - 1.0)
	assert_float(node.current_hp).is_equal(1.0)
	assert_object(_terrain.get_entity(CELL)).is_same(node)

# --- Reading a scene without instantiating it (the ghost's input) ------------

const TorchScene := preload("res://scenes/torch.tscn")


## ❗️The one way the ghost can lie about what will be placed: read the authored
## exports off a real instance and pin them against the cached answer. A cache
## that drifts from the scene draws one shape and places another.
func test_scene_size_matches_a_live_instance() -> void:
	var live: Deployable = auto_free(TorchScene.instantiate())
	assert_vector(Deployable.scene_size(TorchScene)).is_equal(live.size)
	assert_int(Deployable.scene_support_dirs(TorchScene)).is_equal(live.support_dirs)


## Same contract for the item preview: it is read off the scene's own ColorRect,
## so the ghost draws the thing that will actually be placed rather than a second
## copy of its look that could drift.
func test_scene_visual_matches_the_live_instances_color_rect() -> void:
	var live: Deployable = auto_free(TorchScene.instantiate())
	add_child(live) # Only once in the tree does a Control lay its offsets out.
	var visual: ColorRect = live.get_node("Visual")
	var cached := Deployable.scene_visual(TorchScene)
	assert_bool(cached.is_empty()).is_false()
	assert_object(cached.color).is_equal(visual.color)
	assert_vector(cached.rect.size).is_equal(visual.size)
	assert_vector(cached.rect.position).is_equal(visual.position)


## A deployable with nothing to draw must degrade to "footprint tint only"
## rather than crashing the cursor's per-frame draw.
func test_scene_visual_is_empty_when_there_is_nothing_to_preview() -> void:
	var template := DeployableScript.new()
	var scene := PackedScene.new()
	scene.pack(template)
	template.free()
	assert_bool(Deployable.scene_visual(scene).is_empty()).is_true()


## The ghost redraws every frame, so the second call must come off the cache
## rather than instantiating again — and must still give the same answer.
func test_a_second_read_returns_the_same_answer() -> void:
	var first := Deployable.scene_size(TorchScene)
	assert_vector(Deployable.scene_size(TorchScene)).is_equal(first)
	assert_int(Deployable.scene_support_dirs(TorchScene)).is_equal(
		Deployable.scene_support_dirs(TorchScene),
	)

# --- Virtuals ----------------------------------------------------------------


func test_on_placed_fires_once() -> void:
	var node: Observed = auto_free(Observed.new())
	node.setup(CELL)
	add_child(node)
	node.on_placed()
	assert_int(node.placed_calls).is_equal(1)


## The contract 3.4's power graph depends on: an override reads a world without
## this deployable in it, not one where it half-exists.
func test_on_removed_sees_the_cells_already_free() -> void:
	var node: Observed = auto_free(Observed.new())
	node.setup(CELL)
	node.observed_terrain = _terrain
	add_child(node)
	node.register(_terrain)
	node.pop_to_pickup()
	assert_int(node.removed_calls).is_equal(1)
	assert_bool(node.cell_free_on_removed).is_true()
