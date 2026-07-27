## A placed respawn beacon: die anywhere on the map and wake up at the nearest
## one instead of walking back from the Core. The second Utility deployable
## ([automation.md](../../docs/systems/automation.md) §Categories) and the payoff
## for building out — a mineshaft an hour from spawn stops being a one-way trip.
##
## ❗️**No behaviour of its own, not one line.** Everything structural is
## `Deployable`'s, and the *rule* lives in the player: `_respawn_anchor` asks the
## `respawn_beacon` group for the nearest one. So this script is the same shape as
## `Torch` — a `class_name` and a docstring, with `scenes/automation/respawn_beacon.tscn`
## authoring every number.
##
## The group is declared **on the scene root** rather than by an `add_to_group`
## call in `_ready`, matching `core.tscn` and `torch.tscn`. It is also what makes
## the anchor lookup survive a run restart for free: a group dies with the scene,
## where a `static var instance` would dangle across the reload (deployables are
## children of `Main` and are freed with it, so `on_removed` never runs) and would
## need its own `reset_run` hook.
##
## Owning doc: docs/systems/player-combat.md
class_name RespawnBeacon
extends Deployable

## ❗️Deliberately the SAME NAME as `core.gd`'s, so `Player._tick_respawn` keeps
## one code path for both anchors and never asks which kind it got. `core.gd` has
## no `class_name`, so that call is already duck-typed through `as Node2D` — this
## joins that contract rather than adding a second one beside it.
##
## The cell the player's feet land on top of. For a 1×1 beacon that is simply the
## cell it occupies, which is why `support_dirs` is Down: see the scene.
func base_cell() -> Vector2i:
	return cell()
