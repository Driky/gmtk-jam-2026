## A floor tile that hurts whatever stands on it. The cheapest defense there is:
## no power, no ammo, no targeting — just a cell that bites on a timer.
##
## ❗️**Unpowered by design** ([automation.md](../../docs/systems/automation.md)
## §Categories authors Defense's trap that way), which is what makes it the thing
## you can afford before the first generator is up.
##
## ❗️**Enemies only.** A trap that hurts the player is a death with no readable
## cause — nothing on screen ties a hit to a tile — and that is delivered for free
## by feeding `victims` the `enemies` group rather than by a faction check here.
##
## Owning doc: docs/systems/automation.md §Categories → Defense
class_name SpikeTrap
extends Deployable

## Ticks between bites — 10 is 1 s at 10 Hz. Tier lever, all data.
@export var damage_ticks := 10
@export var damage := 4.0

## Injected by tests; fall back to the autoloads.
var automation: Node = null
var waves: Node = null

## ❗️ONE cooldown for the whole trap, not a per-victim table. A spike pit with
## four mobs in it is the case that matters, and a per-victim dictionary is a
## second place for state to live and a second thing to serialize at 4.3 — for a
## distinction the player cannot see.
var _cooldown := 0


func on_placed() -> void:
	_automation().register_machine(self)


func on_removed() -> void:
	_automation().unregister_machine(self)

# --- State (read by the debug overlay and the tests) -------------------------


func cooldown() -> int:
	return _cooldown

# --- Trigger geometry ---------------------------------------------------------


## The world-space box a mob has to be standing in. Its own footprint, no more:
## a trap is meant to be laid in a LINE, so widening the box would make each one
## poach its neighbours' kills and double-count nothing useful.
func trigger_area() -> Rect2:
	return Rect2(Vector2(cell()) * TILE, Vector2(size) * TILE)


## Everything in `area`, from a candidate list. **Static and pure**, so the
## geometry unit-tests with no world at all — the same argument `pick_target` and
## `PowerGrid` make.
##
## ❗️The loop variable is UNTYPED for `pick_target`'s reason: a typed one fails on
## the *assignment* of a freed instance, before the `is_instance_valid` guard in
## the body can run.
static func victims(candidates: Array, area: Rect2) -> Array[Node2D]:
	var caught: Array[Node2D] = []
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		var body := candidate as Node2D
		if body == null:
			continue
		if area.has_point(body.global_position):
			caught.append(body)
	return caught

# --- The tick ----------------------------------------------------------------


## One bite, on a timer, at everything standing on it.
##
## ❗️Unlike the turret, an idle poll DOES spend the cooldown here, and that is the
## right call rather than an inconsistency: a trap has no aim and no ammo, so
## "ready the instant something steps on it" is what a player expects a spike pit
## to be. The turret's rule exists because its rate of fire is a stat; a trap's is
## a rearm.
func on_tick(_terrain: Node) -> void:
	# A no-op returning true at demand 0. ❗️Called anyway, so a powered variant
	# later is a number in a .tscn rather than a change to this file.
	if not spend_power_tick():
		return
	_cooldown = maxi(_cooldown - 1, 0)
	if _cooldown > 0:
		return
	var caught := victims(_waves().enemies(), trigger_area())
	if caught.is_empty():
		return
	# freed-safe: `caught` was built and validity-filtered by `victims()` two lines up,
	# in this same call — it cannot outlive a frame boundary.
	for victim: Node2D in caught:
		# Attributed to the trap, so it draws threat and mobs stop to chew it —
		# the torch precedent, and why a trap has HP worth authoring
		# ([enemies.md](../../docs/systems/enemies.md) §Aggro).
		victim.take_damage(damage, self)
	_cooldown = damage_ticks

# --- Internals ---------------------------------------------------------------


func _automation() -> Node:
	if automation == null:
		automation = Automation
	return automation


func _waves() -> Node:
	if waves == null:
		waves = Waves
	return waves
