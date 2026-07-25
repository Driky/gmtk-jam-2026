## Unit tests for the pickup spawner's drop policy (roadmap 1.6).
## Calls the handler directly — never routes through the live Terrain autoload.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const SpawnerScript := preload("res://scripts/items/pickup_spawner.gd")

const P := Vector2i(100, 100)

var _spawner: Node2D


func before_test() -> void:
	_spawner = auto_free(SpawnerScript.new())
	add_child(_spawner)


func test_player_source_spawns_pickup_at_tile_center() -> void:
	_spawner._on_drops_spawned(P, "dirt", 1, TerrainScript.Source.PLAYER, true)
	assert_int(_spawner.get_child_count()).is_equal(1)
	var pickup: Node2D = _spawner.get_child(0)
	assert_str(pickup.item_id).is_equal("dirt")
	assert_int(pickup.count).is_equal(1)
	assert_vector(pickup.position).is_equal(Vector2(1608, 1608))


func test_monster_source_spawns_pickup() -> void:
	_spawner._on_drops_spawned(P, "coal", 2, TerrainScript.Source.MONSTER, true)
	assert_int(_spawner.get_child_count()).is_equal(1)
	assert_int(_spawner.get_child(0).count).is_equal(2)


func test_machine_source_spawns_nothing() -> void:
	_spawner._on_drops_spawned(P, "iron", 1, TerrainScript.Source.MACHINE, true)
	assert_int(_spawner.get_child_count()).is_equal(0)


## The XP veto rides all the way to the pickup: by the time this is collected
## the tile it came from is long gone, so the flag can't be looked up later.
func test_xp_veto_reaches_the_pickup() -> void:
	_spawner._on_drops_spawned(P, "dirt", 1, TerrainScript.Source.PLAYER, false)
	assert_bool(_spawner.get_child(0).grants_xp).is_false()


func test_ordinary_drops_stay_xp_eligible() -> void:
	_spawner._on_drops_spawned(P, "dirt", 1, TerrainScript.Source.PLAYER, true)
	assert_bool(_spawner.get_child(0).grants_xp).is_true()
