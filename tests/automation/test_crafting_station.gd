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

## Playable (x in [50, 150)) and far from world edges.
const ORIGIN := Vector2i(100, 100)

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


func _furnace(cell := ORIGIN) -> CraftingStation:
	# A floor under it, so the support rule is satisfied like a real placement.
	for x in 2:
		_terrain.set_tile(cell + Vector2i(x, 2), "dirt")
	var node: CraftingStation = auto_free(FurnaceScene.instantiate())
	node.automation = _automation
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
