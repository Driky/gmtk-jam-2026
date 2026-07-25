## Dropped-item entity: manual gravity + tile settle, magnet to the player.
## No physics body or Area2D — keeps per-pickup cost near zero on web.
## Owning doc: docs/systems/player-combat.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
const HALF_SIZE := 4.0
const GRAVITY := 600.0
const MAX_FALL_SPEED := 400.0
const MAGNET_RADIUS := 40.0
const MAGNET_SPEED := 200.0
const COLLECT_RADIUS := 12.0

var item_id := ""
var count := 1

var _velocity := Vector2.ZERO
var _player: Node2D


## Call before add_child; tint happens in _ready.
func setup(id: String, item_count: int) -> void:
	item_id = id
	count = item_count
	_velocity = Vector2(randf_range(-40.0, 40.0), randf_range(-120.0, -60.0))


func _ready() -> void:
	var mat: Dictionary = Materials.MATERIALS.get(item_id, { })
	($Visual as ColorRect).color = mat.get("base_color", Color.WHITE)


func _physics_process(delta: float) -> void:
	_fall(delta)
	_magnet(delta)


func _fall(delta: float) -> void:
	_velocity.y = minf(_velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	var next := position + _velocity * delta
	var foot_cell := Vector2i((Vector2(next.x, next.y + HALF_SIZE) / TILE).floor())
	if _velocity.y > 0.0 and Terrain.is_solid(foot_cell):
		next.y = foot_cell.y * TILE - HALF_SIZE
		_velocity = Vector2.ZERO
	position = next


func _magnet(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist <= COLLECT_RADIUS:
		var leftover: int = Items.player_inventory.add_item(item_id, count)
		if leftover == 0:
			queue_free()
		else:
			count = leftover # Inventory full — stays in the world.
	elif dist <= MAGNET_RADIUS:
		global_position += to_player / dist * MAGNET_SPEED * delta
