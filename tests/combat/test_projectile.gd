## Scene-runner tests for the shared projectile system (roadmap 2.5) — the one
## implementation ranged weapons, spells (4.2) and turrets (3.5) all use.
## Collision resolution needs real physics frames, so this flies shots at
## doubles on the enemies and world layers.
extends GdUnitTestSuite

const PoolScript := preload("res://scripts/combat/projectile_pool.gd")
const ProjectileStatsScript := preload("res://scripts/combat/projectile_stats.gd")


## A mob: damageable, on the enemies layer, recording what it was hit with.
class TargetDouble:
	extends CharacterBody2D

	var hits: Array[float] = []
	var shoves: Array[float] = []


	func _init() -> void:
		collision_layer = Projectile.LAYER_ENEMIES
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(12, 14)
		shape.shape = rect
		add_child(shape)


	func take_damage(amount: float, _attacker: Node2D = null) -> void:
		hits.append(amount)


	func apply_knockback(_direction: Vector2, strength: float) -> void:
		shoves.append(strength)


## A wall: on the world layer, no take_damage — must stop a shot.
class WallDouble:
	extends StaticBody2D

	func _init() -> void:
		collision_layer = Projectile.LAYER_WORLD
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(16, 64)
		shape.shape = rect
		add_child(shape)


func _make_stats() -> ProjectileStats:
	var stats: ProjectileStats = ProjectileStatsScript.new()
	stats.speed = 320.0
	stats.damage = 6.0
	stats.knockback = 60.0
	stats.gravity = 0.0
	stats.lifetime = 1.5
	stats.pierce = 0
	stats.radius = 3.0
	return stats


## Pool at the origin; `bodies` are added around it. Returns the arena parts.
func _build_arena(bodies: Array[Node2D]) -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	var pool: ProjectilePool = PoolScript.new()
	root.add_child(pool)
	for body in bodies:
		root.add_child(body)
	return { "root": root, "pool": pool }

# --- Faction masks (pure) ----------------------------------------------------


## A player bolt must pass through the player, a mob's through other mobs —
## otherwise a turret line shoots itself and a spitter (4.1) kills its escort.
func test_faction_selects_the_mask() -> void:
	var player_mask := Projectile.mask_for(Projectile.Faction.PLAYER)
	assert_bool(player_mask & Projectile.LAYER_ENEMIES != 0).is_true()
	assert_bool(player_mask & Projectile.LAYER_PLAYER != 0).is_false()
	var monster_mask := Projectile.mask_for(Projectile.Faction.MONSTER)
	assert_bool(monster_mask & Projectile.LAYER_PLAYER != 0).is_true()
	assert_bool(monster_mask & Projectile.LAYER_ENEMIES != 0).is_false()
	# Both stop on terrain.
	assert_bool(player_mask & Projectile.LAYER_WORLD != 0).is_true()
	assert_bool(monster_mask & Projectile.LAYER_WORLD != 0).is_true()

# --- Flight & hits -----------------------------------------------------------


func test_shot_damages_and_shoves_a_target() -> void:
	var target := TargetDouble.new()
	target.position = Vector2(60.0, 0.0)
	var arena := _build_arena([target])
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	(arena.pool as ProjectilePool).fire_from_pool(
		_make_stats(),
		Vector2.ZERO,
		Vector2.RIGHT,
		Projectile.Faction.PLAYER,
		null,
	)
	await runner.simulate_frames(30)
	assert_array(target.hits).contains_exactly([6.0])
	assert_array(target.shoves).contains_exactly([60.0])


## The per-shot buff seam (3.5a): a turret's `turret_damage` and 4.2's
## `spell_damage` scale a SHARED `ProjectileStats` rather than each duplicating
## the Resource, so the multiplier has to ride the shot, not the stats.
func test_damage_scale_multiplies_the_hit_without_touching_the_stats() -> void:
	var target := TargetDouble.new()
	target.position = Vector2(60.0, 0.0)
	var arena := _build_arena([target])
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	var stats := _make_stats()
	(arena.pool as ProjectilePool).fire_from_pool(
		stats,
		Vector2.ZERO,
		Vector2.RIGHT,
		Projectile.Faction.PLAYER,
		null,
		1.5,
	)
	await runner.simulate_frames(30)
	assert_array(target.hits).contains_exactly([9.0])
	# The shared Resource is untouched — a scaled shot must not re-tune the ammo
	# for everything else firing it.
	assert_float(stats.damage).is_equal(6.0)


## No pierce means the shot is spent on the first body — it must not carry on
## and clip the mob behind.
func test_no_pierce_stops_on_the_first_target() -> void:
	var first := TargetDouble.new()
	first.position = Vector2(40.0, 0.0)
	var second := TargetDouble.new()
	second.position = Vector2(90.0, 0.0)
	var arena := _build_arena([first, second])
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	(arena.pool as ProjectilePool).fire_from_pool(
		_make_stats(),
		Vector2.ZERO,
		Vector2.RIGHT,
		Projectile.Faction.PLAYER,
		null,
	)
	await runner.simulate_frames(40)
	assert_int(first.hits.size()).is_equal(1)
	assert_array(second.hits).is_empty()


func test_pierce_carries_through_to_the_next_target() -> void:
	var first := TargetDouble.new()
	first.position = Vector2(40.0, 0.0)
	var second := TargetDouble.new()
	second.position = Vector2(90.0, 0.0)
	var arena := _build_arena([first, second])
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	var stats := _make_stats()
	stats.pierce = 1
	(arena.pool as ProjectilePool).fire_from_pool(
		stats,
		Vector2.ZERO,
		Vector2.RIGHT,
		Projectile.Faction.PLAYER,
		null,
	)
	await runner.simulate_frames(40)
	assert_int(first.hits.size()).is_equal(1)
	assert_int(second.hits.size()).is_equal(1)


## Terrain has no take_damage, so "anything not damageable is a stop" is what
## keeps shots from flying through walls without a separate raycast.
func test_shot_stops_on_terrain() -> void:
	var wall := WallDouble.new()
	wall.position = Vector2(40.0, 0.0)
	var behind := TargetDouble.new()
	behind.position = Vector2(90.0, 0.0)
	var arena := _build_arena([wall, behind])
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	(arena.pool as ProjectilePool).fire_from_pool(
		_make_stats(),
		Vector2.ZERO,
		Vector2.RIGHT,
		Projectile.Faction.PLAYER,
		null,
	)
	await runner.simulate_frames(40)
	assert_array(behind.hits).is_empty()
	assert_int((arena.pool as ProjectilePool).active_count()).is_equal(0)


## A shot must never hit whoever fired it — the muzzle sits inside the
## shooter's own body for turrets with a short barrel.
func test_shot_passes_through_its_own_shooter() -> void:
	var shooter := TargetDouble.new()
	shooter.position = Vector2(20.0, 0.0)
	var arena := _build_arena([shooter])
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	(arena.pool as ProjectilePool).fire_from_pool(
		_make_stats(),
		Vector2.ZERO,
		Vector2.RIGHT,
		Projectile.Faction.PLAYER,
		shooter,
	)
	await runner.simulate_frames(30)
	assert_array(shooter.hits).is_empty()

# --- Pooling -----------------------------------------------------------------


## The lifetime backstop: a shot into open sky must return to the pool, or the
## pool bleeds slots until every shot silently steals a live one.
func test_shot_into_empty_space_returns_to_the_pool() -> void:
	var arena := _build_arena([])
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	var stats := _make_stats()
	stats.lifetime = 0.1
	var pool: ProjectilePool = arena.pool
	pool.fire_from_pool(stats, Vector2.ZERO, Vector2.RIGHT, Projectile.Faction.PLAYER, null)
	assert_int(pool.active_count()).is_equal(1)
	await runner.simulate_frames(40)
	assert_int(pool.active_count()).is_equal(0)


## Nothing is instantiated while shots FLY: firing more than the pool holds
## recycles rather than allocating. Capacity only ever changes on a `reserve`,
## which happens at placement time and never mid-flight (test_projectile_pool).
func test_pool_never_grows_past_its_size() -> void:
	var arena := _build_arena([])
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	var pool: ProjectilePool = arena.pool
	var child_count := pool.get_child_count()
	for i in pool.pool_size() + 10:
		pool.fire_from_pool(
			_make_stats(),
			Vector2.ZERO,
			Vector2.RIGHT,
			Projectile.Faction.PLAYER,
			null,
		)
	assert_int(pool.get_child_count()).is_equal(child_count)
	assert_int(pool.active_count()).is_equal(pool.pool_size())


## Turrets (3.5) reach the pool statically, with no node path.
func test_static_fire_routes_to_the_registered_pool() -> void:
	var arena := _build_arena([])
	var runner := scene_runner(arena.root)
	await runner.simulate_frames(2)
	var shot := ProjectilePool.fire(
		_make_stats(),
		Vector2.ZERO,
		Vector2.RIGHT,
		Projectile.Faction.PLAYER,
		null,
	)
	assert_object(shot).is_not_null()
	assert_int((arena.pool as ProjectilePool).active_count()).is_equal(1)


## Called with no pool in the tree (tests, headless tools) it must no-op, not
## crash — the static ref is scene-scoped and legitimately absent sometimes.
func test_static_fire_without_a_pool_is_a_no_op() -> void:
	ProjectilePool.instance = null
	assert_object(
		ProjectilePool.fire(
			_make_stats(),
			Vector2.ZERO,
			Vector2.RIGHT,
			Projectile.Faction.PLAYER,
			null,
		),
	).is_null()
