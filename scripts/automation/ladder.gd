## The first climbable: a 1×1 rung the player builds a column out of, climbed
## with `W`/`S` — and, during a wave, climbed by any biped mob that finds it
## ([enemies.md](../../docs/systems/enemies.md) §Climbables). Player ladders are
## biped highways, which is the deliberate emergent texture: remove them before a
## wave, hide them behind hatches, or (4.1) favour poles.
##
## ❗️**No behaviour of its own, not one line** — the same shape as `Torch` and
## `RespawnBeacon`. Everything structural is `Deployable`'s, and everything a
## climbable *is* rides on the single `is_climbable` export that
## `scenes/automation/ladder.tscn` authors: the stacking rule (a rung is held by
## the rung below it), the player's climb, the flow field's cheap vertical edge,
## `EnemyLocomotion`'s CLIMB branch and the mob's refusal to chew it. Four readers,
## one predicate, no `Ladder` type check anywhere — which is exactly why 4.1's
## rope and pole are a `.tscn` and a `.tres` rather than a second script.
##
## The `class_name` is convention, not a cast: every deployable in this repo has
## one, script-path ≈ owning-doc, and this is where 4.1's directional climbable
## profiles will hang.
##
## Owning doc: docs/systems/automation.md
class_name Ladder
extends Deployable
