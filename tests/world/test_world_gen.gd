## Unit tests for WorldGen (roadmap 1.5). Runs on a small injected world
## against a fresh Terrain instance — never mutates the live autoload.
## Per-cell sweeps collect violations into one array and assert it empty:
## one asserter call instead of thousands, and failures list the positions.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const WorldGenScript := preload("res://scripts/world/world_gen.gd")

const SEED := 1234
const W := 60
const H := 120
const BUF := 10
## Playable x range for the test world.
const PB := BUF
const PE := W - BUF
const CX := 30
const SPAWN_HALF := 4
const CAVE_MIN := 14

## Scaled 5-band table mirroring Biomes.BANDS' shape.
const TEST_BANDS: Array[Dictionary] = [
	{
		name = "surface",
		row_begin = 0,
		row_end = 12,
		material = "dirt",
		cave_threshold = 2.0,
		ores = { },
		deposits = [],
	},
	{
		name = "dirt_caves",
		row_begin = 12,
		row_end = 40,
		material = "dirt",
		cave_threshold = 0.45,
		ores = { coal = 0.02, copper = 0.02 },
		deposits = [{ material = "coal_deposit", count = 1, size = Vector2i(6, 10) }],
	},
	{
		name = "stone",
		row_begin = 40,
		row_end = 70,
		material = "stone",
		cave_threshold = 0.38,
		ores = { iron = 0.025 },
		deposits = [{ material = "iron_deposit", count = 1, size = Vector2i(6, 10) }],
	},
	{
		name = "crystal",
		row_begin = 70,
		row_end = 95,
		material = "ice_stone",
		cave_threshold = 0.35,
		ores = { gold = 0.02 },
		deposits = [],
	},
	{
		name = "magma",
		row_begin = 95,
		row_end = 120,
		material = "magma_stone",
		cave_threshold = 0.33,
		ores = { magmatite = 0.02 },
		deposits = [],
	},
]

const OVERRIDES := {
	width = W,
	height = H,
	buffer_width = BUF,
	bands = TEST_BANDS,
	surface_mean = 7,
	surface_amplitude = 3,
	spawn_half_width = SPAWN_HALF,
	cave_min_row = CAVE_MIN,
	tunnel_count = 2,
}


func _new_terrain() -> Node:
	var terrain: Node = auto_free(TerrainScript.new())
	add_child(terrain)
	return terrain


## Returns [terrain, gen] fully generated with the test overrides.
func _generate(world_seed: int, chunk: int = H) -> Array:
	var terrain := _new_terrain()
	var gen: RefCounted = WorldGenScript.new(terrain, world_seed, OVERRIDES)
	while not gen.is_complete():
		gen.step(chunk)
	return [terrain, gen]


func _material_at(terrain: Node, x: int, y: int) -> String:
	return terrain.get_material_id(Vector2i(x, y))


## Full (source_id, atlas_coords) snapshot — covers type AND autotile result.
func _snapshot(terrain: Node) -> Array:
	var out := []
	for y in H:
		for x in W:
			var pos := Vector2i(x, y)
			out.append(terrain._layer.get_cell_source_id(pos))
			out.append(terrain._layer.get_cell_atlas_coords(pos))
	return out

# --- Determinism (the load-bearing guarantees) --------------------------------


func test_same_seed_identical() -> void:
	var a: Array = _generate(SEED)
	var b: Array = _generate(SEED)
	assert_bool(_snapshot(a[0]) == _snapshot(b[0])).is_true()


func test_chunk_size_independent() -> void:
	var whole: Array = _generate(SEED)
	var chunked: Array = _generate(SEED, 3)
	assert_bool(_snapshot(whole[0]) == _snapshot(chunked[0])).is_true()


func test_different_seed_differs() -> void:
	var a: Array = _generate(SEED)
	var b: Array = _generate(SEED + 1)
	assert_bool(_snapshot(a[0]) == _snapshot(b[0])).is_false()


func test_progress_monotonic_and_complete() -> void:
	var terrain := _new_terrain()
	var gen: RefCounted = WorldGenScript.new(terrain, SEED, OVERRIDES)
	var last := 0.0
	while not gen.is_complete():
		var p: float = gen.step(7)
		assert_bool(p >= last).is_true()
		last = p
	assert_float(last).is_equal_approx(1.0, 0.0001)

# --- Structure ----------------------------------------------------------------


func test_bedrock_border_complete() -> void:
	var terrain: Node = _generate(SEED)[0]
	var violations := []
	for x in W:
		for y in [0, H - 1]:
			if _material_at(terrain, x, y) != "bedrock":
				violations.append(Vector2i(x, y))
	for y in H:
		for x in [0, W - 1]:
			if _material_at(terrain, x, y) != "bedrock":
				violations.append(Vector2i(x, y))
	assert_array(violations).is_empty()


func test_buffers_flat_dirt_only() -> void:
	var result: Array = _generate(SEED)
	var terrain: Node = result[0]
	var gen: RefCounted = result[1]
	var violations := []
	for x in range(1, W - 1):
		if x >= PB and x < PE:
			continue
		var surface: int = gen.surface_height(PB if x < PB else PE - 1)
		for y in range(1, H - 1):
			var expected := "" if y < surface else "dirt"
			if _material_at(terrain, x, y) != expected:
				violations.append(Vector2i(x, y))
	assert_array(violations).is_empty()


func test_spawn_area_flat_grass_no_trees() -> void:
	var result: Array = _generate(SEED)
	var terrain: Node = result[0]
	var gen: RefCounted = result[1]
	var flat_h: int = gen.surface_height(CX)
	var violations := []
	for x in range(CX - SPAWN_HALF, CX + SPAWN_HALF + 1):
		if gen.surface_height(x) != flat_h:
			violations.append(x)
		if _material_at(terrain, x, flat_h) != "grass":
			violations.append(Vector2i(x, flat_h))
		for y in range(1, flat_h):
			if _material_at(terrain, x, y) != "":
				violations.append(Vector2i(x, y))
	assert_array(violations).is_empty()


func test_biome_band_materials() -> void:
	var terrain: Node = _generate(SEED)[0]
	# material → index of the single band whose rows may contain it.
	var owner_band := { }
	for i in TEST_BANDS.size():
		for ore: String in TEST_BANDS[i].ores:
			owner_band[ore] = i
		for spec: Dictionary in TEST_BANDS[i].deposits:
			owner_band[spec.material] = i
	var band_bases := ["dirt", "dirt", "stone", "ice_stone", "magma_stone"]
	var seen := { }
	var violations := []
	for y in range(1, H - 1):
		var band_idx := _band_index(y)
		for x in range(PB, PE):
			var id := _material_at(terrain, x, y)
			seen[id] = true
			if id == "" or id == "grass" or id == "wood" or id == "dirt":
				continue
			var allowed: int = owner_band.get(id, -1)
			if allowed != -1:
				if allowed != band_idx:
					violations.append([Vector2i(x, y), id])
			elif id != band_bases[band_idx]:
				violations.append([Vector2i(x, y), id])
	assert_array(violations).is_empty()
	# Every configured ore/deposit material actually generated somewhere.
	for id: String in owner_band:
		assert_bool(seen.has(id)).append_failure_message("missing material: " + id).is_true()


func _band_index(y: int) -> int:
	for i in TEST_BANDS.size():
		if y < TEST_BANDS[i].row_end:
			return i
	return TEST_BANDS.size() - 1


func test_trees_on_grass_playable_only() -> void:
	var result: Array = _generate(SEED)
	var terrain: Node = result[0]
	var gen: RefCounted = result[1]
	var trunk_columns := { }
	var violations := []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if _material_at(terrain, x, y) != "wood":
				continue
			trunk_columns[x] = true
			if x < PB or x >= PE or y >= gen.surface_height(x):
				violations.append(Vector2i(x, y))
	for x: int in trunk_columns:
		if _material_at(terrain, x, gen.surface_height(x)) != "grass":
			violations.append(x)
	assert_array(violations).is_empty()
	# The chosen seed must actually produce trees for this test to mean much.
	assert_bool(trunk_columns.size() > 0).is_true()


func test_caves_only_below_min_row_and_exist() -> void:
	var result: Array = _generate(SEED)
	var terrain: Node = result[0]
	var gen: RefCounted = result[1]
	var air_below_min := 0
	var violations := []
	for x in range(PB, PE):
		var surface: int = gen.surface_height(x)
		for y in range(surface + 1, H - 1):
			if _material_at(terrain, x, y) != "":
				continue
			if y < CAVE_MIN:
				violations.append(Vector2i(x, y))
			else:
				air_below_min += 1
	assert_array(violations).is_empty()
	assert_bool(air_below_min > 0).is_true()


func test_deposit_reserve_lazy_no_state_entries() -> void:
	var terrain: Node = _generate(SEED)[0]
	assert_bool(terrain._state.is_empty()).is_true()
	var deposit_pos := Vector2i(-1, -1)
	for y in range(1, H - 1):
		for x in range(PB, PE):
			if _material_at(terrain, x, y) == "coal_deposit":
				deposit_pos = Vector2i(x, y)
				break
		if deposit_pos.x != -1:
			break
	assert_bool(deposit_pos.x != -1).is_true()
	assert_int(terrain.get_tile_data(deposit_pos).reserve).is_equal(50)
	assert_bool(terrain._state.is_empty()).is_true()
	terrain.debug_validate()

# --- Autotiling finalized -----------------------------------------------------


## Every non-air cell must display the mask its final neighbors imply — the
## lag-one-row amortization contract, end to end, under a small chunk size.
func test_autotile_masks_match_neighbors_everywhere() -> void:
	var terrain: Node = _generate(SEED, 5)[0]
	var violations := []
	for y in H:
		for x in W:
			var pos := Vector2i(x, y)
			var sid: int = terrain._layer.get_cell_source_id(pos)
			if sid == -1:
				continue
			var mask: int = terrain._neighbor_mask(pos, sid)
			var expected: Vector2i = TileLayout.LAYOUT[mask][TileLayout.variant_hash(pos)]
			if terrain._layer.get_cell_atlas_coords(pos) != expected:
				violations.append(pos)
	assert_array(violations).is_empty()
