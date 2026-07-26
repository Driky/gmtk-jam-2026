## Unit tests for the inserter swing (roadmap 3.2). Fresh Terrain + Automation
## per test, _process off, so the suite drives `step_tick()` itself.
##
## The cases here are the ones a plausible implementation gets wrong: the
## behind/front orientation (a silent 50/50, exactly like 3.1's Up/Down support
## bit), and the give-back when the destination refuses — the one path where an
## item can vanish.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const ConveyorScene := preload("res://scenes/automation/conveyor.tscn")
const InserterScene := preload("res://scenes/automation/inserter.tscn")
const TorchScene := preload("res://scenes/torch.tscn")

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


func _belt(cell: Vector2i, dir := Vector2i.RIGHT) -> Conveyor:
	var c: Conveyor = auto_free(ConveyorScene.instantiate())
	c.automation = _automation
	c.facing = dir
	c.setup(cell)
	add_child(c)
	assert_bool(c.register(_terrain)).is_true()
	c.on_placed()
	return c


func _inserter(cell: Vector2i, dir := Vector2i.RIGHT) -> Inserter:
	var i: Inserter = auto_free(InserterScene.instantiate())
	i.automation = _automation
	i.facing = dir
	i.setup(cell)
	add_child(i)
	assert_bool(i.register(_terrain)).is_true()
	i.on_placed()
	return i


func _torch_at(cell: Vector2i) -> Torch:
	var torch: Torch = auto_free(TorchScene.instantiate())
	torch.setup(cell)
	add_child(torch)
	assert_bool(torch.register(_terrain)).is_true()
	return torch

# --- The swing ----------------------------------------------------------------


## Behind is `cell - facing`, front is `cell + facing`. Checked for all four
## facings in one world (spaced clear of each other), because getting it backwards
## produces a game that mostly works with no error anywhere — the same trap as the
## support bitmask's Up/Down bit, which is why that one has a dedicated test too.
func test_a_swing_moves_one_item_from_behind_to_in_front() -> void:
	var facings: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	var arms: Array[Inserter] = []
	var behinds: Array[Conveyor] = []
	var fronts: Array[Conveyor] = []
	for i in facings.size():
		var facing := facings[i]
		var at := ORIGIN + Vector2i(i * 5, 0)
		arms.append(_inserter(at, facing))
		# Both belts face along the inserter's axis, so neither can advance on its
		# own and only the swing can move anything.
		behinds.append(_belt(at - facing, facing))
		fronts.append(_belt(at + facing, facing))
		behinds[i].accept_item("stone_%d" % i, 1)

	_automation.step_tick()

	for i in facings.size():
		assert_bool(behinds[i].slot_empty()).is_true()
		assert_str(fronts[i].slot().id).is_equal("stone_%d" % i)
		assert_int(arms[i].cooldown()).is_equal(arms[i].swing_ticks)


## Only one item per swing, and only every `swing_ticks`.
func test_the_swing_waits_out_its_cooldown() -> void:
	var arm := _inserter(ORIGIN)
	var behind := _belt(ORIGIN + Vector2i.LEFT, Vector2i.DOWN) # Faces away; jams, keeps its stack.
	var front := _belt(ORIGIN + Vector2i.RIGHT, Vector2i.DOWN)
	behind.accept_item("stone", 4)

	_automation.step_tick()
	assert_int(behind.slot().count).is_equal(3)
	for i in arm.swing_ticks - 1:
		_automation.step_tick()
	assert_int(behind.slot().count).is_equal(3) # Still cooling down.
	_automation.step_tick()
	assert_int(behind.slot().count).is_equal(2)
	assert_int(front.slot().count).is_equal(2)


## ❗️Back-pressure: a full destination must leave the source EXACTLY as it was.
## The inserter extracts before it knows, so this is the give-back path — the one
## place an item can silently vanish.
func test_a_full_destination_leaves_the_source_untouched() -> void:
	_inserter(ORIGIN)
	var behind := _belt(ORIGIN + Vector2i.LEFT, Vector2i.DOWN)
	var front := _belt(ORIGIN + Vector2i.RIGHT, Vector2i.DOWN)
	behind.accept_item("stone", 3)
	front.accept_item("dirt", 1) # Mismatched id: the belt refuses outright.

	_automation.step_tick()

	assert_int(behind.slot().count).is_equal(3)
	assert_str(behind.slot().id).is_equal("stone")
	assert_int(front.slot().count).is_equal(1)


## An idle poll must not spend the cooldown, or the inserter fires late and a
## chain's throughput depends on when the source happened to fill.
func test_a_refused_transfer_does_not_burn_the_cooldown() -> void:
	var arm := _inserter(ORIGIN)
	var behind := _belt(ORIGIN + Vector2i.LEFT, Vector2i.DOWN)
	_belt(ORIGIN + Vector2i.RIGHT, Vector2i.DOWN).accept_item("dirt", 1)
	behind.accept_item("stone", 1)

	_automation.step_tick()

	assert_int(arm.cooldown()).is_equal(0)


## ❗️The payoff of the refusing default on the base: an inserter pointed at a
## torch does nothing, with no type check anywhere in this class.
func test_an_inserter_pointed_at_a_torch_does_nothing() -> void:
	_terrain.set_tile(ORIGIN + Vector2i(1, 1), "dirt") # Something for the torch to mount on.
	_inserter(ORIGIN)
	var behind := _belt(ORIGIN + Vector2i.LEFT, Vector2i.DOWN)
	behind.accept_item("stone", 1)
	_torch_at(ORIGIN + Vector2i.RIGHT)

	_automation.step_tick()

	assert_int(behind.slot().count).is_equal(1)


## And the same in reverse: a torch has nothing to give, so the swing is a no-op
## rather than an error.
func test_an_inserter_pulling_from_a_torch_does_nothing() -> void:
	_terrain.set_tile(ORIGIN + Vector2i(-1, 1), "dirt")
	var arm := _inserter(ORIGIN)
	_torch_at(ORIGIN + Vector2i.LEFT)
	var front := _belt(ORIGIN + Vector2i.RIGHT, Vector2i.DOWN)

	_automation.step_tick()

	assert_bool(front.slot_empty()).is_true()
	assert_int(arm.cooldown()).is_equal(0)


func test_a_missing_source_or_destination_is_a_no_op() -> void:
	var arm := _inserter(ORIGIN)
	var behind := _belt(ORIGIN + Vector2i.LEFT, Vector2i.DOWN)
	behind.accept_item("stone", 1)

	_automation.step_tick() # Nothing in front at all.

	assert_int(behind.slot().count).is_equal(1)
	assert_int(arm.cooldown()).is_equal(0)


## ❗️The locked tick order, from the gameplay side: inserters run BEFORE
## conveyors, so the slot an inserter just emptied is free for the belt's own
## upstream to advance into on the SAME tick.
func test_a_pull_lets_the_source_line_advance_the_same_tick() -> void:
	# A horizontal line whose head jams, with an inserter lifting off its second
	# cell downward: behind = (1,0), front = (1,2).
	var upstream := _belt(ORIGIN)
	var pulled_from := _belt(ORIGIN + Vector2i(1, 0))
	_inserter(ORIGIN + Vector2i(1, 1), Vector2i.DOWN)
	var front := _belt(ORIGIN + Vector2i(1, 2), Vector2i.DOWN)
	upstream.accept_item("upstream", 1)
	pulled_from.accept_item("pulled", 1)

	_automation.step_tick()

	assert_str(front.slot().id).is_equal("pulled")
	assert_str(pulled_from.slot().id).is_equal("upstream")
	assert_bool(upstream.slot_empty()).is_true()


## A belt facing an inserter jams: an inserter PULLS, it is never pushed into.
func test_a_belt_facing_an_inserter_jams() -> void:
	var belt := _belt(ORIGIN)
	_inserter(ORIGIN + Vector2i.RIGHT, Vector2i.DOWN)
	belt.accept_item("stone", 1)

	_automation.step_tick()

	assert_int(belt.slot().count).is_equal(1)

# --- Registration -------------------------------------------------------------


func test_a_placed_inserter_joins_the_tick_and_a_popped_one_leaves_it() -> void:
	var arm := _inserter(ORIGIN)
	assert_int(_automation.inserters().size()).is_equal(1)
	arm.pop_to_pickup()
	assert_int(_automation.inserters().size()).is_equal(0)
	_automation.step_tick() # Must not touch the freed node.
	assert_int(_automation.tick_count).is_equal(1)
