## The first thing in the game that makes an item without the player clicking:
## it eats a deposit's `reserve` into its own output slot every `extract_ticks`,
## and an inserter takes it from there. Everything structural is `Deployable`'s —
## this owns one output slot, one cooldown, and the harvest walk.
##
## ❗️**Its 3×2 footprint stands BESIDE the ore, not on it.** Deposits are solid
## and `Terrain.place_entity` refuses a solid cell, so the machine reaches into a
## harvest block of the same shape one span along `facing` — the arrow points at
## the ore, and placement is gated on finding a deposit there
## ([automation.md](../../docs/systems/automation.md) §Categories).
##
## Owning doc: docs/systems/automation.md
class_name Miner
extends Deployable

## Ticks between extractions — 10 is 1 s at 10 Hz. Tier lever, all data, same
## shape as the belt's `ticks_per_move` and the inserter's `swing_ticks`.
@export var extract_ticks := 10
## Ore per extraction. 1:1 against the deposit's reserve
## ([terrain.md](../../docs/systems/terrain.md) §Deposit mining), against the
## pickaxe's 5-reserve-for-1-drop — mining a deposit by hand "yields poorly" is
## exactly this comparison.
@export var extract_count := 1

## Injected by tests; falls back to the autoload, so a test registers against its
## own Automation instance rather than the live one.
var automation: Node = null

## THE output slot: `{}` or `{ id, count }`, byte-identical to an `Inventory`
## slot and a conveyor's, so ore moves miner → inserter → belt with no conversion
## anywhere and `Inventory.STACK_SIZE` is the one cap.
var _slot: Dictionary = { }
var _cooldown := 0
## Recomputed every tick from the harvest block — see `is_idle`.
var _idle := true


func on_placed() -> void:
	_automation().register_machine(self)


func on_removed() -> void:
	_automation().unregister_machine(self)

# --- State (read by the debug overlay and the tests) -------------------------


func slot() -> Dictionary:
	return _slot


func slot_empty() -> bool:
	return _slot.is_empty()


func cooldown() -> int:
	return _cooldown


## ❗️One state for "the deposit ran dry" and "there was never one here", because
## from the player's side they mean the same thing: this machine is producing
## nothing, come and move it. Counted by the HUD's idle-machine readout
## ([ui.md](../../docs/systems/ui.md)).
##
## Recomputed per tick rather than cached on placement — a deposit is destroyed
## to air the moment its reserve hits zero, which happens *underneath* a miner
## that is otherwise perfectly placed. Six `get_material_id` calls at 10 Hz.
func is_idle() -> bool:
	return _idle

# --- The transfer seam -------------------------------------------------------


## Hands out of the output slot. A miner has no input, so `accept_item` is left
## at the base's refusing default: it is not a chest, and an inserter pointed
## into one simply does nothing.
func extract_item(max_count := 1) -> Dictionary:
	if _slot.is_empty() or max_count <= 0:
		return { }
	var moved: int = mini(max_count, _slot.count)
	var out := { id = _slot.id, count = moved }
	_slot.count -= moved
	if _slot.count <= 0:
		_slot = { }
	return out


## Drained through `extract_item`, so the ore cannot be dropped twice — the
## miner pops as one `miner` item and its held ore lands beside it.
func take_cargo() -> Array[Dictionary]:
	var cargo: Array[Dictionary] = []
	var stack := extract_item(Inventory.STACK_SIZE)
	if not stack.is_empty():
		cargo.append(stack)
	return cargo

# --- The tick ----------------------------------------------------------------


## One extraction, if it is ready and there is both ore to take and room to put
## it. Takes the **first deposit cell in row-major order** so a miner whose block
## straddles two deposits drains them in a defined order rather than one that
## depends on the tick.
##
## ❗️A full output STALLS rather than extracting into nothing — the ore stays in
## the ground, which is back-pressure and also the only reason a jammed line does
## not silently strip-mine the deposit behind it. The cooldown is not spent on a
## stalled tick, so it fires on the first tick both ends are ready (the
## inserter's rule, for the same reason).
func on_tick(terrain: Node) -> void:
	var cells := harvest_cells()
	# Before the power gate: an unpowered miner over bare rock is still a miner
	# the player has to come and move.
	_idle = not has_deposit_in(terrain, cells)
	# ❗️Exactly once per tick, and only here: `spend_power_tick` is the stateful
	# half of the brownout rule, so a second call would run the miner fast on a
	# half-powered grid.
	if not spend_power_tick():
		return
	_cooldown = maxi(_cooldown - 1, 0)
	if _cooldown > 0:
		return
	for cell: Vector2i in cells:
		var mat: Dictionary = Materials.MATERIALS.get(terrain.get_material_id(cell), { })
		if not mat.get("is_deposit", false):
			continue
		# ❗️Room is checked against the drop id BEFORE extracting. The seam has
		# no way to hand ore back into the ground, so extracting into a slot that
		# cannot hold it — full, or holding a different ore — would destroy it.
		var room := _room_for(mat.drop_id)
		if room <= 0:
			return
		var taken: Dictionary = terrain.extract_reserve(cell, mini(extract_count, room))
		if taken.is_empty():
			return
		_store(taken)
		_cooldown = extract_ticks
		return

# --- Internals ---------------------------------------------------------------


func _room_for(id: String) -> int:
	if _slot.is_empty():
		return Inventory.STACK_SIZE
	if _slot.id != id:
		return 0
	return Inventory.STACK_SIZE - _slot.count


func _store(stack: Dictionary) -> void:
	if _slot.is_empty():
		_slot = { id = stack.id, count = stack.count }
		return
	_slot.count += stack.count


func _automation() -> Node:
	if automation == null:
		automation = Automation
	return automation
