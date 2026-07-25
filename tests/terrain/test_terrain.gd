## Unit tests for the Terrain autoload (roadmap 1.4).
## Runs against a fresh instance per test — never mutates the live autoload.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")

## Any position here is playable (x in [50, 150)) and far from world edges.
const P := Vector2i(100, 100)

var _terrain: Node
var _drops: Array = []
var _changed: Array = []
var _broken: Array = []


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)
	_drops = []
	_changed = []
	_broken = []
	_terrain.drops_spawned.connect(
		func(pos: Vector2i, drop_id: String, drop_count: int, source: int) -> void:
			_drops.append([pos, drop_id, drop_count, source]),
	)
	_terrain.tile_changed.connect(
		func(pos: Vector2i) -> void:
			_changed.append(pos),
	)
	_terrain.tile_broken.connect(
		func(pos: Vector2i, material_id: String, source: int) -> void:
			_broken.append([pos, material_id, source]),
	)


## Reverse-lookup the 4-bit mask a cell currently displays.
func _mask_at(pos: Vector2i) -> int:
	var atlas: Vector2i = _terrain._layer.get_cell_atlas_coords(pos)
	for mask: int in TileLayout.LAYOUT:
		if (TileLayout.LAYOUT[mask] as Array).has(atlas):
			return mask
	return -1


func _atlas_at(pos: Vector2i) -> Vector2i:
	return _terrain._layer.get_cell_atlas_coords(pos)


func _fill(origin: Vector2i, size: Vector2i, material_id: String) -> void:
	for y in size.y:
		for x in size.x:
			_terrain.set_tile(origin + Vector2i(x, y), material_id)

# --- Autotiling --------------------------------------------------------------


func test_lone_tile_has_mask_zero_and_pinned_variant() -> void:
	_terrain.set_tile(P, "dirt")
	assert_int(_mask_at(P)).is_equal(0)
	var expected: Vector2i = TileLayout.LAYOUT[0][TileLayout.variant_hash(P)]
	assert_vector(_atlas_at(P)).is_equal(expected)


func test_filled_3x3_center_is_interior() -> void:
	_fill(P, Vector2i(3, 3), "dirt")
	var center := P + Vector2i(1, 1)
	assert_int(_mask_at(center)).is_equal(15)
	var expected: Vector2i = TileLayout.LAYOUT[15][TileLayout.variant_hash(center)]
	assert_vector(_atlas_at(center)).is_equal(expected)
	# Top-middle sees E + S + W.
	assert_int(_mask_at(P + Vector2i(1, 0))).is_equal(2 | 4 | 8)


func test_horizontal_run_middle_is_east_west() -> void:
	for x in 3:
		_terrain.set_tile(P + Vector2i(x, 0), "dirt")
	assert_int(_mask_at(P + Vector2i(1, 0))).is_equal(2 | 8)


func test_self_merge_only_across_materials() -> void:
	_terrain.set_tile(P, "dirt")
	_terrain.set_tile(P + Vector2i(1, 0), "stone")
	assert_int(_mask_at(P)).is_equal(0)
	assert_int(_mask_at(P + Vector2i(1, 0))).is_equal(0)


func test_mining_center_refreshes_neighbors() -> void:
	_fill(P, Vector2i(3, 3), "dirt")
	var center := P + Vector2i(1, 1)
	assert_bool(_terrain.damage_tile(center, 99.0, 1, TerrainScript.Source.PLAYER)).is_true()
	assert_str(_terrain.get_material_id(center)).is_equal("")
	# Top-middle lost its S bit.
	assert_int(_mask_at(P + Vector2i(1, 0))).is_equal(2 | 8)


func test_bulk_raw_set_then_region_pass() -> void:
	for y in 3:
		for x in 3:
			_terrain.set_cell_raw(P + Vector2i(x, y), "stone")
	_terrain.apply_autotile_region(Rect2i(P, Vector2i(3, 3)))
	assert_int(_mask_at(P + Vector2i(1, 1))).is_equal(15)
	assert_int(_mask_at(P)).is_equal(2 | 4) # top-left corner: E + S

# --- Damage pipeline ---------------------------------------------------------


func test_damage_accumulates_below_hardness() -> void:
	_terrain.set_tile(P, "dirt") # hardness 1.0
	assert_bool(_terrain.damage_tile(P, 0.4, 1, TerrainScript.Source.PLAYER)).is_true()
	assert_str(_terrain.get_material_id(P)).is_equal("dirt")
	assert_float(_terrain.get_tile_data(P).damage).is_equal_approx(0.4, 0.001)
	assert_array(_drops).is_empty()


func test_destroy_drops_and_prunes() -> void:
	_terrain.set_tile(P, "dirt")
	_changed.clear()
	_terrain.damage_tile(P, 0.4, 1, TerrainScript.Source.PLAYER)
	_terrain.damage_tile(P, 0.6, 1, TerrainScript.Source.PLAYER)
	assert_str(_terrain.get_material_id(P)).is_equal("")
	assert_array(_drops).contains_exactly([[P, "dirt", 1, TerrainScript.Source.PLAYER]])
	assert_array(_changed).contains([P])
	assert_array(_broken).contains_exactly([[P, "dirt", TerrainScript.Source.PLAYER]])
	assert_bool(_terrain._state.is_empty()).is_true() # sparse invariant
	_terrain.debug_validate()


func test_tool_tier_gating() -> void:
	_terrain.set_tile(P, "stone") # min_tool_tier 2
	assert_bool(_terrain.damage_tile(P, 99.0, 1, TerrainScript.Source.PLAYER)).is_false()
	assert_str(_terrain.get_material_id(P)).is_equal("stone")
	assert_float(_terrain.get_tile_data(P).damage).is_equal_approx(0.0, 0.001)
	assert_bool(_terrain.damage_tile(P, 99.0, 2, TerrainScript.Source.PLAYER)).is_true()


func test_bedrock_unminable() -> void:
	_terrain.set_tile(P, "bedrock")
	assert_bool(_terrain.damage_tile(P, 9999.0, 4, TerrainScript.Source.PLAYER)).is_false()
	assert_str(_terrain.get_material_id(P)).is_equal("bedrock")


func test_buffer_zone_rejects_player_allows_monster() -> void:
	var west := Vector2i(10, 100)
	var east := Vector2i(190, 100)
	for pos: Vector2i in [west, east]:
		_terrain.set_tile(pos, "dirt")
		assert_bool(_terrain.damage_tile(pos, 99.0, 1, TerrainScript.Source.PLAYER)).is_false()
		assert_str(_terrain.get_material_id(pos)).is_equal("dirt")
		assert_bool(_terrain.damage_tile(pos, 99.0, 1, TerrainScript.Source.MONSTER)).is_true()
		assert_str(_terrain.get_material_id(pos)).is_equal("")


func test_playable_boundaries_editable_by_player() -> void:
	for pos: Vector2i in [Vector2i(50, 100), Vector2i(149, 100)]:
		_terrain.set_tile(pos, "dirt")
		assert_bool(_terrain.can_player_edit(pos)).is_true()
		assert_bool(_terrain.damage_tile(pos, 99.0, 1, TerrainScript.Source.PLAYER)).is_true()
	assert_bool(_terrain.can_player_edit(Vector2i(49, 100))).is_false()
	assert_bool(_terrain.can_player_edit(Vector2i(150, 100))).is_false()

# --- Deposits ----------------------------------------------------------------


func test_deposit_chip_yields_and_depletes() -> void:
	_terrain.set_tile(P, "coal_deposit") # hardness 1.5, base_reserve 50
	assert_bool(_terrain.damage_tile(P, 2.0, 1, TerrainScript.Source.PLAYER)).is_true()
	assert_str(_terrain.get_material_id(P)).is_equal("coal_deposit")
	assert_int(_terrain.get_tile_data(P).reserve).is_equal(45)
	assert_array(_drops).contains_exactly([[P, "coal", 1, TerrainScript.Source.PLAYER]])
	assert_array(_broken).is_empty() # chips are not breaks


func test_deposit_exhaustion_becomes_air_no_bonus_drop() -> void:
	_terrain.set_tile(P, "coal_deposit")
	for i in 10: # 50 reserve / 5 per chip
		_terrain.damage_tile(P, 2.0, 1, TerrainScript.Source.PLAYER)
	assert_str(_terrain.get_material_id(P)).is_equal("")
	assert_array(_drops).has_size(10)
	# Exhaustion destroys the cell → exactly one break for the whole deposit.
	assert_array(_broken).contains_exactly([[P, "coal_deposit", TerrainScript.Source.PLAYER]])
	assert_bool(_terrain._state.is_empty()).is_true()

# --- Abandon timeout ---------------------------------------------------------


func test_abandoned_damage_clears_after_timeout() -> void:
	_terrain.set_tile(P, "dirt")
	_terrain.damage_tile(P, 0.5, 1, TerrainScript.Source.PLAYER)
	var hit_ms: int = _terrain._state[P].last_hit_ms
	_terrain._sweep_abandoned(hit_ms + TerrainScript.ABANDON_TIMEOUT_MS - 1)
	assert_float(_terrain.get_tile_data(P).damage).is_equal_approx(0.5, 0.001)
	_terrain._sweep_abandoned(hit_ms + TerrainScript.ABANDON_TIMEOUT_MS)
	assert_float(_terrain.get_tile_data(P).damage).is_equal_approx(0.0, 0.001)
	assert_bool(_terrain._state.is_empty()).is_true()
	_terrain.debug_validate()

# --- Entities ----------------------------------------------------------------


func test_entity_lifecycle() -> void:
	var node: Node2D = auto_free(Node2D.new())
	assert_bool(_terrain.place_entity(P, node)).is_true()
	assert_object(_terrain.get_entity(P)).is_same(node)
	# Occupied cell rejects a second entity.
	var other: Node2D = auto_free(Node2D.new())
	assert_bool(_terrain.place_entity(P, other)).is_false()
	assert_object(_terrain.get_entity(P)).is_same(node)
	_terrain.debug_validate()
	_terrain.remove_entity(P)
	assert_object(_terrain.get_entity(P)).is_null()
	assert_bool(_terrain._state.is_empty()).is_true()


func test_entity_rejected_on_solid_cell() -> void:
	_terrain.set_tile(P, "stone")
	var node: Node2D = auto_free(Node2D.new())
	assert_bool(_terrain.place_entity(P, node)).is_false()
	assert_object(_terrain.get_entity(P)).is_null()
