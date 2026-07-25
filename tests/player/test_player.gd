## Unit tests for placement validity + tile-rect math (roadmap 1.6) and the
## HP/mana stub (roadmap 1.7). Terrain is a fresh instance per test — never
## the live autoload.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const PlayerScript := preload("res://scripts/player/player.gd")

## Playable, far from edges; NOWHERE is a rect that overlaps nothing relevant.
const P := Vector2i(100, 100)
const NOWHERE := Rect2i(0, 0, 1, 1)

var _terrain: Node


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)

# --- can_place_at ------------------------------------------------------------


func test_rejects_floating_placement() -> void:
	# All four neighbors are air — adjacency rule fails.
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_false()


func test_accepts_air_adjacent_to_solid() -> void:
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_true()


func test_rejects_solid_target() -> void:
	_terrain.set_tile(P, "dirt")
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_false()


func test_rejects_buffer_zone() -> void:
	var buffer_pos := Vector2i(10, 100)
	_terrain.set_tile(buffer_pos + Vector2i.DOWN, "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, buffer_pos, NOWHERE)).is_false()


func test_rejects_entity_occupied_cell() -> void:
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	var node: Node2D = auto_free(Node2D.new())
	_terrain.place_entity(P, node)
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_false()


func test_rejects_cell_overlapping_player() -> void:
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	var occupied := Rect2i(P, Vector2i(1, 1))
	assert_bool(PlayerScript.can_place_at(_terrain, P, occupied)).is_false()

# --- tile_rect_at ------------------------------------------------------------


func test_tile_rect_spans_two_rows_when_centered() -> void:
	# Center of column 100, feet on row 101: 12×22 box covers rows 99-100.
	var rect: Rect2i = PlayerScript.tile_rect_at(Vector2(1608.0, 1600.0))
	assert_vector(rect.position).is_equal(Vector2i(100, 99))
	assert_vector(rect.size).is_equal(Vector2i(1, 2))


func test_tile_rect_flush_edge_claims_single_column() -> void:
	# Right edge exactly on the x=1616 tile boundary must not claim column 101.
	var rect: Rect2i = PlayerScript.tile_rect_at(Vector2(1610.0, 1608.0))
	assert_int(rect.position.x).is_equal(100)
	assert_int(rect.size.x).is_equal(1)

# --- Mine → place round trip -------------------------------------------------


func test_mined_drop_id_places_back() -> void:
	var drops: Array = []
	_terrain.drops_spawned.connect(
		func(_pos: Vector2i, drop_id: String, _count: int, _source: int) -> void:
			drops.append(drop_id),
	)
	_terrain.set_tile(P, "grass")
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	_terrain.damage_tile(P, 99.0, 1, TerrainScript.Source.PLAYER)
	assert_array(drops).contains_exactly(["dirt"]) # Grass drops dirt.
	assert_bool(Materials.MATERIALS.has(drops[0])).is_true()
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_true()
	_terrain.set_tile(P, drops[0])
	assert_bool(_terrain.is_solid(P)).is_true()
	assert_str(_terrain.get_material_id(P)).is_equal("dirt")

# --- HP/mana stub (1.7) ------------------------------------------------------


func test_ready_seeds_full_hp_and_mana() -> void:
	var player: CharacterBody2D = auto_free(PlayerScript.new())
	add_child(player)
	assert_float(player.current_hp).is_equal(Progression.get_stat("max_hp"))
	assert_float(player.current_mana).is_equal(Progression.get_stat("max_mana"))


func test_current_hp_clamps_and_signals() -> void:
	var player: CharacterBody2D = auto_free(PlayerScript.new())
	var max_hp := Progression.get_stat("max_hp")
	var events: Array = []
	player.health_changed.connect(
		func(current: float, max_value: float) -> void:
			events.append([current, max_value]),
	)
	player.current_hp = 30.0
	player.current_hp = -10.0 # Clamped to 0.
	player.current_hp = max_hp + 999.0 # Clamped to max.
	assert_float(player.current_hp).is_equal(max_hp)
	assert_array(events).contains_exactly(
		[[30.0, max_hp], [0.0, max_hp], [max_hp, max_hp]],
	)


func test_current_mana_clamps() -> void:
	var player: CharacterBody2D = auto_free(PlayerScript.new())
	var max_mana := Progression.get_stat("max_mana")
	player.current_mana = max_mana + 5.0
	assert_float(player.current_mana).is_equal(max_mana)
	player.current_mana = -1.0
	assert_float(player.current_mana).is_equal(0.0)
