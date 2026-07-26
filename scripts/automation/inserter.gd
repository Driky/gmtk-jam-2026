## Mandatory machine I/O: picks one item from the cell BEHIND and drops it into
## the cell in FRONT, one swing per transfer. Everything structural is
## `Deployable`'s — this owns a cooldown and the swing.
##
## Owning doc: docs/systems/automation.md
class_name Inserter
extends Deployable

## Ticks between transfers — 5 is 0.5 s at 10 Hz. Tier lever, same shape as the
## belt's `ticks_per_move`. (Whole stacks per swing is the stacking inserter,
## Day 4, and is data on top of this.)
@export var swing_ticks := 5

## Injected by tests; falls back to the autoload.
var automation: Node = null

var _cooldown := 0


func on_placed() -> void:
	_automation().register_inserter(self)


func on_removed() -> void:
	_automation().unregister_inserter(self)


func source_cell() -> Vector2i:
	return _cell - facing


func target_cell() -> Vector2i:
	return _cell + facing


func cooldown() -> int:
	return _cooldown


## One swing, if it is ready and both ends cooperate.
##
## ❗️**A failed insert hands the item BACK to the source rather than dropping
## it.** The inserter extracts before it knows the destination will take it, so a
## refused or partial transfer returns the remainder through the source's own
## `accept_item`. That is safe *precisely because* of the locked tick order:
## inserters run **before** conveyors, so the slot it just emptied has not been
## advanced into and is still free. Two virtuals rather than a third `peek`.
##
## ❗️An idle poll does NOT burn the cooldown. Spending it on a tick where the
## source was empty or the destination full would make the inserter feel laggy
## and, worse, make a chain's throughput depend on *when* the source happened to
## fill. This way it fires on the first tick both ends are ready — and not
## picking up is the whole of back-pressure: the item stays on the source belt and
## the line jams behind it.
##
## The transfer is atomic and the inserter holds nothing between ticks. A held
## item would be a third place an item can live — serialized by 4.3, popped when
## the inserter is removed, reasoned about in the conveyor tie-break — for a
## visual a swinging arm already sells.
func on_tick(terrain: Node) -> void:
	_cooldown = maxi(_cooldown - 1, 0)
	if _cooldown > 0:
		return
	var source := terrain.get_entity(source_cell()) as Deployable
	if source == null:
		return
	var destination := terrain.get_entity(target_cell()) as Deployable
	if destination == null:
		return
	var taken: Dictionary = source.extract_item(1)
	if taken.is_empty():
		return
	var accepted: int = destination.accept_item(taken.id, taken.count)
	if accepted < taken.count:
		# The give-back. A torch, a wall or a full belt all land here, with no type
		# check anywhere — the refusing default on the base is what makes that work.
		source.accept_item(taken.id, taken.count - accepted)
	if accepted > 0:
		_cooldown = swing_ticks

# --- Internals ---------------------------------------------------------------


func _automation() -> Node:
	if automation == null:
		automation = Automation
	return automation
