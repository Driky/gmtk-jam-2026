## Enemy base: one CharacterBody2D shell for every ground mob — identity and
## capabilities come from the injected EnemyStats resource. Decisions live in
## EnemyLocomotion (pure); this node only actuates them with move_and_slide().
## Owning doc: docs/systems/enemies.md
class_name Enemy
extends CharacterBody2D

signal died(enemy: Enemy)

const TILE := TileLayout.TILE_SIZE

## Effective tool tier for chewing: everything but bedrock (99) breaks, the
## enforcement behind "digging is correctness" — a tier-gated ore in the path
## must never soft-lock a mob.
const MONSTER_TOOL_TIER := 98

## HP lost per tile fallen beyond max_safe_fall — keeps drop-trap designs
## viable (walker: a 4-tile drop stings, ~8 tiles is lethal).
const FALL_DAMAGE_PER_TILE := 6.0

## Aggro tuning: one melee hit (2.5 lands ~10+) instantly aggroes; an ignored
## attacker is forgotten after a few seconds and the mob resumes the Core.
const THREAT_DECAY_PER_S := 4.0
const THREAT_THRESHOLD := 8.0
## Center-to-center swing distance against an aggro target (1.5 tiles).
const ATTACK_RANGE_PX := 24.0

## Stuck watchdog: the shared field assumes reference capabilities, so its
## guidance can cycle for a mob that can't use a route (e.g. a walker sent
## toward a climb chimney ping-pongs at the cycle boundary). No net movement
## for STUCK_WINDOW while trying to move -> commit to the direct-to-Core dig
## line for DIRECT_MODE_TIME, which always terminates by chewing.
const STUCK_WINDOW := 1.5
const STUCK_EPSILON_PX := 8.0
const DIRECT_MODE_TIME := 6.0

## Set by the spawner before add_child (scene has no default on purpose —
## every mob must state its type).
@export var stats: EnemyStats

## Injected by tests; fall back to the autoloads.
var terrain: Node = null
var waves: Node = null

var current_hp := 0.0

var _threat := ThreatTable.new()
var _core: Node2D = null
var _dead := false
var _attack_left := 0.0
## Highest point of the current airborne stretch; INF = grounded. Tracking
## the apex (not the leave-floor y) charges jump-then-fall arcs correctly.
var _air_top_y := INF
var _stuck_timer := 0.0
var _stuck_anchor := Vector2.INF
var _direct_left := 0.0


func _ready() -> void:
	assert(stats != null)
	if terrain == null:
		terrain = Terrain
	if waves == null:
		waves = Waves
	current_hp = stats.max_hp
	($Visual as ColorRect).color = stats.color


func _physics_process(delta: float) -> void:
	Perf.begin(&"mob")
	_step(delta)
	Perf.end()


func _step(delta: float) -> void:
	# Gravity mirrors the player's tuning — shared consts avoid a second
	# divergent gravity value.
	if is_on_floor():
		_check_landing()
	else:
		_air_top_y = minf(_air_top_y, global_position.y)
		velocity.y = minf(velocity.y + Player.GRAVITY * delta, Player.MAX_FALL_SPEED)
	_attack_left = maxf(_attack_left - delta, 0.0)
	_threat.decay(delta, THREAT_DECAY_PER_S)
	var pos := cell()
	var aggro := _threat.top_target(THREAT_THRESHOLD)
	if aggro != null:
		_pursue_aggro(aggro, pos, delta)
	else:
		_push_core(pos, delta)
	move_and_slide()


## Default behavior: follow the flow field toward the Core, melee entities in
## the way, chew-fallback anything the field can't route.
func _push_core(pos: Vector2i, delta: float) -> void:
	_direct_left = maxf(_direct_left - delta, 0.0)
	var dir := _direct_dir(pos) if _direct_left > 0.0 else _intent_dir(pos)
	var entity := _attackable_entity(pos, dir)
	if entity != null:
		velocity.x = 0.0
		_try_attack(entity)
		return
	var decision := EnemyLocomotion.decide(terrain, pos, dir, stats)
	if decision.action == EnemyLocomotion.Action.NONE:
		# The field's move isn't usable (e.g. wall-climb route) — the
		# direct-to-Core chew fallback absorbs it.
		var direct := _direct_dir(pos)
		if direct != dir:
			decision = EnemyLocomotion.decide(terrain, pos, direct, stats)
	_update_stuck(decision.action, delta)
	_actuate(decision, pos, delta)


## Movement actions that produce no displacement mean field guidance is
## cycling — arm the direct-mode override. Chewing/attacking is progress.
func _update_stuck(action: EnemyLocomotion.Action, delta: float) -> void:
	var moving := (
		action == EnemyLocomotion.Action.WALK
		or action == EnemyLocomotion.Action.FALL
		or action == EnemyLocomotion.Action.JUMP
	)
	if not moving or global_position.distance_to(_stuck_anchor) > STUCK_EPSILON_PX:
		_stuck_anchor = global_position
		_stuck_timer = 0.0
		return
	_stuck_timer += delta
	if _stuck_timer >= STUCK_WINDOW:
		_direct_left = DIRECT_MODE_TIME
		_stuck_timer = 0.0


## Aggro override: direct local chase toward the attacker (no flow field),
## chewing through blockers; swing when in range. take_damage is guarded —
## the Player grows one in 2.5 and melee starts landing then.
func _pursue_aggro(target: Node2D, pos: Vector2i, delta: float) -> void:
	if global_position.distance_to(target.global_position) <= ATTACK_RANGE_PX:
		velocity.x = 0.0
		if target.has_method(&"take_damage"):
			_try_attack(target)
		return
	var d := Vector2i((target.global_position / TILE).floor()) - pos
	var dir := Vector2i(signi(d.x), 0) if d.x != 0 else Vector2i(0, signi(d.y))
	_actuate(EnemyLocomotion.decide(terrain, pos, dir, stats), pos, delta)


func cell() -> Vector2i:
	return Vector2i((global_position / TILE).floor())


## Fall damage beyond max_safe_fall, applied on touching down.
func _check_landing() -> void:
	if _air_top_y == INF:
		return
	var tiles := (global_position.y - _air_top_y) / TILE
	_air_top_y = INF
	if tiles > stats.max_safe_fall:
		take_damage((tiles - stats.max_safe_fall) * FALL_DAMAGE_PER_TILE)


func take_damage(amount: float, attacker: Node2D = null) -> void:
	if _dead:
		return
	current_hp = maxf(current_hp - amount, 0.0)
	if attacker != null:
		_threat.add_threat(attacker, amount)
	if current_hp <= 0.0:
		_die()


## Flow-field gradient, or the direct-to-Core fallback when the field has no
## guidance (consumer contract in flow_field.gd).
func _intent_dir(pos: Vector2i) -> Vector2i:
	if waves != null and waves.flow_field != null:
		var dir: Vector2i = waves.flow_field.get_flow_dir(pos)
		if dir != Vector2i.ZERO:
			return dir
	return _direct_dir(pos)


## Direct mode: horizontal first, vertical when column-aligned.
func _direct_dir(pos: Vector2i) -> Vector2i:
	if _core == null or not is_instance_valid(_core):
		_core = get_tree().get_first_node_in_group(&"core")
		if _core == null:
			return Vector2i.ZERO
	var d: Vector2i = _core.base_cell() - pos
	if d.x != 0:
		return Vector2i(signi(d.x), 0)
	if d.y != 0:
		return Vector2i(0, signi(d.y))
	return Vector2i.ZERO


func _actuate(decision: Dictionary, pos: Vector2i, delta: float) -> void:
	var target: Vector2i = decision.target
	match decision.action:
		EnemyLocomotion.Action.WALK:
			velocity.x = signi(target.x - pos.x) * stats.speed
		EnemyLocomotion.Action.FALL:
			# Steer over the target cell's center: a straight-down fall with
			# zero x-velocity deadlocks when the body still straddles a
			# neighbor tile (dug a hole under its center, feet on the edge).
			var center_x := (target.x + 0.5) * TILE
			var dx := center_x - global_position.x
			velocity.x = 0.0 if absf(dx) < 1.0 else signf(dx) * stats.speed
		EnemyLocomotion.Action.JUMP:
			velocity.x = signi(target.x - pos.x) * stats.speed
			if is_on_floor():
				var tiles: int = decision.jump_tiles
				# +0.6 tiles of apex slack so the body clears the ledge lip.
				velocity.y = -sqrt(2.0 * Player.GRAVITY * (tiles + 0.6) * TILE)
		EnemyLocomotion.Action.CHEW:
			# Standing still keeps the cell (and thus the target) stable, so
			# the 2 s damage-abandon sweep never claws back mob progress.
			velocity.x = 0.0
			terrain.damage_tile(
				target,
				stats.dig_power * delta,
				MONSTER_TOOL_TIER,
				Terrain.Source.MONSTER,
			)
		_:
			velocity.x = 0.0


## An adjacent entity that can be hit (the Core today, deployables Day 3):
## entity cells are air, so blockers registered there take melee hits instead
## of the chew pipeline.
func _attackable_entity(pos: Vector2i, dir: Vector2i) -> Node:
	for probe in [pos, pos + dir]:
		var entity: Node = terrain.get_entity(probe)
		if entity != null and entity.has_method(&"take_damage"):
			return entity
	return null


func _try_attack(entity: Node) -> void:
	if _attack_left > 0.0:
		return
	_attack_left = stats.attack_cooldown
	entity.take_damage(stats.damage)


func _die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	# XP seam — self-wires when Progression.grant_xp lands (roadmap 2.6)
	# same pattern as terrain.gd's mining XP.
	if Progression.has_method(&"grant_xp"):
		Progression.call(&"grant_xp", "kills", stats.xp)
	queue_free()
