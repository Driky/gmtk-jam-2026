## Unit tests for the pool's SIZING (roadmap 3.5a) — the 🔴 blocker that gates
## turrets. Flight and collision live in `test_projectile.gd`; this suite never
## needs a physics frame, because `launch` marks a slot active synchronously and
## nothing here waits for a shot to expire.
##
## The bug these exist to keep dead: a fixed 32-slot pool steals shots that are
## still in flight once the spawner count pushes past it — bolts vanishing
## mid-air, and worse the more turrets you build
## ([player-combat.md](../../docs/systems/player-combat.md) §Projectiles).
extends GdUnitTestSuite

const PoolScript := preload("res://scripts/combat/projectile_pool.gd")
const ProjectileStatsScript := preload("res://scripts/combat/projectile_stats.gd")

## One turret's worth of headroom, near enough: a 1 s fire period against a
## 1.5 s flight is 2 shots in the air, and the real turret adds its own slack.
const RESERVATION := 20


func _make_stats() -> ProjectileStats:
	var stats: ProjectileStats = ProjectileStatsScript.new()
	stats.speed = 320.0
	stats.damage = 6.0
	stats.lifetime = 1.5
	stats.radius = 3.0
	return stats


## A pool in the tree, so `instance` is registered and the static seam resolves.
func _pool() -> ProjectilePool:
	var pool: ProjectilePool = auto_free(PoolScript.new())
	add_child(pool)
	return pool


## Fire `count` shots into open sky. No physics runs in this suite, so every one
## of them stays airborne for the length of the test.
func _fire(pool: ProjectilePool, count: int) -> void:
	for i in count:
		pool.fire_from_pool(
			_make_stats(),
			Vector2.ZERO,
			Vector2.RIGHT,
			Projectile.Faction.PLAYER,
			null,
		)

# --- Sizing ------------------------------------------------------------------


## The floor is the PLAYER's worst case; everything past it is reserved for.
func test_a_fresh_pool_holds_the_base_size() -> void:
	var pool := _pool()
	assert_int(pool.pool_size()).is_equal(ProjectilePool.BASE_POOL_SIZE)
	assert_int(pool.reserved()).is_equal(0)
	assert_int(pool.get_child_count()).is_equal(ProjectilePool.BASE_POOL_SIZE)


func test_reserve_grows_the_pool_by_the_reserved_count() -> void:
	var pool := _pool()

	ProjectilePool.reserve(RESERVATION)

	assert_int(pool.reserved()).is_equal(RESERVATION)
	assert_int(pool.pool_size()).is_equal(ProjectilePool.BASE_POOL_SIZE + RESERVATION)
	# The slots are real nodes, instanced at PLACEMENT time — which is the whole
	# point: nothing is allocated once shots are flying.
	assert_int(pool.get_child_count()).is_equal(ProjectilePool.BASE_POOL_SIZE + RESERVATION)


## Several turrets sum rather than each setting a floor.
func test_reservations_accumulate_across_spawners() -> void:
	var pool := _pool()

	for i in 3:
		ProjectilePool.reserve(RESERVATION)

	assert_int(pool.pool_size()).is_equal(ProjectilePool.BASE_POOL_SIZE + RESERVATION * 3)


## ❗️**Never shrinks.** `release` only keeps the counter honest for the next
## `reserve` — freeing projectiles to reclaim the slots would reintroduce exactly
## the mid-wave allocation churn the pool exists to prevent, and a dormant slot
## costs nothing.
func test_release_keeps_the_counter_honest_without_shrinking_the_pool() -> void:
	var pool := _pool()
	ProjectilePool.reserve(RESERVATION)
	var grown := pool.pool_size()

	ProjectilePool.release(RESERVATION)

	assert_int(pool.reserved()).is_equal(0)
	assert_int(pool.pool_size()).is_equal(grown)

	# And the next reservation does not re-grow what is already there: the
	# counter came back to zero, so the target is the same number again.
	ProjectilePool.reserve(RESERVATION)
	assert_int(pool.pool_size()).is_equal(grown)


## A release with nothing reserved must not drive the counter negative, or the
## next reserve would grow to less than the base and hand out a smaller pool.
func test_releasing_more_than_was_reserved_floors_at_zero() -> void:
	var pool := _pool()
	ProjectilePool.reserve(5)

	ProjectilePool.release(999)

	assert_int(pool.reserved()).is_equal(0)
	assert_int(pool.pool_size()).is_equal(ProjectilePool.BASE_POOL_SIZE + 5)

# --- The bug ------------------------------------------------------------------


## ❗️**The regression this whole chunk exists for.** At the fixed size, this load
## stole shots that were still in flight. With the spawner's reservation in, every
## shot gets its own slot and nothing vanishes mid-air.
func test_a_reserved_pool_does_not_steal_under_the_load_that_used_to_saturate_it() -> void:
	var pool := _pool()
	var load_size := ProjectilePool.BASE_POOL_SIZE + 10

	ProjectilePool.reserve(RESERVATION)
	_fire(pool, load_size)

	assert_int(pool.active_count()).is_equal(load_size)


## The steal survives as the LAST-RESORT backstop: past capacity a caller still
## gets a projectile rather than a null it would have to branch on.
func test_the_steal_remains_the_backstop_past_capacity() -> void:
	var pool := _pool()

	_fire(pool, pool.pool_size() + 10)

	assert_int(pool.active_count()).is_equal(pool.pool_size())

# --- The inert contract --------------------------------------------------------


## Same contract as `fire()`: no pool in the tree means no-op, not a crash. A
## turret placed in a headless test or tool reserves against nothing and works.
func test_reserve_and_release_no_op_without_a_pool() -> void:
	assert_object(ProjectilePool.instance).is_null()

	ProjectilePool.reserve(RESERVATION)
	ProjectilePool.release(RESERVATION)

	assert_object(ProjectilePool.instance).is_null()


## ❗️`_reserved` is an INSTANCE var, and that is load-bearing: it dies with the
## scene reload, so there is no `reset_run()` hook to forget. A static counter
## would survive a restart and hand out capacity for turrets that no longer
## exist — the trap `automation.gd` documents for the tick registries.
func test_reservations_die_with_the_pool_rather_than_surviving_a_restart() -> void:
	var first := _pool()
	ProjectilePool.reserve(RESERVATION)
	assert_int(first.reserved()).is_equal(RESERVATION)

	remove_child(first)

	var second := _pool()
	assert_int(second.reserved()).is_equal(0)
	assert_int(second.pool_size()).is_equal(ProjectilePool.BASE_POOL_SIZE)
