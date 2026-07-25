## Slot-based item storage: 40 slots of {id, count}, hotbar = slots 0-9.
## Pure data model — HUD (1.7) and character screen (3.6) bind the signals.
## Owning doc: docs/systems/player-combat.md
class_name Inventory
extends RefCounted

signal slot_changed(index: int)
signal selected_changed(index: int)

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


func _init() -> void:
	_slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		_slots[i] = { }


## Fills existing stacks first, then empty slots. Returns the leftover count
## that did not fit (0 = fully added).
func add_item(id: String, count: int) -> int:
	var remaining := count
	for i in SLOT_COUNT:
		if remaining <= 0:
			break
		var slot := _slots[i]
		if slot.is_empty() or slot.id != id or slot.count >= STACK_SIZE:
			continue
		var moved: int = mini(remaining, STACK_SIZE - slot.count)
		slot.count += moved
		remaining -= moved
		slot_changed.emit(i)
	for i in SLOT_COUNT:
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
## drop (2.5) uses it to move everything outside the hotbar into a loot bag —
## the returned dicts are detached copies, safe to hand to the bag.
func take_range(from: int, to: int) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	for i in range(maxi(from, 0), mini(to, SLOT_COUNT)):
		if _slots[i].is_empty():
			continue
		taken.append(_slots[i].duplicate())
		_slots[i] = { }
		slot_changed.emit(i)
	return taken


## Read-only view; {} when empty. Callers must not mutate the result.
func get_slot(index: int) -> Dictionary:
	return _slots[index]


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
