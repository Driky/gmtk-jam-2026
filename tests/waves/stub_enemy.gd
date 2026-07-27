## Test-only stand-in for scenes/enemies/enemy.tscn: the spawn/death contract
## the wave manager relies on, with no physics, no Terrain reads and no flow
## field. Injected via Waves.enemy_scene.
##
## ❗️In the `enemies` group like the real thing, because since 3.5a that group
## IS an interface: `Waves.enemies()` reads it, and turrets and traps pick their
## targets out of what it returns.
extends Node2D

signal died(enemy: Node)

var stats: EnemyStats = null


## Mirrors Enemy.take_damage's contract: emit died BEFORE freeing, so the
## manager's handler still sees a valid instance.
func take_damage(_amount: float, _attacker: Node2D = null) -> void:
	died.emit(self)
	queue_free()
