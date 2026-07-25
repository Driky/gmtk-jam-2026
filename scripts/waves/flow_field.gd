## Shared ground flow field: Dijkstra cost-to-Core over the wave region,
## gravity-aware and dig-weighted. Owning doc: docs/systems/enemies.md
##
## cost_at(v) = cheapest cost for a mob standing at cell v to reach the Core.
## Seeded at the Core footprint and expanded outward, so when relaxing settled
## cell u toward neighbor v the edge evaluated is the mob's actual move v -> u:
## tentative = cost[u] + cost_of_entering(from = v, to = u). Gravity costs are
## asymmetric (falling ~free, ascending restricted) — the swapped-roles call is
## what keeps them pointing the right way.
##
## Consumer contract (mobs 2.3, wave manager 2.4/Day 4): cost_at == INF or
## get_flow_dir == Vector2i.ZERO means "no guidance — fall back to direct chew
## toward the Core". Queries reflect the terrain snapshot taken by the last
## recompute(); Waves owns the debounce that keeps it fresh.
class_name FlowField
extends RefCounted

## Field rows (full world width x this): mobs live near the surface; anything
## deeper reads as no-data.
const REGION_ROWS := 150
## Reference mob capabilities (accepted simplification: one field for every
## ground mob) — Day-4 tuning knobs.
const REFERENCE_DIG_POWER := 1.0
const FALL_COST := 0.05
const MOVE_COST := 1.0
const ENTITY_HP_COST_FACTOR := 0.01
## min_tool_tier at/above this can never break via damage_tile -> impassable.
const UNMINABLE_TOOL_TIER := 99

## Mob step directions; _flow stores an index into this (FLOW_NONE = no data).
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const DX: Array[int] = [0, 1, 0, -1]
const DY: Array[int] = [-1, 0, 1, 0]
const FLOW_NONE := 255

## Injected by Waves (the Terrain autoload) or tests (a double exposing
## get_cell_source_id / get_entity / get_entity_cells).
var terrain: Node = null
## Vars, not consts, so tests can shrink the grid.
var region_width := WorldConfig.WORLD_WIDTH
var region_rows := REGION_ROWS

## Wall-clock cost of the last recompute(), surfaced by the F4 perf overlay —
## the browser has no editor profiler and this is the number we tune against.
var last_solve_msec := 0.0

var _computed := false
var _cost := PackedFloat32Array()
var _flow := PackedByteArray()
## Terrain snapshot for one solve: atlas source id per cell (-1 = air),
## support flag (any cardinal solid), sparse entity surcharge by flat index.
var _sid := PackedInt32Array()
var _supported := PackedByteArray()
var _entity_cost: Dictionary[int, float] = { }
## Per-source enter cost for solid cells (INF = unminable), from materials.gd.
var _dig_cost_by_source := PackedFloat32Array()

var _heap_cells := PackedInt32Array()
var _heap_keys := PackedFloat32Array()
var _heap_size := 0


func _init() -> void:
	for id: String in Materials.ORDER:
		var mat: Dictionary = Materials.MATERIALS[id]
		assert(mat.is_solid) # Non-solid materials would need an air-like branch.
		if mat.min_tool_tier >= UNMINABLE_TOOL_TIER:
			_dig_cost_by_source.append(INF)
		else:
			_dig_cost_by_source.append(1.0 + mat.hardness / REFERENCE_DIG_POWER)

# --- Public API --------------------------------------------------------------


func recompute(goal_cells: Array[Vector2i]) -> void:
	assert(terrain != null)
	var t0 := Time.get_ticks_usec()
	var w := region_width
	var rows := region_rows
	_snapshot()
	_cost.resize(w * rows)
	_cost.fill(INF)
	_flow.resize(w * rows)
	_flow.fill(FLOW_NONE)
	_heap_size = 0
	for pos in goal_cells:
		if _in_region(pos):
			_cost[pos.y * w + pos.x] = 0.0
			_heap_push(pos.y * w + pos.x, 0.0)
	while _heap_size > 0:
		var u := _heap_cells[0]
		var k := _heap_keys[0]
		_heap_pop_root()
		if k > _cost[u]: # Lazy deletion: u was settled via a cheaper key.
			continue
		var ux := u % w
		@warning_ignore("integer_division")
		var uy := u / w
		var su := _sid[u]
		# Entering u costs the same from all 4 sides except the gravity branch.
		var dig := _dig_cost_by_source[su] if su != -1 else 0.0
		var surcharge: float = _entity_cost.get(u, 0.0)
		if dig == INF:
			continue # Bedrock: nothing ever enters u, skip all 4 edges.
		for di in 4:
			var vx := ux + DX[di]
			var vy := uy + DY[di]
			if vx < 0 or vx >= w or vy < 0 or vy >= rows:
				continue
			var v := vy * w + vx
			var step: float
			if su != -1:
				step = dig
			elif uy > vy:
				step = FALL_COST # u below v: the mob falls in.
			elif _supported[v] == 1 or _supported[u] == 1:
				# Up/sideways air move: needs support at either end — `to`
				# covers floors/wall-climbs, `from` covers stepping off a
				# ledge (so the gradient can point over drops; stair-digging
				# 2.3 triggers on exactly that). Over-connectivity is the
				# documented accepted error: the dig fallback absorbs it.
				step = MOVE_COST
			else:
				continue
			var tentative := k + step + surcharge
			if tentative < _cost[v]:
				_cost[v] = tentative
				_flow[v] = (di + 2) & 3 # Mob step v -> u = opposite of u -> v.
				_heap_push(v, tentative)
	_computed = true
	last_solve_msec = (Time.get_ticks_usec() - t0) / 1000.0
	print_verbose("FlowField recompute: %d cells in %.1f ms" % [w * rows, last_solve_msec])


func is_computed() -> bool:
	return _computed


func cost_at(cell: Vector2i) -> float:
	if not _computed or not _in_region(cell):
		return INF
	return _cost[cell.y * region_width + cell.x]


func get_flow_dir(cell: Vector2i) -> Vector2i:
	if not _computed or not _in_region(cell):
		return Vector2i.ZERO
	var f := _flow[cell.y * region_width + cell.x]
	return Vector2i.ZERO if f == FLOW_NONE else DIRS[f]


## Independent copy for the Day-4 fortification baseline.
func snapshot_costs() -> PackedFloat32Array:
	return _cost.duplicate()


## Reference edge cost: mob standing at `from` steps into the cardinal
## neighbor `to`. Reads the last recompute() snapshot — the Dijkstra loop
## inlines this exact logic (GDScript call overhead x 120k edges); tests
## cross-check both paths.
func cost_of_entering(from: Vector2i, to: Vector2i) -> float:
	if not _in_region(from) or not _in_region(to):
		return INF
	var ti := to.y * region_width + to.x
	var step: float
	var sid := _sid[ti]
	if sid != -1:
		step = _dig_cost_by_source[sid]
		if step == INF:
			return INF
	elif to.y > from.y:
		step = FALL_COST
	elif _supported[ti] == 1 or _supported[from.y * region_width + from.x] == 1:
		step = MOVE_COST
	else:
		return INF
	return step + _entity_cost.get(ti, 0.0)

# --- Internals ---------------------------------------------------------------


func _in_region(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < region_width and pos.y >= 0 and pos.y < region_rows


## One pass of native reads up front so the solve never calls across objects.
func _snapshot() -> void:
	var w := region_width
	var rows := region_rows
	_sid.resize(w * rows)
	_supported.resize(w * rows)
	var i := 0
	for y in rows:
		for x in w:
			_sid[i] = terrain.get_cell_source_id(Vector2i(x, y))
			i += 1
	i = 0
	for y in rows:
		for x in w:
			var sup := false
			if x > 0 and _sid[i - 1] != -1:
				sup = true
			elif x < w - 1 and _sid[i + 1] != -1:
				sup = true
			elif y > 0 and _sid[i - w] != -1:
				sup = true
			elif y < rows - 1 and _sid[i + w] != -1:
				sup = true
			_supported[i] = 1 if sup else 0
			i += 1
	_entity_cost.clear()
	for pos: Vector2i in terrain.get_entity_cells():
		if not _in_region(pos):
			continue
		var ent: Node = terrain.get_entity(pos)
		if ent == null or ent.is_in_group("core"): # Core cells are goals, never obstacles.
			continue
		var hp: Variant = ent.get("current_hp")
		if hp != null:
			_entity_cost[pos.y * w + pos.x] = float(hp) * ENTITY_HP_COST_FACTOR


func _heap_push(cell: int, key: float) -> void:
	if _heap_size == _heap_cells.size():
		var cap := maxi(64, _heap_size * 2)
		_heap_cells.resize(cap)
		_heap_keys.resize(cap)
	var i := _heap_size
	_heap_size += 1
	_heap_cells[i] = cell
	_heap_keys[i] = key
	while i > 0:
		var parent := (i - 1) >> 1
		if _heap_keys[parent] <= _heap_keys[i]:
			break
		_heap_swap(i, parent)
		i = parent


func _heap_pop_root() -> void:
	_heap_size -= 1
	_heap_cells[0] = _heap_cells[_heap_size]
	_heap_keys[0] = _heap_keys[_heap_size]
	var i := 0
	while true:
		var child := i * 2 + 1
		if child >= _heap_size:
			break
		if child + 1 < _heap_size and _heap_keys[child + 1] < _heap_keys[child]:
			child += 1
		if _heap_keys[i] <= _heap_keys[child]:
			break
		_heap_swap(i, child)
		i = child


func _heap_swap(a: int, b: int) -> void:
	var c := _heap_cells[a]
	_heap_cells[a] = _heap_cells[b]
	_heap_cells[b] = c
	var key := _heap_keys[a]
	_heap_keys[a] = _heap_keys[b]
	_heap_keys[b] = key
