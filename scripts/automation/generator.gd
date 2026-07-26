## The only thing in the game that MAKES power: a 2×2 emitter with one fuel slot,
## burning a unit every `fuel_ticks` and supplying `power_output` while it burns.
##
## ❗️**It burns constantly, not on demand.** [terrain.md](../../docs/systems/terrain.md)
## already says so ("generators burn fuel constantly, these matter most"), it is
## what makes the coal deposit tier mean something, and it is the simplest code
## there is — an on-demand burn needs the grid's demand *before* supply is known,
## which is the one ordering the two-pass solve cannot give it.
##
## ❗️**This is what finally gives coal a consumer.** The furnace deliberately has
## no fuel slot ([automation.md](../../docs/systems/automation.md) §Categories) —
## the coal goes here, and everything downstream runs off the radius.
##
## Owning doc: docs/systems/automation.md §Power
class_name Generator
extends PowerEmitter

## Added to its grid's supply every tick it is burning. Sized against
## `power_demand`: one generator runs exactly one miner and one furnace at full
## rate, so the second machine you hang off it is a visible brownout rather than
## an invisible one.
@export var power_output := 2.0
## What counts as fuel. A `PackedStringArray` rather than one id so a tier-2 fuel
## is a row here, not a second script — the `station_id` bargain again.
@export var fuel_ids: PackedStringArray = ["coal"]
## Ticks one unit of fuel lasts. 100 = 10 s at 10 Hz.
@export var fuel_ticks := 100

## THE fuel slot: `{}` or `{ id, count }`, byte-identical to a conveyor's and an
## `Inventory`'s, so coal reaches it belt → inserter → generator with no
## conversion and `Inventory.STACK_SIZE` is the one cap.
var _fuel: Dictionary = { }
## Ticks left on the unit currently burning. `0` means dark.
var _burn := 0

# --- State (read by the power overlay and the tests) -------------------------


func fuel_slot() -> Dictionary:
	return _fuel


func burn_left() -> int:
	return _burn


## ❗️Dry, so it joins the HUD's idle count beside a miner over bare rock — the
## same "come and feed me" signal, and this one stops the whole factory rather
## than one machine ([ui.md](../../docs/systems/ui.md) §HUD).
func is_idle() -> bool:
	return _burn <= 0 and _fuel.is_empty()

# --- The transfer seam -------------------------------------------------------


## ❗️**Routes by ID**, exactly as `CraftingStation.accept_item` routes recipe
## inputs and for the same reason: the seam has no port argument. Anything that
## is not fuel is refused outright, so an inserter pointed at a generator by
## mistake jams its own belt instead of filling the generator with dirt that
## `extract_item` can never reach.
func accept_item(id: String, count: int) -> int:
	if count <= 0 or not fuel_ids.has(id):
		return 0
	if _fuel.is_empty():
		var taken: int = mini(count, Inventory.STACK_SIZE)
		_fuel = { id = id, count = taken }
		return taken
	if _fuel.id != id:
		return 0
	var moved: int = mini(count, Inventory.STACK_SIZE - _fuel.count)
	if moved <= 0:
		return 0
	_fuel.count += moved
	return moved


## `extract_item` stays at the base's REFUSING default: fuel put into a generator
## is spent, not stored, so an inserter pointed at one takes nothing. Removing
## the generator is the only way the coal comes back — through `take_cargo`.
func take_cargo() -> Array[Dictionary]:
	var cargo: Array[Dictionary] = []
	if not _fuel.is_empty():
		cargo.append({ id = _fuel.id, count = _fuel.count })
	_fuel = { }
	# The unit already alight is NOT returned: it is partway burnt, and handing
	# back a whole coal for it would make place → remove → place a fuel fountain.
	_burn = 0
	return cargo

# --- The burn ----------------------------------------------------------------


## One tick of fuel, run by `Automation` **before** supply is read — so a
## generator that runs dry stops powering on that tick rather than one tick late.
##
## Refilling in the same call is what makes the burn seamless: the tick that
## finishes a unit lights the next one, so a stocked generator never blinks.
func burn_tick() -> void:
	if _burn > 0:
		_burn -= 1
	if _burn > 0 or _fuel.is_empty():
		return
	_fuel.count -= 1
	if _fuel.count <= 0:
		_fuel = { }
	_burn = fuel_ticks


## Nothing while dark. The relay's zero is the base's; this one is a state.
func power_supply() -> float:
	return power_output if _burn > 0 else 0.0
