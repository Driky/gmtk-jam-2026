## Hovered-tile feedback plus the placement ghost. Three things it draws, in
## precedence order: a hovered deployable in reach (amber, thick — swinging
## takes it back rather than mining it) · the W×H ghost of whatever placeable
## item is selected, **with a translucent preview of the item inside it** (green
## when the placement would be accepted, red when not) · otherwise the plain
## hovered-tile outline with its damage-ratio fill.
##
## ❗️The item preview is not decoration. A footprint box alone is identical to
## the mining cursor at 1×1 — only the colour differs — so the ghost read as
## "the cursor turned green" rather than "here is your torch", and the W×H part
## that justifies the whole feature stays invisible until 3.3 ships a multi-cell
## machine. The preview reuses the scene's own `ColorRect`, so it cannot drift
## from what actually gets placed.
##
## A harvesting placeable (3.3's miner) draws a **second, dimmer outline** for
## its harvest block, one span along the pending facing. Without it a 3×2 whose
## ore block sits three cells to the left is unreadable, and "point the arrow at
## the ore" — the whole placement rule — is invisible.
##
## ❗️The ghost is **modeless**: there is no toggle and no binding, it simply
## draws whenever the selected hotbar item is placeable. And it lives here
## rather than in a node of its own — this one is already `top_level`, already
## polls the player's target tile, and already owns the other two outlines. A
## second node drawing on the same cell is visual mush plus a duplicate copy of
## the reach rule that would drift from this one.
##
## Owning doc: docs/systems/player-combat.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
const OK_COLOR := Color.WHITE
const REJECT_COLOR := Color(1.0, 0.25, 0.25)
## A hovered deployable reads differently from a hovered tile: amber and a
## thicker outline, because swinging at it takes it back rather than mining it.
const DEPLOYABLE_COLOR := Color(1.0, 0.8, 0.35)
const DEPLOYABLE_WIDTH := 2.0
## Green rather than white, so "this will go down here" never reads as "this is
## the tile you are about to mine".
const GHOST_COLOR := Color(0.4, 1.0, 0.45)
const GHOST_FILL_ALPHA := 0.22
## The item preview inside the ghost. Solid enough to read as the thing you are
## about to place, translucent enough that it can't be mistaken for a placed one.
const GHOST_ITEM_ALPHA := 0.55
const RATIO_FILL_ALPHA := 0.35
## Facing arrow for a directional placeable (conveyor, inserter). Sized as a
## fraction of the footprint so it reads at 1×1 and does not swamp a 1-cell
## ghost, and drawn in the SAME validity colour as the outline — a second colour
## here would read as a second signal.
## The harvest block outline (3.3's miner). Dimmer than the footprint's, in the
## same validity colour: it marks where the ore has to be, not a second thing
## being placed.
const HARVEST_OUTLINE_ALPHA := 0.45
const ARROW_LENGTH := 0.34
const ARROW_HEAD := 0.16
const ARROW_WIDTH := 2.0

var _target := Vector2i(-1, -1)
var _ratio := 0.0
## ZERO = the selected item is not placeable, so no ghost. Cached off the
## inventory signals rather than polled: selected_item() allocates a Dictionary
## and this would otherwise run every frame.
var _ghost_size := Vector2i.ZERO
var _ghost_dirs := Deployable.SUPPORT_ALL
## Translucent preview of the item itself, in cell-local space. A zero size means
## nothing to preview. Without this a 1×1 ghost is indistinguishable from the
## mining cursor — only the colour differs — so the footprint box alone reads as
## "the cursor turned green" rather than "here is your torch".
var _ghost_item := Rect2()
var _ghost_item_color := Color.WHITE
## Draw a facing arrow? True for a conveyor or an inserter, false for a torch or
## a block. Cached alongside the rest of the placement answer.
var _ghost_directional := false
## Does this placement need a deposit under its harvest block (3.3's miner)?
## Cached with the rest, and drawn as a second, dimmer outline — a 3×2 whose
## harvest block sits three cells to the left is unreadable without it, and the
## whole placement rule is "point the arrow at the ore".
var _ghost_harvests := false

@onready var _player: Player = get_parent()


func _ready() -> void:
	top_level = true # Draw in world space, unaffected by the player transform.
	Terrain.tile_damaged.connect(_on_tile_damaged)
	Terrain.tile_changed.connect(_on_tile_changed)
	var inventory := Items.player_inventory
	inventory.selected_changed.connect(_on_selection_changed)
	inventory.slot_changed.connect(_on_slot_changed)
	_refresh_placement()


func _process(_delta: float) -> void:
	var target: Vector2i = _player.target_tile()
	if target != _target:
		_target = target
		_ratio = 0.0
	position = Vector2(_target) * TILE
	queue_redraw()


func _on_tile_damaged(pos: Vector2i, ratio: float) -> void:
	if pos == _target:
		_ratio = clampf(ratio, 0.0, 1.0)


func _on_tile_changed(pos: Vector2i) -> void:
	if pos == _target:
		_ratio = 0.0


func _on_selection_changed(_index: int) -> void:
	_refresh_placement()


## A slot edit only matters when it changes what is IN HAND — mining a stack of
## dirt fires this on every break.
func _on_slot_changed(index: int) -> void:
	if index == Items.player_inventory.selected_slot:
		_refresh_placement()


func _refresh_placement() -> void:
	var item: Dictionary = Items.player_inventory.selected_item()
	var id: String = item.get("id", "")
	_ghost_size = Player.placement_size(id)
	_ghost_dirs = Player.placement_support_dirs(id)
	_ghost_directional = Player.placement_directional(id)
	_ghost_harvests = Player.placement_harvests(id)
	_ghost_item = Rect2()
	if _ghost_size == Vector2i.ZERO:
		return
	var scene := Items.stats_for(id).place_scene
	if scene != null:
		var visual := Deployable.scene_visual(scene)
		if not visual.is_empty():
			# setup() anchors a deployable at its footprint CENTRE, so the
			# authored rect is relative to that, not to the origin cell.
			var centre := Vector2(_ghost_size) * 0.5 * TILE
			_ghost_item = Rect2(centre + visual.rect.position, visual.rect.size)
			_ghost_item_color = visual.color
		return
	# A block has no scene, so it previews as the tile it is about to become —
	# the same base_color a pickup of it is tinted with.
	var material: Dictionary = Materials.MATERIALS.get(id, { })
	_ghost_item = Rect2(Vector2.ZERO, Vector2.ONE * TILE)
	_ghost_item_color = material.get("base_color", Color.WHITE)


func _draw() -> void:
	var actionable: bool = _player.in_reach(_target) and Terrain.can_player_edit(_target)
	# `as Deployable`, so the Core is never advertised as something you can take
	# back — it is a plain Node2D and deliberately not one of these.
	var deployable := Terrain.get_entity(_target) as Deployable
	if deployable != null and actionable:
		_draw_target(DEPLOYABLE_COLOR, DEPLOYABLE_WIDTH, deployable.removal_ratio())
		return
	if _ghost_size != Vector2i.ZERO:
		_draw_ghost()
		# Mining feedback survives the ghost: LMB still digs with a block in
		# hand, and losing the chip fill would read as the swing doing nothing.
		if _ratio > 0.0:
			_draw_ratio_fill(OK_COLOR, _ratio)
		return
	_draw_target(OK_COLOR if actionable else REJECT_COLOR, 1.0, _ratio)


func _draw_target(color: Color, width: float, ratio: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * TILE), color, false, width)
	if ratio > 0.0:
		_draw_ratio_fill(color, ratio)


func _draw_ratio_fill(color: Color, ratio: float) -> void:
	draw_rect(
		Rect2(0.0, TILE * (1.0 - ratio), TILE, TILE * ratio),
		Color(color, RATIO_FILL_ALPHA),
	)


## Three layers: the translucent item, then the per-cell validity tint over it
## (so a 2×3 also reads as six grid cells), then the outline.
##
## ❗️Validity is drawn ON TOP of the item, not under it. A block previews as a
## full cell of its own colour, which buried the green/red underneath it — and
## "can I put it here" has to survive whatever the item happens to look like.
##
## Validity is the same `can_place_at` the click runs, with the same reach test,
## so the ghost can never promise something the click then refuses. The preview
## draws whether or not the spot is valid: you should be able to see what you
## are carrying while you look for somewhere to put it.
func _draw_ghost() -> void:
	var valid: bool = (
		_player.in_reach(_target)
		and Player.can_place_at(
			Terrain,
			_target,
			_player.tile_rect(),
			_ghost_size,
			_ghost_dirs,
			_player.place_facing,
			_ghost_harvests,
		)
	)
	var color := GHOST_COLOR if valid else REJECT_COLOR
	if _ghost_item.size != Vector2.ZERO:
		draw_rect(_ghost_item, Color(_ghost_item_color, GHOST_ITEM_ALPHA))
	for cell: Vector2i in Deployable.footprint_at(Vector2i.ZERO, _ghost_size):
		draw_rect(
			Rect2(Vector2(cell) * TILE, Vector2.ONE * TILE),
			Color(color, GHOST_FILL_ALPHA),
		)
	draw_rect(Rect2(Vector2.ZERO, Vector2(_ghost_size) * TILE), color, false, 1.0)
	if _ghost_harvests:
		_draw_harvest_block(color)
	if _ghost_directional:
		_draw_facing_arrow(color)


## The block of tiles a miner will eat, one span along the pending facing.
## Dimmer and dashed-thin rather than a second bright box: it is *where the ore
## has to be*, not a second thing being placed. Same validity colour, because it
## is the same answer — the red ghost and the empty harvest block are one
## rejection, and drawing it in a colour of its own would read as two.
func _draw_harvest_block(color: Color) -> void:
	# Asked of the SAME static the placement gate calls, anchored at ZERO because
	# this node is already translated to the target cell. The span rule is not
	# re-derived here — a second copy of it would be a ghost that promises a
	# harvest block the miner does not have.
	var cells := Deployable.harvest_cells_at(Vector2i.ZERO, _ghost_size, _player.place_facing)
	draw_rect(
		Rect2(Vector2(cells[0]) * TILE, Vector2(_ghost_size) * TILE),
		Color(color, HARVEST_OUTLINE_ALPHA),
		false,
		1.0,
	)


## Which way the thing will point once it is down. Read off the PLAYER's pending
## facing — the same value `_place_scene` stamps on the instance — so the arrow
## can no more disagree with the placement than the validity tint can.
func _draw_facing_arrow(color: Color) -> void:
	var extent := Vector2(_ghost_size) * TILE
	var centre := extent * 0.5
	var span: float = minf(extent.x, extent.y)
	var dir := Vector2(_player.place_facing)
	var tip := centre + dir * span * ARROW_LENGTH
	# Perpendicular, for the two head strokes — a filled triangle at this size
	# reads as a blob, where three lines read as an arrow.
	var side := Vector2(-dir.y, dir.x) * span * ARROW_HEAD
	var back := tip - dir * span * ARROW_HEAD
	draw_line(centre - dir * span * ARROW_LENGTH, tip, color, ARROW_WIDTH)
	draw_line(tip, back + side, color, ARROW_WIDTH)
	draw_line(tip, back - side, color, ARROW_WIDTH)
