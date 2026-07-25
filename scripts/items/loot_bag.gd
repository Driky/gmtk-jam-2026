## What a death leaves behind: the slots the player was carrying outside the
## hotbar, dropped where they fell and retrievable by walking back.
##
## Deliberately NOT a pickup per item — a full inventory would spray 30 of them
## across a mob-filled trench. One bag, one walk back, whole haul.
## Persists forever: a bag that despawned would turn a bad death into a lost
## run, and the Core (not the player) is the loss condition.
## Owning doc: docs/systems/player-combat.md
class_name LootBag
extends Node2D

const TILE := TileLayout.TILE_SIZE
const GRAVITY := 600.0
const MAX_FALL_SPEED := 400.0
const HALF_SIZE := 5.0
## Bigger than a pickup's 12 px: this is a deliberate walk-back, so it should
## never feel like you're hunting the exact pixel.
const COLLECT_RADIUS := 20.0

## Slots as {id, count} dicts, exactly as taken from the inventory.
var contents: Array[Dictionary] = []

var _velocity := Vector2.ZERO
var _player: Node2D = null


## Call before add_child.
func setup(slots: Array[Dictionary]) -> void:
	contents = slots


func _physics_process(delta: float) -> void:
	_fall(delta)
	_try_collect()


## Same manual settle as pickup.gd — no physics body, so a bag left on a mob
## route costs nothing while the wave runs over it.
func _fall(delta: float) -> void:
	_velocity.y = minf(_velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	var next := position + _velocity * delta
	var foot_cell := Vector2i((Vector2(next.x, next.y + HALF_SIZE) / TILE).floor())
	if _velocity.y > 0.0 and Terrain.is_solid(foot_cell):
		next.y = foot_cell.y * TILE - HALF_SIZE
		_velocity = Vector2.ZERO
	position = next


## Hands back everything that fits and keeps the rest — same contract as
## pickup.gd, so recovering a bag with a full inventory doesn't delete items.
func _try_collect() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player")
		if _player == null:
			return
	# ❗️A corpse must not collect. The bag drops at the player's own feet and
	# the body stays there for the whole respawn timer, so without this the bag
	# is handed straight back on the next physics frame and dying costs nothing.
	if _player.has_method(&"is_dead") and _player.is_dead():
		return
	if global_position.distance_to(_player.global_position) > COLLECT_RADIUS:
		return
	var leftover: Array[Dictionary] = []
	for slot in contents:
		var remaining: int = Items.player_inventory.add_item(slot.id, slot.count)
		if remaining > 0:
			leftover.append({ id = slot.id, count = remaining })
	contents = leftover
	if contents.is_empty():
		queue_free()
