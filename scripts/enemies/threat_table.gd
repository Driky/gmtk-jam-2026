## Per-monster aggro bookkeeping: damage received adds threat to the attacker,
## threat decays over time, and the highest entry above a threshold overrides
## the Core as the mob's target. Pure RefCounted so it unit-tests without a
## scene tree. Owning doc: docs/systems/enemies.md
class_name ThreatTable
extends RefCounted

## ❗️Deliberately UNTYPED — do not "improve" this to Dictionary[Node2D, float].
## A typed dictionary validates the key on erase(), and a freed instance fails
## that check: erase() returns false, the entry survives, and Godot prints
## "Attempted to erase an invalid (previously freed?) object instance" every
## time. Since decay() runs per mob per physics frame, one dead attacker would
## spam that forever and never be pruned. Untyped erase handles freed keys fine.
## Every write goes through add_threat(attacker: Node2D), so the key type is
## still enforced where it matters.
var _threat: Dictionary = { }


func add_threat(attacker: Node2D, amount: float) -> void:
	_threat[attacker] = _threat.get(attacker, 0.0) + amount


## Linear decay; entries at zero (or freed attackers) are dropped, so mobs
## naturally resume pushing the Core.
func decay(delta: float, rate: float) -> void:
	for attacker in _threat.keys():
		if not is_instance_valid(attacker) or _threat[attacker] - rate * delta <= 0.0:
			_threat.erase(attacker)
		else:
			_threat[attacker] -= rate * delta


## Highest-threat attacker at or above `threshold`, or null (push the Core).
func top_target(threshold: float) -> Node2D:
	var best: Node2D = null
	var best_threat := threshold
	for attacker in _threat.keys():
		if not is_instance_valid(attacker):
			_threat.erase(attacker)
		elif _threat[attacker] >= best_threat:
			best_threat = _threat[attacker]
			best = attacker
	return best


func reset() -> void:
	_threat.clear()
