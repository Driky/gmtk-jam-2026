## Hovered-tile feedback: outline (white = actionable, red = rejected) plus a
## damage-ratio fill. Doubles as the buffer-rejection cue until the HUD (1.7).
## Owning doc: docs/systems/player-combat.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
const OK_COLOR := Color.WHITE
const REJECT_COLOR := Color(1.0, 0.25, 0.25)
## A hovered deployable reads differently from a hovered tile: amber and a
## thicker outline, because swinging at it takes it back rather than mining it.
const DEPLOYABLE_COLOR := Color(1.0, 0.8, 0.35)
const DEPLOYABLE_WIDTH := 2.0

var _target := Vector2i(-1, -1)
var _ratio := 0.0

@onready var _player: Player = get_parent()


func _ready() -> void:
	top_level = true # Draw in world space, unaffected by the player transform.
	Terrain.tile_damaged.connect(_on_tile_damaged)
	Terrain.tile_changed.connect(_on_tile_changed)


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


func _draw() -> void:
	var actionable: bool = _player.in_reach(_target) and Terrain.can_player_edit(_target)
	var color := OK_COLOR if actionable else REJECT_COLOR
	var width := 1.0
	var ratio := _ratio
	# `as Deployable`, so the Core is never advertised as something you can take
	# back — it is a plain Node2D and deliberately not one of these.
	var deployable := Terrain.get_entity(_target) as Deployable
	if deployable != null and actionable:
		color = DEPLOYABLE_COLOR
		width = DEPLOYABLE_WIDTH
		ratio = deployable.removal_ratio()
	draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * TILE), color, false, width)
	if ratio > 0.0:
		var fill := Color(color, 0.35)
		draw_rect(Rect2(0.0, TILE * (1.0 - ratio), TILE, TILE * ratio), fill)
