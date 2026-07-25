## Unit tests for the Enemy node's non-physics logic (fall damage, death) —
## the node never enters the tree, so no autoloads and no physics frames.
extends GdUnitTestSuite

const EnemyScript := preload("res://scripts/enemies/enemy.gd")


func _make_enemy() -> Enemy:
	var enemy: Enemy = auto_free(EnemyScript.new())
	enemy.stats = EnemyStats.new()
	enemy.current_hp = enemy.stats.max_hp
	return enemy

# --- Fall damage -------------------------------------------------------------


func test_safe_fall_deals_no_damage() -> void:
	var enemy := _make_enemy()
	enemy.global_position = Vector2(0, 3 * 16.0)
	enemy._air_top_y = 0.0 # Fell exactly max_safe_fall tiles.
	enemy._check_landing()
	assert_float(enemy.current_hp).is_equal(enemy.stats.max_hp)


func test_fall_damage_scales_beyond_max_safe_fall() -> void:
	var enemy := _make_enemy()
	enemy.global_position = Vector2(0, 8 * 16.0)
	enemy._air_top_y = 0.0 # 8-tile fall, 5 beyond the safe 3.
	enemy._check_landing()
	var expected := enemy.stats.max_hp - 5.0 * Enemy.FALL_DAMAGE_PER_TILE
	assert_float(enemy.current_hp).is_equal_approx(expected, 0.001)


func test_landing_resets_apex() -> void:
	var enemy := _make_enemy()
	enemy.global_position = Vector2(0, 8 * 16.0)
	enemy._air_top_y = 0.0
	enemy._check_landing()
	var hp := enemy.current_hp
	enemy._check_landing() # Grounded: must be a no-op.
	assert_float(enemy.current_hp).is_equal(hp)

# --- Damage / death ----------------------------------------------------------


func test_take_damage_reduces_hp() -> void:
	var enemy := _make_enemy()
	enemy.take_damage(10.0)
	assert_float(enemy.current_hp).is_equal(enemy.stats.max_hp - 10.0)


func test_damage_with_attacker_builds_aggro() -> void:
	var enemy := _make_enemy()
	var attacker: Node2D = auto_free(Node2D.new())
	enemy.take_damage(10.0, attacker)
	assert_that(enemy._threat.top_target(Enemy.THREAT_THRESHOLD)).is_same(attacker)


func test_fall_damage_builds_no_aggro() -> void:
	var enemy := _make_enemy()
	enemy.global_position = Vector2(0, 8 * 16.0)
	enemy._air_top_y = 0.0
	enemy._check_landing()
	assert_that(enemy._threat.top_target(0.1)).is_null()


func test_lethal_damage_emits_died_once() -> void:
	var enemy := _make_enemy()
	var deaths: Array[Enemy] = []
	enemy.died.connect(func(e: Enemy) -> void: deaths.append(e))
	enemy.take_damage(999.0)
	enemy.take_damage(999.0) # Already dead: must not re-emit.
	assert_int(deaths.size()).is_equal(1)
	assert_that(deaths[0]).is_same(enemy)
