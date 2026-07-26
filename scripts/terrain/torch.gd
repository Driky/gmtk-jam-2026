## A placed torch: one cell, one light source, nothing else.
##
## Everything structural — footprint, HP, support, hit-counted removal and the
## pop-to-pickup drop path — is `Deployable`'s
## ([automation.md](../../docs/systems/automation.md)). What is left here is the
## one thing a torch owns that no other deployable does: its light colour.
## `scenes/torch.tscn` authors the numbers (`item_id`, `max_hp`); this script
## deliberately holds none of them.
##
## It lives under scripts/terrain/ rather than scripts/automation/ because the
## repo convention is script path ≈ owning doc: automation.md owns the base,
## terrain.md owns this torch as a light source.
##
## Owning doc: docs/systems/terrain.md
class_name Torch
extends Deployable

## Warm, against daylight's faint cool. Read by the light grid through the
## `light_source` group — a torch owns no light node, because there are no
## light nodes any more (terrain.md §Lighting).
var light_color := Color(1.0, 0.78, 0.45)
