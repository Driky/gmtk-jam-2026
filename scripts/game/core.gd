## The Core — pre-placed base heart; monsters' default target; its death
## ends the run. main.gd instances it on the flat spawn area after world
## gen. Entity damage stays on this node (Terrain is tile-only); enemies
## (2.3) call take_damage directly. Owning doc: docs/plan.md
extends Node2D

signal health_changed(current: float, max_value: float)
signal died

const MAX_HP := 1000.0
## Footprint: 3 columns × 2 rows of air cells resting on the surface row.
const HALF_COLS := 1
const ROWS := 2

var current_hp := MAX_HP

var _center_x := 0
var _surface_row := 0
var _dead := false


## Call before add_child — anchors the node to the grid: origin at the
## footprint center, bottom edge on top of the surface tile.
func setup(center_x: int, surface_row: int) -> void:
	_center_x = center_x
	_surface_row = surface_row
	position = Vector2(
		(center_x + 0.5) * TileLayout.TILE_SIZE,
		(surface_row - 1.0) * TileLayout.TILE_SIZE,
	)


func footprint() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(-HALF_COLS, HALF_COLS + 1):
		for dy in range(1, ROWS + 1):
			cells.append(Vector2i(_center_x + dx, _surface_row - dy))
	return cells


## The ground flow field (2.2) seeds its Dijkstra from here.
func base_cell() -> Vector2i:
	return Vector2i(_center_x, _surface_row - 1)


## Register every footprint cell in the terrain entity dict — blocks player
## block placement inside the Core and gives future systems a cell lookup.
## All-or-nothing: rolls back already-placed cells on failure.
func register_footprint(terrain: Node) -> bool:
	var placed: Array[Vector2i] = []
	for cell in footprint():
		if not terrain.place_entity(cell, self):
			for done in placed:
				terrain.remove_entity(done)
			return false
		placed.append(cell)
	return true


func take_damage(amount: float) -> void:
	if _dead:
		return
	current_hp = maxf(current_hp - amount, 0.0)
	health_changed.emit(current_hp, MAX_HP)
	if current_hp <= 0.0:
		_dead = true
		died.emit()
