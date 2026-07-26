## Unit tests for the placed torch (roadmap 2.7). Runs against a fresh Terrain
## instance per test — never the live autoload.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const TorchScene := preload("res://scenes/torch.tscn")

## Playable (x in [50, 150)) and far from world edges.
const CELL := Vector2i(100, 100)

var _terrain: Node


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)


func _torch(cell: Vector2i) -> Torch:
	var torch: Torch = auto_free(TorchScene.instantiate())
	torch.setup(cell)
	return torch

# --- Placement ---------------------------------------------------------------


## setup() before add_child, per the Core/loot-bag convention — and it has to
## land on the cell CENTRE, because the light grid floors a world position back
## to a cell and an origin-anchored torch would light the wrong one at negative
## coordinates.
func test_setup_anchors_the_torch_at_its_cell_centre() -> void:
	var torch := _torch(CELL)
	assert_vector(torch.position).is_equal(Vector2(100.5, 100.5) * TileLayout.TILE_SIZE)
	assert_vector(torch.cell()).is_equal(CELL)


func test_register_claims_the_cell() -> void:
	var torch := _torch(CELL)
	assert_bool(torch.register(_terrain)).is_true()
	assert_object(_terrain.get_entity(CELL)).is_same(torch)


## The claim is what stops the item being consumed for nothing, so it must
## actually fail on an occupied cell rather than silently overwrite.
func test_register_fails_on_an_occupied_cell() -> void:
	var first := _torch(CELL)
	assert_bool(first.register(_terrain)).is_true()
	var second := _torch(CELL)
	assert_bool(second.register(_terrain)).is_false()
	assert_object(_terrain.get_entity(CELL)).is_same(first)

# --- Removal -----------------------------------------------------------------


## Hit counting, not damage accumulation: a swing is a discrete beat on the
## item's cooldown, and "three hits" is something a player can feel and count.
func test_a_torch_comes_off_in_one_hit() -> void:
	var torch := _torch(CELL)
	assert_bool(torch.take_removal_hit()).is_true()
	assert_float(torch.removal_ratio()).is_equal(1.0)


func test_removal_ratio_starts_empty() -> void:
	assert_float(_torch(CELL).removal_ratio()).is_equal(0.0)


## The deferred-free trap: queue_free runs at end of frame, so an entity entry
## cleared only by _exit_tree would still be there when the player re-places
## into the same cell on the very next tick.
func test_removal_frees_the_cell_immediately() -> void:
	var torch: Torch = TorchScene.instantiate()
	torch.setup(CELL)
	add_child(torch)
	assert_bool(torch.register(_terrain)).is_true()
	torch.remove(_terrain, null)
	assert_object(_terrain.get_entity(CELL)).is_null() # Before any frame boundary.


func test_a_cell_freed_by_removal_accepts_a_new_torch() -> void:
	var first: Torch = TorchScene.instantiate()
	first.setup(CELL)
	add_child(first)
	first.register(_terrain)
	first.remove(_terrain, null)
	var second := _torch(CELL)
	assert_bool(second.register(_terrain)).is_true()


## A missing spawner must not crash the removal — the cell still has to be
## freed, or a failed drop would leave an un-placeable hole in the world.
func test_removal_without_a_spawner_still_frees_the_cell() -> void:
	var torch: Torch = TorchScene.instantiate()
	torch.setup(CELL)
	add_child(torch)
	torch.register(_terrain)
	torch.remove(_terrain, null)
	assert_object(_terrain.get_entity(CELL)).is_null()

# --- Lighting seam -----------------------------------------------------------


## The torch owns no light node — the grid finds it by group. Losing either the
## group or the colour makes it a dark stick with no error anywhere.
func test_a_torch_is_a_light_source_in_the_group() -> void:
	var torch := _torch(CELL)
	assert_bool(torch.is_in_group(&"light_source")).is_true()
	assert_bool(torch.is_in_group(&"torch")).is_true()


## Warm against daylight's faint cool, or the two are indistinguishable.
func test_torch_light_is_warm() -> void:
	var torch := _torch(CELL)
	assert_float(torch.light_color.r).is_greater(torch.light_color.b)

# --- Flow field --------------------------------------------------------------


## Load-bearing absence: flow_field.gd reads `current_hp` and skips entities
## that return null, so a torch costs the field nothing and mobs walk through
## it. 3.1 giving torches HP is what changes this, deliberately.
func test_a_torch_has_no_hp_so_it_costs_the_flow_field_nothing() -> void:
	var torch := _torch(CELL)
	assert_object(torch.get(&"current_hp")).is_null()
