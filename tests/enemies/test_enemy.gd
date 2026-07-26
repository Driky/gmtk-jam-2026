## Unit tests for the Enemy node's non-physics logic (fall damage, death) —
## the node never enters the tree, so no autoloads and no physics frames.
extends GdUnitTestSuite

const EnemyScript := preload("res://scripts/enemies/enemy.gd")
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")
const SpawnerScript := preload("res://scripts/items/pickup_spawner.gd")


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


func test_fall_steers_over_the_target_cell() -> void:
	# Body straddling the edge of a hole dug under its center: FALL must
	# push toward the hole's center-x, not zero out (deadlock otherwise).
	var enemy := _make_enemy()
	enemy.global_position = Vector2(71.0 * 16.0 + 0.7, 22.5 * 16.0)
	var decision := {
		"action": EnemyLocomotion.Action.FALL,
		"target": Vector2i(71, 23),
		"jump_tiles": 0,
	}
	enemy._actuate(decision, Vector2i(71, 22), 1.0 / 60.0)
	assert_float(enemy.velocity.x).is_greater(0.0)


func test_stuck_walking_arms_direct_mode() -> void:
	# WALK frames with no displacement -> direct-to-Core override arms.
	var enemy := _make_enemy()
	enemy.global_position = Vector2(100.0, 100.0)
	for i in 95: # 95 frames at 1/60 s > STUCK_WINDOW (1.5 s).
		enemy._update_stuck(EnemyLocomotion.Action.WALK, 1.0 / 60.0)
	assert_float(enemy._direct_left).is_greater(0.0)


func test_chewing_never_reads_as_stuck() -> void:
	var enemy := _make_enemy()
	enemy.global_position = Vector2(100.0, 100.0)
	for i in 200:
		enemy._update_stuck(EnemyLocomotion.Action.CHEW, 1.0 / 60.0)
	assert_float(enemy._direct_left).is_equal(0.0)


func test_movement_resets_stuck_timer() -> void:
	var enemy := _make_enemy()
	enemy.global_position = Vector2(100.0, 100.0)
	for i in 60:
		enemy._update_stuck(EnemyLocomotion.Action.WALK, 1.0 / 60.0)
		enemy.global_position.x += 1.0 # Real progress every frame.
	assert_float(enemy._direct_left).is_equal(0.0)

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

# --- Loot drops & kill XP (2.6) ----------------------------------------------


## Uses the scene (not a bare script) because a tree-resident Enemy reads its
## own Visual child in _ready. Stats are a FRESH resource, never walker.tres —
## mutating the shared preload would leak into every other suite.
func _make_dropping_enemy(drop_id: String, drop_count := 1) -> Enemy:
	var enemy: Enemy = auto_free(EnemyScene.instantiate())
	var stats := EnemyStats.new()
	stats.drop_id = drop_id
	stats.drop_count = drop_count
	enemy.stats = stats
	add_child(enemy)
	return enemy


func test_death_drops_loot_as_a_world_pickup() -> void:
	var spawner: Node2D = auto_free(SpawnerScript.new())
	add_child(spawner)
	var enemy := _make_dropping_enemy("coal", 2)
	enemy.global_position = Vector2(64.0, 32.0)
	enemy.take_damage(999.0)
	assert_int(spawner.get_child_count()).is_equal(1)
	var pickup: Node2D = spawner.get_child(0)
	assert_str(pickup.item_id).is_equal("coal")
	assert_int(pickup.count).is_equal(2)
	assert_vector(pickup.position).is_equal(Vector2(64.0, 32.0))
	# Ordinary loot: mob drops feed the looting channel like any mined drop.
	assert_bool(pickup.grants_xp).is_true()


func test_a_mob_with_no_drop_id_leaves_nothing() -> void:
	var spawner: Node2D = auto_free(SpawnerScript.new())
	add_child(spawner)
	_make_dropping_enemy("").take_damage(999.0)
	assert_int(spawner.get_child_count()).is_equal(0)


## The suites above kill enemies that were never added to the tree; that path
## must stay drop-free rather than dereferencing a null SceneTree.
func test_dying_outside_the_tree_is_safe() -> void:
	var enemy := _make_enemy()
	enemy.stats.drop_id = "coal"
	enemy.take_damage(999.0)
	assert_bool(enemy._dead).is_true()


func test_death_grants_kill_xp() -> void:
	var enemy := _make_enemy()
	enemy.stats.xp = 7.0
	var before: float = Progression.xp_by_source.get("kills", 0.0)
	enemy.take_damage(999.0)
	var granted: float = Progression.xp_by_source.get("kills", 0.0) - before
	assert_float(granted).is_equal_approx(7.0, 0.001)

# --- Knockback (2.5) ---------------------------------------------------------


func test_knockback_pushes_away_and_lifts() -> void:
	var enemy := _make_enemy()
	enemy.apply_knockback(Vector2(3.0, 0.0), 100.0) # Raw offset, not normalized.
	assert_float(enemy.velocity.x).is_equal_approx(100.0, 0.001)
	assert_float(enemy.velocity.y).is_equal(-Enemy.KNOCKBACK_LIFT)
	assert_float(enemy._knockback_left).is_equal(Enemy.KNOCKBACK_TIME)


## A zero direction (attacker exactly on top of the mob) must not produce a NaN
## velocity that corrupts the body forever.
func test_knockback_survives_a_zero_direction() -> void:
	var enemy := _make_enemy()
	enemy.apply_knockback(Vector2.ZERO, 100.0)
	assert_bool(is_nan(enemy.velocity.x)).is_false()
	assert_float(absf(enemy.velocity.x)).is_equal_approx(100.0, 0.001)


func test_zero_strength_is_not_a_knockback() -> void:
	var enemy := _make_enemy()
	enemy.apply_knockback(Vector2.RIGHT, 0.0)
	assert_float(enemy._knockback_left).is_equal(0.0)


func test_dead_mobs_are_not_shoved() -> void:
	var enemy := _make_enemy()
	enemy.take_damage(999.0)
	enemy.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(enemy._knockback_left).is_equal(0.0)

# --- Attackable entities (3.1) -----------------------------------------------

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const TorchScene := preload("res://scenes/torch.tscn")
const CoreScene := preload("res://scenes/core.tscn")

const MOB_CELL := Vector2i(100, 100)


func _enemy_with_terrain() -> Enemy:
	var enemy := _make_enemy()
	enemy.terrain = auto_free(TerrainScript.new())
	add_child(enemy.terrain)
	return enemy


func _torch_at(terrain: Node, cell: Vector2i) -> Torch:
	var torch: Torch = auto_free(TorchScene.instantiate())
	torch.setup(cell)
	add_child(torch)
	torch.register(terrain)
	return torch


## ❗️A torch in the mob's own cell is one it has already walked through. Chewing
## it would also take the early return in _push_core, which skips _update_stuck
## and starves the watchdog a mob needs to escape a cycling route.
func test_a_deployable_in_the_mobs_own_cell_is_not_attacked() -> void:
	var enemy := _enemy_with_terrain()
	_torch_at(enemy.terrain, MOB_CELL)
	assert_object(enemy._attackable_entity(MOB_CELL, Vector2i.RIGHT)).is_null()


## Chewing what is in front of you is the intended behaviour — that is what
## makes a lit tunnel an accidental mob-slowing corridor.
func test_a_deployable_in_front_of_the_mob_is_attacked() -> void:
	var enemy := _enemy_with_terrain()
	var torch := _torch_at(enemy.terrain, MOB_CELL + Vector2i.RIGHT)
	assert_object(enemy._attackable_entity(MOB_CELL, Vector2i.RIGHT)).is_same(torch)


## The Core is 3×2, so a mob can stand INSIDE it — that is why the own-cell
## probe exists at all, and the skip must not take it with it. It is a plain
## Node2D, deliberately not a Deployable.
func test_the_core_in_the_mobs_own_cell_is_still_attacked() -> void:
	var enemy := _enemy_with_terrain()
	var core: Node2D = auto_free(CoreScene.instantiate())
	core.setup(MOB_CELL.x, MOB_CELL.y + 1)
	add_child(core)
	assert_bool(core.register_footprint(enemy.terrain)).is_true()
	assert_object(enemy._attackable_entity(MOB_CELL, Vector2i.RIGHT)).is_same(core)


## Ground lost to a shove must not read as "field guidance is cycling" — the
## watchdog would otherwise flip mobs into direct-dig mode every time you hit
## one with a high-knockback tool.
func test_knockback_clears_the_stuck_watchdog() -> void:
	var enemy := _make_enemy()
	enemy.global_position = Vector2(100.0, 100.0)
	for i in 60:
		enemy._update_stuck(EnemyLocomotion.Action.WALK, 1.0 / 60.0)
	enemy.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(enemy._stuck_timer).is_equal(0.0)
