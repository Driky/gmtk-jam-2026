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
var _entity_changed: Array = []


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)
	_drops = []
	_changed = []
	_broken = []
	_entity_changed = []
	_terrain.entity_changed.connect(
		func(pos: Vector2i) -> void:
			_entity_changed.append(pos),
	)
	_terrain.drops_spawned.connect(
		func(pos: Vector2i, drop_id: String, drop_count: int, source: int, grants_xp: bool) -> void:
			_drops.append([pos, drop_id, drop_count, source, grants_xp]),
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
	assert_array(_drops).contains_exactly([[P, "dirt", 1, TerrainScript.Source.PLAYER, true]])
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

# --- Player-placed blocks & mining XP (2.6) ----------------------------------


## Lifetime mining XP on the live autoload. Asserted as a DELTA rather than an
## absolute: Terrain grants through the real Progression singleton, so other
## suites in the same run have already moved the number.
func _mining_xp() -> float:
	return Progression.xp_by_source.get("mining", 0.0)


## The flag has to defeat the sparse-dict prune: an otherwise pristine placed
## tile still needs its entry, or the flag evaporates on the next write.
func test_player_placed_tile_keeps_its_state_entry() -> void:
	_terrain.set_tile(P, "dirt", true)
	assert_bool(_terrain.get_tile_data(P).player_placed).is_true()
	assert_bool(_terrain._state.is_empty()).is_false()
	_terrain.debug_validate()


func test_natural_tile_is_not_flagged_and_stays_pruned() -> void:
	_terrain.set_tile(P, "dirt")
	assert_bool(_terrain.get_tile_data(P).player_placed).is_false()
	assert_bool(_terrain._state.is_empty()).is_true() # sparse invariant


## Whatever occupies the cell next declares its own origin — a placed block
## broken and regenerated over must not stay poisoned.
func test_replacing_a_tile_clears_the_flag() -> void:
	_terrain.set_tile(P, "dirt", true)
	_terrain.set_tile(P, "stone")
	assert_bool(_terrain.get_tile_data(P).player_placed).is_false()
	assert_bool(_terrain._state.is_empty()).is_true()


func test_mining_a_natural_block_grants_flat_xp_and_an_eligible_drop() -> void:
	_terrain.set_tile(P, "dirt")
	var before := _mining_xp()
	_terrain.damage_tile(P, 99.0, 1, TerrainScript.Source.PLAYER)
	var granted := _mining_xp() - before
	assert_float(granted).is_equal_approx(Progression.MINING_XP_PER_BLOCK, 0.001)
	assert_bool(_drops[0][4]).is_true()


## Flat, not per-hardness: a stone block (hardness 2) pays exactly what dirt
## (hardness 1) pays, so a slow tool can't out-earn a fast one.
func test_mining_xp_does_not_scale_with_hardness() -> void:
	_terrain.set_tile(P, "stone")
	var before := _mining_xp()
	_terrain.damage_tile(P, 99.0, 2, TerrainScript.Source.PLAYER)
	assert_float(_mining_xp() - before).is_equal_approx(Progression.MINING_XP_PER_BLOCK, 0.001)


## The anti-farm rule: wall up, mine it back, earn nothing on either channel.
func test_mining_a_player_placed_block_grants_nothing() -> void:
	_terrain.set_tile(P, "dirt", true)
	var before := _mining_xp()
	_terrain.damage_tile(P, 99.0, 1, TerrainScript.Source.PLAYER)
	assert_float(_mining_xp() - before).is_equal_approx(0.0, 0.001)
	assert_array(_drops).contains_exactly([[P, "dirt", 1, TerrainScript.Source.PLAYER, false]])


## Monster chew never paid mining XP and still doesn't — but the drop it frees
## is ordinary loot, so it stays XP-eligible.
func test_monster_dig_grants_no_mining_xp_but_an_eligible_drop() -> void:
	_terrain.set_tile(P, "dirt")
	var before := _mining_xp()
	_terrain.damage_tile(P, 99.0, 1, TerrainScript.Source.MONSTER)
	assert_float(_mining_xp() - before).is_equal_approx(0.0, 0.001)
	assert_bool(_drops[0][4]).is_true()

# --- Deposits ----------------------------------------------------------------


func test_deposit_chip_yields_and_depletes() -> void:
	_terrain.set_tile(P, "coal_deposit") # hardness 1.5, base_reserve 50
	assert_bool(_terrain.damage_tile(P, 2.0, 1, TerrainScript.Source.PLAYER)).is_true()
	assert_str(_terrain.get_material_id(P)).is_equal("coal_deposit")
	assert_int(_terrain.get_tile_data(P).reserve).is_equal(45)
	assert_array(_drops).contains_exactly([[P, "coal", 1, TerrainScript.Source.PLAYER, true]])
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

# --- The machine seam (3.3) --------------------------------------------------


## 1:1, against the chip path's 5-reserve-for-1-drop. That contrast is the whole
## reason a Miner does not route through `damage_tile`.
func test_extract_reserve_takes_ore_one_for_one() -> void:
	_terrain.set_tile(P, "coal_deposit") # base_reserve 50
	var taken: Dictionary = _terrain.extract_reserve(P, 3)
	assert_str(taken.id).is_equal("coal")
	assert_int(taken.count).is_equal(3)
	assert_int(_terrain.get_tile_data(P).reserve).is_equal(47)


## ❗️The ore goes into the machine, never onto the floor — and because
## `_award` only ever grants XP for a PLAYER source, that is also what makes
## machine-extracted ore worth zero on both channels.
func test_extract_reserve_spawns_no_drops() -> void:
	_terrain.set_tile(P, "coal_deposit")
	_terrain.extract_reserve(P, 5)
	assert_array(_drops).is_empty()


## The exhaustion tail is shared with the chip path, so it must produce the same
## air cell and the same single `tile_broken` — only the source differs.
func test_extract_reserve_to_exhaustion_destroys_the_tile() -> void:
	_terrain.set_tile(P, "coal_deposit")
	_terrain.set_reserve(P, 4)
	var taken: Dictionary = _terrain.extract_reserve(P, 10)
	assert_int(taken.count).is_equal(4) # Never more than is there.
	assert_str(_terrain.get_material_id(P)).is_equal("")
	assert_array(_broken).contains_exactly([[P, "coal_deposit", TerrainScript.Source.MACHINE]])
	assert_array(_drops).is_empty()
	assert_bool(_terrain._state.is_empty()).is_true()


## Resolves the lazy -1 rather than reading it as a count, or the first
## extraction from an untouched deposit would take nothing forever.
func test_extract_reserve_resolves_an_untouched_reserve() -> void:
	_terrain.set_tile(P, "iron_deposit")
	assert_bool(_terrain._state.has(P)).is_false()
	assert_int(_terrain.extract_reserve(P, 1).count).is_equal(1)
	assert_int(_terrain.get_tile_data(P).reserve).is_equal(49)


func test_extract_reserve_refuses_anything_that_is_not_a_deposit() -> void:
	_terrain.set_tile(P, "coal") # Plain ore, not a deposit.
	assert_dict(_terrain.extract_reserve(P, 1)).is_empty()
	assert_dict(_terrain.extract_reserve(P + Vector2i(0, 1), 1)).is_empty() # Air.
	assert_str(_terrain.get_material_id(P)).is_equal("coal")


func test_extract_reserve_refuses_a_non_positive_amount() -> void:
	_terrain.set_tile(P, "coal_deposit")
	assert_dict(_terrain.extract_reserve(P, 0)).is_empty()
	assert_int(_terrain.get_tile_data(P).reserve).is_equal(50)

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
	assert_array(_entity_changed).is_empty()


func test_entity_changed_emits_on_place_and_real_remove_only() -> void:
	var node: Node2D = auto_free(Node2D.new())
	_terrain.remove_entity(P) # No entity here — must not emit.
	assert_array(_entity_changed).is_empty()
	_terrain.place_entity(P, node)
	assert_array(_entity_changed).contains_exactly([P])
	var other: Node2D = auto_free(Node2D.new())
	_terrain.place_entity(P, other) # Occupied → rejected, no emit.
	assert_array(_entity_changed).contains_exactly([P])
	_terrain.remove_entity(P)
	assert_array(_entity_changed).contains_exactly([P, P])


func test_get_entity_cells_reflects_occupancy() -> void:
	assert_array(_terrain.get_entity_cells()).is_empty()
	var node: Node2D = auto_free(Node2D.new())
	var q := P + Vector2i(2, 0)
	_terrain.place_entity(P, node)
	_terrain.place_entity(q, node)
	# Damage-only state must not count as an entity cell.
	_terrain.set_tile(P + Vector2i(5, 0), "dirt")
	_terrain.damage_tile(P + Vector2i(5, 0), 0.4, 1, TerrainScript.Source.PLAYER)
	assert_array(_terrain.get_entity_cells()).contains_exactly_in_any_order([P, q])
	_terrain.remove_entity(P)
	assert_array(_terrain.get_entity_cells()).contains_exactly([q])
