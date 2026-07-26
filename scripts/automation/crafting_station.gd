## A machine that turns inputs into an output on a recipe table: two slots, one
## progress counter, one `station_id`. Named for the CATEGORY rather than for the
## furnace, because 4.2's assembler and ammo press are then a `.tscn`, a
## `station_id` and rows in `data/recipe_defs.gd` — no new script.
##
## ❗️**No fuel slot.** A furnace runs on the power grid (3.4), not on coal in a
## third slot — [automation.md](../../docs/systems/automation.md) §Categories
## records that resolution. The coal goes in the *generator*.
##
## Owning doc: docs/systems/automation.md
class_name CraftingStation
extends Deployable

## Which rows of `RecipeDefs.RECIPES` this machine can run. Authored per scene:
## the assembler is the same script with a different string.
@export var station_id := "furnace"

## Injected by tests; falls back to the autoload, so a test registers against its
## own Automation instance rather than the live one.
var automation: Node = null

## Two slots, input and output — both `{}` or `{ id, count }`, byte-identical to
## a conveyor's and an `Inventory`'s.
var _input: Dictionary = { }
var _output: Dictionary = { }
var _progress := 0


func on_placed() -> void:
	_automation().register_machine(self)


func on_removed() -> void:
	_automation().unregister_machine(self)

# --- State (read by the debug overlay and the tests) -------------------------


func input_slot() -> Dictionary:
	return _input


func output_slot() -> Dictionary:
	return _output


func progress() -> int:
	return _progress

# --- The transfer seam -------------------------------------------------------


## ❗️**Routes by ID, because the seam has no port argument.** An item is taken
## into the INPUT slot only if some recipe this station runs uses it; everything
## else is refused outright. Refusing is the load-bearing half: without it an
## inserter jams the furnace full of dirt permanently, and there is no way back
## out — `extract_item` only ever reaches the output.
func accept_item(id: String, count: int) -> int:
	if count <= 0 or not RecipeDefs.accepts_input(station_id, id):
		return 0
	if _input.is_empty():
		var taken: int = mini(count, Inventory.STACK_SIZE)
		_input = { id = id, count = taken }
		return taken
	if _input.id != id:
		return 0
	var moved: int = mini(count, Inventory.STACK_SIZE - _input.count)
	if moved <= 0:
		return 0
	_input.count += moved
	return moved


## ❗️**Output only.** If this could reach the input slot, an inserter would pull
## the ore straight back out of the machine it had just fed it to — a chain that
## looks wired correctly and produces nothing at all.
func extract_item(max_count := 1) -> Dictionary:
	if _output.is_empty() or max_count <= 0:
		return { }
	var moved: int = mini(max_count, _output.count)
	var out := { id = _output.id, count = moved }
	_output.count -= moved
	if _output.count <= 0:
		_output = { }
	return out


## Both slots, so a furnace knocked down mid-craft returns the ore that went in
## as well as the bars that came out. Nothing is held anywhere else: progress is
## a counter, not a half-eaten stack.
func take_cargo() -> Array[Dictionary]:
	var cargo: Array[Dictionary] = []
	for stack: Dictionary in [_input, _output]:
		if not stack.is_empty():
			cargo.append({ id = stack.id, count = stack.count })
	_input = { }
	_output = { }
	return cargo

# --- The tick ----------------------------------------------------------------


## One tick of crafting: pick the first recipe whose inputs are present,
## accumulate progress, and at `ticks` **consume the inputs and write the output
## in the same step**.
##
## ❗️**Consume on COMPLETION, not on start.** Mid-craft removal then has no
## half-eaten ore for `take_cargo` to lose, and a full output slot simply stalls
## at full progress — which is back-pressure, and resumes the instant the output
## is drained. Consuming on start would need a third place an item can live, plus
## a rule for what happens to it when the machine is knocked down.
func on_tick(_terrain: Node) -> void:
	# ❗️Exactly once per tick, and only here — see `Deployable.spend_power_tick`.
	# A brownout costs the station whole ticks of progress, so a 20-tick smelt on
	# a half-fed grid takes 40 and the slowdown is visible rather than inferred.
	if not spend_power_tick():
		return
	var recipe := _active_recipe()
	if recipe.is_empty():
		# Nothing to make: progress resets rather than being banked, so swapping
		# the input mid-craft cannot cash a copper's progress into an iron bar.
		_progress = 0
		return
	_progress = mini(_progress + 1, recipe.ticks)
	if _progress < recipe.ticks:
		return
	if _room_for(recipe.output.id) < recipe.output.count:
		return
	_consume(recipe.inputs)
	_store_output(recipe.output)
	_progress = 0

# --- Internals ---------------------------------------------------------------


## The first recipe (table order) whose inputs are all present. One input slot
## means a multi-input row can never match today — that is fine, and the map
## shape is what lets 4.2's assembler grow a second slot without a rewrite.
func _active_recipe() -> Dictionary:
	for recipe: Dictionary in RecipeDefs.for_station(station_id):
		if _has_inputs(recipe.inputs):
			return recipe
	return { }


func _has_inputs(inputs: Dictionary) -> bool:
	if inputs.is_empty():
		return false
	if _input.is_empty():
		return false
	for id: String in inputs:
		if _input.id != id or _input.count < inputs[id]:
			return false
	return true


func _consume(inputs: Dictionary) -> void:
	for id: String in inputs:
		_input.count -= inputs[id]
	if _input.count <= 0:
		_input = { }


func _room_for(id: String) -> int:
	if _output.is_empty():
		return Inventory.STACK_SIZE
	if _output.id != id:
		return 0
	return Inventory.STACK_SIZE - _output.count


func _store_output(output: Dictionary) -> void:
	if _output.is_empty():
		_output = { id = output.id, count = output.count }
		return
	_output.count += output.count


func _automation() -> Node:
	if automation == null:
		automation = Automation
	return automation
