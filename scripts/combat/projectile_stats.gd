## Parameterization of the ONE projectile system. Ranged weapons, spells
## (4.2, cut line 4), and turrets (3.5) all fire through it — one
## implementation serving three features is the whole point, so resist adding
## a second projectile path when something doesn't fit: add a field here.
## Owning doc: docs/systems/player-combat.md
class_name ProjectileStats
extends Resource

@export var display_name := ""
@export var speed := 320.0 ## px/s along the fire direction.
@export var damage := 6.0
@export var knockback := 60.0
## 0 = flies straight. Arcing shots (a bow at range) raise this; turret bolts
## and spells generally don't want it.
@export var gravity := 0.0
## Seconds before it despawns on its own. Also the backstop that guarantees a
## shot fired into open sky returns to the pool.
@export var lifetime := 1.5
## Extra bodies it may pass through after the first. 0 = stops on first hit.
@export var pierce := 0
@export var radius := 3.0 ## Collision circle; also the drawn size.
@export var color := Color(1.0, 0.9, 0.4)
