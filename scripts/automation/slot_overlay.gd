## Debug view of the automation sim: per conveyor and inserter, the facing arrow,
## the slot's id and count, and the cooldown counter.
##
## Automation tick bugs — ordering, dupes, stack merges — are the top-listed risk
## in [plan.md](../../docs/plan.md), and this is the other half of that
## mitigation next to the two-phase commit: it is what makes a jam, a starved
## junction or a stuck cooldown visible instead of inferred.
##
## Visibility is driven by the F3 debug menu ([ui.md](../../docs/systems/ui.md))
## — this node owns no keybinding, same as `flow_field_overlay.gd`.
## Owning doc: docs/systems/automation.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
## Above the light map (100), unlike the item layer: a debug readout has to stay
## legible in an unlit cave.
const Z_INDEX := 101
const BELT_COLOR := Color(0.4, 0.9, 1.0, 0.9)
const INSERTER_COLOR := Color(1.0, 0.7, 0.3, 0.9)
## A belt holding something reads differently from an empty one at a glance,
## which is how a jam shows up as a solid block of colour.
const OCCUPIED_ALPHA := 0.25
const ARROW_LENGTH := 5.0
const ARROW_HEAD := 3.0
const LABEL_SIZE := 7
const SLOT_OFFSET := Vector2(-7.0, -2.0)
const COOLDOWN_OFFSET := Vector2(-7.0, 7.0)

## Injected by tests; falls back to the autoload.
var automation: Node = null


func _ready() -> void:
	top_level = true # Draw in world space, unaffected by the parent transform.
	visible = false
	z_index = Z_INDEX
	if automation == null:
		automation = Automation


func _process(_delta: float) -> void:
	if visible:
		queue_redraw() # Debug-only cost; tracks camera motion and the sim alike.


func _draw() -> void:
	# Same view-rect derivation as flow_field_overlay.gd, grown a tile so a label
	# at the edge does not blink out.
	var view: Rect2 = (
		get_viewport().get_canvas_transform().affine_inverse()
		* get_viewport().get_visible_rect()
	).grow(TILE)
	var font := ThemeDB.fallback_font
	for node: Deployable in automation.conveyors():
		var belt := node as Conveyor
		var centre := _centre(belt.cell())
		if not view.has_point(centre):
			continue
		var stack := belt.slot()
		if not stack.is_empty():
			draw_rect(
				Rect2(centre - Vector2.ONE * TILE * 0.5, Vector2.ONE * TILE),
				Color(BELT_COLOR, OCCUPIED_ALPHA),
			)
			var count: int = stack.count
			_label(font, centre + SLOT_OFFSET, "%s×%d" % [stack.id, count], BELT_COLOR)
		_arrow(centre, belt.facing, BELT_COLOR)
		if belt.cooldown() > 0:
			_label(font, centre + COOLDOWN_OFFSET, "cd %d" % belt.cooldown(), BELT_COLOR)
	for node: Deployable in automation.inserters():
		var arm := node as Inserter
		var centre := _centre(arm.cell())
		if not view.has_point(centre):
			continue
		# Drawn from BEHIND to in front, so the pick-up end is visible too — the
		# orientation is the thing most worth seeing on an inserter.
		draw_line(_centre(arm.source_cell()), _centre(arm.target_cell()), INSERTER_COLOR, 1.0)
		_arrow(centre, arm.facing, INSERTER_COLOR)
		if arm.cooldown() > 0:
			_label(font, centre + COOLDOWN_OFFSET, "cd %d" % arm.cooldown(), INSERTER_COLOR)


static func _centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


func _arrow(centre: Vector2, facing: Vector2i, color: Color) -> void:
	var dir := Vector2(facing)
	var tip := centre + dir * ARROW_LENGTH
	var side := Vector2(-dir.y, dir.x) * ARROW_HEAD
	var back := tip - dir * ARROW_HEAD
	draw_line(centre - dir * ARROW_LENGTH, tip, color, 1.0)
	draw_line(tip, back + side, color, 1.0)
	draw_line(tip, back - side, color, 1.0)


func _label(font: Font, at: Vector2, text: String, color: Color) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)
