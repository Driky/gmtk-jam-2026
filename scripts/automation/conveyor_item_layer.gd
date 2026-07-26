## Items visibly flowing through conveyors — the never-cut bullet of the whole
## factory loop ([plan.md](../../docs/plan.md): "visible items flowing through
## conveyors — the genre").
##
## ❗️ONE immediate-mode `_draw` layer, deliberately **not** a pooled
## `Sprite2D` + `Label` per item. Zero nodes, no pool to size (the fixed-32
## projectile pool is already a logged 3.5 blocker for exactly that reason —
## [player-combat.md](../../docs/systems/player-combat.md)), and the renderer
## reads the sim directly every frame, so it cannot desync from it. The codebase
## has settled on this shape twice already: culled `_draw`
## (`flow_field_overlay.gd`) and cached-texture reuse (`Hud.icon_for`).
##
## Owning doc: docs/systems/automation.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
## Smaller than a cell, so the belt under it stays readable and two items on
## neighbouring cells read as two items rather than one bar.
const ITEM_SIZE := Vector2(10.0, 10.0)
const HALF := ITEM_SIZE * 0.5
## Between the tilemap (0) and the LightMap (100), so belt items are LIT like
## everything else instead of glowing in a dark cave.
const Z_INDEX := 50
## Count label, offset down-right of the icon so it clears the art.
const COUNT_OFFSET := Vector2(2.0, 10.0)
const COUNT_FONT_SIZE := 8
const COUNT_COLOR := Color(1.0, 1.0, 1.0, 0.9)

## Injected by tests; falls back to the autoload.
var automation: Node = null


func _ready() -> void:
	top_level = true # Draw in world space, unaffected by any parent transform.
	z_index = Z_INDEX
	if automation == null:
		automation = Automation


## Redrawn every frame there is anything to draw: the cull below depends on the
## view rect, so camera motion alone changes the drawn set. An idle factory costs
## one early-outing scan of the registry.
func _process(_delta: float) -> void:
	if automation.has_items_in_transit():
		queue_redraw()


func _draw() -> void:
	var alpha: float = automation.tick_alpha()
	# Same view-rect derivation as flow_field_overlay.gd. Grown by a tile so an
	# item straddling the edge does not pop in and out as the camera pans.
	var view: Rect2 = (
		get_viewport().get_canvas_transform().affine_inverse()
		* get_viewport().get_visible_rect()
	).grow(TILE)
	var font := ThemeDB.fallback_font
	for node: Deployable in automation.conveyors():
		var belt := node as Conveyor
		var stack := belt.slot()
		if stack.is_empty():
			continue
		var pos := item_position(belt.prev_cell(), belt.cell(), alpha)
		if not view.has_point(pos):
			continue
		draw_texture_rect(Hud.icon_for(stack.id), Rect2(pos - HALF, ITEM_SIZE), false)
		# Counts only above 1: draw_string is the expensive call here and most
		# slots carry a single item.
		var count: int = stack.count
		if count > 1:
			draw_string(
				font,
				pos + COUNT_OFFSET,
				str(count),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				COUNT_FONT_SIZE,
				COUNT_COLOR,
			)


## Where an item renders this frame. Static and pure so the interpolation is
## unit-testable without a viewport — it is the one part of this renderer that
## can be wrong in a way a screenshot hides.
static func item_position(prev_cell: Vector2i, current: Vector2i, alpha: float) -> Vector2:
	var from := (Vector2(prev_cell) + Vector2(0.5, 0.5)) * TILE
	var to := (Vector2(current) + Vector2(0.5, 0.5)) * TILE
	return from.lerp(to, clampf(alpha, 0.0, 1.0))
