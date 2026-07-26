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

## Swings needed to take it off the wall. One for a torch — it is a stick, and
## relighting a shaft you are re-digging should never be a chore. Heavier 3.1
## machines raise this; the counter lives here rather than on the player so each
## deployable owns its own toughness.
const REMOVAL_HITS := 1

## What a completed removal pops out as a pickup. A property rather than a
## constant because 3.1's Deployable base needs the same field on every machine.
var item_id := "torch"

var _cell := Vector2i.ZERO
var _removal_hits := 0


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


## One landed swing. True once the deployable has taken enough to come off the
## wall — the caller then calls remove(). Un-deploying is counted in HITS rather
## than accumulated damage like a tile: a swing is a discrete beat on the item's
## cooldown, and "three hits" is a thing a player can feel and count.
func take_removal_hit(hits := 1) -> bool:
	_removal_hits += hits
	return _removal_hits >= REMOVAL_HITS


## Progress toward removal, for the cursor highlight.
func removal_ratio() -> float:
	return clampf(float(_removal_hits) / float(REMOVAL_HITS), 0.0, 1.0)


## Off the wall: free the cell and pop the item out as a world pickup.
##
## The cell is freed **eagerly** rather than waiting for queue_free, which
## defers to the end of the frame — a removal followed by a re-place into the
## same cell on the same frame would otherwise hit a stale entity entry and be
## rejected for no visible reason.
##
## The pickup carries `grants_xp = false`: place → remove → place would
## otherwise be an infinite looting-XP loop ([progression.md](../../docs/systems/progression.md)).
func remove(terrain: Node, spawner: Node) -> void:
	terrain.remove_entity(_cell)
	if spawner != null:
		spawner.spawn_at(global_position, item_id, 1, false)
	queue_free()
