## Scene-runner tests for the swing arc (roadmap 2.5). The overlap half needs
## real physics frames, so this drives the hitbox against a body on the enemies
## layer rather than asserting on geometry.
extends GdUnitTestSuite

const HitboxScene := preload("res://scenes/combat/swing_hitbox_default.tscn")
const ENEMY_LAYER := 4 # Physics layer 3, what the arc's mask selects.


## Minimal stand-in for a mob: a body on the enemies layer, nothing else.
class TargetDouble:
	extends CharacterBody2D

	func _init() -> void:
		collision_layer = ENEMY_LAYER
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(12, 14)
		shape.shape = rect
		add_child(shape)


## Hitbox at the origin plus a target `offset` away. Returns the pieces the
## tests assert on, including a running tally of target_hit emissions.
func _build_arena(offset: Vector2) -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	var hitbox: SwingHitbox = HitboxScene.instantiate()
	root.add_child(hitbox)
	var target := TargetDouble.new()
	target.position = offset
	root.add_child(target)
	var hits: Array[Node2D] = []
	hitbox.target_hit.connect(func(body: Node2D) -> void: hits.append(body))
	return { "root": root, "hitbox": hitbox, "target": target, "hits": hits }


func test_swing_hits_a_target_in_the_aim_direction() -> void:
	var arena := _build_arena(Vector2(20.0, 0.0))
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	(arena.hitbox as SwingHitbox).activate(Vector2.RIGHT, 90.0, 0.15)
	await runner.simulate_frames(10)
	assert_array(arena.hits).contains([arena.target])


func test_swing_misses_a_target_behind_the_swinger() -> void:
	var arena := _build_arena(Vector2(-40.0, 0.0))
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	(arena.hitbox as SwingHitbox).activate(Vector2.RIGHT, 90.0, 0.15)
	await runner.simulate_frames(10)
	assert_array(arena.hits).is_empty()


## The whole reason the hitbox tracks hits per swing: a 0.15 s active window is
## ~9 physics frames, and a per-frame poll would otherwise deal 9× damage.
func test_target_is_hit_once_per_swing() -> void:
	var arena := _build_arena(Vector2(20.0, 0.0))
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	(arena.hitbox as SwingHitbox).activate(Vector2.RIGHT, 90.0, 0.15)
	await runner.simulate_frames(20)
	assert_int((arena.hits as Array).size()).is_equal(1)


## A mob already overlapping when the arc switches on never emits body_entered,
## so the first frame has to be polled — otherwise standing on top of something
## makes you unable to hit it.
func test_target_already_inside_the_arc_is_hit() -> void:
	var arena := _build_arena(Vector2(18.0, 0.0))
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(5) # Settle with the target already overlapping.
	(arena.hitbox as SwingHitbox).activate(Vector2.RIGHT, 90.0, 0.15)
	await runner.simulate_frames(5)
	assert_array(arena.hits).contains([arena.target])


func test_a_second_swing_can_hit_the_same_target_again() -> void:
	var arena := _build_arena(Vector2(20.0, 0.0))
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	(arena.hitbox as SwingHitbox).activate(Vector2.RIGHT, 90.0, 0.15)
	await runner.simulate_frames(30) # Window elapsed, hitbox disabled.
	(arena.hitbox as SwingHitbox).activate(Vector2.RIGHT, 90.0, 0.15)
	await runner.simulate_frames(20)
	assert_int((arena.hits as Array).size()).is_equal(2)


## The arc must not stay live after its window: a hitbox left monitoring would
## damage every mob that walks past for the rest of the run.
func test_arc_disables_itself_after_the_window() -> void:
	var arena := _build_arena(Vector2(20.0, 0.0))
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	(arena.hitbox as SwingHitbox).activate(Vector2.RIGHT, 90.0, 0.15)
	await runner.simulate_frames(40)
	assert_bool((arena.hitbox as SwingHitbox).is_swinging()).is_false()
