## The player-facing half of power: a bolt over every machine that is not running
## at full rate, and — on **P** — every grid's coverage circles, colour-coded per
## component, with a supply/demand readout over each generator.
##
## ❗️**This is the one overlay that owns a keybinding, and it is a sanctioned
## exception rather than an oversight.** [ui.md](../../docs/systems/ui.md) locks
## "debug overlays own no keybindings of their own" — this is not a debug
## overlay, it is a player-facing readout, and `ui.md` already binds `P` for it
## in its own inventory of shortcuts. The slot overlay next door stays an F3 row.
##
## ❗️**The bolt layer is NOT behind the toggle.** A machine goes dark while you
## are somewhere else entirely, so the signal has to be on screen when you come
## back — the same argument that turned the exhausted-miner toast into a
## persistent HUD count ([ui.md](../../docs/systems/ui.md) §HUD). `P` toggles the
## *circles*, an internal flag rather than `visible`, precisely so the bolts stay.
##
## Owning doc: docs/systems/automation.md §Power
extends Node2D

const TILE := TileLayout.TILE_SIZE
## Above the light map (100), like the slot overlay: a bolt over a machine in an
## unlit cave has to stay legible, or the readout is missing exactly where the
## factory is hardest to read.
const Z_INDEX := 101

## Dead: on no grid at all, or on one with no supply.
const UNPOWERED_COLOR := Color(1.0, 0.35, 0.3, 0.95)
## Running, but slowed — the state that is otherwise indistinguishable from
## "this machine is just slow".
const BROWNOUT_COLOR := Color(1.0, 0.78, 0.25, 0.95)
## Roughly the size of one tile, so it reads over a 1-cell machine and does not
## swamp it.
const BOLT_SIZE := 14.0
## ❗️Two convex triangles, NOT a font glyph and NOT one concave polygon. Open
## Sans has no U+26A1 and a missing glyph renders as a blank box — the `[!]`
## lesson the idle counter already paid for ([ui.md](../../docs/systems/ui.md)) —
## and `draw_colored_polygon` triangulates a concave outline unreliably.
## Unit-box coordinates, scaled by `BOLT_SIZE` at draw time. Plain `Array[Vector2]`
## rather than a `PackedVector2Array`: the packed constructor is not a constant
## expression, so a `const` of it fails to parse.
const BOLT_UPPER: Array[Vector2] = [Vector2(0.22, -0.5), Vector2(-0.3, 0.08), Vector2(0.05, 0.08)]
const BOLT_LOWER: Array[Vector2] = [Vector2(-0.22, 0.5), Vector2(0.3, -0.08), Vector2(-0.05, -0.08)]

## One colour per grid, cycled by component index. Fixed and small on purpose:
## the question a player asks is "are these two the same grid", which four
## distinguishable colours answer as well as forty.
const GRID_COLORS: Array[Color] = [
	Color(0.45, 0.85, 1.0),
	Color(0.65, 1.0, 0.5),
	Color(1.0, 0.6, 0.9),
	Color(1.0, 0.85, 0.4),
	Color(0.75, 0.7, 1.0),
	Color(0.5, 1.0, 0.85),
]
const DISC_FILL_ALPHA := 0.08
const DISC_LINE_ALPHA := 0.55
const DISC_SEGMENTS := 48
const LABEL_SIZE := 8
const LABEL_OFFSET := Vector2(-16.0, -4.0)

## Injected by tests; falls back to the autoload.
var automation: Node = null

## ❗️An internal flag, not `visible`: toggling the node would take the bolts with
## it, and the bolts are the part that must survive not being asked for.
var _show_grids := false
## Coverage radius (in tiles) of whatever is in hand, and whether it needs power
## at all. Cached off the inventory signals rather than polled, exactly as
## `mining_cursor.gd` caches the rest of the placement answer.
var _held_radius := 0.0
var _held_demand := 0.0


func _ready() -> void:
	top_level = true # Draw in world space, unaffected by the parent transform.
	z_index = Z_INDEX
	if automation == null:
		automation = Automation
	var inventory := Items.player_inventory
	inventory.selected_changed.connect(_on_selection_changed)
	inventory.slot_changed.connect(_on_slot_changed)
	_refresh_held()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_power_overlay"):
		_show_grids = not _show_grids


## Public so a test (and the F3 panel, if it ever grows a row) can drive the
## toggle without synthesising input.
func toggle_grids() -> void:
	_show_grids = not _show_grids


func grids_shown() -> bool:
	return _show_grids


func _process(_delta: float) -> void:
	# Tracks camera motion as well as the sim: the cull depends on the view rect,
	# so a redraw is needed whenever there is anything at all to draw.
	if _show_grids or _showing_coverage() or not automation.machines().is_empty():
		queue_redraw()


## Existing coverage appears while a power-relevant item is in hand — a furnace
## as much as a generator, because "will this land powered" is the question you
## are asking while you look for somewhere to put it.
func _showing_coverage() -> bool:
	return _held_radius > 0.0 or _held_demand > 0.0


func _on_selection_changed(_index: int) -> void:
	_refresh_held()


## A slot edit only matters when it changes what is IN HAND — mining the last of
## a stack changes it without the selection moving.
func _on_slot_changed(index: int) -> void:
	if index == Items.player_inventory.selected_slot:
		_refresh_held()


func _refresh_held() -> void:
	var item: Dictionary = Items.player_inventory.selected_item()
	var id: String = item.get("id", "")
	_held_radius = Player.placement_power_radius(id)
	_held_demand = Player.placement_power_demand(id)


func _draw() -> void:
	# Same view-rect derivation as slot_overlay.gd, grown a tile so a bolt at the
	# edge does not blink out.
	var view: Rect2 = (
		get_viewport().get_canvas_transform().affine_inverse()
		* get_viewport().get_visible_rect()
	).grow(TILE)
	if _show_grids or _showing_coverage():
		_draw_coverage(view)
	_draw_bolts(view)


## Every emitter's disc, filled dim and outlined, coloured by its GRID rather
## than by its own index — two generators that merged read as one colour, which
## is the whole question the overlay exists to answer.
func _draw_coverage(view: Rect2) -> void:
	var grid: PowerGrid = automation.power_grid()
	if grid == null:
		return
	var font := ThemeDB.fallback_font
	var emitters: Array[PowerEmitter] = automation.emitters()
	for i in emitters.size():
		if i >= grid.emitter_count():
			break # A placement this frame, before the next tick rebuilt the graph.
		var centre := grid.centre_of(i)
		var radius := grid.radius_of(i)
		# Cull on the disc's own bounds, not its centre: a circle whose edge
		# crosses the screen is exactly the one worth seeing.
		if not view.intersects(Rect2(centre - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)):
			continue
		var component := grid.component_of(i)
		var color := GRID_COLORS[component % GRID_COLORS.size()]
		draw_circle(centre, radius, Color(color, DISC_FILL_ALPHA))
		draw_arc(centre, radius, 0.0, TAU, DISC_SEGMENTS, Color(color, DISC_LINE_ALPHA), 1.0)
		# The readout is the toggle's own half: it answers "why is this browning
		# out", which is not a question you have while placing a belt.
		if not _show_grids:
			continue
		var generator := emitters[i] as Generator
		if generator == null:
			continue
		draw_string(
			font,
			centre + LABEL_OFFSET,
			(
				"%.1f/%.1f  %s"
				% [
					grid.supply_of(component),
					grid.demand_of(component),
					"DRY" if generator.burn_left() <= 0 else "burn %d" % generator.burn_left(),
				]
			),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			LABEL_SIZE,
			color,
		)


## ❗️Drawn for a machine that is dead OR slowed, and for nothing else. A bolt
## over a healthy machine would put an icon on every machine in the factory
## forever, which is a screen you stop reading — the signal is the exception, and
## it persists for exactly as long as the exception does.
func _draw_bolts(view: Rect2) -> void:
	for machine: Deployable in automation.machines():
		if machine.power_demand <= 0.0:
			continue
		var powered := machine.is_powered()
		var ratio := machine.power_ratio()
		if powered and ratio >= 1.0:
			continue
		var centre := (Vector2(machine.cell()) + Vector2(machine.size) * 0.5) * TILE
		if not view.has_point(centre):
			continue
		_draw_bolt(centre, UNPOWERED_COLOR if not powered else BROWNOUT_COLOR)


func _draw_bolt(centre: Vector2, color: Color) -> void:
	_draw_shape(centre, BOLT_UPPER, color)
	_draw_shape(centre, BOLT_LOWER, color)


func _draw_shape(centre: Vector2, shape: Array[Vector2], color: Color) -> void:
	var points := PackedVector2Array()
	for point: Vector2 in shape:
		points.append(centre + point * BOLT_SIZE)
	draw_colored_polygon(points, color)
