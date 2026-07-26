## Hovered-tile feedback plus the placement ghost. Three things it draws, in
## precedence order: a hovered deployable in reach (amber, thick — swinging
## takes it back rather than mining it) · the W×H ghost of whatever placeable
## item is selected (green when the placement would be accepted, red when not)
## · otherwise the plain hovered-tile outline with its damage-ratio fill.
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
const RATIO_FILL_ALPHA := 0.35

var _target := Vector2i(-1, -1)
var _ratio := 0.0
## ZERO = the selected item is not placeable, so no ghost. Cached off the
## inventory signals rather than polled: selected_item() allocates a Dictionary
## and this would otherwise run every frame.
var _ghost_size := Vector2i.ZERO
var _ghost_dirs := Deployable.SUPPORT_ALL

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


## The whole footprint, tinted by whether the placement would actually be
## accepted — validity is the same `can_place_at` the click runs, with the same
## reach test, so the ghost can never promise something the click then refuses.
## Per-cell fills rather than one big rect, so a 2×3 reads as six grid cells.
func _draw_ghost() -> void:
	var valid: bool = (
		_player.in_reach(_target)
		and Player.can_place_at(Terrain, _target, _player.tile_rect(), _ghost_size, _ghost_dirs)
	)
	var color := GHOST_COLOR if valid else REJECT_COLOR
	for cell: Vector2i in Deployable.footprint_at(Vector2i.ZERO, _ghost_size):
		draw_rect(
			Rect2(Vector2(cell) * TILE, Vector2.ONE * TILE),
			Color(color, GHOST_FILL_ALPHA),
		)
	draw_rect(Rect2(Vector2.ZERO, Vector2(_ghost_size) * TILE), color, false, 1.0)
