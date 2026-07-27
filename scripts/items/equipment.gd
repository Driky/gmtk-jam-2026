## What the player is WEARING: 8 slots, 5 armor + 3 accessories, one item id each.
## Deliberately no tool or weapon slot — LMB is locked as "use the active hotbar
## item" and every combat number resolves through `Items.selected_stats()`, so a
## weapon slot would be a second source of truth for what you swing
## ([ui.md](../../docs/systems/ui.md) §Character screen).
##
## ❗️**Not an `Inventory` with 8 slots.** `add_item` would cheerfully put a helmet
## in the feet slot from any auto-fill path, and `count_of` / `take_range` would
## then treat worn gear as ordinary cargo a loot bag can take away.
##
## `slot_changed` is deliberately the same shape as `Inventory.slot_changed`, so
## the one `ItemSlot` widget binds either model.
##
## Owning doc: docs/systems/player-combat.md
class_name Equipment
extends RefCounted

signal slot_changed(slot: int)

## The panel's slots. ⚠️ There are TWO ring slots here and only one `RING` on the
## item — see `ItemStats.EquipSlot`.
enum Slot { HELMET, CHEST, LEGS, FEET, BACK, RING_1, RING_2, NECKLACE }

## Authored slot on the item → the panel slot it fits.
##
## ❗️`RING` is absent on purpose: it is the one value that fits TWO slots, so it is
## handled explicitly in `slot_accepts` where an entry here would have to pick one.
## Spelled out rather than derived from the enum ordering, which is a coincidence
## that a reorder would silently break.
const _FITS: Dictionary = {
	ItemStats.EquipSlot.HELMET: Slot.HELMET,
	ItemStats.EquipSlot.CHEST: Slot.CHEST,
	ItemStats.EquipSlot.LEGS: Slot.LEGS,
	ItemStats.EquipSlot.FEET: Slot.FEET,
	ItemStats.EquipSlot.BACK: Slot.BACK,
	ItemStats.EquipSlot.NECKLACE: Slot.NECKLACE,
}

## One item id per slot; "" is empty. Ids rather than `ItemStats`, so this is
## already the shape a save file wants (4.3) and there is one resolution chain.
var _worn: Array[String] = []


func _init() -> void:
	_worn.resize(Slot.size())
	for i in _worn.size():
		_worn[i] = ""


func slot_count() -> int:
	return _worn.size()


## The id worn in `slot`, or "".
func get_item(slot: int) -> String:
	return _worn[slot]


## Wear `id` in `slot` and return the id it **displaced**, "" if the slot was
## empty.
##
## An id this slot does not accept is a no-op returning "" — the caller is
## expected to ask `slot_accepts` first, exactly as placement asks `can_place_at`
## before `_place_scene`. That is what lets the screen refuse a wrong-type drop
## while the cursor keeps its stack ([ui.md](../../docs/systems/ui.md)).
##
## ❗️**An accepted `id` ALWAYS goes in, even when the same id is already worn**,
## and there is deliberately no "you're already wearing that" shortcut. The screen
## consumes one from the cursor and hands the displaced id back; a call that
## silently did nothing while reporting "" would be indistinguishable from an
## empty slot, and the item consumed for it would be gone. One identical repaint
## is the cheaper failure by a mile.
func equip(slot: int, id: String) -> String:
	if not slot_accepts(slot, id):
		return ""
	var displaced := _worn[slot]
	_worn[slot] = id
	slot_changed.emit(slot)
	return displaced


## Take whatever is in `slot` off and return it, "" if it was already empty.
func unequip(slot: int) -> String:
	var worn := _worn[slot]
	if worn == "":
		return ""
	_worn[slot] = ""
	slot_changed.emit(slot)
	return worn


## Armor points across every filled slot — the one number `Player.take_damage`
## reads. Summed on demand rather than cached: eight `stats_for` lookups on a hit
## is nothing, and a cache is a second source of truth to forget to invalidate.
func armor_total() -> float:
	var total := 0.0
	for id in _worn:
		if id != "":
			total += ItemDefs.stats_for(id).armor
	return total


## Would `slot` take `id`? Static and pure, so the screen can ask before it
## commits and a test can sweep every id in the game against every slot.
static func slot_accepts(slot: int, id: String) -> bool:
	if id == "":
		return false
	var wanted: int = ItemDefs.stats_for(id).equip_slot
	if wanted == ItemStats.EquipSlot.RING:
		return slot == Slot.RING_1 or slot == Slot.RING_2
	return _FITS.get(wanted, -1) == slot


## Which slot `id` would go in if dropped on the panel with no slot named — the
## double-click / shift-click target. `-1` for anything unwearable, and RING
## resolves to the first FREE ring slot so a second ring does not evict the first.
func slot_for(id: String) -> int:
	if id == "":
		return -1
	var wanted: int = ItemDefs.stats_for(id).equip_slot
	if wanted == ItemStats.EquipSlot.RING:
		return Slot.RING_1 if _worn[Slot.RING_1] == "" else Slot.RING_2
	return _FITS.get(wanted, -1)
