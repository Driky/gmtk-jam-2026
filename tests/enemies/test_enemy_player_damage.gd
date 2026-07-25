## Scene-runner test for the two ways a mob hurts the player (roadmap 2.5):
## the attack of opportunity inside its reach, and contact damage from the
## player's own hurtbox. Both route through Player.take_damage, so the grace
## window is what keeps them from stacking — that's the thing worth proving
## with real physics rather than doubles.
extends GdUnitTestSuite

const TILE := 16.0
const FLOOR_ROW := 10
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")
const PlayerScene := preload("res://scenes/player.tscn")


class TerrainDouble:
	extends Node

	func is_solid(pos: Vector2i) -> bool:
		return pos.y == FLOOR_ROW


	func get_entity(_pos: Vector2i) -> Node:
		return null


	func damage_tile(_pos: Vector2i, _amount: float, _tier: int, _source: int) -> bool:
		return false


class WavesDouble:
	extends Node

	var flow_field: RefCounted = null


## Player and one walker standing on a physics floor, `gap` pixels apart.
func _build_arena(gap: float) -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40.0 * TILE, TILE)
	shape.shape = rect
	body.add_child(shape)
	body.position = Vector2(20.0 * TILE, FLOOR_ROW * TILE + TILE / 2.0)
	root.add_child(body)

	var terrain := TerrainDouble.new()
	root.add_child(terrain)
	var waves := WavesDouble.new()
	root.add_child(waves)

	var player: Player = PlayerScene.instantiate()
	player.position = Vector2(10.0 * TILE, FLOOR_ROW * TILE - 12.0)
	root.add_child(player)

	var enemy: Enemy = EnemyScene.instantiate()
	enemy.stats = EnemyStats.new()
	enemy.terrain = terrain
	enemy.waves = waves
	enemy.position = player.position + Vector2(gap, 0.0)
	root.add_child(enemy)
	return { "root": root, "player": player, "enemy": enemy }


## The headline behaviour: a passive player standing next to a mob takes damage.
## Before 2.5 the player wasn't in the terrain entity dict and threat only came
## from damage dealt, so an unarmed player was invisible to the whole wave.
func test_passive_player_takes_damage_from_an_adjacent_mob() -> void:
	var arena := _build_arena(14.0)
	var runner := scene_runner(arena.root)
	var player: Player = arena.player
	var full := player.current_hp
	await runner.simulate_frames(20)
	assert_float(player.current_hp).is_less(full)


## Contact and the mob's swing both fire while touching; the grace window means
## the player loses at most one hit's worth per window, not two.
func test_touching_a_mob_never_deals_double_in_one_window() -> void:
	var arena := _build_arena(10.0)
	var runner := scene_runner(arena.root)
	var player: Player = arena.player
	var enemy: Enemy = arena.enemy
	var full := player.current_hp
	# One grace window's worth of frames, generously counted.
	await runner.simulate_frames(20)
	var lost := full - player.current_hp
	assert_float(lost).is_greater(0.0)
	assert_float(lost).is_less_equal(enemy.stats.damage)


func test_a_mob_out_of_reach_does_not_hurt_the_player() -> void:
	var arena := _build_arena(8.0 * TILE)
	var runner := scene_runner(arena.root)
	var player: Player = arena.player
	var full := player.current_hp
	await runner.simulate_frames(10)
	assert_float(player.current_hp).is_equal(full)
