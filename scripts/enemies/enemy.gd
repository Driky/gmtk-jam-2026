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

## Set by the spawner before add_child (scene has no default on purpose —
## every mob must state its type).
@export var stats: EnemyStats

## Injected by tests; fall back to the autoloads.
var terrain: Node = null
var waves: Node = null

var current_hp := 0.0

var _core: Node2D = null
var _dead := false
var _attack_left := 0.0
## Highest point of the current airborne stretch; INF = grounded. Tracking
## the apex (not the leave-floor y) charges jump-then-fall arcs correctly.
var _air_top_y := INF


func _ready() -> void:
	assert(stats != null)
	if terrain == null:
		terrain = Terrain
	if waves == null:
		waves = Waves
	current_hp = stats.max_hp
	($Visual as ColorRect).color = stats.color


func _physics_process(delta: float) -> void:
	# Gravity mirrors the player's tuning — shared consts avoid a second
	# divergent gravity value.
	if is_on_floor():
		_check_landing()
	else:
		_air_top_y = minf(_air_top_y, global_position.y)
		velocity.y = minf(velocity.y + Player.GRAVITY * delta, Player.MAX_FALL_SPEED)
	_attack_left = maxf(_attack_left - delta, 0.0)
	var pos := cell()
	var dir := _intent_dir(pos)
	var entity := _attackable_entity(pos, dir)
	if entity != null:
		velocity.x = 0.0
		_try_attack(entity)
	else:
		var decision := EnemyLocomotion.decide(terrain, pos, dir, stats)
		if decision.action == EnemyLocomotion.Action.NONE:
			# The field's move isn't usable (e.g. wall-climb route) — the
			# direct-to-Core chew fallback absorbs it.
			var direct := _direct_dir(pos)
			if direct != dir:
				decision = EnemyLocomotion.decide(terrain, pos, direct, stats)
		_actuate(decision, pos, delta)
	move_and_slide()


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


func take_damage(amount: float, _attacker: Node2D = null) -> void:
	if _dead:
		return
	current_hp = maxf(current_hp - amount, 0.0)
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
		EnemyLocomotion.Action.WALK, EnemyLocomotion.Action.FALL:
			velocity.x = signi(target.x - pos.x) * stats.speed
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
	queue_free()
