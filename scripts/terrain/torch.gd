## A placed torch: one cell, one light source, nothing else.
##
## Deliberately minimal. Day 3's `Deployable` base ([automation.md](../../docs/systems/automation.md))
## brings HP, faction, a W×H footprint, `on_placed`/`on_removed` and a placement
## ghost; this is the one-cell special case that lands before any of that exists,
## and 3.1 folds it in rather than growing a second placement system.
##
## It carries **no `current_hp`**, and that is load-bearing rather than an
## omission: `flow_field.gd` reads `ent.get("current_hp")` and skips entities
## that return null, so a torch adds exactly zero cost to the field and mobs
## walk through it. The day 3.1 gives torches HP they start costing the field,
## which is the intended 3.1 behaviour — don't "fix" it here.
##
## Owning doc: docs/systems/terrain.md
class_name Torch
extends Node2D

const TILE := TileLayout.TILE_SIZE

## Warm, against daylight's faint cool. Read by the light grid through the
## `light_source` group — a torch owns no light node, because there are no
## light nodes any more (terrain.md §Lighting).
var light_color := Color(1.0, 0.78, 0.45)

var _cell := Vector2i.ZERO


## Call before add_child, matching Core.setup — anchors the node to the grid at
## its cell's centre, which is what the light grid floors back to a cell.
func setup(cell: Vector2i) -> void:
	_cell = cell
	position = (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


func cell() -> Vector2i:
	return _cell


## Claim the cell. False when something else already holds it, in which case the
## caller must NOT have consumed the item yet — see Player._place_scene.
func register(terrain: Node) -> bool:
	return terrain.place_entity(_cell, self)


## Taken back by hand (RMB). Frees the cell **eagerly** rather than waiting for
## queue_free: that defers to the end of the frame, so a pick-up followed by a
## re-place in the same cell on the same frame would otherwise hit a stale
## entity entry and be rejected.
func pick_up(terrain: Node) -> void:
	terrain.remove_entity(_cell)
	queue_free()
