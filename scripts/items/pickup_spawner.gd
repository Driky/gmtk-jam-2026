## Owns the drop policy for Terrain.drops_spawned (seam reserved in terrain.gd):
## PLAYER and MONSTER digs spawn world pickups; MACHINE output is buffered
## inside the machine (3.3) and never dropped.
##
## Also the single spawn path for loot that has no tile behind it — mob drops
## (2.6) — so everything droppable becomes the same Pickup and feeds the same
## looting XP channel. Reached by group rather than a node path: dying mobs
## have no reference to this node.
## Owning doc: docs/systems/player-combat.md
extends Node2D

const PickupScene := preload("res://scenes/pickup.tscn")
const TILE := TileLayout.TILE_SIZE


func _ready() -> void:
	add_to_group(&"pickup_spawner")
	Terrain.drops_spawned.connect(_on_drops_spawned)


## Drop a stack at a world position. `grants_xp` false marks loot that must not
## pay the looting channel (a player-placed block's drop — progression.md).
func spawn_at(world_pos: Vector2, id: String, count: int, grants_xp := true) -> void:
	if id == "" or count <= 0:
		return
	var pickup: Node2D = PickupScene.instantiate()
	pickup.setup(id, count, grants_xp)
	pickup.position = world_pos
	add_child(pickup)


func _on_drops_spawned(
		pos: Vector2i,
		drop_id: String,
		drop_count: int,
		source: int,
		grants_xp: bool,
) -> void:
	if source == Terrain.Source.MACHINE:
		return
	spawn_at((Vector2(pos) + Vector2(0.5, 0.5)) * TILE, drop_id, drop_count, grants_xp)
