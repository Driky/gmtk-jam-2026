## Enemy base: one CharacterBody2D shell for every ground mob — identity and
## capabilities come from the injected EnemyStats resource. Decisions live in
## EnemyLocomotion (pure); this node only actuates them with move_and_slide().
## Owning doc: docs/systems/enemies.md
class_name Enemy
extends CharacterBody2D

signal died(enemy: Enemy)

const TILE := TileLayout.TILE_SIZE

## Set by the spawner before add_child (scene has no default on purpose —
## every mob must state its type).
@export var stats: EnemyStats

## Injected by tests; fall back to the autoloads.
var terrain: Node = null
var waves: Node = null

var current_hp := 0.0

var _core: Node2D = null
var _dead := false


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
	if not is_on_floor():
		velocity.y = minf(velocity.y + Player.GRAVITY * delta, Player.MAX_FALL_SPEED)
	var pos := cell()
	var decision := EnemyLocomotion.decide(terrain, pos, _intent_dir(pos), stats)
	_actuate(decision, pos)
	move_and_slide()


func cell() -> Vector2i:
	return Vector2i((global_position / TILE).floor())


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


func _actuate(decision: Dictionary, pos: Vector2i) -> void:
	match decision.action:
		EnemyLocomotion.Action.WALK, EnemyLocomotion.Action.FALL:
			var target: Vector2i = decision.target
			velocity.x = signi(target.x - pos.x) * stats.speed
		_:
			velocity.x = 0.0


func _die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	queue_free()
