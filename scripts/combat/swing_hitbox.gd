## Root of any swing hitbox scene: the Area2D arc a melee use sweeps through.
##
## Lifecycle is instance-on-equip, enable-on-swing — NEVER instance per swing.
## The equipped item's hitbox hangs off the swinger with monitoring off, so a
## swing costs a property write and a tween, not a scene instantiation on every
## click. This root aims itself, so it needs no separate mount node.
##
## Shape sets are indexed by swing STEP so a combo (roughly: a wide horizontal
## sweep, then a narrow lunge) is a data change — a scene with two shape sets
## and a caller passing step 1. 2.5 always passes 0; the combo system itself
## (input chaining, timing windows) is not in this step.
##
## Overlaps come from POLLING, never body_entered: a swing is ~9 physics frames
## of a reused area, and polling depends on no signal timing while solving the
## already-overlapping-at-frame-0 case for free. Leave `monitorable` alone —
## see the warning in projectile.gd about what setting it false costs.
## Owning doc: docs/systems/player-combat.md
class_name SwingHitbox
extends Node2D

## One hit per target per swing, so a 0.15 s active window can't tick damage
## every physics frame. Payload is the body — the swinger applies the damage,
## because only it knows the item's buffed numbers.
signal target_hit(body: Node2D)

## Each child Area2D is one step's shape set; step N uses the Nth, and a step
## past the end falls back to the last (a 1-area scene works for every step).
@onready var _areas: Array[Area2D] = _collect_areas()

var _active: Area2D = null
var _hit_this_swing: Array[Node2D] = []
var _tween: Tween = null


func _ready() -> void:
	for area in _areas:
		_disable(area)


## Point the arc at `aim_dir` and sweep it through `arc_degrees` over
## `active_window` seconds. Re-entrant: a swing that lands mid-sweep restarts
## cleanly rather than leaving an area monitoring forever.
func activate(aim_dir: Vector2, arc_degrees: float, active_window: float, step := 0) -> void:
	if _areas.is_empty():
		return
	_cancel()
	_active = _areas[mini(step, _areas.size() - 1)]
	_hit_this_swing.clear()

	var aim := aim_dir.angle() if not aim_dir.is_zero_approx() else 0.0
	var half := deg_to_rad(arc_degrees) * 0.5
	rotation = aim - half
	_active.monitoring = true
	_active.visible = true

	# Catches a mob already standing on top of you: its overlap predates the
	# swing, so nothing would announce it.
	_poll.call_deferred()

	_tween = create_tween()
	_tween.tween_property(self, "rotation", aim + half, active_window)
	_tween.tween_callback(_cancel)


func is_swinging() -> bool:
	return _active != null


func _physics_process(_delta: float) -> void:
	if _active != null:
		_poll()


func _poll() -> void:
	if _active == null or not _active.monitoring:
		return
	for body: Node2D in _active.get_overlapping_bodies():
		if body in _hit_this_swing:
			continue
		_hit_this_swing.append(body)
		target_hit.emit(body)


func _cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _active != null:
		_disable(_active)
		_active = null


func _disable(area: Area2D) -> void:
	area.monitoring = false
	area.visible = false


func _collect_areas() -> Array[Area2D]:
	var areas: Array[Area2D] = []
	for child in get_children():
		if child is Area2D:
			areas.append(child as Area2D)
	return areas
