## Player: platformer controller, hold-to-mine, block placement, hotbar input.
## Owning doc: docs/systems/player-combat.md
class_name Player
extends CharacterBody2D

signal health_changed(current: float, max_value: float)
signal mana_changed(current: float, max_value: float)
## Died, with the seconds until respawn — the HUD announces off this (4.5
## replaces the banner with a real death screen).
signal died(respawn_seconds: float)
signal respawned

const TILE := TileLayout.TILE_SIZE

const GRAVITY := 1200.0
const MAX_FALL_SPEED := 700.0 ## < 1 tile/frame at 60 fps — no tunneling.
const JUMP_VELOCITY := -370.0 ## ~3.6-tile apex: clears 3, not 4.
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.12
const REACH_RADIUS_PX := 4.5 * TILE ## Player center → tile center.
const COLLISION_EXTENTS := Vector2(6.0, 11.0) ## 12×22 box, fits 1-wide tunnels.
## Physics layer 2 ("player" in project.godot) — restored after a death.
const COLLISION_LAYER_PLAYER := 2

const DEFAULT_HITBOX := preload("res://scenes/combat/swing_hitbox_default.tscn")
## Muzzle distance: clear of the 12×22 body, so a shot never spawns inside the
## tile the player is standing in and dies on frame one.
const MUZZLE_OFFSET_PX := 14.0

## Grace window after any hit. Also what stops a mob's swing and its contact
## damage double-dipping on the same frame — both route through take_damage,
## so one gate covers both.
const INVULN_TIME := 0.6
## Blink cadence while invulnerable. Alpha rather than a hard hide: at 12×22 px
## a vanishing player reads as a glitch, a dimming one reads as invulnerable.
const BLINK_PERIOD := 0.08
const BLINK_ALPHA := 0.3
## Shove taken from a hit. Suppresses input briefly, or the movement code
## rewrites velocity.x the same tick and the hit has no weight.
const HURT_KNOCKBACK := 140.0
const HURT_LIFT := 80.0
const HURT_STUN := 0.15

const LOOT_BAG := preload("res://scenes/loot_bag.tscn")
## Long enough to register the death, short enough that a wave doesn't resolve
## itself without you. The Core is what ends a run, not this.
const RESPAWN_TIME := 3.0
## The hotbar rides along; everything past it goes in the bag. You respawn able
## to dig and fight, and it's the bulk haul that's at risk.
const KEPT_SLOTS := Inventory.HOTBAR_SIZE

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
## Seconds until the active item may be used again — one clock for swings and
## shots alike, because ItemStats.use_cooldown is one knob.
var _use_left := 0.0
## The equipped item's hitbox, instanced on equip (never per swing). It hangs
## directly off the player: the hitbox root aims itself, so there's nothing for
## a mount node to do, and the scene stays free of a child the script owns.
var _hitbox: SwingHitbox = null
var _hitbox_scene: PackedScene = null
var _invuln_left := 0.0
var _stun_left := 0.0
var _blink_left := 0.0
## > 0 while dead. Doubles as the is_dead() flag so there's one source of truth.
var _respawn_left := 0.0

@onready var _visual: ColorRect = $Visual
@onready var _hurtbox: Area2D = $Hurtbox


func _ready() -> void:
	current_hp = Progression.get_stat("max_hp")
	current_mana = Progression.get_stat("max_mana")
	var inventory := Items.player_inventory
	inventory.selected_changed.connect(_on_selection_changed)
	inventory.slot_changed.connect(_on_slot_changed)
	_equip(Items.selected_stats())


func _physics_process(delta: float) -> void:
	Perf.begin(&"player")
	_step(delta)
	Perf.end()


func _step(delta: float) -> void:
	if is_dead():
		_tick_respawn(delta)
		return
	_tick_invulnerability(delta)
	_move(delta)
	_contact_damage()
	_use_left = maxf(_use_left - delta, 0.0)
	if Input.is_action_pressed("mine"):
		_use(delta)
	elif Input.is_action_pressed("place"):
		_place()

# --- Taking damage -----------------------------------------------------------


## Mobs hurt you two ways — a swing when you're in their reach, and simply
## touching them. Both land here, so the grace window keeps them from stacking.
## `attacker` is accepted for symmetry with Enemy.take_damage (and to attribute
## damage later); the player has no threat table to feed.
func take_damage(amount: float, _attacker: Node2D = null) -> void:
	if _invuln_left > 0.0 or is_dead():
		return
	current_hp -= amount
	_invuln_left = INVULN_TIME
	_blink_left = 0.0
	if current_hp <= 0.0:
		_die()


func is_dead() -> bool:
	return _respawn_left > 0.0


## Shove taken from a hit, mirroring Enemy.apply_knockback so both sides of a
## fight read the same. Direction is a raw offset; a zero can't make a NaN.
func apply_knockback(direction: Vector2, strength: float) -> void:
	if strength <= 0.0:
		return
	var away := direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	velocity = Vector2(away.x * strength, -HURT_LIFT)
	_stun_left = HURT_STUN


func is_invulnerable() -> bool:
	return _invuln_left > 0.0


func _tick_invulnerability(delta: float) -> void:
	_stun_left = maxf(_stun_left - delta, 0.0)
	if _invuln_left <= 0.0:
		return
	_invuln_left -= delta
	if _invuln_left <= 0.0:
		_visual.modulate.a = 1.0
		return
	_blink_left -= delta
	if _blink_left <= 0.0:
		_blink_left = BLINK_PERIOD
		_visual.modulate.a = BLINK_ALPHA if _visual.modulate.a >= 1.0 else 1.0

# --- Death & respawn ---------------------------------------------------------


## Drop the haul where you fell, then sit out the respawn timer. The run does
## NOT end here — the Core is the loss condition (plan.md), so the wave keeps
## pushing while you're down, which is the actual cost of dying.
func _die() -> void:
	_respawn_left = RESPAWN_TIME
	velocity = Vector2.ZERO
	_drop_loot_bag()
	visible = false
	# Deferred: _step runs inside physics, and changing collision mid-flush is
	# an error. A corpse must not block mobs or take further hits either way.
	set_deferred(&"collision_layer", 0)
	died.emit(RESPAWN_TIME)


## Everything past the hotbar goes into one bag at the death position. One bag
## rather than N pickups: a full inventory would otherwise spray 30 items
## across whatever killed you.
func _drop_loot_bag() -> void:
	var dropped := Items.player_inventory.take_range(KEPT_SLOTS, Inventory.SLOT_COUNT)
	if dropped.is_empty():
		return
	var bag: Node2D = LOOT_BAG.instantiate()
	bag.setup(dropped)
	bag.global_position = global_position
	get_parent().add_child(bag)


func _tick_respawn(delta: float) -> void:
	_respawn_left -= delta
	if _respawn_left > 0.0:
		return
	_respawn_left = 0.0
	var core := get_tree().get_first_node_in_group(&"core") as Node2D
	if core != null:
		# On top of the Core's anchor cell, feet clear of the surface tile.
		global_position = (Vector2(core.base_cell()) + Vector2(0.5, 0.0)) * TILE - Vector2(0.0, 12.0)
	current_hp = Progression.get_stat("max_hp")
	visible = true
	_visual.modulate.a = 1.0
	set_deferred(&"collision_layer", COLLISION_LAYER_PLAYER)
	# Land on your feet, not in a mob's mouth.
	_invuln_left = INVULN_TIME
	respawned.emit()


## Touching a mob hurts, with no threat required — a wave you can walk through
## unharmed isn't a wave. The mob's own swing (enemies.md) is the other path.
## One hurtbox on the player rather than one per mob keeps this at a single
## Area2D no matter how many are alive.
func _contact_damage() -> void:
	if _invuln_left > 0.0:
		return
	for body: Node2D in _hurtbox.get_overlapping_bodies():
		var enemy := body as Enemy
		if enemy == null:
			continue
		take_damage(enemy.stats.damage, enemy)
		apply_knockback(global_position - enemy.global_position, HURT_KNOCKBACK)
		return


## The one verb behind LMB: use the active hotbar item. A swingable item (tool,
## melee weapon, block, bare hand) mines the hovered tile AND arcs at whatever
## is in front of you — both, always, so there's no targeting rule to infer.
## Mining is continuous per tick; the arc lands on the item's cooldown.
func _use(delta: float) -> void:
	var stats := Items.selected_stats()
	if stats.use_kind == ItemStats.UseKind.SWING:
		_mine(delta, stats)
	if _use_left > 0.0:
		return
	_use_left = stats.effective_cooldown()
	if stats.use_kind == ItemStats.UseKind.SWING:
		_swing(stats)
	else:
		_shoot(stats)


func _swing(stats: ItemStats) -> void:
	if _hitbox == null:
		return
	_hitbox.activate(_aim(), stats.arc_degrees, stats.active_window)


## Ammo and mana costs land with the real weapons (4.2) — the placeholder
## caster is free, so the pooled system gets exercised the way a bow will.
func _shoot(stats: ItemStats) -> void:
	var aim := _aim()
	# Spawn clear of the body so the shot doesn't start inside our own tile.
	ProjectilePool.fire(
		stats.projectile,
		global_position + aim.normalized() * MUZZLE_OFFSET_PX,
		aim,
		Projectile.Faction.PLAYER,
		self,
	)


## Everything the player aims is mouse-relative — one definition so the swing
## arc and a shot can never disagree about where "forward" is.
func _aim() -> Vector2:
	var aim := get_global_mouse_position() - global_position
	return Vector2.RIGHT if aim.is_zero_approx() else aim


## Damage is resolved here rather than in the hitbox: only the swinger knows
## which item swung and what Progression multiplies it by.
func _on_target_hit(body: Node2D) -> void:
	if not body.has_method(&"take_damage"):
		return
	var stats := Items.selected_stats()
	body.take_damage(stats.effective_melee_damage(), self)
	if body.has_method(&"apply_knockback"):
		var away := body.global_position - global_position
		body.apply_knockback(away, stats.effective_knockback())


func _unhandled_input(event: InputEvent) -> void:
	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Items.player_inventory.selected_slot = i
			return


func _move(delta: float) -> void:
	# While stunned, velocity.x is the knockback's — writing input over it would
	# erase the shove on the very tick it lands.
	if _stun_left <= 0.0:
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


func _mine(delta: float, stats: ItemStats) -> void:
	var target := target_tile()
	if not in_reach(target):
		return
	var amount := stats.effective_mining_power() * delta
	Terrain.damage_tile(target, amount, stats.tool_tier, Terrain.Source.PLAYER)


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

# --- Equipment ---------------------------------------------------------------


func _on_selection_changed(_index: int) -> void:
	_equip(Items.selected_stats())


## A slot edit only matters when it changes what's in HAND — mining a stack of
## dirt fires this every break, and reinstancing the hitbox each time would
## cancel a swing mid-sweep.
func _on_slot_changed(index: int) -> void:
	if index == Items.player_inventory.selected_slot:
		_equip(Items.selected_stats())


## Swap the equipped hitbox. Keyed on the SCENE, not the item: switching
## between two items that share the default arc keeps the same instance, so
## cycling the hotbar mid-fight can't interrupt a swing.
func _equip(stats: ItemStats) -> void:
	var scene: PackedScene = stats.hitbox_scene if stats.hitbox_scene != null else DEFAULT_HITBOX
	if scene == _hitbox_scene and _hitbox != null:
		return
	_hitbox_scene = scene
	if _hitbox != null:
		_hitbox.queue_free()
	_hitbox = scene.instantiate()
	_hitbox.target_hit.connect(_on_target_hit)
	add_child(_hitbox)


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
