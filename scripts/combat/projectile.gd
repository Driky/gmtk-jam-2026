## One pooled projectile. Never instanced or freed during play — the pool
## hands out dormant ones and takes them back ([projectile_pool.gd]).
##
## Faction picks the collision mask, so one Area2D resolves both jobs: anything
## with take_damage is a target, anything else (the TileMapLayer, a wall) is a
## stop. That's why terrain needs no separate raycast.
##
## ❗️`monitorable` MUST stay true even though nothing monitors this area.
## Setting it false silently stops an Area2D from detecting StaticBody2D at all
## (CharacterBody2D still works, which is what makes it so easy to miss) —
## found by a shot flying clean through a wall while mobs took hits normally.
## The whole terrain is static tile bodies, so `monitorable = false` here would
## mean projectiles ignore the world.
##
## Hits come from POLLING get_overlapping_bodies() rather than body_entered:
## a pooled projectile is reused mid-scene, and polling under an explicit
## _active gate depends on no signal timing and needs no special case for a
## body already overlapping at launch. Same approach as swing_hitbox.gd and
## pickup.gd. The shape is disabled while dormant purely to keep idle
## projectiles out of the broadphase — correctness never rests on it.
## Owning doc: docs/systems/player-combat.md
class_name Projectile
extends Area2D

## Physics layers from project.godot: 1 world · 2 player · 3 enemies.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMIES := 4

enum Faction { PLAYER, MONSTER }

var stats: ProjectileStats = null
## Who fired it — carried so damage attributes threat to the real attacker
## (a turret tanks its own aggro) and so a shot can't hit its own shooter.
var source: Node2D = null
## Per-shot multiplier on `stats.damage`, stamped by `launch`. 1.0 for the
## player's own shots — the buff seam for turrets and (4.2) spells.
var damage_scale := 1.0

var _velocity := Vector2.ZERO
var _life_left := 0.0
var _pierce_left := 0
var _active := false
## Bodies already hit this flight, so a pierce shot can't tick the same target
## on every frame it stays inside.
var _hit_bodies: Array[Node2D] = []

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Sub-resources are shared across instances of a PackedScene, so every
	# pooled projectile would otherwise share one circle — a spell orb launch
	# would resize every bolt already in the air.
	_shape.shape = _shape.shape.duplicate()
	_deactivate()


## Masks are per faction, not per shot: a player bolt must pass through the
## player, and a spitter's (4.1) must pass through other mobs.
static func mask_for(faction: Faction) -> int:
	if faction == Faction.MONSTER:
		return LAYER_WORLD | LAYER_PLAYER
	return LAYER_WORLD | LAYER_ENEMIES


## Called by the pool. `direction` need not be normalized.
##
## `damage_scale` is per SHOT rather than per stats: a turret's
## `turret_damage` buff and 4.2's `spell_damage` scale the same shared
## `ProjectileStats` without either duplicating the Resource.
func launch(
		projectile_stats: ProjectileStats,
		origin: Vector2,
		direction: Vector2,
		faction: Faction,
		shooter: Node2D,
		scale := 1.0,
) -> void:
	stats = projectile_stats
	source = shooter
	damage_scale = scale
	var dir := direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	global_position = origin
	_velocity = dir * stats.speed
	rotation = dir.angle()
	_life_left = stats.lifetime
	_pierce_left = stats.pierce
	_hit_bodies.clear()
	(_shape.shape as CircleShape2D).radius = stats.radius
	collision_mask = mask_for(faction)
	_active = true
	visible = true
	set_physics_process(true)
	# Deferred: launch can be called from inside a physics callback (a turret
	# firing on contact), where changing a shape mid-flush is an error.
	_shape.set_deferred(&"disabled", false)
	queue_redraw()


func is_active() -> bool:
	return _active


func _physics_process(delta: float) -> void:
	_life_left -= delta
	if _life_left <= 0.0:
		# The backstop that guarantees a shot into open sky comes back.
		_deactivate()
		return
	_velocity.y += stats.gravity * delta
	global_position += _velocity * delta
	if stats.gravity != 0.0:
		rotation = _velocity.angle()
	_resolve_contacts()


## Terrain stops the shot outright; damageable bodies take a hit and spend
## pierce. Overlap order is arbitrary, so on a frame where a shot reaches a mob
## and a wall together the mob may still take the hit before the wall ends the
## flight — the right call at 5 px of travel per step, and it keeps a mob
## standing flush against a wall from being unhittable.
func _resolve_contacts() -> void:
	for body: Node2D in get_overlapping_bodies():
		if body == source or body in _hit_bodies:
			continue
		if not body.has_method(&"take_damage"):
			_deactivate() # Terrain or scenery: the shot stops here.
			return
		_hit_bodies.append(body)
		body.take_damage(stats.damage * damage_scale, source)
		if body.has_method(&"apply_knockback"):
			body.apply_knockback(_velocity, stats.knockback)
		if _pierce_left <= 0:
			_deactivate()
			return
		_pierce_left -= 1


## Back to dormant. The shape is deferred-disabled for the same reason as
## launch: this can run from inside a physics callback.
func _deactivate() -> void:
	_active = false
	visible = false
	set_physics_process(false)
	_shape.set_deferred(&"disabled", true)
	_hit_bodies.clear()
	stats = null
	source = null
	damage_scale = 1.0


func _draw() -> void:
	if stats != null:
		draw_circle(Vector2.ZERO, stats.radius, stats.color)
