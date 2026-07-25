## Player: platformer controller, hold-to-mine, block placement, hotbar input.
## Owning doc: docs/systems/player-combat.md
class_name Player
extends CharacterBody2D

signal health_changed(current: float, max_value: float)
signal mana_changed(current: float, max_value: float)

const TILE := TileLayout.TILE_SIZE

const GRAVITY := 1200.0
const MAX_FALL_SPEED := 700.0 ## < 1 tile/frame at 60 fps — no tunneling.
const JUMP_VELOCITY := -370.0 ## ~3.6-tile apex: clears 3, not 4.
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.12
const REACH_RADIUS_PX := 4.5 * TILE ## Player center → tile center.
const COLLISION_EXTENTS := Vector2(6.0, 11.0) ## 12×22 box, fits 1-wide tunnels.

## Equipment seam: tool items (3.6/4.2) replace these with equipped-tool stats.
var tool_tier := 1
var tool_power := 4.0 ## Hardness per second of held mining.

## Combat seam (2.5): damage/spells only mutate these — clamp + HUD notify are
## in the setters. Maxima live in Progression, not here.
var current_hp := 0.0:
	set(value):
		current_hp = clampf(value, 0.0, Progression.get_stat("max_hp"))
		health_changed.emit(current_hp, Progression.get_stat("max_hp"))

var current_mana := 0.0:
	set(value):
		current_mana = clampf(value, 0.0, Progression.get_stat("max_mana"))
		mana_changed.emit(current_mana, Progression.get_stat("max_mana"))

var _coyote := 0.0
var _jump_buffer := 0.0


func _ready() -> void:
	current_hp = Progression.get_stat("max_hp")
	current_mana = Progression.get_stat("max_mana")


func _physics_process(delta: float) -> void:
	Perf.begin(&"player")
	_step(delta)
	Perf.end()


func _step(delta: float) -> void:
	_move(delta)
	if Input.is_action_pressed("mine"):
		_mine(delta)
	elif Input.is_action_pressed("place"):
		_place()


func _unhandled_input(event: InputEvent) -> void:
	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Items.player_inventory.selected_slot = i
			return


func _move(delta: float) -> void:
	velocity.x = Input.get_axis("move_left", "move_right") * Progression.get_stat("move_speed")
	if is_on_floor():
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _coyote > 0.0 and _jump_buffer > 0.0:
		velocity.y = JUMP_VELOCITY
		_coyote = 0.0
		_jump_buffer = 0.0
	move_and_slide()


func _mine(delta: float) -> void:
	var target := target_tile()
	if not in_reach(target):
		return
	var amount: float = tool_power * Progression.get_stat("mining_speed") * delta
	Terrain.damage_tile(target, amount, tool_tier, Terrain.Source.PLAYER)


func _place() -> void:
	var target := target_tile()
	if not in_reach(target):
		return
	var item: Dictionary = Items.player_inventory.selected_item()
	if item.is_empty() or not Materials.MATERIALS.has(item.id):
		return
	if not can_place_at(Terrain, target, tile_rect()):
		return
	var id: String = item.id
	if Items.player_inventory.consume_selected(1):
		Terrain.set_tile(target, id)


func target_tile() -> Vector2i:
	return Vector2i((get_global_mouse_position() / TILE).floor())


func in_reach(pos: Vector2i) -> bool:
	var tile_center := (Vector2(pos) + Vector2(0.5, 0.5)) * TILE
	return tile_center.distance_to(global_position) <= REACH_RADIUS_PX


## Tile-space AABB currently overlapped by the collision box centered at `center`.
static func tile_rect_at(center: Vector2) -> Rect2i:
	# Epsilon keeps a flush edge from claiming the next tile over.
	var top_left := Vector2i(((center - COLLISION_EXTENTS) / TILE).floor())
	var bottom_right := Vector2i(((center + COLLISION_EXTENTS - Vector2(0.01, 0.01)) / TILE).floor())
	return Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)


func tile_rect() -> Rect2i:
	return tile_rect_at(global_position)


## Placement validity. Terrain is injected so tests run on fresh instances.
## Adjacency rule (locked): a placed block must touch a solid tile cardinally.
static func can_place_at(terrain: Node, pos: Vector2i, occupied: Rect2i) -> bool:
	if not terrain.can_player_edit(pos):
		return false
	if terrain.is_solid(pos):
		return false
	if terrain.get_entity(pos) != null:
		return false
	if occupied.has_point(pos):
		return false
	for offset: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if terrain.is_solid(pos + offset):
			return true
	return false
