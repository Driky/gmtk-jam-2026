## World grid — ALL tile access goes through this API. Owning doc: docs/systems/terrain.md
##
## Hybrid model: the TileMapLayer is authoritative for tile TYPE (static props
## read from data/materials.gd keyed by atlas source id); a sparse dict holds
## dynamic state only (damage, deposit reserve, occupying entity).
extends Node

## Structure changed (type or solidity) — Day-2 flow-field debounce hooks here.
signal tile_changed(pos: Vector2i)
## A break/chip produced drops — the pickup spawner (1.6) hooks here and owns
## drop policy (source is in the payload).
signal drops_spawned(pos: Vector2i, drop_id: String, drop_count: int, source: int)
## Mining feedback (ratio = accumulated damage / hardness).
signal tile_damaged(pos: Vector2i, ratio: float)
## The cell was destroyed outright (normal break or deposit exhaustion —
## deposit chips don't emit). The blocks-mined run stat (2.1) hooks here.
## Fires after the cell is already air.
signal tile_broken(pos: Vector2i, material_id: String, source: int)

enum Source { PLAYER, MONSTER, MACHINE }

const TILESET_PATH := "res://assets/generated/terrain_tileset.tres"
## Mining damage on a cell clears if the cell isn't hit again within this window.
const ABANDON_TIMEOUT_MS := 2000
const SWEEP_INTERVAL := 0.5
## Reserve consumed per pickaxe chip (1 drop each) — chipping "yields poorly"
## vs. a Miner; Day-4 tuning knob.
const DEPOSIT_CHIP_RESERVE_COST := 5

## Autotile neighbor bits (must match TileLayout.LAYOUT): 1=N, 2=E, 4=S, 8=W.
const NEIGHBORS: Array = [
	[1, Vector2i(0, -1)],
	[2, Vector2i(1, 0)],
	[4, Vector2i(0, 1)],
	[8, Vector2i(-1, 0)],
]


## Dynamic per-cell state. Entries exist only while non-default (sparse dict
## invariant — see _prune). reserve == -1 means "untouched": resolved lazily
## from the material's base_reserve so world gen never materializes entries
## for every deposit tile.
class TileState:
	var damage := 0.0
	var last_hit_ms := 0
	var reserve := -1
	var entity: Node = null


	func is_default() -> bool:
		return damage == 0.0 and reserve == -1 and entity == null


var _layer: TileMapLayer
var _state: Dictionary[Vector2i, TileState] = { }
## Cells with damage > 0 only — keeps the abandon sweep off the main dict.
var _damaged: Dictionary[Vector2i, bool] = { }
var _solid_by_source: Array[bool] = []
var _source_by_material: Dictionary[String, int] = { }
var _sweep_accum := 0.0


func _ready() -> void:
	_layer = TileMapLayer.new()
	_layer.name = "TileMapLayer"
	_layer.tile_set = load(TILESET_PATH)
	add_child(_layer)
	for source_id in Materials.ORDER.size():
		var id: String = Materials.ORDER[source_id]
		_source_by_material[id] = source_id
		_solid_by_source.append(Materials.MATERIALS[id].is_solid)


func _process(delta: float) -> void:
	_sweep_accum += delta
	if _sweep_accum >= SWEEP_INTERVAL:
		_sweep_accum = 0.0
		_sweep_abandoned(Time.get_ticks_msec())

# --- Reads -------------------------------------------------------------------


## Full snapshot (static props + dynamic state); {} for air/out-of-world.
## Allocates — don't call from hot loops; use is_solid/get_material_id there.
func get_tile_data(pos: Vector2i) -> Dictionary:
	var sid := _layer.get_cell_source_id(pos)
	if sid == -1:
		return { }
	var id: String = Materials.ORDER[sid]
	var mat: Dictionary = Materials.MATERIALS[id]
	var state: TileState = _state.get(pos)
	return {
		material_id = id,
		hardness = mat.hardness,
		drop_id = mat.drop_id,
		drop_count = mat.drop_count,
		is_solid = mat.is_solid,
		is_ore = mat.is_ore,
		is_deposit = mat.is_deposit,
		min_tool_tier = mat.min_tool_tier,
		damage = state.damage if state != null else 0.0,
		reserve = _resolve_reserve(state, mat),
		entity = state.entity if state != null else null,
	}


func get_material_id(pos: Vector2i) -> String:
	var sid := _layer.get_cell_source_id(pos)
	return "" if sid == -1 else Materials.ORDER[sid]


func is_solid(pos: Vector2i) -> bool:
	var sid := _layer.get_cell_source_id(pos)
	return sid != -1 and _solid_by_source[sid]


## Buffer-zone rule for player actions (mining ghost tint, place-block checks).
func can_player_edit(pos: Vector2i) -> bool:
	return WorldConfig.is_in_world(pos) and not WorldConfig.is_in_buffer(pos)

# --- Mining ------------------------------------------------------------------


## The single damage entry point: player mining, monster digging, machines.
## Returns false when the hit is rejected (out of world, air, tool tier too
## low, or player-sourced in a buffer zone — monsters dig buffers freely).
func damage_tile(pos: Vector2i, amount: float, tool_tier: int, source: Source) -> bool:
	if not WorldConfig.is_in_world(pos):
		return false
	var sid := _layer.get_cell_source_id(pos)
	if sid == -1:
		return false
	var mat: Dictionary = Materials.MATERIALS[Materials.ORDER[sid]]
	if tool_tier < mat.min_tool_tier:
		return false
	if source == Source.PLAYER and WorldConfig.is_in_buffer(pos):
		return false

	var state := _state_for(pos)
	state.damage += amount
	state.last_hit_ms = Time.get_ticks_msec()
	_damaged[pos] = true
	tile_damaged.emit(pos, state.damage / mat.hardness)
	if state.damage < mat.hardness:
		return true

	# Break threshold reached.
	state.damage = 0.0
	_damaged.erase(pos)
	if mat.is_deposit:
		if state.reserve == -1:
			state.reserve = mat.base_reserve
		state.reserve -= DEPOSIT_CHIP_RESERVE_COST
		_award(pos, mat, source)
		if state.reserve > 0:
			return true
	else:
		_award(pos, mat, source)
	# Destroyed (normal break, or deposit chipped to exhaustion — no 2nd drop).
	assert(state.entity == null)
	_state.erase(pos)
	set_tile(pos, "")
	tile_broken.emit(pos, Materials.ORDER[sid], source)
	return true

# --- Writes ------------------------------------------------------------------


## Set a cell to a material id ("" = air), re-autotile it + its 4 neighbors,
## emit tile_changed. Resets any mining damage/reserve on the cell.
func set_tile(pos: Vector2i, material_id: String) -> void:
	if not WorldConfig.is_in_world(pos):
		return
	var state: TileState = _state.get(pos)
	if state != null:
		# Entities live in air cells only — a solid tile must never bury one.
		assert(material_id == "" or state.entity == null)
		state.damage = 0.0
		state.reserve = -1
		_damaged.erase(pos)
		_prune(pos, state)
	if material_id == "":
		_layer.erase_cell(pos)
	else:
		assert(_source_by_material.has(material_id))
		var sid: int = _source_by_material[material_id]
		_layer.set_cell(pos, sid, TileLayout.LAYOUT[15][TileLayout.variant_hash(pos)])
	_refresh_with_neighbors(pos)
	tile_changed.emit(pos)

# --- Entities (deployables — automation.md registers per occupied cell) ------


func place_entity(pos: Vector2i, node: Node) -> bool:
	if not WorldConfig.is_in_world(pos) or is_solid(pos):
		return false
	var state := _state_for(pos)
	if state.entity != null:
		_prune(pos, state)
		return false
	state.entity = node
	return true


func remove_entity(pos: Vector2i) -> void:
	var state: TileState = _state.get(pos)
	if state == null:
		return
	state.entity = null
	_prune(pos, state)


func get_entity(pos: Vector2i) -> Node:
	var state: TileState = _state.get(pos)
	return state.entity if state != null else null

# --- Bulk seam (1.5 world gen) -----------------------------------------------


## Fast path: no autotile recompute, no signals. Places an interior frame as
## placeholder; pair with apply_autotile_region once a band is filled.
func set_cell_raw(pos: Vector2i, material_id: String) -> void:
	if material_id == "":
		_layer.erase_cell(pos)
		return
	var sid: int = _source_by_material[material_id]
	_layer.set_cell(pos, sid, TileLayout.LAYOUT[15][TileLayout.variant_hash(pos)])


func set_reserve(pos: Vector2i, amount: int) -> void:
	_state_for(pos).reserve = amount


## Recompute autotile masks for every cell in rect. World gen amortizes this
## across frames: raw-set N rows, then a region pass with one row of overlap.
func apply_autotile_region(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_apply_mask(Vector2i(x, y))


## Wipe all run state ahead of a scene reload (restart flow, 2.1). Every
## autoload holding run state exposes reset_run() — tech-design.md.
func reset_run() -> void:
	_layer.clear()
	_state.clear()
	_damaged.clear()
	_sweep_accum = 0.0

# --- Debug -------------------------------------------------------------------


## Drift guard: dict bookkeeping must agree with the TileMap. assert compiles
## out of release exports — debug builds only, zero release cost.
func debug_validate() -> void:
	for pos: Vector2i in _state:
		var state: TileState = _state[pos]
		assert(not state.is_default())
		if state.entity != null:
			assert(is_instance_valid(state.entity))
			assert(not is_solid(pos))
		if state.damage > 0.0:
			assert(_damaged.has(pos))
	for pos: Vector2i in _damaged:
		var state: TileState = _state.get(pos)
		assert(state != null and state.damage > 0.0)

# --- Internals ---------------------------------------------------------------


func _state_for(pos: Vector2i) -> TileState:
	var state: TileState = _state.get(pos)
	if state == null:
		state = TileState.new()
		_state[pos] = state
	return state


## Keep the dict sparse: erase entries that returned to default state.
func _prune(pos: Vector2i, state: TileState) -> void:
	if state.is_default():
		_state.erase(pos)


func _resolve_reserve(state: TileState, mat: Dictionary) -> int:
	if not mat.is_deposit:
		return 0
	if state == null or state.reserve == -1:
		return mat.base_reserve
	return state.reserve


## Drops + XP for one successful break/chip.
func _award(pos: Vector2i, mat: Dictionary, source: int) -> void:
	if mat.drop_id != "":
		drops_spawned.emit(pos, mat.drop_id, mat.drop_count, source)
	# XP seam — self-wires when Progression.grant_xp lands (roadmap 2.6).
	if source == Source.PLAYER and Progression.has_method(&"grant_xp"):
		Progression.call(&"grant_xp", "mining", mat.hardness)


## Clear mining damage on cells not hit within ABANDON_TIMEOUT_MS. The clock
## is a parameter so tests can drive it directly.
func _sweep_abandoned(now_ms: int) -> void:
	for pos: Vector2i in _damaged.keys():
		var state: TileState = _state.get(pos)
		if state == null:
			_damaged.erase(pos)
			continue
		if now_ms - state.last_hit_ms >= ABANDON_TIMEOUT_MS:
			state.damage = 0.0
			_damaged.erase(pos)
			_prune(pos, state)


## 4-bit self-merge mask: bit set iff the cardinal neighbor has the SAME
## atlas source id (air/out-of-map = unset; deposits and their base ore are
## different source ids, so they correctly don't merge).
func _neighbor_mask(pos: Vector2i, sid: int) -> int:
	var mask := 0
	for entry: Array in NEIGHBORS:
		if _layer.get_cell_source_id(pos + entry[1]) == sid:
			mask |= entry[0]
	return mask


func _apply_mask(pos: Vector2i) -> void:
	var sid := _layer.get_cell_source_id(pos)
	if sid == -1:
		return
	var mask := _neighbor_mask(pos, sid)
	_layer.set_cell(pos, sid, TileLayout.LAYOUT[mask][TileLayout.variant_hash(pos)])


func _refresh_with_neighbors(pos: Vector2i) -> void:
	_apply_mask(pos)
	for entry: Array in NEIGHBORS:
		_apply_mask(pos + entry[1])
