## Unit tests for the Generator and the Relay (roadmap 3.4), driven through the
## shipped scenes. Fresh Terrain + Automation per test, `_process` off.
##
## The cases here are the ones a plausible implementation gets wrong: a fuel slot
## that accepts anything (a generator jammed with copper and no way to empty it),
## a burn that lasts one tick more or less than the authored number, and supply
## that keeps flowing after the coal runs out — which looks like a working
## factory right up until the first time you forget to refill.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const GeneratorScene := preload("res://scenes/automation/generator.tscn")
const RelayScene := preload("res://scenes/automation/relay.tscn")

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


func _generator(cell := ORIGIN) -> Generator:
	# A floor under it, so the support rule is satisfied like a real placement.
	for x in 2:
		_terrain.set_tile(cell + Vector2i(x, 2), "dirt")
	var node: Generator = auto_free(GeneratorScene.instantiate())
	node.automation = _automation
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	return node


func _burn(node: Generator, ticks: int) -> void:
	for i in ticks:
		node.burn_tick()

# --- Fuel --------------------------------------------------------------------


## ❗️Routing by id is the load-bearing half. Without it an inserter fills the
## generator with copper and `extract_item` can never reach it to get it out.
func test_it_accepts_coal_and_refuses_everything_else() -> void:
	var node := _generator()
	assert_int(node.accept_item("copper", 5)).is_equal(0)
	assert_int(node.accept_item("dirt", 5)).is_equal(0)
	assert_int(node.accept_item("coal", 5)).is_equal(5)
	assert_str(node.fuel_slot().id).is_equal("coal")
	assert_int(node.fuel_slot().count).is_equal(5)


func test_the_fuel_slot_caps_at_one_stack_and_reports_a_partial_accept() -> void:
	var node := _generator()
	assert_int(node.accept_item("coal", Inventory.STACK_SIZE)).is_equal(Inventory.STACK_SIZE)
	assert_int(node.accept_item("coal", 5)).is_equal(0)


## Fuel put in is spent, not stored — an inserter pointed at a generator takes
## nothing, so a chain cannot quietly siphon its own power back out.
func test_nothing_can_extract_the_fuel_back_out() -> void:
	var node := _generator()
	node.accept_item("coal", 5)
	assert_dict(node.extract_item()).is_empty()
	assert_dict(node.extract_item(99)).is_empty()
	assert_int(node.fuel_slot().count).is_equal(5)


## Removing it hands the unburnt coal back, through the same one drop path
## everything else uses.
func test_take_cargo_returns_the_unburnt_fuel_and_empties_the_slot() -> void:
	var node := _generator()
	node.accept_item("coal", 4)
	node.burn_tick() # One unit is now alight.

	var cargo := node.take_cargo()

	assert_int(cargo.size()).is_equal(1)
	assert_str(cargo[0].id).is_equal("coal")
	# ❗️Three, not four: the unit already alight is partway burnt, and handing a
	# whole coal back for it would make place → remove → place a fuel fountain.
	assert_int(cargo[0].count).is_equal(3)
	assert_dict(node.fuel_slot()).is_empty()
	assert_int(node.burn_left()).is_equal(0)

# --- The burn ----------------------------------------------------------------


func test_an_empty_generator_supplies_nothing() -> void:
	var node := _generator()
	_burn(node, 5)
	assert_float(node.power_supply()).is_equal_approx(0.0, 0.0001)


## ❗️One coal is worth EXACTLY `fuel_ticks` ticks of supply — the tick that
## lights it counts, the tick after the last one does not.
func test_one_unit_of_fuel_burns_for_exactly_fuel_ticks() -> void:
	var node := _generator()
	node.accept_item("coal", 1)

	_burn(node, node.fuel_ticks)

	assert_float(node.power_supply()).is_equal_approx(node.power_output, 0.0001)
	assert_dict(node.fuel_slot()).is_empty() # The unit was taken on tick one.

	node.burn_tick()

	assert_float(node.power_supply()).is_equal_approx(0.0, 0.0001)


## ❗️Fuel burns whether or not anything is drawing — [terrain.md] says so, and it
## is what makes the coal deposit tier mean something. Nothing here is powered,
## and the coal still goes.
func test_it_burns_with_nothing_drawing_on_the_grid() -> void:
	var node := _generator()
	node.accept_item("coal", 2)

	# Long enough to consume the first unit and light the second, with no machine
	# anywhere and no grid drawing a thing.
	_burn(node, node.fuel_ticks + 1)

	assert_dict(node.fuel_slot()).is_empty()
	assert_float(node.power_supply()).is_equal_approx(node.power_output, 0.0001)


## A stocked generator never blinks: the tick that finishes a unit lights the
## next one in the same call.
func test_a_stocked_generator_never_drops_to_zero_between_units() -> void:
	var node := _generator()
	node.accept_item("coal", 3)
	for i in node.fuel_ticks * 3:
		node.burn_tick()
		assert_float(node.power_supply()).override_failure_message(
			"Supply blinked at tick %d" % i,
		).is_equal_approx(node.power_output, 0.0001)


func test_it_goes_dark_when_the_last_unit_runs_out() -> void:
	var node := _generator()
	node.accept_item("coal", 1)
	_burn(node, node.fuel_ticks + 1)
	assert_float(node.power_supply()).is_equal_approx(0.0, 0.0001)

	node.accept_item("coal", 1)
	node.burn_tick()

	assert_float(node.power_supply()).is_equal_approx(node.power_output, 0.0001)

# --- Idle --------------------------------------------------------------------


## ❗️A dry generator joins the HUD's idle tally beside a miner over bare rock:
## same "come and feed me" signal, and this one stops the whole factory.
func test_a_dry_generator_is_idle_and_a_burning_one_is_not() -> void:
	var node := _generator()
	assert_bool(node.is_idle()).is_true()

	node.accept_item("coal", 1)
	node.burn_tick()

	assert_bool(node.is_idle()).is_false()

	_burn(node, node.fuel_ticks)

	assert_bool(node.is_idle()).is_true()


func test_the_idle_tally_counts_a_dry_generator() -> void:
	_generator()
	_automation.step_tick()
	assert_int(_automation.idle_machines()).is_equal(1)

# --- Placement and the graph --------------------------------------------------


func test_a_placed_generator_joins_the_emitter_registry_and_a_popped_one_leaves() -> void:
	var node := _generator()
	assert_array(_automation.emitters()).contains_exactly([node])

	node.pop_to_pickup()

	assert_array(_automation.emitters()).is_empty()


## ❗️The authored numbers, asserted where a scene edit would be caught. A radius
## of zero would make the generator a machine that powers nothing, silently.
func test_the_generator_scene_authors_a_radius_and_no_demand() -> void:
	var node := _generator()
	assert_float(node.power_radius).is_greater(0.0)
	assert_float(node.power_demand).is_equal_approx(0.0, 0.0001)
	assert_str(node.item_id).is_equal("generator")


## ❗️The relay is the plain `PowerEmitter` script: a bigger radius, **no supply
## and no fuel**. Coverage alone does not run a factory, which is exactly what
## makes it worth placing next to a generator rather than instead of one.
func test_the_relay_covers_further_than_a_generator_and_supplies_nothing() -> void:
	var relay: PowerEmitter = auto_free(RelayScene.instantiate())
	relay.automation = _automation
	relay.setup(ORIGIN + Vector2i(20, 0))
	add_child(relay)
	relay.on_placed()

	assert_float(relay.power_supply()).is_equal_approx(0.0, 0.0001)
	assert_float(relay.power_radius).is_greater(_generator().power_radius)
	assert_bool(relay.is_idle()).is_false() # Nothing to feed it, so never "dry".
	assert_str(relay.item_id).is_equal("relay")


## ❗️The reason the relay ships at all: two generators too far apart to touch are
## two economies until a relay bridges them, and then they are one.
func test_a_relay_bridges_two_generators_that_do_not_reach_each_other() -> void:
	var left := _generator(ORIGIN)
	var right := _generator(ORIGIN + Vector2i(30, 0))
	_automation.step_tick()
	assert_int(_automation.power_grid().component_count()).is_equal(2)

	var relay: PowerEmitter = auto_free(RelayScene.instantiate())
	relay.automation = _automation
	relay.setup(ORIGIN + Vector2i(15, 0))
	add_child(relay)
	relay.on_placed()
	_automation.step_tick()

	assert_int(_automation.power_grid().component_count()).is_equal(1)
	# And the bridged grid pools BOTH generators' supply.
	left.accept_item("coal", 1)
	right.accept_item("coal", 1)
	_automation.step_tick()
	assert_float(_automation.power_grid().supply_of(0)).is_equal_approx(
		left.power_output + right.power_output,
		0.0001,
	)
