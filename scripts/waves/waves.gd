## Wave composition, spawning, aggro helpers; owns the shared ground flow
## field (2.2). Owning doc: docs/systems/enemies.md
##
## The wave is pre-rolled into a spawn queue at wave start (composition table:
## data/wave_roster.gd), then trickled out from both buffer zones. Clear
## contract: game.notify_wave_cleared() once the queue is empty AND every mob
## it spawned is dead.
##
## Signal note: phase flow goes through Game (see game.gd) — wave_progress
## does not. It's this manager's own data, so the HUD listens here directly.
extends Node

## The flow field was rebuilt — the debug overlay redraws on this; mobs just
## re-read the field every frame and don't need it.
signal flow_field_updated
## Spawn queue or alive count changed; payload is remaining(). HUD readout.
signal wave_progress_changed(remaining: int)

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const TILE := TileLayout.TILE_SIZE
## Leading-edge debounce: the first change arms the timer, later changes never
## re-arm it (a trailing debounce would starve under continuous mob chewing).
const RECOMPUTE_DEBOUNCE := 0.5
## Wall clock the field solve may take per frame. A full solve costs ~57 ms in
## the browser, so spreading it at this rate lands inside RECOMPUTE_DEBOUNCE —
## the field is never more than one debounce behind, and no frame stalls.
const STEP_BUDGET_USEC := 4000

## Concurrent-mob perf ceiling. Hitting it stalls the trickle — the wave keeps
## its full budget, the queue just drains slower.
const MAX_ALIVE := 25
## Seconds between trickle spawns (Day-4 balance knob, roadmap 4.6).
const SPAWN_INTERVAL := 1.2
## Spawn band, measured from the OUTER world edge: mobs traverse the whole
## player-immutable buffer, so no approach can be booby-trapped at the source.
## Clear of the bedrock border column (x = 0) either way.
const SPAWN_MARGIN_MIN := 3
const SPAWN_MARGIN_MAX := 8
## Enemy collision box is 12x14, so feet sit 7 px below center; 1 px of slack
## against overlapping the surface tile (mirrors main.gd's player spawn).
const SPAWN_FEET_OFFSET := 8.0

## Injected by tests; fall back to the autoloads (both load before us).
var game: Node = null
var terrain: Node = null
## Spawn seams for tests: a stub scene and an explicit parent keep wave tests
## off the real physics enemy and the live scene tree.
var enemy_scene: PackedScene = ENEMY_SCENE
var spawn_parent: Node = null

## null until initialize_flow_field() (main.gd, right after world gen).
var flow_field: FlowField = null

var _goal_cells: Array[Vector2i] = []
## Untouched-terrain cost snapshot (Core registered, zero player edits) —
## the Day-4 fortification score compares spawn-cell costs against this.
var _baseline_costs := PackedFloat32Array()
var _recompute_left := 0.0
## A change landed while a solve was already in flight — rebuild on publish.
var _rebuild_pending := false
## Per-frame solve budget; tests raise it so a solve finishes in one step.
var step_budget_usec := STEP_BUDGET_USEC

## Types still to spawn this wave, in roll order.
var _queue: Array[EnemyStats] = []
## Mobs this manager spawned and hasn't seen die.
var _alive: Array[Node] = []
var _spawn_left := 0.0
## Alternates 0/1 so consecutive spawns come from opposite buffers.
var _next_side := 0
var _rng := RandomNumberGenerator.new()


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
	_advance_solve()
	if game.state == game.State.WAVE_PHASE:
		_tick_spawning(delta)


## Spend this frame's slice on an in-flight solve; announce when it publishes.
func _advance_solve() -> void:
	if flow_field == null or not flow_field.is_building():
		return
	if not flow_field.step_recompute(step_budget_usec):
		return
	flow_field_updated.emit()
	if _rebuild_pending:
		_rebuild_pending = false
		flow_field.begin_recompute(_goal_cells)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_clear_wave") and game.state == game.State.WAVE_PHASE:
		_queue.clear()
		for enemy in _alive.duplicate(): # Lethal damage, so the real death path runs.
			if is_instance_valid(enemy):
				enemy.take_damage(INF)
		_check_cleared()
	# Debug spawner: drops one walker at the cursor, outside the wave budget.
	if event.is_action_pressed(&"debug_spawn_walker", true):
		var scene := get_tree().current_scene
		var in_run: bool = (
			game.state == game.State.BUILD_PHASE or game.state == game.State.WAVE_PHASE
		)
		if in_run and scene is Node2D:
			var stats: EnemyStats = WaveRoster.ENTRIES[0].stats
			spawn_enemy(stats, (scene as Node2D).get_global_mouse_position())
	# Poke the nearest enemy as the player: verifies aggro before 2.5 melee.
	if event.is_action_pressed(&"debug_poke_enemy"):
		var player: Node2D = get_tree().get_first_node_in_group(&"player")
		if player != null:
			var nearest: Node = null
			var best := INF
			for enemy: Node2D in get_tree().get_nodes_in_group(&"enemies"):
				var dist := enemy.global_position.distance_to(player.global_position)
				if dist < best:
					best = dist
					nearest = enemy
			if nearest != null:
				nearest.take_damage(5.0, player)

# --- Wave manager (2.4) ------------------------------------------------------


## Mobs left in this wave: still to spawn plus still alive. Exact head count —
## the queue is pre-rolled, so no cost-to-count estimation is involved.
func remaining() -> int:
	return _queue.size() + alive_count()


func alive_count() -> int:
	var count := 0
	for enemy in _alive:
		if is_instance_valid(enemy):
			count += 1
	return count


func spawn_enemy(stats: EnemyStats, world_pos: Vector2) -> Node2D:
	var enemy: Node2D = enemy_scene.instantiate()
	enemy.stats = stats
	enemy.position = world_pos
	enemy.died.connect(_on_enemy_died)
	_alive.append(enemy)
	var parent: Node = spawn_parent if spawn_parent != null else get_tree().current_scene
	parent.add_child(enemy)
	return enemy


func _tick_spawning(delta: float) -> void:
	if _queue.is_empty() or alive_count() >= MAX_ALIVE:
		return
	_spawn_left -= delta
	if _spawn_left > 0.0:
		return
	_spawn_left = SPAWN_INTERVAL
	spawn_enemy(_queue.pop_front(), _spawn_position())
	wave_progress_changed.emit(remaining())


## Alternating buffer, random depth in the outer band, standing on the surface.
func _spawn_position() -> Vector2:
	var margin := _rng.randi_range(SPAWN_MARGIN_MIN, SPAWN_MARGIN_MAX)
	var x := margin if _next_side == 0 else WorldConfig.WORLD_WIDTH - 1 - margin
	_next_side = 1 - _next_side
	return Vector2((x + 0.5) * TILE, _surface_row(x) * TILE - SPAWN_FEET_OFFSET)


## First solid row in a column, skipping the row-0 bedrock border (solid across
## the whole world — scanning from 0 would park every mob on the roof). Buffers
## are flat dirt with no caves and no resources (world-gen.md), so this short
## scan can't stop on a cave roof either. Fallback 1 = drop in from the top.
func _surface_row(x: int) -> int:
	for y in range(1, FlowField.REGION_ROWS):
		if terrain.is_solid(Vector2i(x, y)):
			return y
	return 1


func _on_enemy_died(enemy: Node) -> void:
	_alive.erase(enemy)
	wave_progress_changed.emit(remaining())
	_check_cleared()


## Game.notify_wave_cleared is itself guarded against double-fire (grace beat).
func _check_cleared() -> void:
	if game.state != game.State.WAVE_PHASE:
		return
	if _queue.is_empty() and alive_count() == 0:
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
	_rebuild_pending = false
	_queue.clear()
	_alive.clear()
	_spawn_left = 0.0
	_next_side = 0

# --- Internals ---------------------------------------------------------------


func _on_cell_changed(pos: Vector2i) -> void:
	# Changes below the wave region (deep mining) never trigger a recompute.
	if flow_field == null or pos.y >= flow_field.region_rows:
		return
	if _recompute_left <= 0.0:
		_recompute_left = RECOMPUTE_DEBOUNCE


## Start an amortized solve. A change arriving mid-solve can't cancel the one
## in flight (the front buffer would be left stale indefinitely under
## continuous chewing) — it queues a rebuild for the moment this one publishes.
func _recompute_now() -> void:
	_recompute_left = 0.0
	if flow_field.is_building():
		_rebuild_pending = true
		return
	flow_field.begin_recompute(_goal_cells)


func _on_wave_started(wave_number: int) -> void:
	# Mobs must never spawn against a stale field, so this one flush is
	# synchronous. Its ~57 ms lands on the frame that also plays the wave
	# banner, where a hitch is masked — once per wave, not once per chew.
	if _recompute_left > 0.0 or flow_field != null and flow_field.is_building():
		_recompute_left = 0.0
		_rebuild_pending = false
		flow_field.recompute(_goal_cells)
		flow_field_updated.emit()
	# Seeded per (run, wave) so a wave replays identically for a seed (save.md).
	_rng.seed = game.world_seed ^ (wave_number * 0x9E3779B1)
	_queue = WaveRoster.build_queue(_rng, wave_number)
	_spawn_left = 0.0 # First mob of the wave spawns on the next tick.
	wave_progress_changed.emit(remaining())
