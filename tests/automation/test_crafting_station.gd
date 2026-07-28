## Unit tests for the crafting station (roadmap 3.3), driven through the furnace
## scene. Fresh Terrain + Automation per test, _process off, so the suite drives
## `step_tick()` itself.
##
## The cases here are the two that make a chain that LOOKS correct produce
## nothing: a station that accepts an unsmeltable id (jammed permanently, since
## `extract_item` cannot reach the input) and one whose `extract_item` reaches
## the input (the inserter pulls the ore straight back out of the machine it
## just fed).
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const FurnaceScene := preload("res://scenes/automation/furnace.tscn")
const AmmoPressScene := preload("res://scenes/automation/ammo_press.tscn")

## Playable (x in [50, 150)) and far from world edges.
const ORIGIN := Vector2i(100, 100)
## Deliberately huge: this suite is about smelting, not about geometry, so the
## fixture's only job is "there is power here".
const POWER_RADIUS := 64.0


## ❗️Since 3.4 a furnace on no grid does not tick at all, so every test here
## needs a supply. Kept as a local double rather than the real generator: this
## suite has no business modelling a fuel economy, and the repo already
## duplicates small doubles per suite (`SpawnerDouble`) rather than sharing them.
class Supply:
	extends PowerEmitter

	func power_supply() -> float:
		return 100.0


## Injected `Progression`, so this suite drives `crafting_speed` and
## `crafting_yield` without spending a skill point.
##
## ⚠️ **Per stat, not one flat multiplier for all of them.** The station reads
## BOTH buffs off this in one tick, so a single number would make every
## crafting-speed case silently a yield case as well — a test that passes for the
## wrong reason. Writable mid-test on purpose: taking a node MID-CRAFT is one of
## the cases below.
class ProgressionDouble:
	extends Node

	var stats: Dictionary = { }


	func get_stat(stat_name: String) -> float:
		return stats.get(stat_name, 1.0)


var _terrain: Node
var _automation: Node


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)
	var game: Node = auto_free(GameScript.new()) # Out of the tree: only `state` is read.
	game.state = GameScript.State.BUILD_PHASE
	_automation = auto_free(AutomationScript.new())
	_automation.terrain = _terrain
	_automation.game = game
	add_child(_automation)
	_automation.set_process(false)
	_power_the_world()


func _power_the_world() -> void:
	var node: Supply = auto_free(Supply.new())
	node.automation = _automation
	node.power_radius = POWER_RADIUS
	node.setup(ORIGIN)
	add_child(node)
	node.on_placed()


func _furnace(cell := ORIGIN) -> CraftingStation:
	# A floor under it, so the support rule is satisfied like a real placement.
	for x in 2:
		_terrain.set_tile(cell + Vector2i(x, 2), "dirt")
	var node: CraftingStation = auto_free(FurnaceScene.instantiate())
	node.automation = _automation
	node.progression = auto_free(ProgressionDouble.new())
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	return node


## The furnace's first recipe, so a test never restates the numbers it is
## asserting against.
func _recipe() -> Dictionary:
	return RecipeDefs.for_station("furnace")[0]

# --- The transfer seam -------------------------------------------------------


## ❗️Routing is by ID, because the seam has no port argument — and refusing an
## unsmeltable id is the load-bearing half. Without it an inserter jams the
## furnace full of dirt permanently, and `extract_item` can never reach it.
func test_it_accepts_only_ids_some_recipe_actually_uses() -> void:
	var node := _furnace()
	assert_int(node.accept_item("dirt", 5)).is_equal(0)
	assert_int(node.accept_item("copper_bar", 5)).is_equal(0) # Its own output.
	assert_int(node.accept_item("copper", 5)).is_equal(5)
	assert_str(node.input_slot().id).is_equal("copper")


func test_a_second_id_is_refused_while_the_input_holds_another() -> void:
	var node := _furnace()
	node.accept_item("copper", 1)
	assert_int(node.accept_item("iron", 1)).is_equal(0)
	assert_int(node.input_slot().count).is_equal(1)


## A partial accept is legal — the caller keeps the remainder, which is what the
## inserter's give-back depends on.
func test_the_input_slot_caps_at_one_stack() -> void:
	var node := _furnace()
	assert_int(node.accept_item("copper", Inventory.STACK_SIZE + 10)).is_equal(
		Inventory.STACK_SIZE,
	)
	assert_int(node.accept_item("copper", 1)).is_equal(0)


## ❗️If `extract_item` could reach the input, an inserter would pull the ore
## straight back out of the machine it had just fed it to — a chain that is wired
## correctly and produces nothing.
func test_extract_item_never_surrenders_the_input() -> void:
	var node := _furnace()
	node.accept_item("copper", 3)
	assert_dict(node.extract_item(99)).is_empty()
	assert_int(node.input_slot().count).is_equal(3)

# --- Crafting ----------------------------------------------------------------


## Exactly `ticks`, not one either side: a station that completes a tick early
## silently changes every downstream throughput number.
func test_it_crafts_after_exactly_the_recipes_tick_count() -> void:
	var recipe := _recipe()
	var node := _furnace()
	node.accept_item(recipe.inputs.keys()[0], 1)

	for i in recipe.ticks - 1:
		_automation.step_tick()
	assert_bool(node.output_slot().is_empty()).is_true()

	_automation.step_tick()

	assert_str(node.output_slot().id).is_equal(recipe.output.id)
	assert_int(node.output_slot().count).is_equal(recipe.output.count)
	assert_bool(node.input_slot().is_empty()).is_true()
	assert_int(node.progress()).is_equal(0)


## ❗️Inputs are consumed on COMPLETION, not on start, so a furnace knocked down
## mid-craft has no half-eaten ore for `take_cargo` to lose.
func test_a_craft_in_progress_has_not_eaten_its_input_yet() -> void:
	var recipe := _recipe()
	var node := _furnace()
	node.accept_item(recipe.inputs.keys()[0], 1)

	for i in recipe.ticks - 1:
		_automation.step_tick()

	assert_int(node.input_slot().count).is_equal(1)
	assert_int(node.progress()).is_equal(recipe.ticks - 1)


## Back-pressure: a full output stalls AT full progress and resumes the instant
## it is drained, rather than dropping the craft or overfilling the slot.
func test_a_full_output_stalls_at_full_progress() -> void:
	var recipe := _recipe()
	var node := _furnace()
	node.accept_item(recipe.inputs.keys()[0], 2)
	node._output = { id = recipe.output.id, count = Inventory.STACK_SIZE }

	for i in recipe.ticks + 5:
		_automation.step_tick()

	assert_int(node.progress()).is_equal(recipe.ticks)
	assert_int(node.output_slot().count).is_equal(Inventory.STACK_SIZE)
	assert_int(node.input_slot().count).is_equal(2) # Untouched.

	node.extract_item(Inventory.STACK_SIZE)
	_automation.step_tick() # Already at full progress: completes immediately.

	assert_int(node.output_slot().count).is_equal(recipe.output.count)

# --- crafting_speed and crafting_yield (3.7) ----------------------------------


## The clamp, without a station: a big enough multiplier divides to zero, and a
## station at zero ticks crafts on every tick forever.
func test_the_effective_duration_never_falls_below_one_tick() -> void:
	assert_int(CraftingStation.effective_ticks(20, 1.0)).is_equal(20)
	assert_int(CraftingStation.effective_ticks(20, 2.0)).is_equal(10)
	assert_int(CraftingStation.effective_ticks(20, 1000.0)).is_equal(1)
	assert_int(CraftingStation.effective_ticks(1, 4.0)).is_equal(1)
	# ⚠️ `ceili`: a +15% node must not shave a whole tick off a 3-tick recipe.
	assert_int(CraftingStation.effective_ticks(3, 1.15)).is_equal(3)
	# A zero or negative multiplier is a broken buff, not a free craft.
	assert_int(CraftingStation.effective_ticks(20, 0.0)).is_equal(20)


func test_a_doubled_crafting_speed_halves_the_tick_count() -> void:
	var recipe := _recipe()
	var node := _furnace()
	node.progression.stats["crafting_speed"] = 2.0
	node.accept_item(recipe.inputs.keys()[0], 1)

	for i in recipe.ticks / 2:
		_automation.step_tick()

	assert_int(node.output_slot().count).is_equal(recipe.output.count)


## ❗️Why the comparison is `>=` and not `==`. Taking the node mid-craft drops the
## target BELOW the progress already banked, and `==` would step straight past it
## — a station stuck at full progress forever, on the tick a buff was meant to
## help it.
func test_taking_the_node_mid_craft_completes_rather_than_overshooting() -> void:
	var recipe := _recipe()
	var node := _furnace()
	node.accept_item(recipe.inputs.keys()[0], 1)

	for i in recipe.ticks - 2:
		_automation.step_tick()
	assert_bool(node.output_slot().is_empty()).is_true()

	node.progression.stats["crafting_speed"] = 4.0 # The point is spent here.
	_automation.step_tick()

	assert_int(node.output_slot().count).is_equal(recipe.output.count)
	assert_int(node.progress()).is_equal(0)


## The output half. A ×2 station hands back two bars for the one ore a recipe
## charges — the input side is untouched, exactly as the miner's reserve is.
func test_a_yield_buff_fattens_the_output_without_touching_the_input() -> void:
	var recipe := _recipe()
	var node := _furnace()
	node.progression.stats["crafting_yield"] = 2.0
	node.accept_item(recipe.inputs.keys()[0], 3)

	# The full duration: a yield node is not a speed node, and the suite would not
	# notice if it quietly became one.
	for i in recipe.ticks:
		_automation.step_tick()

	assert_int(node.output_slot().count).is_equal(recipe.output.count * 2)
	assert_int(node.input_slot().count).is_equal(2) # One ore charged, not two.


## ❗️A station stalled at full progress re-enters the tick every frame. Asking
## for the yield before the room check would bank a fresh bonus each of those
## ticks and dump the pile the moment the slot drained.
func test_a_stalled_station_banks_no_yield_credit() -> void:
	var recipe := _recipe()
	var node := _furnace()
	node.progression.stats["crafting_yield"] = 2.0
	node.accept_item(recipe.inputs.keys()[0], 2)
	node._output = { id = recipe.output.id, count = Inventory.STACK_SIZE }

	for i in recipe.ticks + 20:
		_automation.step_tick()

	assert_float(node.yield_credit()).is_equal_approx(0.0, 0.0001)
	assert_int(node.output_slot().count).is_equal(Inventory.STACK_SIZE)


## An empty input banks nothing, so swapping what you feed it mid-craft cannot
## cash one recipe's progress into another's output.
func test_progress_resets_when_the_inputs_go_away() -> void:
	var recipe := _recipe()
	var node := _furnace()
	node.accept_item(recipe.inputs.keys()[0], 1)
	for i in recipe.ticks - 2:
		_automation.step_tick()
	assert_int(node.progress()).is_greater(0)

	node._input = { }
	_automation.step_tick()

	assert_int(node.progress()).is_equal(0)


## A crafting station is never idle in the 3.3 sense — that state belongs to a
## miner whose ore ran out, and a furnace with nothing to smelt is just waiting.
func test_a_station_is_never_reported_idle() -> void:
	var node := _furnace()
	_automation.step_tick()
	assert_bool(node.is_idle()).is_false()

# --- Removal -----------------------------------------------------------------


## Both slots come back, through the one drop path.
func test_take_cargo_returns_the_input_and_the_output() -> void:
	var recipe := _recipe()
	var node := _furnace()
	node.accept_item(recipe.inputs.keys()[0], 3)
	node._output = { id = recipe.output.id, count = 2 }

	var cargo := node.take_cargo()

	assert_int(cargo.size()).is_equal(2)
	assert_int(cargo[0].count).is_equal(3)
	assert_int(cargo[1].count).is_equal(2)
	assert_bool(node.input_slot().is_empty()).is_true()
	assert_bool(node.output_slot().is_empty()).is_true()

# --- Registration ------------------------------------------------------------


func test_a_placed_station_joins_the_tick_and_a_popped_one_leaves_it() -> void:
	var node := _furnace()
	assert_int(_automation.machines().size()).is_equal(1)
	node.pop_to_pickup()
	assert_int(_automation.machines().size()).is_equal(0)
	_automation.step_tick() # Must not touch the freed node.
	assert_int(_automation.tick_count).is_equal(1)

# --- The ammo press (3.5a) ----------------------------------------------------
#
# The whole point of the `station_id` bargain: a SECOND machine on this same
# script, proven by running it through the same fixture. If any of this needed a
# change in `crafting_station.gd`, the bargain was not real.


func _press(cell := ORIGIN) -> CraftingStation:
	for x in 2:
		_terrain.set_tile(cell + Vector2i(x, 2), "dirt")
	var node: CraftingStation = auto_free(AmmoPressScene.instantiate())
	node.automation = _automation
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	return node


## Same script, different string — no subclass, no branch.
func test_the_press_is_the_same_script_with_another_station_id() -> void:
	var node := _press()
	assert_str(node.station_id).is_equal("ammo_press")
	assert_str(node.get_script().resource_path).is_equal(
		"res://scripts/automation/crafting_station.gd",
	)


## ❗️It eats BARS, not ore: `accepts_input` routes by id off the table alone, so
## an inserter that mistakes the press for a furnace jams its own belt rather
## than filling the press with copper it can never smelt.
func test_the_press_takes_bars_and_refuses_ore() -> void:
	var node := _press()
	assert_int(node.accept_item("copper_bar", 1)).is_equal(1)
	assert_int(node.accept_item("copper", 1)).is_equal(0)
	assert_int(node.accept_item("dirt", 1)).is_equal(0)


func test_the_press_turns_a_bar_into_a_stack_of_ammo() -> void:
	var node := _press()
	var recipe: Dictionary = RecipeDefs.for_station("ammo_press")[0]
	node.accept_item(recipe.inputs.keys()[0], 1)

	for i in recipe.ticks:
		_automation.step_tick()

	assert_str(node.output_slot().id).is_equal(recipe.output.id)
	assert_int(node.output_slot().count).is_equal(recipe.output.count)
	assert_bool(node.input_slot().is_empty()).is_true()


## The chain the step exists to make: a furnace and a press on one grid, the
## bar walking from one to the other by hand (the inserter has its own suite).
func test_a_furnace_feeds_a_press_without_either_knowing_the_other() -> void:
	var furnace := _furnace()
	var press := _press(ORIGIN + Vector2i(6, 0))
	furnace.accept_item("copper", 1)
	for i in RecipeDefs.for_station("furnace")[0].ticks:
		_automation.step_tick()

	var bar := furnace.extract_item(1)
	assert_str(bar.id).is_equal("copper_bar")
	assert_int(press.accept_item(bar.id, bar.count)).is_equal(1)

	for i in RecipeDefs.for_station("ammo_press")[0].ticks:
		_automation.step_tick()

	assert_str(press.output_slot().id).is_equal("copper_ammo")
