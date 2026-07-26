## Debug view of the automation sim: per conveyor and inserter, the facing arrow,
## the slot's id and count, and the cooldown counter; per machine its slots, its
## cooldown or craft progress, and — for a miner — the harvest block it is
## eating.
##
## ❗️The machine pass is not optional polish. Until 3.3 this overlay was blind
## to the only things that CREATE items, so "the belt is empty" and "the miner
## never started" looked identical.
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
const MACHINE_COLOR := Color(0.6, 1.0, 0.55, 0.9)
## An idle machine is the thing you are looking for when you open this — a miner
## whose ore ran out reads as a red box, not as a green one with different text.
const IDLE_COLOR := Color(1.0, 0.4, 0.35, 0.95)
## Where a miner is reaching. The whole placement rule is "the arrow points at
## the ore", so a miner that found nothing is only diagnosable next to this.
const HARVEST_COLOR := Color(0.9, 0.8, 0.4, 0.7)
## A belt holding something reads differently from an empty one at a glance,
## which is how a jam shows up as a solid block of colour.
const OCCUPIED_ALPHA := 0.25
const ARROW_LENGTH := 5.0
const ARROW_HEAD := 3.0
const LABEL_SIZE := 7
const SLOT_OFFSET := Vector2(-7.0, -2.0)
const COOLDOWN_OFFSET := Vector2(-7.0, 7.0)
## A machine is 2–3 cells wide, so its readout is anchored to the footprint's
## top-left corner and stacked downward rather than centred like a belt's.
const MACHINE_LINE_HEIGHT := 8.0
const MACHINE_TEXT_INSET := Vector2(2.0, 9.0)

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
	for node: Deployable in automation.machines():
		# Multi-cell, so the box is the whole footprint rather than one tile, and
		# the cull tests the origin corner.
		var origin := Vector2(node.cell()) * TILE
		if not view.has_point(origin):
			continue
		var color := IDLE_COLOR if node.is_idle() else MACHINE_COLOR
		draw_rect(Rect2(origin, Vector2(node.size) * TILE), color, false, 1.0)
		# `as` casts rather than a virtual on the base: this is a debug view, it
		# already casts belts and inserters the same way, and pushing a readout
		# API onto every Deployable to keep one debug node tidy is the wrong
		# trade. Anything not matched simply draws its box.
		var lines: Array[String] = []
		var miner := node as Miner
		if miner != null:
			draw_rect(
				Rect2(Vector2(miner.harvest_cells()[0]) * TILE, Vector2(node.size) * TILE),
				HARVEST_COLOR,
				false,
				1.0,
			)
			lines.append(_stack_text("out", miner.slot()))
			lines.append("cd %d" % miner.cooldown())
			if node.is_idle():
				lines.append("NO ORE")
		var station := node as CraftingStation
		if station != null:
			lines.append(_stack_text("in", station.input_slot()))
			lines.append(_stack_text("out", station.output_slot()))
			lines.append("craft %d" % station.progress())
		for i in lines.size():
			_label(
				font,
				origin + MACHINE_TEXT_INSET + Vector2(0.0, i * MACHINE_LINE_HEIGHT),
				lines[i],
				color,
			)


## `label —` for an empty slot rather than an omitted line: a machine holding
## nothing has to look different from one this overlay failed to read.
static func _stack_text(label: String, stack: Dictionary) -> String:
	if stack.is_empty():
		return "%s —" % label
	return "%s %s×%d" % [label, stack.id, stack.count]


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
