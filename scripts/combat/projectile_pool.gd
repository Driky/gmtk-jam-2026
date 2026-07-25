## Fixed pool of projectiles, instanced once and recycled forever — nothing is
## instantiated or freed while shots are flying, which is what keeps a turret
## line (3.5) from allocating during a wave.
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

## Ceiling on concurrent shots = fire rate × lifetime, summed over everything
## shooting. Fine for the player alone (~2/s × 1.5 s = 3).
##
## ❗️FIXED SIZE DOES NOT SURVIVE TURRETS (3.5). Every turret is another
## spawner, so a defended base blows past 32 and `_take` starts stealing shots
## that are still in flight — bolts vanishing mid-air, and worse the more
## turrets you build, which is exactly backwards. Before turrets ship, size the
## pool from its spawners instead of a constant: have each one `reserve()` its
## own worst case on place and release it on remove, grow the pool to the sum
## (never shrink mid-wave), and keep the steal only as a last-resort backstop.
## Growing is safe — nothing holds a Projectile reference across frames.
const POOL_SIZE := 32

static var instance: ProjectilePool = null

var _pool: Array[Projectile] = []
## Round-robin start point, so a saturated pool recycles the OLDEST shot rather
## than always stealing the same slot.
var _next := 0


func _ready() -> void:
	instance = self
	for i in POOL_SIZE:
		var projectile: Projectile = ProjectileScene.instantiate()
		add_child(projectile)
		_pool.append(projectile)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## The one entry point for every ranged attack. No-ops (returns null) when no
## pool is in the tree — tests and headless tools can call it safely.
static func fire(
		stats: ProjectileStats,
		origin: Vector2,
		direction: Vector2,
		faction: Projectile.Faction,
		shooter: Node2D,
) -> Projectile:
	if instance == null or stats == null:
		return null
	return instance.fire_from_pool(stats, origin, direction, faction, shooter)


func fire_from_pool(
		stats: ProjectileStats,
		origin: Vector2,
		direction: Vector2,
		faction: Projectile.Faction,
		shooter: Node2D,
) -> Projectile:
	var projectile := _take()
	projectile.launch(stats, origin, direction, faction, shooter)
	return projectile


func active_count() -> int:
	var count := 0
	for projectile in _pool:
		if projectile.is_active():
			count += 1
	return count


## First dormant slot from the round-robin cursor. Under saturation it steals
## the slot at the cursor: dropping the oldest shot beats allocating mid-wave.
func _take() -> Projectile:
	for i in POOL_SIZE:
		var index := (_next + i) % POOL_SIZE
		if not _pool[index].is_active():
			_next = (index + 1) % POOL_SIZE
			return _pool[index]
	var stolen := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	return stolen
