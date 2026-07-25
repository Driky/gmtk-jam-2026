## Owns the drop policy for Terrain.drops_spawned (seam reserved in terrain.gd):
## PLAYER and MONSTER digs spawn world pickups; MACHINE output is buffered
## inside the machine (3.3) and never dropped.
## Owning doc: docs/systems/player-combat.md
extends Node2D

const PickupScene := preload("res://scenes/pickup.tscn")
const TILE := TileLayout.TILE_SIZE


func _ready() -> void:
	Terrain.drops_spawned.connect(_on_drops_spawned)


func _on_drops_spawned(
		pos: Vector2i,
		drop_id: String,
		drop_count: int,
		source: int,
		grants_xp: bool,
) -> void:
	if source == Terrain.Source.MACHINE:
		return
	var pickup: Node2D = PickupScene.instantiate()
	pickup.setup(drop_id, drop_count, grants_xp)
	pickup.position = (Vector2(pos) + Vector2(0.5, 0.5)) * TILE
	add_child(pickup)
