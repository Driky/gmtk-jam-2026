## Player: platformer controller, hold-to-mine, block placement, hotbar input.
## Owning doc: docs/systems/player-combat.md
class_name Player
extends CharacterBody2D

signal health_changed(current: float, max_value: float)
signal mana_changed(current: float, max_value: float)
## Died, with the seconds until respawn — the HUD announces off this (4.5
## replaces the banner with a real death screen).
signal died(respawn_seconds: float)
## Respawned, and whether it was at a beacon rather than the Core (3.5c). The
## payload exists because the HUD's announcement would otherwise name the Core
## while you stand at a beacon — the WORDING stays in the HUD, the fact is here.
signal respawned(at_beacon: bool)

const TILE := TileLayout.TILE_SIZE

const GRAVITY := 1200.0
const MAX_FALL_SPEED := 700.0 ## < 1 tile/frame at 60 fps — no tunneling.
const JUMP_VELOCITY := -370.0 ## ~3.6-tile apex: clears 3, not 4.
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.12
## Climb rate on a ladder, against a `move_speed` of 110: slower than walking, so
## going up reads as deliberate, fast enough that a 20-rung shaft is not a chore.
const CLIMB_SPEED := 90.0
## How far below the feet the second climb probe sits. 1 px, so Godot's collision
## separation margin — which can leave the feet a hair ABOVE a surface — cannot
## floor the probe into the cell above the rung the player is standing on.
const FOOT_PROBE_PX := 1.0
const REACH_RADIUS_PX := 4.5 * TILE ## Player center → tile center.
const COLLISION_EXTENTS := Vector2(6.0, 11.0) ## 12×22 box, fits 1-wide tunnels.
## Physics layer 2 ("player" in project.godot) — restored after a death.
const COLLISION_LAYER_PLAYER := 2

const DEFAULT_HITBOX := preload("res://scenes/combat/swing_hitbox_default.tscn")
## Muzzle distance: clear of the 12×22 body, so a shot never spawns inside the
## tile the player is standing in and dies on frame one.
const MUZZLE_OFFSET_PX := 14.0
## Reach of the default swing arc (its Area2D sits at x = 20 with a 20×14 box,
## so it lands out to 30 px), plus slack. A mob inside this counts as "in the
## swing" and shields whatever deployable is behind it — see _hit_deployable.
const MELEE_PRECEDENCE_PX := 34.0
## Buffer zones are player-immutable by design (world-gen.md) — the one
## placement rejection that needs saying out loud.
const BUFFER_REJECT_TOAST := "You can't build in the buffer zone"

## Armor at which a hit lands at exactly half strength, and the hardest a hit can
## ever be softened. Both are `# Tuning: 4.6` knobs — the shape is locked
## ([player-combat.md](../../docs/systems/player-combat.md) §Taking damage), the
## numbers are a first pass to be adjusted once the game is feature complete.
const ARMOR_HALF_POINT := 12.0 # Tuning: 4.6
const MIN_DAMAGE_FRACTION := 0.20 # Tuning: 4.6

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

## What `rotate_placement` (R) cycles through, in order. Clockwise on screen,
## which is what "R again" reads as when you are laying a line.
const FACING_CYCLE: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

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

## Facing stamped onto the next directional placement, cycled with R and read by
## the ghost. Held on the PLAYER rather than per item: the pending rotation is a
## property of the hand, so switching hotbar slots keeps it and a whole downward
## conveyor line is one R press, not one per belt.
var place_facing := Vector2i.RIGHT

var _coyote := 0.0
var _jump_buffer := 0.0
## On a ladder right now. ❗️A LATCH, not a per-frame answer: it engages on an
## up/down press inside a climbable cell and holds until you leave the cell, jump
## or take a hit. Without the latch, walking past a ladder on flat ground — or
## brushing one mid-jump — would stick you to it.
var _climbing := false
## Jumped off a ladder and may not re-grab it yet. ❗️EDGE-TRIGGERED, and it has
## no other clear condition on purpose: `_try_climb` engages on a HELD key, so
## without this the frame after a jump re-latches on the `W` you never let go of
## and overwrites the jump at CLIMB_SPEED — you never leave. A key held from
## before the jump has to be released and pressed again.
var _climb_locked := false
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
## Maxima as of the last level-up, so a level can grant exactly the increase.
## Cached here rather than asked of Progression: it reports the NEW maximum by
## the time leveled_up fires, so the delta is unrecoverable otherwise.
var _last_max_hp := 0.0
var _last_max_mana := 0.0
var _blink_left := 0.0
## > 0 while dead. Doubles as the is_dead() flag so there's one source of truth.
var _respawn_left := 0.0

## Read by the light grid (terrain.md §Lighting) — cool, against the torch's
## warm. The player is a source in the group, not a light node: the grid owns
## every light in the game, so there is no per-light cost to manage here.
var light_color := Color(0.85, 0.9, 1.0)

@onready var _visual: ColorRect = $Visual
@onready var _hurtbox: Area2D = $Hurtbox


func _ready() -> void:
	add_to_group(&"light_source")
	current_hp = Progression.get_stat("max_hp")
	current_mana = Progression.get_stat("max_mana")
	_last_max_hp = current_hp
	_last_max_mana = current_mana
	Progression.leveled_up.connect(_on_leveled_up)
	# ❗️**Both signals raise a maximum, so both have to come through the same
	# code.** A skill node lifting `max_hp` outside this path leaves `_last_max_hp`
	# stale, and the next level-up then grants the level's delta PLUS the node's,
	# while the node's own grant never lands as current HP at all.
	Progression.node_unlocked.connect(_on_node_unlocked)
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
	# Gameplay polls Input directly rather than going through the UI, so a click
	# on a debug button would otherwise also swing at the world behind it. One
	# shared predicate rather than an OR that grows a term per screen
	# ([ui.md](../../docs/systems/ui.md) §An open gameplay screen).
	if UiState.blocks_gameplay_actions():
		return
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
	current_hp -= mitigate(amount, Items.equipment.armor_total())
	_invuln_left = INVULN_TIME
	_blink_left = 0.0
	if current_hp <= 0.0:
		_die()


## What `amount` actually costs you at `armor` points of worn equipment
## ([player-combat.md](../../docs/systems/player-combat.md) §Taking damage owns
## the rule). A **pure static**, the `can_place_at` / `Turret.pick_target`
## precedent: this is the part that can be wrong in a way a screenshot hides, so
## it unit-tests with no world at all.
##
## `kept = HALF / (HALF + armor)` — a diminishing percentage, so armor never stops
## reaching but never zeroes a hit either. At 12 armor a hit lands at half.
##
## ❗️**The floor is a FRACTION OF THE INCOMING DAMAGE, not a constant.** Flat
## subtraction clamped to a minimum of 1.0 turns every mob in the game into a
## permanent 1-damage nuisance the moment you are geared, and — the immediate
## breakage — the F3 kill row clears `_invuln_left` and passes `INF`, which only
## stays lethal because `INF * 0.20` is still `INF`.
static func mitigate(amount: float, armor: float) -> float:
	var kept := ARMOR_HALF_POINT / (ARMOR_HALF_POINT + maxf(armor, 0.0))
	return amount * maxf(kept, MIN_DAMAGE_FRACTION)


func is_dead() -> bool:
	return _respawn_left > 0.0


## A level raises the ceiling and current rises by exactly that much — NOT a
## full heal. Healing to full would make leveling a heal button you farm
## mid-wave by mining a few blocks (progression.md).
func _on_leveled_up(_level: int, _points: int) -> void:
	_absorb_max_gain()


## A skill node can raise a maximum too — `conditioning` is `max_hp × 1.1`. It
## goes through the level-up's own code rather than beside it, so the gain is felt
## NOW and the cache stays honest for the next level.
func _on_node_unlocked(_id: String, _level: int) -> void:
	_absorb_max_gain()


## Raise current HP and mana by however much their ceilings just moved, and
## re-cache the ceilings. ⚠️ **The cache refresh is the whole point** and has to
## happen in the same breath as the grant: `Progression` reports the NEW maximum
## by the time either signal fires, so the delta is unrecoverable from anywhere
## else. A gain of zero is a no-op, which is what makes this safe to run on every
## node taken rather than only on the ones that name a maximum.
func _absorb_max_gain() -> void:
	var max_hp := Progression.get_stat("max_hp")
	var max_mana := Progression.get_stat("max_mana")
	current_hp += max_hp - _last_max_hp
	current_mana += max_mana - _last_max_mana
	_last_max_hp = max_hp
	_last_max_mana = max_mana


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
	# Dropped with the velocity: respawning inside a ladder cell must not resume a
	# climb nobody asked for.
	_climbing = false
	_climb_locked = false
	_drop_loot_bag()
	# Also puts the Light child out — a corpse must not keep glowing. That's why
	# there is no light code here; don't "fix" it by reaching into the node.
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


## Where you come back: the nearest beacon to where you fell, else the Core.
##
## ❗️A GROUP QUERY, not a `static var instance` and not most-recently-placed.
## A static would dangle across a run restart — deployables are children of `Main`
## and are freed with the scene reload without `on_removed` ever running, so it
## would need its own `reset_run` hook where a group dies with the scene for free
## (`Automation.reset_run`'s docstring makes the same argument). Most-recent is
## also not stable across [save.md](../../docs/systems/save.md)'s
## restore-in-file-order — the same reason the tick iterates row-major.
##
## And it is the better rule: build beacons across the map and you come back at
## whichever one you died closest to.
##
## Both anchors answer `base_cell()`, so the caller never asks which it got.
## `core.gd` has no `class_name`, hence `Node2D`.
func _respawn_anchor(from: Vector2) -> Node2D:
	# `Turret.pick_target` is the repo's one nearest-selector: a pure static over an
	# untyped, is_instance_valid-filtered loop. `Waves.debug_poke_nearest` already
	# reuses it generically at INF range; a second loop here would be the copy that
	# forgets the freed-instance filter.
	var beacon := Turret.pick_target(get_tree().get_nodes_in_group(&"respawn_beacon"), from, INF)
	if beacon != null:
		return beacon
	return get_tree().get_first_node_in_group(&"core") as Node2D


func _tick_respawn(delta: float) -> void:
	_respawn_left -= delta
	if _respawn_left > 0.0:
		return
	_respawn_left = 0.0
	# ❗️Read BEFORE the move below overwrites it. No `_death_position` member is
	# needed because `_step` returns early while dead, so the corpse has not moved
	# since `_die` — `_drop_loot_bag` already depends on exactly that.
	var anchor := _respawn_anchor(global_position)
	if anchor != null:
		# On top of the anchor's cell, feet clear of the surface tile.
		global_position = (Vector2(anchor.base_cell()) + Vector2(0.5, 0.0)) * TILE - Vector2(0.0, 12.0)
	current_hp = Progression.get_stat("max_hp")
	visible = true
	_visual.modulate.a = 1.0
	set_deferred(&"collision_layer", COLLISION_LAYER_PLAYER)
	# Land on your feet, not in a mob's mouth.
	_invuln_left = INVULN_TIME
	respawned.emit(anchor is RespawnBeacon)


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
		_hit_deployable(Terrain, target_tile())
	else:
		_shoot(stats)


## Un-deploying is the SAME swing that mines tiles and hits mobs, so it works
## with bare hands, a tool, a weapon or a fistful of stone — there is no
## dedicated removal tool to carry, and no extra button to learn. Point at the
## deployable (it highlights) and swing; each one takes a set number of hits.
##
## ❗️**A mob in swing range takes precedence and the deployable takes nothing.**
## That rule is the whole reason removal can live on the busy button at all:
## torches and machines survive a fight you have standing next to them. Tile
## mining is deliberately NOT suppressed — only the deployable is protected.
##
## Terrain and the target cell are both parameters so this unit-tests on a
## fresh instance without a mouse. `as Deployable` rather than a group check is
## what keeps the Core un-removable with no special case anywhere: the Core is a
## plain Node2D and owns its footprint registration itself.
func _hit_deployable(terrain: Node, cell: Vector2i) -> bool:
	if _enemy_in_swing_range():
		return false
	if not in_reach(cell):
		return false
	var deployable := terrain.get_entity(cell) as Deployable
	if deployable == null:
		return false
	if deployable.take_removal_hit():
		# Same exit a mob kill and a lost support take — the deployable finds
		# the spawner itself, so there is one drop path and no caller variant.
		deployable.pop_to_pickup()
	return true


## Generous on purpose: protecting a deployable is the safe wrong answer, and
## losing one mid-fight is the annoying one.
func _enemy_in_swing_range() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Node2D
		if enemy == null:
			continue
		if enemy.global_position.distance_to(global_position) <= MELEE_PRECEDENCE_PX:
			return true
	return false


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
	if event.is_action_pressed("interact"):
		# ⚠️ Gated, matching `mine`/`place` rather than `rotate_placement` and the
		# hotbar keys next door — a third behaviour at one call site would be the
		# thing nobody can remember. It also means E never toggles the panel shut:
		# Esc and `I` close it.
		if not UiState.blocks_gameplay_actions():
			interact(Terrain, target_tile())
		return
	if event.is_action_pressed("rotate_placement"):
		rotate_placement()
		return
	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Items.player_inventory.selected_slot = i
			return


## `E`: open the panel of whatever container is under the cursor and in reach.
## True when one was found. The only verb that is neither use nor place, and it
## exists because LMB already means *un-deploy* on a deployable
## ([ui.md](../../docs/systems/ui.md) §Bindings).
##
## ❗️**Duck-typed on `has_method(&"storage")`, not `as Chest`** — the same argument
## `_hit_deployable` makes for `as Deployable` over a group check: 4.x's next
## container needs no edit here, and this script learns nothing about chests.
##
## The handler lives on the player because the player already owns `target_tile()`,
## `in_reach()` and the `get_entity` idiom; the screen owns no cursor→cell
## conversion and should not learn one. It reaches the screen through a static, so
## there is no node path here either — and it is a no-op with no screen in the tree.
##
## Terrain and the cell are both parameters for the same reason `_hit_deployable`
## takes them: this unit-tests on a fresh instance without a mouse.
func interact(terrain: Node, cell: Vector2i) -> bool:
	if not in_reach(cell):
		return false
	var entity: Node = terrain.get_entity(cell)
	if entity == null or not entity.has_method(&"storage"):
		return false
	CharacterScreen.open_container(entity)
	return true


## Advance the pending placement facing one step round the cycle. Public so a
## test drives it without synthesising input, and so the binding is the only
## thing that would have to change to add a counter-clockwise one.
func rotate_placement() -> void:
	var next := FACING_CYCLE.find(place_facing) + 1
	place_facing = FACING_CYCLE[next % FACING_CYCLE.size()]

# --- Movement input ----------------------------------------------------------
#
# ❗️**Blocking movement is not a guard at the top of `_step`.** Skipping `_move`
# skips the gravity block *and* `move_and_slide()`, so the player freezes in
# mid-air. It has to zero the input READS, which is these three wrappers over five
# sites ([ui.md](../../docs/systems/ui.md) §An open gameplay screen).
#
# ❗️**Skipping this ships the Space bug.** `jump` is Space and a focused `Button`
# consumes `ui_accept`, so pressing Space over a tab button in the character window
# activates it *and* jumps the player.


func _move_axis() -> float:
	return 0.0 if UiState.blocks_movement() else Input.get_axis("move_left", "move_right")


## Both the buffer stamp in `_move` and the one in the climb branch go through here,
## so a screen opened mid-jump cannot leave a buffered press behind either.
func _jump_pressed() -> bool:
	return not UiState.blocks_movement() and Input.is_action_just_pressed("jump")


func _climb_axis() -> float:
	return 0.0 if UiState.blocks_movement() else Input.get_axis("move_up", "move_down")


## The `_climb_locked` release check: a fresh up/down press is what clears the lock,
## and while a screen is open there are no fresh presses.
func _climb_repress() -> bool:
	if UiState.blocks_movement():
		return false
	return Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("move_down")


func _move(delta: float) -> void:
	# While stunned, velocity.x is the knockback's — writing input over it would
	# erase the shove on the very tick it lands.
	if _stun_left <= 0.0:
		velocity.x = _move_axis() * Progression.get_stat("move_speed")
	# Before the gravity block, and it owns velocity.y for the frame when it takes
	# it — the whole of "no gravity while climbing" is this early return.
	if _try_climb(Terrain, delta):
		move_and_slide()
		return
	# A column's top rung reads as ground. Stamping `_coyote` is what makes jumping
	# off a ladder top work through the EXISTING jump path — `is_on_floor()` itself
	# stays false, and `_move` is its only reader, so nothing else notices the floor
	# is virtual.
	if is_on_floor() or _stand_on_climbable(Terrain, delta):
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	if _jump_pressed():
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _coyote > 0.0 and _jump_buffer > 0.0:
		velocity.y = JUMP_VELOCITY
		_coyote = 0.0
		_jump_buffer = 0.0
	move_and_slide()


## Climb a ladder for this frame, or report that we are not on one. True means
## `_move` skips gravity entirely and `velocity.y` is ours.
##
## ❗️**A grid query, not physics.** Deployables carry no collision bodies at all
## (a torch scene is a `Node2D` and a `ColorRect`) and the player's mask only sees
## the tilemap, so there is nothing to detect — this asks the entity dict directly,
## exactly as `loot_bag.gd` asks `Terrain.is_solid` instead of carrying a body.
##
## Terrain is a parameter for the same reason `_hit_deployable` takes one: this
## unit-tests on a fresh instance rather than against the live world.
func _try_climb(terrain: Node, delta: float) -> bool:
	# ❗️A hit knocks you off, and the guard is the same one `velocity.x` has for
	# the same reason: `apply_knockback` writes `velocity.y = -HURT_LIFT`, so an
	# unguarded climb would erase the shove on the very tick it lands. Being
	# knocked off a ladder is also the better feel.
	if _stun_left > 0.0:
		_climbing = false
		return false
	# TWO probes, because one cannot tell "topped out" from "not on a ladder": the
	# centre is the cell you are climbing THROUGH, the feet are the cell you are
	# standing ON. Standing on top of a column only the second one is climbable.
	var on := Deployable.climbable_at(terrain, Vector2i((global_position / TILE).floor()))
	var feet := global_position.y + COLLISION_EXTENTS.y + FOOT_PROBE_PX
	var below := Deployable.climbable_at(
		terrain,
		Vector2i((Vector2(global_position.x, feet) / TILE).floor()),
	)
	# Held while EITHER is true — that is what carries you the last 11 px up and
	# out of a column instead of dropping the latch at the lip.
	if not (on or below):
		if _climbing:
			# ❗️Topped out one pixel above the standing position, still moving up at
			# CLIMB_SPEED. Without this zero you hop ~3 px and settle over several
			# frames; with it `_stand_on_climbable` plants you on the next one.
			velocity.y = 0.0
		_climbing = false
		return false
	var axis := _climb_axis()
	# ❗️A jump has to complete. Only a FRESH press re-grabs, so the key that was
	# already down when you jumped cannot re-latch and cancel it.
	if _climb_locked:
		if not _climb_repress():
			return false
		_climb_locked = false
	if not _climbing:
		if is_zero_approx(axis):
			return false
		# ❗️Standing ON TOP of a column (centre clear, feet on the rung): only DOWN
		# re-grabs. UP would sink you into the rung under your feet, which is the
		# bobbing bug in a new costume. This branch is also the ONLY way back onto a
		# ladder from its top, so it is load-bearing rather than a guard.
		if not on and axis < 0.0:
			return false
		_climbing = true
	# ❗️Decayed HERE too. The early return skips the gravity block, which is where
	# the buffer normally ages out — climb for five seconds after a stray jump
	# press and you would step off the top into an instant buffered jump.
	if _jump_pressed():
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	# Stepping off is the EXISTING coyote + buffer path, which is why jumping off a
	# ladder needs no second jump implementation: hand it a fresh coyote window and
	# let go of the frame.
	_coyote = COYOTE_TIME
	if _jump_buffer > 0.0:
		_climbing = false
		# ⚠️ Does NOT suppress `_stand_on_climbable`: jumping while standing on a
		# column's top rung is an ordinary platform jump that lands you back on it,
		# which is what "reads as ground" means. Going down is `S`.
		_climb_locked = true
		return false
	velocity.y = axis * CLIMB_SPEED
	return true


## Plant the player on top of a column, the way a terrain tile would. True when
## it did, having clamped the feet to the rung's top edge and zeroed `velocity.y`.
##
## ❗️**A grid query, not a one-way collision body**, for the same reason the climb
## is one: deployables carry no collision bodies at all, so a `StaticBody2D` per
## rung would have reversed that decision, needed a new physics layer plus a
## deferred mask toggle, and made EVERY rung a platform — falling down a shaft
## would stop at the first one.
##
## ❗️**Top rung only.** That one extra lookup is the whole of "falling down a
## shaft is never interrupted", on a frame that was already doing one.
##
## Standing still re-satisfies the crossing test every frame (`feet == edge`,
## `velocity.y == 0`), so this holds you there rather than needing an "am I
## standing" flag of its own.
##
## Terrain is a parameter for the same reason `_try_climb` takes one.
func _stand_on_climbable(terrain: Node, delta: float) -> bool:
	# Descending (`S` from the top) must beat standing on it — hence the call
	# order in `_move` — and jumping UP through a column is not landing on it.
	if _climbing or velocity.y < 0.0:
		return false
	var feet := global_position.y + COLLISION_EXTENTS.y
	var next_feet := feet + velocity.y * delta
	var rung := Vector2i((Vector2(global_position.x, next_feet) / TILE).floor())
	var edge := float(rung.y * TILE)
	if feet > edge or next_feet < edge:
		return false
	if not Deployable.climbable_at(terrain, rung):
		return false
	if Deployable.climbable_at(terrain, rung + Vector2i.UP):
		return false
	global_position.y = edge - COLLISION_EXTENTS.y
	velocity.y = 0.0
	return true


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
	if item.is_empty():
		return
	# RMB on a cell that already holds a deployable hands it ONE item instead of
	# failing the placement — the only way to get anything into the factory before
	# 3.3's miner exists, and the reason placement does not simply reject an
	# occupied cell. ✅ The container panel landed at 3.6a on `E`, and this stayed:
	# one click into a belt is faster than opening a screen, and it works on the
	# machines that are not containers at all.
	#
	# Checked before the buffer rule so feeding a machine never toasts: a deployable
	# cannot exist in a buffer zone in the first place, and "you can't build here"
	# would be a lie about what the click was trying to do.
	var occupant := Terrain.get_entity(target) as Deployable
	if occupant != null:
		# ❗️Edge-triggered, and that is not optional. `place` is polled with
		# is_action_pressed every physics frame, so a held RMB would empty a 99-stack
		# into a belt in under two seconds. One click, one item.
		if Input.is_action_just_pressed("place"):
			hand_feed(occupant, item)
		return
	# The buffer rule is the one rejection worth explaining — every other
	# invalid cell (floating, occupied, inside you) is legible from the cursor,
	# but "the world refuses to let you build here" is not (ui.md §Other screens).
	# Checked before validity so the reason is specific rather than generic.
	if WorldConfig.is_in_buffer(target):
		Hud.show_toast(BUFFER_REJECT_TOAST)
		return
	# Data-driven dispatch, following the hitbox_scene precedent: an item that
	# names a scene places that scene, anything else falls through to the block
	# path. Day 3's miner/conveyor/turret are .tres rows, not branches here.
	var stats := Items.stats_for(item.id)
	if stats.place_scene != null:
		_place_scene(Terrain, target, stats.place_scene)
		return
	if not Materials.MATERIALS.has(item.id):
		return
	if not can_place_at(Terrain, target, tile_rect()):
		return
	var id: String = item.id
	if Items.player_inventory.consume_selected(1):
		# Flagged as hand-placed: re-mining your own wall earns no XP on either
		# channel (progression.md).
		Terrain.set_tile(target, id, true)


## Deposit one item from the selected slot into a deployable. True when it went
## in. Whether it fits at all is the deployable's own answer through
## `accept_item` ([automation.md](../../docs/systems/automation.md) §transfer
## seam), so this works on a belt, 3.3's furnace and 3.5's ammo turret alike with
## no branch here — and a torch simply refuses.
##
## ❗️Offer first, consume second. `accept_item` reports how many it took, so a
## refused offer leaves the inventory untouched by construction — where consuming
## first and refunding on refusal is one full-inventory `add_item` away from
## eating the item. The consume cannot itself fail: the caller has already
## established the slot is non-empty.
##
## Public so a test can drive it without synthesising a mouse click.
func hand_feed(occupant: Deployable, item: Dictionary) -> bool:
	if occupant.accept_item(item.id, 1) <= 0:
		return false
	Items.player_inventory.consume_selected(1)
	return true


## Put a placeable scene down at a cell. Validity is `can_place_at` again — the
## same rule blocks get, widened to the deployable's own footprint and mounting
## directions rather than a relaxed copy.
##
## The instance is made FIRST and asked what shape it is: `size` and
## `support_dirs` are authored per scene, so the player never learns a machine's
## dimensions. A rejected placement frees the node, which costs one instantiate
## on a click the player already got wrong.
##
## Order matters and is the reverse of the block path. `set_tile` cannot fail so
## blocks consume first and write second; `register` CAN fail, so the cells are
## claimed first and the item is only consumed once they are ours. A failed
## claim hands the item back instead of eating it, and a failed CONSUME rolls
## the whole footprint back via unregister().
##
## Terrain is a parameter for the same reason `_hit_deployable` takes one: this
## unit-tests on a fresh instance rather than against the live world.
func _place_scene(terrain: Node, cell: Vector2i, scene: PackedScene) -> void:
	var node: Deployable = scene.instantiate()
	# Stamped before anything else looks at the node, so `on_placed()` and every
	# later reader see the facing the ghost was showing. Harmlessly ignored by a
	# non-directional deployable.
	node.facing = place_facing
	node.setup(cell) # Before add_child, per the Core/loot-bag convention.
	if not can_place_at(
		terrain,
		cell,
		tile_rect(),
		node.size,
		node.support_dirs,
		node.facing,
		node.harvests_deposits,
		node.is_climbable,
	):
		node.free()
		return
	if not node.register(terrain):
		node.free()
		return
	if not Items.player_inventory.consume_selected(1):
		node.unregister(terrain)
		node.free()
		return
	# Parent is Main, like _drop_loot_bag — the same canvas as the tilemap.
	get_parent().add_child(node)
	# After add_child, so an override (3.4's power graph) reads a node that is
	# actually in the world rather than one halfway into it.
	node.on_placed()

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


## Placement validity for a W×H footprint anchored at its TOP-LEFT cell.
## Terrain is injected so tests run on fresh instances.
##
## Every cell has to be free, editable and clear of the player; support is one
## question asked of the footprint as a whole, delegated to the SAME static
## predicate the post-mine re-check calls ([automation.md](../../docs/systems/automation.md)),
## so a machine can never be placeable somewhere it would immediately pop.
##
## `size` and `support_dirs` default to a 1×1 that mounts in any direction —
## the block rule, unchanged, so every block call site stays a three-argument
## call and the 2.7 behaviour is preserved by construction. `facing`/`harvests`
## default the same way, so 3.1's five-argument deployable call sites are
## untouched too, and 3.5b's `climbable` joins the same bargain: it is what lets
## a ladder rung stand on the rung below it and nothing else changes.
##
## ❗️`harvests` is ONE generic clause, not a `Miner` type check: a deployable
## that harvests must have at least one deposit in its harvest block, which is
## how "placed on the deposit" is delivered without ever letting a footprint
## cell be solid ([automation.md](../../docs/systems/automation.md)). The player
## still knows nothing about miners — the answer comes off the scene.
static func can_place_at(
		terrain: Node,
		origin: Vector2i,
		occupied: Rect2i,
		size := Vector2i.ONE,
		support_dirs := Deployable.SUPPORT_ALL,
		facing := Vector2i.RIGHT,
		harvests := false,
		climbable := false,
) -> bool:
	for cell: Vector2i in Deployable.footprint_at(origin, size):
		if not terrain.can_player_edit(cell):
			return false
		if terrain.is_solid(cell):
			return false
		if terrain.get_entity(cell) != null:
			return false
		if occupied.has_point(cell):
			return false
	if harvests:
		var harvest := Deployable.harvest_cells_at(origin, size, facing)
		if not Deployable.has_deposit_in(terrain, harvest):
			return false
	return Deployable.is_supported_at(terrain, origin, size, support_dirs, climbable)


## What placing this item id would occupy. `ZERO` means "not placeable at all",
## which is how the ghost knows to draw nothing for a pickaxe — there is no mode
## to toggle, only an answer to this question ([automation.md](../../docs/systems/automation.md)).
##
## The two branches mirror `_place`'s dispatch exactly: a scene placeable wins
## over the material-id block path, and a block is always a 1×1.
static func placement_size(item_id: String) -> Vector2i:
	if item_id == "":
		return Vector2i.ZERO
	var scene := Items.stats_for(item_id).place_scene
	if scene != null:
		return Deployable.scene_size(scene)
	return Vector2i.ONE if Materials.MATERIALS.has(item_id) else Vector2i.ZERO


## Mounting rule for the same item. Blocks keep the cardinal-adjacency default.
static func placement_support_dirs(item_id: String) -> int:
	if item_id == "":
		return Deployable.SUPPORT_ALL
	var scene := Items.stats_for(item_id).place_scene
	if scene == null:
		return Deployable.SUPPORT_ALL
	return Deployable.scene_support_dirs(scene)


## Whether the ghost should show a facing arrow for this item. A block never
## points anywhere, so the two branches mirror `placement_size`'s exactly.
static func placement_directional(item_id: String) -> bool:
	if item_id == "":
		return false
	var scene := Items.stats_for(item_id).place_scene
	return scene != null and Deployable.scene_directional(scene)


## Whether placing this item is gated on a deposit under its harvest block —
## the ghost's third question after size and facing. Same two branches again: a
## block never harvests anything.
static func placement_harvests(item_id: String) -> bool:
	if item_id == "":
		return false
	var scene := Items.stats_for(item_id).place_scene
	return scene != null and Deployable.scene_harvests(scene)


## Whether placing this item puts a climbable down — the ghost's fourth question,
## and the one that decides whether a rung may stand on the rung below it. Same
## two branches again: a block is never climbable.
##
## ❗️Without this the ghost tints red exactly where the click accepts, on every
## rung of a column above the first — the one thing the "ghost validity IS
## `can_place_at`" invariant exists to prevent
## ([player-combat.md](../../docs/systems/player-combat.md) §Placement).
static func placement_is_climbable(item_id: String) -> bool:
	if item_id == "":
		return false
	var scene := Items.stats_for(item_id).place_scene
	return scene != null and Deployable.scene_is_climbable(scene)


## Coverage radius (in TILES) placing this item would emit, `0.0` for anything
## that is not an emitter — the ghost's prospective circle. Same two branches
## again: a block never powers anything.
static func placement_power_radius(item_id: String) -> float:
	if item_id == "":
		return 0.0
	var scene := Items.stats_for(item_id).place_scene
	return 0.0 if scene == null else Deployable.scene_power_radius(scene)


## What placing this item would DRAW off a grid. Read by the power overlay to
## decide whether existing coverage is worth showing: "will this land powered" is
## only a question for something that needs power.
static func placement_power_demand(item_id: String) -> float:
	if item_id == "":
		return 0.0
	var scene := Items.stats_for(item_id).place_scene
	return 0.0 if scene == null else Deployable.scene_power_demand(scene)
