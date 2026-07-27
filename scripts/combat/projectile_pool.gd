## Pool of projectiles, recycled forever — nothing is freed while shots are
## flying, which is what keeps a turret line from allocating during a wave.
## Sized from its SPAWNERS: the player's worst case is the floor, and every
## turret `reserve()`s its own on top (3.5a).
##
## Reached through `ProjectilePool.fire(...)` rather than a node path, so
## turrets and spells need no reference to this node and the fixed autoload map
## in tech-design.md stays untouched. The static ref is scene-tree-scoped: it
## registers in _ready and clears in _exit_tree, so a scene reload can't leave
## a dangling pool behind.
## Owning doc: docs/systems/player-combat.md
class_name ProjectilePool
extends Node2D

const ProjectileScene := preload("res://scenes/combat/projectile.tscn")

## What the pool holds before anything reserves: the PLAYER's own worst case
## (fire rate × lifetime, ~2/s × 1.5 s = 3), with room to spare. Everything
## beyond the player is reserved for by its own spawner.
##
## ❗️A fixed size did not survive turrets. Every turret is another spawner, so a
## defended base blew past 32 and `_take` started stealing shots that were still
## in flight — bolts vanishing mid-air, and worse the more turrets you built,
## which is exactly backwards. The pool is sized from its SPAWNERS now: each one
## `reserve()`s its own worst case on place and `release()`s it on remove.
const BASE_POOL_SIZE := 32

static var instance: ProjectilePool = null

var _pool: Array[Projectile] = []
## Round-robin start point, so a saturated pool recycles the OLDEST shot rather
## than always stealing the same slot.
var _next := 0
## Sum of every live spawner's reservation.
##
## ❗️An INSTANCE var, not a static, and that is load-bearing: it dies with the
## scene reload, so there is no `reset_run()` hook to forget. A static counter
## would survive a restart and hand out capacity for turrets that no longer
## exist — the exact trap `automation.gd` documents for the tick registries.
var _reserved := 0


func _ready() -> void:
	instance = self
	_grow_to(BASE_POOL_SIZE + _reserved)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Live capacity. Read by the tests and by anything reasoning about saturation —
## never `BASE_POOL_SIZE`, which is only the floor.
func pool_size() -> int:
	return _pool.size()


func reserved() -> int:
	return _reserved


## Claim `count` slots for a spawner that is about to start firing. No-ops when
## no pool is in the tree, the same inert-without-a-node contract as `fire()`:
## a turret placed in a headless test reserves against nothing and works.
##
## ❗️Growing mid-wave is safe *because* nothing holds a `Projectile` reference
## across frames — the pool hands one out and takes it back within the flight.
static func reserve(count: int) -> void:
	if instance == null or count <= 0:
		return
	instance._reserved += count
	instance._grow_to(BASE_POOL_SIZE + instance._reserved)


## Give the slots back. ❗️The pool NEVER SHRINKS — this only keeps the counter
## honest for the next `reserve`. Freeing projectiles mid-wave to reclaim memory
## would reintroduce the allocation churn the pool exists to prevent, and the
## slots cost nothing sitting dormant.
static func release(count: int) -> void:
	if instance == null or count <= 0:
		return
	instance._reserved = maxi(instance._reserved - count, 0)


## The one entry point for every ranged attack. No-ops (returns null) when no
## pool is in the tree — tests and headless tools can call it safely.
##
## `damage_scale` multiplies the stats' damage for THIS shot only, so a turret
## applies `Progression.get_stat("turret_damage")` (and 4.2's spells
## `spell_damage`) without duplicating a `ProjectileStats` per shot.
static func fire(
		stats: ProjectileStats,
		origin: Vector2,
		direction: Vector2,
		faction: Projectile.Faction,
		shooter: Node2D,
		damage_scale := 1.0,
) -> Projectile:
	if instance == null or stats == null:
		return null
	return instance.fire_from_pool(stats, origin, direction, faction, shooter, damage_scale)


func fire_from_pool(
		stats: ProjectileStats,
		origin: Vector2,
		direction: Vector2,
		faction: Projectile.Faction,
		shooter: Node2D,
		damage_scale := 1.0,
) -> Projectile:
	var projectile := _take()
	projectile.launch(stats, origin, direction, faction, shooter, damage_scale)
	return projectile


func active_count() -> int:
	var count := 0
	for projectile in _pool:
		if projectile.is_active():
			count += 1
	return count


## First dormant slot from the round-robin cursor. ❗️The steal is the LAST-RESORT
## backstop now, not the sizing strategy: with every spawner reserving its own
## worst case it should never fire. Kept because a stolen shot is still better
## than a null return every caller would have to branch on.
func _take() -> Projectile:
	var size := _pool.size()
	for i in size:
		var index := (_next + i) % size
		if not _pool[index].is_active():
			_next = (index + 1) % size
			return _pool[index]
	var stolen := _pool[_next]
	_next = (_next + 1) % size
	return stolen


## Instantiate up to `target`, appending. Never removes — see `release`.
func _grow_to(target: int) -> void:
	while _pool.size() < target:
		var projectile: Projectile = ProjectileScene.instantiate()
		add_child(projectile)
		_pool.append(projectile)
