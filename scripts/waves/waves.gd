## Wave composition, spawning, aggro helpers; owns the shared ground flow
## field (2.2). Owning doc: docs/systems/enemies.md
##
## 2.1 stub: no enemies exist yet, so a wave "clears" on a fixed timer (or
## the F9 debug action). The real manager (2.4) replaces the timer but keeps
## the same clear contract: call game.notify_wave_cleared() when all spawned
## mobs are dead.
extends Node

## The flow field was rebuilt — the debug overlay redraws on this; mobs just
## re-read the field every frame and don't need it.
signal flow_field_updated

## Placeholder wave length until enemies land in 2.3/2.4.
const STUB_WAVE_DURATION := 15.0
## Leading-edge debounce: the first change arms the timer, later changes never
## re-arm it (a trailing debounce would starve under continuous mob chewing).
const RECOMPUTE_DEBOUNCE := 0.5

## Injected by tests; fall back to the autoloads (both load before us).
var game: Node = null
var terrain: Node = null

## null until initialize_flow_field() (main.gd, right after world gen).
var flow_field: FlowField = null

var _goal_cells: Array[Vector2i] = []
## Untouched-terrain cost snapshot (Core registered, zero player edits) —
## the Day-4 fortification score compares spawn-cell costs against this.
var _baseline_costs := PackedFloat32Array()
var _recompute_left := 0.0
var _time_left := 0.0


func _ready() -> void:
	if game == null:
		game = Game
	if terrain == null:
		terrain = Terrain
	game.wave_started.connect(_on_wave_started)
	terrain.tile_changed.connect(_on_cell_changed)
	terrain.entity_changed.connect(_on_cell_changed)


func _process(delta: float) -> void:
	# The recompute debounce runs in BUILD and WAVE phases alike.
	if _recompute_left > 0.0:
		_recompute_left -= delta
		if _recompute_left <= 0.0:
			_recompute_now()
	if _time_left <= 0.0 or game.state != game.State.WAVE_PHASE:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		game.notify_wave_cleared()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_clear_wave") and game.state == game.State.WAVE_PHASE:
		_time_left = 0.0
		game.notify_wave_cleared()

# --- Flow field (2.2) --------------------------------------------------------


## Called by main.gd once world gen completes and the Core footprint is
## registered, before any player edit — so the first compute doubles as the
## untouched-terrain baseline.
func initialize_flow_field(core: Node) -> void:
	_goal_cells = core.footprint()
	flow_field = FlowField.new()
	flow_field.terrain = terrain
	flow_field.recompute(_goal_cells)
	_baseline_costs = flow_field.snapshot_costs()
	flow_field_updated.emit()


## Untouched-terrain cost-to-Core (fortification score input, Day 4).
func baseline_cost_at(cell: Vector2i) -> float:
	if flow_field == null or _baseline_costs.is_empty():
		return INF
	if cell.x < 0 or cell.x >= flow_field.region_width:
		return INF
	if cell.y < 0 or cell.y >= flow_field.region_rows:
		return INF
	return _baseline_costs[cell.y * flow_field.region_width + cell.x]


## Wipe run state ahead of a scene reload — standing convention (plan.md).
func reset_run() -> void:
	flow_field = null
	_goal_cells = []
	_baseline_costs = PackedFloat32Array()
	_recompute_left = 0.0
	_time_left = 0.0

# --- Internals ---------------------------------------------------------------


func _on_cell_changed(pos: Vector2i) -> void:
	# Changes below the wave region (deep mining) never trigger a recompute.
	if flow_field == null or pos.y >= flow_field.region_rows:
		return
	if _recompute_left <= 0.0:
		_recompute_left = RECOMPUTE_DEBOUNCE


func _recompute_now() -> void:
	_recompute_left = 0.0
	flow_field.recompute(_goal_cells)
	flow_field_updated.emit()


func _on_wave_started(_wave_number: int) -> void:
	_time_left = STUB_WAVE_DURATION
	if _recompute_left > 0.0:
		_recompute_now() # Mobs must never spawn against a stale field.
