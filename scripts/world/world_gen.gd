## Seeded, deterministic world generator driving Terrain's bulk seam.
## Owning doc: docs/systems/world-gen.md
##
## All randomness resolves in _init: two noise fields, discrete features
## (heights, trees, tunnels, deposit blobs) precomputed with one seeded RNG
## consumed in fixed order, and a per-cell hash for ore scatter. The amortized
## row sweep in step() consumes no RNG, so output is identical for any chunk
## size — the save system replays seed + diff and depends on this.
class_name WorldGen
extends RefCounted

## Rows filled per step() call — web loading-time tuning knob.
const ROWS_PER_FRAME := 24
const SURFACE_MEAN := 24
const SURFACE_AMPLITUDE := 8
## Columns flattened around the world center for the Core, each side.
const SPAWN_HALF_WIDTH := 8
const SPAWN_BLEND := 4
const TREE_CHANCE := 0.15
const TREE_MIN_GAP := 4
const TREE_HEIGHT_MIN := 4
const TREE_HEIGHT_MAX := 7
const TUNNEL_COUNT := 3
## No carving above this row — solid roof under the surface band + spawn area.
const CAVE_MIN_ROW := 45
## Radius-1 cross carved around each tunnel-walk step.
const TUNNEL_STAMP: Array[Vector2i] = [
	Vector2i.ZERO,
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var width: int
var height: int
var buffer_width: int
var bands: Array[Dictionary] = []

var _terrain: Node
var _seed: int
var _surface_mean: int
var _surface_amplitude: int
var _spawn_half_width: int
var _cave_min_row: int
var _tunnel_count: int

var _height_noise: FastNoiseLite
var _cave_noise: FastNoiseLite
var _heights: PackedInt32Array
## Tree column x → trunk height (tiles of wood above the grass tile).
var _trees: Dictionary[int, int] = { }
## Cells carved by random-walk tunnels (noise caves are computed per cell).
var _carve: Dictionary[Vector2i, bool] = { }
var _deposit_cells: Dictionary[Vector2i, String] = { }
## Per band: [[cumulative_threshold, material], ...] for the ore-scatter hash.
var _ore_tables: Array = []

var _fill_row := 0
var _tiled_row := 0


## overrides is the test seam: width/height/buffer_width/bands plus the
## surface/cave knobs, defaulting to WorldConfig / Biomes / the consts above.
func _init(terrain: Node, world_seed: int, overrides: Dictionary = { }) -> void:
	_terrain = terrain
	_seed = world_seed
	width = overrides.get("width", WorldConfig.WORLD_WIDTH)
	height = overrides.get("height", WorldConfig.WORLD_HEIGHT)
	buffer_width = overrides.get("buffer_width", WorldConfig.BUFFER_WIDTH)
	bands.assign(overrides.get("bands", Biomes.BANDS))
	_surface_mean = overrides.get("surface_mean", SURFACE_MEAN)
	_surface_amplitude = overrides.get("surface_amplitude", SURFACE_AMPLITUDE)
	_spawn_half_width = overrides.get("spawn_half_width", SPAWN_HALF_WIDTH)
	_cave_min_row = overrides.get("cave_min_row", CAVE_MIN_ROW)
	_tunnel_count = overrides.get("tunnel_count", TUNNEL_COUNT)

	_height_noise = FastNoiseLite.new()
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_height_noise.seed = world_seed
	_height_noise.fractal_octaves = 1
	_height_noise.frequency = 0.03
	_cave_noise = FastNoiseLite.new()
	_cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_cave_noise.seed = world_seed + 1
	_cave_noise.fractal_octaves = 3
	_cave_noise.frequency = 0.06

	for band in bands:
		var table := []
		var cum := 0.0
		for mat: String in band.ores:
			cum += band.ores[mat]
			table.append([cum, mat])
		_ore_tables.append(table)

	# Fixed RNG consumption order — never reorder (breaks saved seeds).
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	_compute_heights()
	# Straight away, not at completion: lighting reads this every frame and the
	# amortized fill takes many frames to finish (terrain.md §Lighting).
	_terrain.set_surface_rows(_heights)
	_precompute_trees(rng)
	_precompute_tunnels(rng)
	_precompute_deposits(rng)

# --- Amortized sweep ----------------------------------------------------------


## Fill up to `rows` rows, then autotile the region that lags one row behind
## the fill front (so every tiled cell has final N and S neighbors — masks
## read only source ids, hence chunk-size independence). Returns progress 0..1.
func step(rows: int = ROWS_PER_FRAME) -> float:
	var fill_target := mini(_fill_row + rows, height)
	while _fill_row < fill_target:
		_fill_one_row(_fill_row)
		_fill_row += 1
	var tile_end := height if _fill_row == height else _fill_row - 1
	if tile_end > _tiled_row:
		_terrain.apply_autotile_region(Rect2i(0, _tiled_row, width, tile_end - _tiled_row))
		_tiled_row = tile_end
	return float(_fill_row + _tiled_row) / float(2 * height)


func is_complete() -> bool:
	return _tiled_row >= height


## Tests and tools; the game loop calls step() per frame instead.
func generate_all() -> void:
	while not is_complete():
		step(height)


## Surface row for column x (valid after _init) — Core/camera placement.
func surface_height(x: int) -> int:
	return _heights[x]

# --- Precompute (all RNG lives here) ------------------------------------------


func _compute_heights() -> void:
	_heights.resize(width)
	var pb := buffer_width
	var pe := width - buffer_width
	var cx := int(width / 2.0)
	var flat_h := _noise_height(cx)
	for x in range(pb, pe):
		var h := _noise_height(x)
		var d := absi(x - cx)
		if d <= _spawn_half_width:
			h = flat_h
		elif d <= _spawn_half_width + SPAWN_BLEND:
			var t := float(d - _spawn_half_width) / float(SPAWN_BLEND)
			h = roundi(lerpf(float(flat_h), float(h), t))
		_heights[x] = h
	# Buffers: perfectly flat at the adjacent playable edge height (continuity
	# at the boundary is automatic).
	for x in pb:
		_heights[x] = _heights[pb]
	for x in range(pe, width):
		_heights[x] = _heights[pe - 1]


func _noise_height(x: int) -> int:
	return _surface_mean + roundi(_height_noise.get_noise_1d(float(x)) * _surface_amplitude)


func _precompute_trees(rng: RandomNumberGenerator) -> void:
	var cx := int(width / 2.0)
	var exclude := _spawn_half_width + SPAWN_BLEND
	var last := -TREE_MIN_GAP
	for x in range(buffer_width, width - buffer_width):
		if absi(x - cx) <= exclude or x - last < TREE_MIN_GAP:
			continue
		if rng.randf() < TREE_CHANCE:
			_trees[x] = rng.randi_range(TREE_HEIGHT_MIN, TREE_HEIGHT_MAX)
			last = x


## Downward-biased random walks stamping a radius-1 cross, clamped inside the
## playable range and above the bedrock floor — buffers can never be breached.
func _precompute_tunnels(rng: RandomNumberGenerator) -> void:
	var x_min := buffer_width + 1
	var x_max := width - buffer_width - 2
	var y_min := _cave_min_row
	var y_max := height - 3
	if y_min > y_max or x_min > x_max:
		return
	for i in _tunnel_count:
		var x := rng.randi_range(x_min + 2, x_max - 2)
		var y := rng.randi_range(y_min, mini(y_min + 10, y_max))
		var steps := rng.randi_range(int(height / 2.0), int(height * 0.75))
		for s in steps:
			for offset in TUNNEL_STAMP:
				var cell := Vector2i(
					clampi(x + offset.x, x_min, x_max),
					clampi(y + offset.y, y_min, y_max),
				)
				_carve[cell] = true
			x = clampi(x + rng.randi_range(-1, 1), x_min, x_max)
			y = clampi(y + (1 if rng.randf() < 0.55 else 0), y_min, y_max)


## Drunkard-walk blob fill per spec, clamped inside the playable range and the
## owning band's rows. Reserve is NOT written — Terrain resolves base_reserve
## lazily, keeping the sparse state dict empty after generation.
func _precompute_deposits(rng: RandomNumberGenerator) -> void:
	var x_min := buffer_width + 1
	var x_max := width - buffer_width - 2
	for band in bands:
		var y_min: int = maxi(band.row_begin + 1, 1)
		var y_max: int = mini(band.row_end - 2, height - 2)
		if y_min > y_max:
			continue
		for spec: Dictionary in band.deposits:
			for i in spec.count:
				var pos := Vector2i(
					rng.randi_range(x_min + 1, x_max - 1),
					rng.randi_range(y_min, y_max),
				)
				var target: int = rng.randi_range(spec.size.x, spec.size.y)
				var placed := 0
				var guard := target * 20
				while placed < target and guard > 0:
					guard -= 1
					if not _deposit_cells.has(pos):
						_deposit_cells[pos] = spec.material
						placed += 1
					var dir := rng.randi_range(0, 3)
					pos.x = clampi(pos.x + [1, -1, 0, 0][dir], x_min, x_max)
					pos.y = clampi(pos.y + [0, 0, 1, -1][dir], y_min, y_max)

# --- Row sweep (no RNG, no allocation beyond Vector2i) ------------------------


func _fill_one_row(y: int) -> void:
	var band_idx := _band_index_for_row(y)
	var band: Dictionary = bands[band_idx]
	var base: String = band.material
	var cave_threshold: float = band.cave_threshold
	var ore_table: Array = _ore_tables[band_idx]
	var edge_y := y == 0 or y == height - 1
	var carve_row := y >= _cave_min_row and y < height - 1
	for x in width:
		var id := _cell_material(x, y, base, cave_threshold, ore_table, edge_y, carve_row)
		# Air skips the write entirely — the map starts empty.
		if id != "":
			_terrain.set_cell_raw(Vector2i(x, y), id)


## Priority: bedrock border → buffer (flat dirt) → above-surface air / trunk →
## grass top → carve → deposit → ore hash → band base material.
func _cell_material(
		x: int,
		y: int,
		base: String,
		cave_threshold: float,
		ore_table: Array,
		edge_y: bool,
		carve_row: bool,
) -> String:
	if edge_y or x == 0 or x == width - 1:
		return "bedrock"
	var h := _heights[x]
	if x < buffer_width or x >= width - buffer_width:
		return "dirt" if y >= h else ""
	if y < h:
		return "wood" if h - y <= _trees.get(x, 0) else ""
	if y == h:
		return "grass"
	var pos := Vector2i(x, y)
	if carve_row and (_carve.has(pos) or _cave_noise.get_noise_2d(float(x), float(y)) > cave_threshold):
		return ""
	var deposit: String = _deposit_cells.get(pos, "")
	if deposit != "":
		return deposit
	if not ore_table.is_empty():
		var r := _cell_hash01(_seed, x, y)
		for entry: Array in ore_table:
			if r < entry[0]:
				return entry[1]
	return base


func _band_index_for_row(y: int) -> int:
	for i in bands.size():
		if y < bands[i].row_end:
			return i
	return bands.size() - 1


## Per-cell ore roll: stateless seeded hash → [0, 1). Same integer-mix style
## as the pinned TileLayout.variant_hash — NOT engine hash() (not stable).
static func _cell_hash01(world_seed: int, x: int, y: int) -> float:
	var h := world_seed ^ (x * 0x9E3779B1) ^ (y * 0x85EBCA77)
	h = (h ^ (h >> 16)) * 0x45D9F3B
	h = (h ^ (h >> 16)) * 0x45D9F3B
	return float((h ^ (h >> 16)) & 0x7FFFFFFF) / 2147483648.0
