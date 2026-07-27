## The first thing the player builds that FIGHTS: a 1×1 machine that draws power,
## eats ammo, picks the nearest mob in range and fires the shared projectile
## system at it. Everything structural is `Deployable`'s — this owns one ammo
## slot, one cooldown and the target query.
##
## ❗️**It draws power AND eats ammo**, which is deliberate: power alone makes it
## a free kill zone the moment a generator is up, and ammo alone divorces defense
## from the factory. Needing both is what makes
## `miner → furnace → ammo press → turret` the thing you build.
##
## ❗️**The projectile is read off the AMMO, not authored here.** `ItemStats`
## already carries a `projectile` field, so an ammo tier is a `.tres` pair and
## there is no turret-side table of tiers to keep in sync
## ([progression.md](../../docs/systems/progression.md) §Recipe tiers).
##
## Owning doc: docs/systems/automation.md §Categories → Defense
class_name Turret
extends Deployable

const AutomationScript := preload("res://scripts/automation/automation.gd")

## Spawn point offset along the aim, so the bolt does not appear inside the
## turret's own sprite. Correctness never rests on it — `Projectile` already
## refuses to hit its own `source`.
const MUZZLE_OFFSET_PX := 6.0

## Ticks between shots — 10 is 1 s at 10 Hz. Tier lever, all data, the same shape
## as the miner's `extract_ticks` and the inserter's `swing_ticks`.
@export var fire_ticks := 10
## Reach in TILES, multiplied by `TILE` at the one place the query is made, so no
## reader has to remember which unit it is holding.
@export var range_tiles := 8.0
## What this turret will load. A `PackedStringArray` rather than one id so a
## tier-2 ammo is a row here, not a second script — `Generator.fuel_ids` again.
@export var ammo_ids: PackedStringArray = ["copper_ammo", "iron_ammo"]

## Injected by tests; fall back to the autoloads.
var automation: Node = null
var waves: Node = null
var progression: Node = null

## THE ammo slot: `{}` or `{ id, count }`, byte-identical to a conveyor slot and
## an `Inventory`'s, so ammo reaches it press → belt → inserter → turret with no
## conversion and `Inventory.STACK_SIZE` is the one cap.
var _ammo: Dictionary = { }
var _cooldown := 0
## What it shot at last, for the debug overlay only. Never drives a decision —
## the target is re-picked from scratch every time it fires.
var _target: Node2D = null
## What was handed to the pool, remembered so `on_removed` gives back exactly
## what `on_placed` took rather than recomputing against possibly-edited exports.
var _reserved := 0


func on_placed() -> void:
	_automation().register_machine(self)
	_reserved = reserve_shots()
	ProjectilePool.reserve(_reserved)


func on_removed() -> void:
	_automation().unregister_machine(self)
	ProjectilePool.release(_reserved)
	_reserved = 0

# --- Pool sizing --------------------------------------------------------------


## How many of THIS turret's shots can be in the air at once: one every
## `fire_ticks` for as long as its longest-lived ammo flies, plus the one leaving
## the barrel. Reserved on place, released on remove
## ([player-combat.md](../../docs/systems/player-combat.md) §Projectiles).
##
## ❗️Computed from the authored `ammo_ids` rather than from whatever is loaded,
## because `on_placed` runs before any ammo exists — the reservation has to be
## the worst case over everything this turret could ever fire.
func reserve_shots() -> int:
	var period := maxf(float(fire_ticks) * AutomationScript.TICK_INTERVAL, AutomationScript.TICK_INTERVAL)
	return ceili(_longest_ammo_lifetime() / period) + 1


func _longest_ammo_lifetime() -> float:
	var longest := 0.0
	for id: String in ammo_ids:
		var stats: ProjectileStats = ItemDefs.stats_for(id).projectile
		if stats != null:
			longest = maxf(longest, stats.lifetime)
	return longest

# --- State (read by the debug overlay and the tests) -------------------------


func ammo_slot() -> Dictionary:
	return _ammo


func cooldown() -> int:
	return _cooldown


func target() -> Node2D:
	return _target if is_instance_valid(_target) else null


## ❗️Out of ammo, joining the HUD's idle count beside a miner over bare rock and
## a dry generator — the same "come and feed me" signal, with no type check
## anywhere ([ui.md](../../docs/systems/ui.md) §HUD).
func is_idle() -> bool:
	return _ammo.is_empty()

# --- Target selection ---------------------------------------------------------


## Nearest valid candidate within `range_px`, or null. **Static and pure**, so
## the part that can be wrong in a way a screenshot hides unit-tests with no
## world at all — the argument `PowerGrid` makes for being a solver.
##
## ❗️**Nearest, full stop.** "Highest threat" is incoherent for a turret:
## `ThreatTable` is a *mob's* private list of who to attack, not a targetability
## score, and a turret has no threat toward a mob it has not shot yet.
##
## Candidates are filtered for validity because a freed mob can linger in the
## `enemies` group for a frame ([waves.gd] `enemies`).
##
## ❗️**The loop variable is UNTYPED, and that is not laziness.** A typed
## `for candidate: Node in candidates` fails on the *assignment* — "Trying to
## assign invalid previously freed instance" — before the body's
## `is_instance_valid` guard ever runs, so the guard silently protects nothing.
## Same family as the typed-Dictionary-key trap in `ThreatTable`.
static func pick_target(candidates: Array, from: Vector2, range_px: float) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		var body := candidate as Node2D
		if body == null:
			continue
		var dist := body.global_position.distance_to(from)
		if dist > range_px or dist >= best_dist:
			continue
		best = body
		best_dist = dist
	return best

# --- The transfer seam -------------------------------------------------------


## ❗️**Routes by ID**, exactly as `Generator.accept_item` routes fuel and for the
## same reason: the seam has no port argument. Anything that is not ammo this
## turret can fire is refused outright, so an inserter pointed at a turret by
## mistake jams its own belt instead of filling it with dirt that `extract_item`
## can never reach.
func accept_item(id: String, count: int) -> int:
	if count <= 0 or not ammo_ids.has(id):
		return 0
	if _ammo.is_empty():
		var taken: int = mini(count, Inventory.STACK_SIZE)
		_ammo = { id = id, count = taken }
		return taken
	if _ammo.id != id:
		return 0
	var moved: int = mini(count, Inventory.STACK_SIZE - _ammo.count)
	if moved <= 0:
		return 0
	_ammo.count += moved
	return moved


## `extract_item` stays at the base's REFUSING default, for the generator's
## reason: ammo loaded into a turret is spent, not stored. Taking the turret back
## down is the only way it returns — through `take_cargo`.
func take_cargo() -> Array[Dictionary]:
	var cargo: Array[Dictionary] = []
	if not _ammo.is_empty():
		cargo.append({ id = _ammo.id, count = _ammo.count })
	_ammo = { }
	return cargo

# --- The tick ----------------------------------------------------------------


## One shot, if it is powered, off cooldown, loaded, and something is in range.
##
## ❗️**An idle poll must not burn the cooldown.** The cooldown is only reset on a
## shot that actually happened, so a turret fires on the first tick a mob walks
## into range — the inserter's rule, for the inserter's reason. Otherwise the
## turret's DPS would depend on *when* a mob happened to arrive relative to a
## cooldown that had been ticking against nothing.
##
## A brownout therefore reads as a slower rate of fire, which is the shared
## brownout rule working rather than a special case living here.
func on_tick(_terrain: Node) -> void:
	# ❗️Exactly once per tick, and only here: `spend_power_tick` is the stateful
	# half of the brownout rule ([deployable.gd]).
	if not spend_power_tick():
		return
	_cooldown = maxi(_cooldown - 1, 0)
	if _cooldown > 0:
		return
	_target = null
	if _ammo.is_empty():
		return
	# An ammo id with no ProjectileStats fires nothing rather than crashing, and
	# is checked BEFORE a round is spent — otherwise a bad .tres would silently
	# eat the whole stack.
	var shot: ProjectileStats = ItemDefs.stats_for(_ammo.id).projectile
	if shot == null:
		return
	_target = pick_target(_waves().enemies(), global_position, range_tiles * TILE)
	if _target == null:
		return
	_fire(shot, _target)
	_spend_round()
	_cooldown = fire_ticks

# --- Internals ---------------------------------------------------------------


## Fired through the base's own `faction` — the var 3.1 declared for exactly this
## and nothing had read yet. Threat attribution then comes free: `take_damage`
## adds threat to the attacker, so a turret tanks its own aggro, which is already
## the designed behaviour ([enemies.md](../../docs/systems/enemies.md) §Aggro).
func _fire(shot: ProjectileStats, at: Node2D) -> void:
	var aim := at.global_position - global_position
	var muzzle := global_position + aim.normalized() * MUZZLE_OFFSET_PX
	ProjectilePool.fire(
		shot,
		muzzle,
		aim,
		faction,
		self,
		_progression().get_stat("turret_damage"),
	)


func _spend_round() -> void:
	_ammo.count -= 1
	if _ammo.count <= 0:
		_ammo = { }


func _automation() -> Node:
	if automation == null:
		automation = Automation
	return automation


func _waves() -> Node:
	if waves == null:
		waves = Waves
	return waves


func _progression() -> Node:
	if progression == null:
		progression = Progression
	return progression
