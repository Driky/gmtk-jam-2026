## Unit tests for conveyor slots and the two-phase advance (roadmap 3.2).
##
## `plan.md` names automation tick bugs — ordering, dupes, stack merges — the
## top-listed risk of the jam, so these lean hard on the cases a naive
## implementation gets wrong: chain compression, a rotating loop, and the item
## COUNT before and after. Fresh Terrain + Automation per test, _process off, so
## the suite drives `step_tick()` itself.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const ConveyorScene := preload("res://scenes/automation/conveyor.tscn")

## Playable (x in [50, 150)) and far from world edges.
const ORIGIN := Vector2i(100, 100)

var _terrain: Node
var _automation: Node
var _spawner: SpawnerDouble


## Records what the real spawner would have dropped, without the autoload wiring
## or a Pickup in the tree.
class SpawnerDouble:
	extends Node

	var drops: Array = []


	func spawn_at(world_pos: Vector2, id: String, count: int, grants_xp := true) -> void:
		drops.append({ pos = world_pos, id = id, count = count, grants_xp = grants_xp })


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)
	_spawner = auto_free(SpawnerDouble.new())
	_spawner.add_to_group(&"pickup_spawner")
	add_child(_spawner)
	var game: Node = auto_free(GameScript.new()) # Out of the tree: only `state` is read.
	game.state = GameScript.State.BUILD_PHASE
	_automation = auto_free(AutomationScript.new())
	_automation.terrain = _terrain
	_automation.game = game
	add_child(_automation)
	_automation.set_process(false)


## Built through the real placement path — `register` then `on_placed()` — so the
## registration seam is exercised rather than bypassed.
func _belt(cell: Vector2i, dir: Vector2i, ticks := 1) -> Conveyor:
	var c: Conveyor = auto_free(ConveyorScene.instantiate())
	c.automation = _automation
	c.facing = dir
	c.ticks_per_move = ticks
	c.setup(cell)
	add_child(c)
	assert_bool(c.register(_terrain)).is_true()
	c.on_placed()
	return c


## A straight run of `count` belts from ORIGIN, all facing right.
func _line(count: int, ticks := 1) -> Array[Conveyor]:
	var belts: Array[Conveyor] = []
	for i in count:
		belts.append(_belt(ORIGIN + Vector2i(i, 0), Vector2i.RIGHT, ticks))
	return belts


## Closed 2×2 loop, clockwise. Returned in row-major order, which is also the
## order the tick walks it in.
func _loop(slow_index := -1, slow_ticks := 3) -> Array[Conveyor]:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT]
	var belts: Array[Conveyor] = []
	for i in cells.size():
		belts.append(_belt(ORIGIN + cells[i], dirs[i], slow_ticks if i == slow_index else 1))
	return belts


## ❗️The dupe/loss guard every advance test carries: the sim must be a
## permutation of what went in, never a source or a sink.
func _total_items(belts: Array[Conveyor]) -> int:
	var total := 0
	for belt in belts:
		if belt.slot_empty():
			continue
		var count: int = belt.slot().count
		total += count
	return total


## Slot contents in the given order, "" for empty — the whole state of a line in
## one assertable value.
func _ids(belts: Array[Conveyor]) -> Array[String]:
	var out: Array[String] = []
	for belt in belts:
		if belt.slot_empty():
			out.append("")
			continue
		var id: String = belt.slot().id
		out.append(id)
	return out

# --- accept_item / extract_item ----------------------------------------------


func test_accept_takes_into_an_empty_slot() -> void:
	var belt := _belt(ORIGIN, Vector2i.RIGHT)
	assert_int(belt.accept_item("stone", 1)).is_equal(1)
	assert_str(belt.slot().id).is_equal("stone")
	assert_int(belt.slot().count).is_equal(1)


## Merging onto a MATCHING id is how a hand-fed stack builds up and how an
## inserter tops a belt off; the cap is Inventory's, not a second number.
func test_accept_merges_onto_a_matching_id_up_to_the_stack_cap() -> void:
	var belt := _belt(ORIGIN, Vector2i.RIGHT)
	belt.accept_item("stone", Inventory.STACK_SIZE - 2)
	assert_int(belt.accept_item("stone", 5)).is_equal(2) # Only what fits.
	assert_int(belt.slot().count).is_equal(Inventory.STACK_SIZE)
	assert_int(belt.accept_item("stone", 1)).is_equal(0) # Full.


## A mismatched id is refused outright: one slot has nowhere to put a second
## kind, and densifying a saturated line is the Stacker's job.
func test_accept_refuses_a_mismatched_id() -> void:
	var belt := _belt(ORIGIN, Vector2i.RIGHT)
	belt.accept_item("stone", 1)
	assert_int(belt.accept_item("dirt", 1)).is_equal(0)
	assert_str(belt.slot().id).is_equal("stone")


func test_extract_empties_the_slot_when_it_takes_the_last_one() -> void:
	var belt := _belt(ORIGIN, Vector2i.RIGHT)
	belt.accept_item("stone", 2)
	var first: Dictionary = belt.extract_item(1)
	assert_int(first.count).is_equal(1)
	assert_bool(belt.slot_empty()).is_false()
	var second: Dictionary = belt.extract_item(9) # Only what is there.
	assert_int(second.count).is_equal(1)
	assert_bool(belt.slot_empty()).is_true()
	assert_dict(belt.extract_item()).is_empty()


## An item that appears in place must render parked, not slide in from wherever
## this belt last received from — the interpolation reads `_prev_cell` and nothing
## else, so `accept_item` owns this.
func test_an_item_fed_into_an_empty_slot_starts_parked_on_its_own_cell() -> void:
	var belts := _line(2)
	belts[0].accept_item("stone", 1)
	_automation.step_tick() # Moves it along, so belts[1] now lerps from belts[0].
	assert_vector(belts[1].prev_cell()).is_equal(belts[0].cell())

	belts[1].extract_item(1) # As an inserter would.
	belts[1].accept_item("stone", 1) # Hand-fed straight back in.

	assert_vector(belts[1].prev_cell()).is_equal(belts[1].cell())

# --- Advance ------------------------------------------------------------------


func test_an_item_advances_one_cell_per_tick() -> void:
	var belts := _line(3)
	belts[0].accept_item("stone", 1)
	_automation.step_tick()
	assert_array(_ids(belts)).is_equal(["", "stone", ""])
	_automation.step_tick()
	assert_array(_ids(belts)).is_equal(["", "", "stone"])


## The tier lever, all data: `ticks_per_move` is set on RECEIPT, so a belt holds
## its stack for that many ticks before passing it on.
func test_a_two_tick_belt_advances_every_other_tick() -> void:
	var belts := _line(4, 2)
	belts[0].accept_item("stone", 1)
	_automation.step_tick()
	assert_array(_ids(belts)).is_equal(["", "stone", "", ""])
	_automation.step_tick() # Still cooling down.
	assert_array(_ids(belts)).is_equal(["", "stone", "", ""])
	_automation.step_tick()
	assert_array(_ids(belts)).is_equal(["", "", "stone", ""])


## ❗️Chain compression, and the test a naive per-belt implementation fails: it
## advances only the head, which still passes the one-cell-per-tick test above.
func test_a_full_chain_advances_as_a_body_in_one_tick() -> void:
	var belts := _line(5)
	for i in 4:
		belts[i].accept_item("item_%d" % i, 1)

	_automation.step_tick()

	assert_array(_ids(belts)).is_equal(["", "item_0", "item_1", "item_2", "item_3"])
	assert_int(_total_items(belts)).is_equal(4)


## ❗️A belt facing nothing JAMS rather than spilling — items on a belt never fall
## on the floor — and a jammed line loses nothing however long it sits.
func test_a_blocked_head_jams_the_line_and_loses_nothing() -> void:
	var belts := _line(4)
	for i in 4:
		belts[i].accept_item("item_%d" % i, 1)
	var before := _ids(belts)

	for i in 10:
		_automation.step_tick()

	assert_array(_ids(belts)).is_equal(before)
	assert_int(_total_items(belts)).is_equal(4)


## Unblocking the far end has to move the WHOLE line off at once, not one belt
## per tick — the same compression as above, reached from a jam.
func test_unblocking_the_head_releases_the_whole_line_at_once() -> void:
	var belts := _line(4)
	for i in 4:
		belts[i].accept_item("item_%d" % i, 1)
	_automation.step_tick() # Jammed.

	var vent := _belt(ORIGIN + Vector2i(4, 0), Vector2i.RIGHT)
	_automation.step_tick()

	assert_array(_ids(belts)).is_equal(["", "item_0", "item_1", "item_2"])
	assert_array(_ids([vent] as Array[Conveyor])).is_equal(["item_3"])

# --- Cycles -------------------------------------------------------------------


## ❗️A closed loop of full belts ROTATES, one cell per tick. This is the single
## least obvious property of the pass: it works because re-entering a belt that is
## already RESOLVING answers `true`, and that optimism is self-fulfilling under a
## simultaneous commit. A naive `can_move` deadlocks the loop instead.
func test_a_full_loop_rotates_one_cell_per_tick() -> void:
	var belts := _loop()
	# Row-major (0,0) (1,0) (0,1) (1,1); the cycle runs (0,0)→(1,0)→(1,1)→(0,1)→.
	for i in belts.size():
		belts[i].accept_item("item_%d" % i, 1)

	_automation.step_tick()

	assert_array(_ids(belts)).is_equal(["item_2", "item_0", "item_3", "item_1"])
	assert_int(_total_items(belts)).is_equal(4)
	_automation.step_tick()
	assert_int(_total_items(belts)).is_equal(4)


## The memo must carry no hidden dependence on where the walk began: a rotated
## list produces the same move set in a different order, and the commit is
## order-independent.
func test_the_loop_rotates_identically_whichever_member_the_walk_starts_from() -> void:
	var belts := _loop()
	for i in belts.size():
		belts[i].accept_item("item_%d" % i, 1)
	var rotated: Array[Deployable] = [belts[2], belts[3], belts[0], belts[1]]

	Conveyor.advance_all(_terrain, rotated)

	assert_array(_ids(belts)).is_equal(["item_2", "item_0", "item_3", "item_1"])
	assert_int(_total_items(belts)).is_equal(4)


## The cycle's negative case: the optimism must NOT fire when a member is still
## cooling down. `_evaluate` checks the target's cooldown before recursing, which
## is what makes a slow belt block the whole loop.
func test_a_loop_with_one_cooling_belt_does_not_move() -> void:
	var belts := _loop(0, 3)
	for i in belts.size():
		belts[i].accept_item("item_%d" % i, 1)
	_automation.step_tick() # Rotates once; belts[0] now holds a 3-tick cooldown.
	var after_first := _ids(belts)

	_automation.step_tick()

	assert_array(_ids(belts)).is_equal(after_first)
	assert_int(_total_items(belts)).is_equal(4)


## ❗️The case that catches claiming the destination BEFORE the recursion returns.
## B and C point at each other and legally swap; A feeds B and must lose the
## tie. Claim-first lets A and C both write B, and the total silently drops to 2.
func test_a_two_belt_swap_beats_its_feeder_and_loses_nothing() -> void:
	var a := _belt(ORIGIN, Vector2i.RIGHT)
	var b := _belt(ORIGIN + Vector2i(1, 0), Vector2i.RIGHT)
	var c := _belt(ORIGIN + Vector2i(2, 0), Vector2i.LEFT)
	a.accept_item("a", 1)
	b.accept_item("b", 1)
	c.accept_item("c", 1)

	var all: Array[Conveyor] = [a, b, c]
	_automation.step_tick()

	assert_array(_ids(all)).is_equal(["a", "c", "b"])
	assert_int(_total_items(all)).is_equal(3)

# --- Determinism --------------------------------------------------------------


## Two belts facing one cell: the row-major-earlier one claims it and the other
## waits. Which one wins matters less than that it is always the same one.
func test_two_belts_facing_one_cell_let_the_row_major_earlier_one_win() -> void:
	var target := _belt(ORIGIN + Vector2i(0, 1), Vector2i.DOWN) # Jams; keeps what it gets.
	var early := _belt(ORIGIN, Vector2i.DOWN)
	var late := _belt(ORIGIN + Vector2i(1, 1), Vector2i.LEFT)
	early.accept_item("early", 1)
	late.accept_item("late", 1)

	var all: Array[Conveyor] = [target, early, late]
	_automation.step_tick()

	# Kept, not eaten: the loser retains its stack and retries next tick.
	assert_array(_ids(all)).is_equal(["early", "", "late"])


## Registration order must not change the answer — that is the whole point of
## sorting by cell. Built back to front here, so insertion order is the reverse.
func test_the_tie_break_is_the_same_whatever_order_the_belts_were_placed_in() -> void:
	var late := _belt(ORIGIN + Vector2i(1, 1), Vector2i.LEFT)
	var target := _belt(ORIGIN + Vector2i(0, 1), Vector2i.DOWN)
	var early := _belt(ORIGIN, Vector2i.DOWN)
	early.accept_item("early", 1)
	late.accept_item("late", 1)

	_automation.step_tick()

	assert_array(_ids([target] as Array[Conveyor])).is_equal(["early"])

# --- Registration -------------------------------------------------------------


func test_a_placed_conveyor_joins_the_tick_and_a_popped_one_leaves_it() -> void:
	var belt := _belt(ORIGIN, Vector2i.RIGHT)
	assert_int(_automation.conveyors().size()).is_equal(1)
	belt.pop_to_pickup()
	assert_int(_automation.conveyors().size()).is_equal(0)
	_automation.step_tick() # Must not touch the freed node.
	assert_int(_automation.tick_count).is_equal(1)


## ❗️A belt that pops must drop what it was CARRYING, not just itself. Losing the
## cargo is a silent item sink: nothing reports it, and a wave chewing through a
## loaded line would quietly eat the haul it was carrying.
func test_popping_a_loaded_conveyor_drops_its_cargo_too() -> void:
	var belt := _belt(ORIGIN, Vector2i.RIGHT)
	belt.accept_item("copper", 7)

	belt.pop_to_pickup()

	assert_int(_spawner.drops.size()).is_equal(2)
	assert_str(_spawner.drops[0].id).is_equal("conveyor_t1") # The belt itself.
	assert_int(_spawner.drops[0].count).is_equal(1)
	assert_str(_spawner.drops[1].id).is_equal("copper") # What it was carrying.
	assert_int(_spawner.drops[1].count).is_equal(7)
	# ❗️No XP on either: the ore already paid when it was mined, so belt → pop →
	# re-place must not be a fresh looting-XP loop.
	assert_bool(_spawner.drops[1].grants_xp).is_false()


## An empty belt drops exactly one thing. `take_cargo` returning an empty stack
## must not become a zero-count pickup.
func test_popping_an_empty_conveyor_drops_only_itself() -> void:
	_belt(ORIGIN, Vector2i.RIGHT).pop_to_pickup()
	assert_int(_spawner.drops.size()).is_equal(1)
	assert_str(_spawner.drops[0].id).is_equal("conveyor_t1")


## `take_cargo` is destructive on purpose. `pop_to_pickup` re-enters itself
## through `entity_changed`, so a pure read would be one re-entry away from
## duplicating the stack.
func test_taking_the_cargo_empties_the_slot() -> void:
	var belt := _belt(ORIGIN, Vector2i.RIGHT)
	belt.accept_item("copper", 7)
	assert_int(belt.take_cargo().size()).is_equal(1)
	assert_bool(belt.slot_empty()).is_true()
	assert_array(belt.take_cargo()).is_empty()


func test_has_items_in_transit_answers_for_the_whole_registry() -> void:
	var belts := _line(3)
	assert_bool(_automation.has_items_in_transit()).is_false()
	belts[1].accept_item("stone", 1)
	assert_bool(_automation.has_items_in_transit()).is_true()
