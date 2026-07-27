## Slot-based item storage: {id, count} per slot, 40 by default, hotbar = 0-9.
## Pure data model — HUD (1.7) and character screen (3.6) bind the signals.
## Owning doc: docs/systems/player-combat.md
class_name Inventory
extends RefCounted

signal slot_changed(index: int)
signal selected_changed(index: int)

## The PLAYER's size, and the default. A container authors its own — 3.5c's chest
## is the first, at 20 — so every N-slot store in the game is this one model
## rather than a second hand-rolled shape.
const SLOT_COUNT := 40
const STACK_SIZE := 99
const HOTBAR_SIZE := 10

## Each slot is {} (empty) or { id: String, count: int }.
var _slots: Array[Dictionary] = []

var selected_slot := 0:
	set(value):
		var clamped := clampi(value, 0, HOTBAR_SIZE - 1)
		if clamped == selected_slot:
			return
		selected_slot = clamped
		selected_changed.emit(selected_slot)


func _init(slot_count := SLOT_COUNT) -> void:
	_slots.resize(slot_count)
	for i in slot_count:
		_slots[i] = { }


## The size this instance was built at. Every loop below walks it rather than
## `SLOT_COUNT`, so a 20-slot chest cannot read or write past its own end.
func slot_count() -> int:
	return _slots.size()


## Fills existing stacks first, then empty slots. Returns the leftover count
## that did not fit (0 = fully added).
func add_item(id: String, count: int) -> int:
	return add_item_in_range(id, count, 0, _slots.size())


## `add_item` bounded to `[from, to)`, and the ONE stacking implementation —
## `add_item` is this call over the whole array.
##
## ⚠️ The range is not a convenience. `add_item` starts at slot 0, so a
## shift-click *out of* the hotbar would merge straight back into the hotbar
## stack it just left ([ui.md](../../docs/systems/ui.md) §Character screen). Out
## of bounds is clamped rather than an error, the way `take_range` clamps.
func add_item_in_range(id: String, count: int, from: int, to: int) -> int:
	var begin := maxi(from, 0)
	var end := mini(to, _slots.size())
	var remaining := count
	for i in range(begin, end):
		if remaining <= 0:
			break
		var slot := _slots[i]
		if slot.is_empty() or slot.id != id or slot.count >= STACK_SIZE:
			continue
		var moved: int = mini(remaining, STACK_SIZE - slot.count)
		slot.count += moved
		remaining -= moved
		slot_changed.emit(i)
	for i in range(begin, end):
		if remaining <= 0:
			break
		if not _slots[i].is_empty():
			continue
		var moved := mini(remaining, STACK_SIZE)
		_slots[i] = { id = id, count = moved }
		remaining -= moved
		slot_changed.emit(i)
	return remaining


## Returns how many were actually removed; clears the slot at count 0.
func remove_from_slot(index: int, count: int) -> int:
	var slot := _slots[index]
	if slot.is_empty():
		return 0
	var removed: int = mini(count, slot.count)
	slot.count -= removed
	if slot.count <= 0:
		_slots[index] = { }
	slot_changed.emit(index)
	return removed


## Empty slots [from, to) and return what was in them, in slot order. The death
## drop (2.5) uses it to move everything outside the hotbar into a loot bag, and
## a chest's `take_cargo` (3.5c) empties itself with it — the returned dicts are
## detached copies, safe to hand straight to the bag or the pop-to-pickup drop.
func take_range(from: int, to: int) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	for i in range(maxi(from, 0), mini(to, _slots.size())):
		if _slots[i].is_empty():
			continue
		taken.append(_slots[i].duplicate())
		_slots[i] = { }
		slot_changed.emit(i)
	return taken

# --- The held-stack API (3.6a) -----------------------------------------------
#
# ❗️**Every call below is TOTAL**: the sum of `count` over (all slots + whatever
# the caller is holding) is unchanged by it. `put_in_slot` returning the residue
# is what makes that true, and it is the invariant the character screen's
# conservation tests pin ([ui.md](../../docs/systems/ui.md) §Character screen).
#
# ❗️**Every dict handed out is DETACHED**, copying what `take_range` already did.
# `get_slot` hands back the live dict and `add_item` grows it in place, so a UI
# that parked `get_slot(i)` on the cursor would get free items every time a pickup
# magnets in — `pickup.gd` and `loot_bag.gd` both route through `add_item`.
#
# ❗️**There is deliberately no `set_slot(index, stack)`.** It cannot be total,
# and it is the one signature that makes that dupe reachable again.
#
# ❗️**Each writes `_slots` completely, THEN emits.** `slot_changed` fires
# synchronously into three listeners, one of which (`Player._on_slot_changed`)
# frees and re-instantiates the swing hitbox — emitting mid-swap would show them
# a world where the item exists twice or not at all.


## The whole stack at `index`, removed and detached. `{}` when the slot is empty.
func take_slot(index: int) -> Dictionary:
	var slot := _slots[index]
	if slot.is_empty():
		return { }
	var taken := slot.duplicate()
	_slots[index] = { }
	slot_changed.emit(index)
	return taken


## Up to `count` from `index`, removed and detached — the RMB one-or-half split.
## `{}` when there was nothing to take.
func take_from_slot(index: int, count: int) -> Dictionary:
	if count <= 0:
		return { }
	var slot := _slots[index]
	if slot.is_empty():
		return { }
	var moved: int = mini(count, slot.count)
	var taken := { id = slot.id, count = moved }
	if moved >= slot.count:
		_slots[index] = { }
	else:
		# A FRESH dict rather than `slot.count -= moved`: the remainder must not be
		# the same object anything else could still be holding.
		_slots[index] = { id = slot.id, count = slot.count - moved }
	slot_changed.emit(index)
	return taken


## Put `stack` into `index` and return **what the caller still holds**: `{}` when
## it all went in, the overflow on a merge, the displaced stack on a swap, and the
## whole thing back untouched when a full same-id slot can take nothing.
func put_in_slot(index: int, stack: Dictionary) -> Dictionary:
	if stack.is_empty():
		return { }
	var slot := _slots[index]
	if slot.is_empty():
		# Clamped even here, so an oversized stack cannot be parked past
		# STACK_SIZE by going through the cursor.
		var placed: int = mini(stack.count, STACK_SIZE)
		_slots[index] = { id = stack.id, count = placed }
		slot_changed.emit(index)
		if placed >= stack.count:
			return { }
		return { id = stack.id, count = stack.count - placed }
	if slot.id == stack.id:
		var moved: int = mini(stack.count, STACK_SIZE - slot.count)
		if moved <= 0:
			return stack # Full: nothing moved, so nothing is emitted either.
		_slots[index] = { id = slot.id, count = slot.count + moved }
		slot_changed.emit(index)
		if moved >= stack.count:
			return { }
		return { id = stack.id, count = stack.count - moved }
	var displaced := slot.duplicate()
	_slots[index] = stack.duplicate()
	slot_changed.emit(index)
	return displaced


## Read-only view; {} when empty.
##
## ❗️**This is the LIVE dict, not a copy**, and `add_item` grows it in place — so
## a caller that keeps it does not have a snapshot, it has a window onto a slot
## that changes under it. Read it and forget it; to hold a stack, `take_slot`.
func get_slot(index: int) -> Dictionary:
	return _slots[index]


## Live like `get_slot`, and aliased identically — read it, don't keep it.
func selected_item() -> Dictionary:
	return _slots[selected_slot]


func consume_selected(count := 1) -> bool:
	var slot := _slots[selected_slot]
	if slot.is_empty() or slot.count < count:
		return false
	return remove_from_slot(selected_slot, count) == count


func count_of(id: String) -> int:
	var total := 0
	for slot in _slots:
		if not slot.is_empty() and slot.id == id:
			total += slot.count
	return total
