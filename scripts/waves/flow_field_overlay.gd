## Debug view of the ground flow field (2.2): a cost heat-map + flow-direction
## ticks for the cells in view. Visibility is driven by the F3 debug menu
## ([ui.md](../../docs/systems/ui.md)) — this node owns no keybinding.
## Owning doc: docs/systems/enemies.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
const HEAT_ALPHA := 0.35
## Costs at/above this all render at the hot end of the ramp.
const HEAT_MAX_COST := 60.0
const TICK_LENGTH := 6.0
const TICK_COLOR := Color(1.0, 1.0, 1.0, 0.8)

## Injected by tests; falls back to the Waves autoload.
var waves: Node = null


func _ready() -> void:
	top_level = true # Draw in world space, unaffected by the parent transform.
	visible = false
	z_index = 100
	if waves == null:
		waves = Waves


func _process(_delta: float) -> void:
	if visible:
		queue_redraw() # Debug-only cost; tracks camera motion + field updates.


func _draw() -> void:
	var field: FlowField = waves.flow_field
	if field == null or not field.is_computed():
		return
	var view: Rect2 = (
		get_viewport().get_canvas_transform().affine_inverse()
		* get_viewport().get_visible_rect()
	)
	var x0 := maxi(int(floor(view.position.x / TILE)), 0)
	var y0 := maxi(int(floor(view.position.y / TILE)), 0)
	var x1 := mini(int(ceil(view.end.x / TILE)) + 1, field.region_width)
	var y1 := mini(int(ceil(view.end.y / TILE)) + 1, field.region_rows)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var cell := Vector2i(x, y)
			var cost := field.cost_at(cell)
			if cost == INF:
				continue
			var heat := clampf(cost / HEAT_MAX_COST, 0.0, 1.0)
			# Hue ramp: green (cheap, near the Core) -> red (expensive).
			var color := Color.from_hsv((1.0 - heat) * 0.33, 1.0, 1.0, HEAT_ALPHA)
			draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), color)
			var dir := field.get_flow_dir(cell)
			if dir != Vector2i.ZERO:
				var center := Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
				draw_line(center, center + Vector2(dir) * TICK_LENGTH, TICK_COLOR, 1.0)
