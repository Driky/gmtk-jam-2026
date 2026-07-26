## Unit tests for the deployable support re-check (roadmap 3.1) and the 10 Hz
## automation tick (3.2). Runs a fresh Automation against a fresh Terrain —
## never the live autoloads — with _process disabled so the drain and the tick
## happen exactly when a test says so.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const DeployableScript := preload("res://scripts/automation/deployable.gd")
const GameScript := preload("res://scripts/game/game.gd")
const TorchScene := preload("res://scenes/torch.tscn")
const ConveyorScene := preload("res://scenes/automation/conveyor.tscn")

## Playable (x in [50, 150)) and far from world edges.
const CELL := Vector2i(100, 100)
## Directly under CELL — the tile a wall-mounted torch is standing on.
const ANCHOR := CELL + Vector2i.DOWN

var _terrain: Node
var _automation: Node
var _game: Node
var _spawner: SpawnerDouble
## Tick order, appended to by the Counter doubles.
var _order: Array[String] = []


## Records what the real spawner would have dropped, without the autoload
## wiring or a Pickup in the tree.
class SpawnerDouble:
	extends Node

	var drops: Array = []


	func spawn_at(world_pos: Vector2, id: String, count: int, grants_xp := true) -> void:
		drops.append({ pos = world_pos, id = id, count = count, grants_xp = grants_xp })


## Support that also accepts a live Deployable ABOVE. Deliberately NOT the
## shipped rule (a deployable never holds another one up) — it exists to build a
## chain deep enough that a recursive drain would blow the stack, which is the
## only way to prove the shipped drain is iterative. One-directional, or a row
## would hold itself up circularly and never pop at all. Hung downward rather
## than sideways because the world is only 200 columns wide but 1200 rows deep.
class Linked:
	extends Deployable

	func is_supported(t: Node) -> bool:
		if super.is_supported(t):
			return true
		return t.get_entity(cell() + Vector2i.UP) is Deployable


## Counts the ticks it was handed and appends its label to a shared log, so a
## test can assert the ORDER the registry was walked in. Stands in for 3.3's
## miner: the machine phase is a real loop over a real registry even though
## nothing ships a machine yet.
class Counter:
	extends Deployable

	## The suite's own array, shared by reference.
	var log_sink: Array[String] = []
	var label := ""
	var ticks := 0


	func on_tick(_terrain: Node) -> void:
		ticks += 1
		log_sink.append(label)


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)
	_spawner = auto_free(SpawnerDouble.new())
	_spawner.add_to_group(&"pickup_spawner")
	add_child(_spawner)
	# Not in the tree: game.gd's _ready reaches for the live Terrain autoload,
	# and the tick gate only ever reads `state`.
	_game = auto_free(GameScript.new())
	_game.state = GameScript.State.BUILD_PHASE
	_automation = auto_free(AutomationScript.new())
	_automation.terrain = _terrain
	_automation.game = _game
	add_child(_automation) # _ready wires the two Terrain signals.
	# The drain is a test's own business here; a stray frame must not do it first.
	_automation.set_process(false)
	_order = []


func _torch_at(cell: Vector2i) -> Torch:
	var torch: Torch = auto_free(TorchScene.instantiate())
	torch.setup(cell)
	add_child(torch)
	torch.register(_terrain)
	return torch


func _deployable_at(cell: Vector2i, dirs := Deployable.SUPPORT_ALL) -> Deployable:
	var node: Deployable = auto_free(DeployableScript.new())
	node.support_dirs = dirs
	node.item_id = "torch"
	node.setup(cell)
	add_child(node)
	node.register(_terrain)
	return node

# --- Losing support ----------------------------------------------------------


## The visible proof of the whole feature: mine the tile a torch is mounted on
## and it drops as a pickup instead of hanging in mid-air.
func test_mining_the_tile_a_torch_is_mounted_on_pops_it() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	var torch := _torch_at(CELL)
	_automation.drain_support_queue() # Settle the registration's own signals.

	_terrain.damage_tile(ANCHOR, 999.0, 99, TerrainScript.Source.PLAYER)
	_automation.drain_support_queue()

	assert_object(_terrain.get_entity(CELL)).is_null()
	assert_int(_spawner.drops.size()).is_equal(1)
	assert_str(_spawner.drops[0].id).is_equal("torch")
	assert_bool(torch.is_queued_for_deletion()).is_true()
	_terrain.debug_validate()


## A torch with a second wall behind it is still mounted — the check asks the
## whole bitmask, not just the neighbour that happened to change.
func test_a_torch_with_a_second_neighbour_survives_the_same_mine() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	_terrain.set_tile(CELL + Vector2i.LEFT, "dirt")
	var torch := _torch_at(CELL)
	_automation.drain_support_queue()

	_terrain.damage_tile(ANCHOR, 999.0, 99, TerrainScript.Source.PLAYER)
	_automation.drain_support_queue()

	assert_object(_terrain.get_entity(CELL)).is_same(torch)
	assert_array(_spawner.drops).is_empty()


## `0` is the opt-out, and it has to hold under the re-check too — a free-
## floating machine must never pop just because a tile near it changed.
func test_a_zero_support_deployable_never_pops() -> void:
	var node := _deployable_at(CELL, Deployable.SUPPORT_NONE)
	_automation.queue_support_check(CELL)
	_automation.drain_support_queue()
	assert_object(_terrain.get_entity(CELL)).is_same(node)


## O(1) per mined tile is the whole budget argument: only the five cells a
## change can touch are probed, so digging across the map costs nothing.
func test_a_distant_tile_change_queues_nothing() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	_torch_at(CELL)
	_automation.drain_support_queue()

	_terrain.set_tile(CELL + Vector2i(3, 0), "dirt")
	assert_int(_automation.pending_checks()).is_equal(0)


## Registration emits one entity_changed per occupied cell, and a change beside
## a big machine can touch several of them — but a pop is one machine and one
## item on the floor, however many times it was queued.
func test_a_multi_cell_deployable_pops_once_however_many_cells_are_queued() -> void:
	var floor_cell := CELL + Vector2i(0, 2)
	_terrain.set_tile(floor_cell, "dirt")
	var big: Deployable = auto_free(DeployableScript.new())
	big.size = Vector2i(2, 2)
	big.item_id = "torch"
	big.setup(CELL)
	add_child(big)
	assert_bool(big.register(_terrain)).is_true()
	_automation.drain_support_queue() # Standing on the floor.

	_terrain.damage_tile(floor_cell, 999.0, 99, TerrainScript.Source.PLAYER)
	for cell: Vector2i in big.footprint():
		_automation.queue_support_check(cell) # As several nearby changes would.
	assert_int(_automation.pending_checks()).is_equal(4)
	_automation.drain_support_queue()

	assert_int(_spawner.drops.size()).is_equal(1)
	for cell: Vector2i in Deployable.footprint_at(CELL, Vector2i(2, 2)):
		assert_object(_terrain.get_entity(cell)).is_null()
	_terrain.debug_validate()

# --- Coalescing & iteration --------------------------------------------------


## Fifty changes around one torch must cost one check, not fifty. The dedupe is
## the entire reason this needs no timer.
func test_fifty_changes_around_one_torch_coalesce_into_one_check() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	_torch_at(CELL)
	_automation.drain_support_queue()

	for i in 50:
		_automation.queue_support_check(CELL)
	assert_int(_automation.pending_checks()).is_equal(1)
	_automation.drain_support_queue()
	assert_int(_automation.pending_checks()).is_equal(0)


## ❗️The test that fails under a recursive implementation. A 200-long chain,
## anchored by one tile: mining it has to unwind the whole row inside a single
## drain, each link popping exactly once and nothing running out of stack.
func test_one_drain_unwinds_a_two_hundred_long_chain() -> void:
	const CHAIN := 200
	var ceiling := CELL + Vector2i.UP
	_terrain.set_tile(ceiling, "dirt") # The only real support in the column.
	for i in CHAIN:
		var link: Deployable = auto_free(Linked.new())
		link.item_id = "torch"
		link.setup(CELL + Vector2i(0, i))
		add_child(link)
		assert_bool(link.register(_terrain)).is_true()
	_automation.drain_support_queue()
	assert_int(_spawner.drops.size()).is_equal(0) # The chain is standing.

	_terrain.damage_tile(ceiling, 999.0, 99, TerrainScript.Source.PLAYER)
	_automation.drain_support_queue()

	assert_int(_spawner.drops.size()).is_equal(CHAIN) # Each popped exactly once.
	for i in CHAIN:
		assert_object(_terrain.get_entity(CELL + Vector2i(0, i))).is_null()
	assert_int(_automation.pending_checks()).is_equal(0)
	_terrain.debug_validate()

# --- The 10 Hz tick (3.2) ----------------------------------------------------


func _counter_at(cell: Vector2i, label: String) -> Counter:
	var node: Counter = auto_free(Counter.new())
	node.label = label
	node.log_sink = _order
	node.support_dirs = Deployable.SUPPORT_NONE
	node.setup(cell)
	add_child(node)
	node.register(_terrain)
	return node


## TICK_HZ ticks per second of accumulated time, fed one ordinary frame at a
## time. 101 frames rather than 100: `TICK_INTERVAL` is 0.1, which no binary
## float represents exactly, so a run of exactly ten intervals sits right on the
## comparison boundary and the assertion would be testing rounding rather than
## the accumulator.
func test_a_second_of_frames_runs_ten_ticks() -> void:
	for i in 101:
		_automation.advance(0.01)
	assert_int(_automation.tick_count).is_equal(AutomationScript.TICK_HZ)


## The accumulator subtracts the interval instead of resetting, so the remainder
## of a long frame carries into the next one. Under a reset this would read 1
## then 1; the carried 0.05 is exactly what gets dropped.
func test_a_long_frame_carries_its_remainder() -> void:
	_automation.advance(0.25) # Two whole intervals plus half of a third.
	assert_int(_automation.tick_count).is_equal(2)
	_automation.advance(0.06) # The carried 0.05 completes the third.
	assert_int(_automation.tick_count).is_equal(3)


## ❗️The clamp that keeps a backgrounded browser tab from hanging the page:
## Chrome hands back one enormous delta, and without this the factory would run
## hundreds of ticks inside a single frame.
func test_a_ten_second_frame_runs_only_the_catch_up_limit() -> void:
	_automation.advance(10.0)
	assert_int(_automation.tick_count).is_equal(AutomationScript.MAX_CATCH_UP)
	# And the backlog is dropped rather than paid off over the next frames.
	_automation.advance(1.0 / 60.0)
	assert_int(_automation.tick_count).is_equal(AutomationScript.MAX_CATCH_UP)


func test_no_tick_outside_the_playable_phases() -> void:
	_game.state = GameScript.State.GENERATING
	_automation.advance(1.0)
	assert_int(_automation.tick_count).is_equal(0)


## ❗️The factory keeps running *during* a wave — that is the fantasy (plan.md),
## and this gate is the one thing that could quietly break it.
func test_the_tick_runs_during_the_wave_phase() -> void:
	_game.state = GameScript.State.WAVE_PHASE
	_automation.advance(1.0)
	assert_int(_automation.tick_count).is_equal(AutomationScript.MAX_CATCH_UP)


## tick_alpha is the renderer's only input: 0 right after a tick, climbing to 1
## as the next one comes due.
func test_tick_alpha_tracks_the_interval() -> void:
	assert_float(_automation.tick_alpha()).is_equal_approx(0.0, 0.001)
	_automation.advance(AutomationScript.TICK_INTERVAL * 0.5)
	assert_float(_automation.tick_alpha()).is_equal_approx(0.5, 0.001)
	_automation.advance(AutomationScript.TICK_INTERVAL * 0.5)
	assert_int(_automation.tick_count).is_equal(1)
	assert_float(_automation.tick_alpha()).is_equal_approx(0.0, 0.001)


func test_a_registered_machine_is_ticked_once_per_tick() -> void:
	var machine := _counter_at(CELL, "m")
	_automation.register_machine(machine)
	_automation.step_tick()
	_automation.step_tick()
	assert_int(machine.ticks).is_equal(2)


## ❗️Row-major by cell, NOT insertion order. Registered back-to-front on
## purpose: insertion order is reproducible within a session but not across
## 4.3's save/load, which restores entities in file order.
func test_machines_tick_in_row_major_order_not_insertion_order() -> void:
	# Registered bottom-right first, so insertion order is the reverse of the
	# answer this has to produce.
	_automation.register_machine(_counter_at(CELL + Vector2i(1, 1), "d"))
	_automation.register_machine(_counter_at(CELL + Vector2i(0, 1), "c"))
	_automation.register_machine(_counter_at(CELL + Vector2i(1, 0), "b"))
	_automation.register_machine(_counter_at(CELL, "a"))
	_automation.step_tick()
	assert_array(_order).is_equal(["a", "b", "c", "d"])


## Placing during a run has to re-sort, or everything placed after the first
## tick ticks in insertion order forever.
func test_a_machine_registered_after_the_first_tick_still_sorts_in() -> void:
	_automation.register_machine(_counter_at(CELL + Vector2i(1, 0), "b"))
	_automation.step_tick()
	_order.clear()
	_automation.register_machine(_counter_at(CELL, "a"))
	_automation.step_tick()
	assert_array(_order).is_equal(["a", "b"])


func test_unregistering_takes_a_machine_out_of_the_tick() -> void:
	var machine := _counter_at(CELL, "m")
	_automation.register_machine(machine)
	_automation.unregister_machine(machine)
	_automation.step_tick()
	assert_int(machine.ticks).is_equal(0)

# --- Run state ---------------------------------------------------------------


## ❗️A cell surviving a restart re-checks something else entirely in the new
## world. Easy to forget, invisible when wrong.
func test_reset_run_clears_the_queue() -> void:
	_terrain.set_tile(ANCHOR, "dirt")
	_torch_at(CELL)
	_automation.queue_support_check(CELL)
	assert_int(_automation.pending_checks()).is_greater(0)
	_automation.reset_run()
	assert_int(_automation.pending_checks()).is_equal(0)


## The dedupe dict has to be cleared alongside the array, or every cell queued
## before the restart is silently un-queueable afterwards.
func test_a_cell_queued_before_reset_can_be_queued_again() -> void:
	_automation.queue_support_check(CELL)
	_automation.reset_run()
	_automation.queue_support_check(CELL)
	assert_int(_automation.pending_checks()).is_equal(1)


## ❗️Deployables are children of Main and die with the scene reload without ever
## being popped, so a surviving registry would hold freed references and the
## first tick of the new run would fault on them.
func test_reset_run_empties_the_registries_and_zeroes_the_tick() -> void:
	_automation.register_machine(_counter_at(CELL, "m"))
	_automation.register_inserter(_counter_at(CELL + Vector2i(2, 0), "i"))
	var belt: Conveyor = auto_free(ConveyorScene.instantiate())
	belt.automation = _automation
	belt.setup(CELL + Vector2i(4, 0))
	add_child(belt)
	belt.register(_terrain)
	belt.on_placed()
	_automation.step_tick()
	assert_int(_automation.tick_count).is_equal(1)

	_automation.reset_run()

	assert_int(_automation.tick_count).is_equal(0)
	assert_array(_automation.inserters()).is_empty()
	assert_array(_automation.conveyors()).is_empty()
	_order.clear()
	_automation.step_tick()
	assert_array(_order).is_empty()

# --- Idle machines (3.3) -----------------------------------------------------


## Reports whatever a test tells it to, so the counter is exercised without
## building a miner and a deposit for it.
class Idler:
	extends Deployable

	var idle := false


	func is_idle() -> bool:
		return idle


func _idler_at(cell: Vector2i, idle: bool) -> Idler:
	var node: Idler = auto_free(Idler.new())
	node.idle = idle
	node.setup(cell)
	add_child(node)
	return node


func test_the_idle_count_tallies_only_the_idle_machines() -> void:
	var dry := _idler_at(CELL, true)
	_automation.register_machine(dry)
	_automation.register_machine(_idler_at(CELL + Vector2i(2, 0), false))

	_automation.step_tick()
	assert_int(_automation.idle_machines()).is_equal(1)

	dry.idle = false
	_automation.step_tick()
	assert_int(_automation.idle_machines()).is_equal(0)


## ❗️Emitted on a TRANSITION, not every tick — the signal drives a HUD label,
## and 10 repaints a second for an unchanged number is a redraw for nothing.
func test_the_idle_signal_fires_only_on_a_change() -> void:
	var counts: Array[int] = []
	_automation.idle_machines_changed.connect(
		func(count: int) -> void:
			counts.append(count),
	)
	var dry := _idler_at(CELL, true)
	_automation.register_machine(dry)

	for i in 5:
		_automation.step_tick()
	dry.idle = false
	for i in 5:
		_automation.step_tick()

	assert_array(counts).contains_exactly([1, 0])


## A machine that goes away stops being counted — a popped miner must not leave
## a permanent alert on screen.
func test_a_popped_machine_leaves_the_idle_count() -> void:
	var dry := _idler_at(CELL, true)
	dry.register(_terrain)
	_automation.register_machine(dry)
	_automation.step_tick()
	assert_int(_automation.idle_machines()).is_equal(1)

	_automation.unregister_machine(dry)
	_automation.step_tick()

	assert_int(_automation.idle_machines()).is_equal(0)


func test_reset_run_zeroes_the_idle_count() -> void:
	_automation.register_machine(_idler_at(CELL, true))
	_automation.step_tick()
	assert_int(_automation.idle_machines()).is_equal(1)

	_automation.reset_run()

	assert_int(_automation.idle_machines()).is_equal(0)
	assert_array(_automation.machines()).is_empty()

# --- Power (3.4) --------------------------------------------------------------


## Stands in for a generator without the fuel economy: it reports whatever
## supply a test says, and records that the tick asked it to burn.
class Supply:
	extends PowerEmitter

	var output := 0.0
	var burns := 0
	var dry := false


	func burn_tick() -> void:
		burns += 1


	func power_supply() -> float:
		return output


	func is_idle() -> bool:
		return dry


## A machine that only exists to draw power, so the demand and ratio arithmetic
## is exercised without a miner and a deposit.
class Drawing:
	extends Deployable

	var seen_ratio := -1.0
	var acted := 0


	func on_tick(_terrain: Node) -> void:
		seen_ratio = power_ratio()
		if spend_power_tick():
			acted += 1


## `radius` is in TILES, exactly as a scene authors it.
func _emitter_at(cell: Vector2i, radius: float, output := 0.0) -> Supply:
	var node: Supply = auto_free(Supply.new())
	node.automation = _automation
	node.power_radius = radius
	node.output = output
	node.setup(cell)
	add_child(node)
	node.on_placed()
	return node


func _drawing_at(cell: Vector2i, demand := 1.0) -> Drawing:
	var node: Drawing = auto_free(Drawing.new())
	node.power_demand = demand
	node.setup(cell)
	add_child(node)
	_automation.register_machine(node)
	return node


func test_an_emitter_joins_and_leaves_the_registry_through_the_virtuals() -> void:
	var emitter := _emitter_at(CELL, 4.0)
	assert_array(_automation.emitters()).contains_exactly([emitter])

	emitter.on_removed()

	assert_array(_automation.emitters()).is_empty()


## Fuel burns whether or not anything is drawing — [terrain.md] says so, and it
## is what makes the coal deposit tier mean something.
func test_every_emitter_is_asked_to_burn_once_per_tick() -> void:
	var emitter := _emitter_at(CELL, 4.0, 5.0)
	_automation.step_tick()
	_automation.step_tick()
	assert_int(emitter.burns).is_equal(2)


## ❗️The graph is rebuilt on place/remove ONLY, never per tick. Proved by
## sliding an emitter behind the registry's back: the grid keeps the position it
## was built with, because nothing told it anything moved.
func test_the_graph_is_rebuilt_only_when_the_emitter_set_changes() -> void:
	var emitter := _emitter_at(CELL, 4.0, 5.0)
	_automation.step_tick()
	var built_at: Vector2 = _automation.power_grid().centre_of(0)

	emitter.global_position += Vector2(500.0, 0.0)
	_automation.step_tick()

	assert_vector(_automation.power_grid().centre_of(0)).is_equal(built_at)


func test_placing_a_second_emitter_rebuilds_the_graph() -> void:
	_emitter_at(CELL, 4.0, 5.0)
	_automation.step_tick()
	assert_int(_automation.power_grid().emitter_count()).is_equal(1)

	_emitter_at(CELL + Vector2i(50, 0), 4.0, 5.0)
	_automation.step_tick()

	assert_int(_automation.power_grid().emitter_count()).is_equal(2)
	assert_int(_automation.power_grid().component_count()).is_equal(2)


func test_a_machine_inside_a_fuelled_radius_is_stamped_at_full_rate() -> void:
	_emitter_at(CELL, 4.0, 10.0)
	var machine := _drawing_at(CELL + Vector2i(2, 0))

	_automation.step_tick()

	assert_float(machine.power_ratio()).is_equal_approx(1.0, 0.0001)
	assert_bool(machine.is_powered()).is_true()


## ❗️The seam 3.3 shipped stubbed: outside every circle, a machine that draws
## power does nothing at all.
func test_a_machine_outside_every_radius_is_stamped_dead() -> void:
	_emitter_at(CELL, 4.0, 10.0)
	var machine := _drawing_at(CELL + Vector2i(40, 0))

	for i in 10:
		_automation.step_tick()

	assert_float(machine.power_ratio()).is_equal_approx(0.0, 0.0001)
	assert_bool(machine.is_powered()).is_false()
	assert_int(machine.acted).is_equal(0)


## A relay covers, but supplies nothing — coverage alone does not run a factory.
func test_a_radius_with_no_supply_powers_nothing() -> void:
	_emitter_at(CELL, 4.0) # output 0.0: a relay.
	var machine := _drawing_at(CELL + Vector2i(1, 0))

	_automation.step_tick()

	assert_bool(machine.is_powered()).is_false()


## Demand is summed across every machine on the component before any ratio
## exists — which is why the pass is two loops, not one.
func test_demand_is_summed_per_component() -> void:
	_emitter_at(CELL, 4.0, 2.0)
	var a := _drawing_at(CELL + Vector2i(1, 0))
	var b := _drawing_at(CELL + Vector2i(2, 0))
	var c := _drawing_at(CELL + Vector2i(3, 0))
	var d := _drawing_at(CELL + Vector2i(-1, 0))

	_automation.step_tick()

	var grid: PowerGrid = _automation.power_grid()
	assert_float(grid.demand_of(0)).is_equal_approx(4.0, 0.0001)
	for machine: Drawing in [a, b, c, d]:
		assert_float(machine.power_ratio()).is_equal_approx(0.5, 0.0001)


## ❗️The ordering proof: every machine sees the SAME ratio on the tick it runs,
## whichever position it holds in the row-major walk. A single-pass solver would
## give the first machine 1.0 and the last one 0.25.
func test_every_machine_sees_the_final_ratio_on_the_tick_it_runs() -> void:
	_emitter_at(CELL, 4.0, 2.0)
	var first := _drawing_at(CELL + Vector2i(-1, 0))
	var last := _drawing_at(CELL + Vector2i(3, 0))
	_drawing_at(CELL + Vector2i(1, 0))
	_drawing_at(CELL + Vector2i(2, 0))

	_automation.step_tick()

	assert_float(first.seen_ratio).is_equal_approx(0.5, 0.0001)
	assert_float(last.seen_ratio).is_equal_approx(0.5, 0.0001)


## Two generators too far apart to touch are two economies: starving one must
## not slow the other.
func test_separate_grids_do_not_share_supply() -> void:
	_emitter_at(CELL, 4.0, 10.0)
	_emitter_at(CELL + Vector2i(60, 0), 4.0, 0.0)
	var fed := _drawing_at(CELL + Vector2i(1, 0))
	var starved := _drawing_at(CELL + Vector2i(61, 0))

	_automation.step_tick()

	assert_float(fed.power_ratio()).is_equal_approx(1.0, 0.0001)
	assert_float(starved.power_ratio()).is_equal_approx(0.0, 0.0001)


## ❗️ANY footprint cell inside the disc powers the whole machine — a 3×2 with one
## corner covered is fair, and a visibly half-covered machine that is dead reads
## as a bug.
func test_a_machine_with_one_footprint_cell_in_range_is_powered() -> void:
	_emitter_at(CELL, 2.0, 10.0)
	var machine: Drawing = auto_free(Drawing.new())
	machine.power_demand = 1.0
	machine.size = Vector2i(3, 2)
	# ❗️Anchored so the origin cell — the FIRST one the walk visits — is outside
	# the circle and only the far column is inside. A check that stopped at the
	# origin (or at the centre) would pass every other test here and fail this one.
	machine.setup(CELL + Vector2i(-3, 0))
	add_child(machine)
	_automation.register_machine(machine)

	_automation.step_tick()

	assert_bool(machine.is_powered()).is_true()


## A machine authored with no demand keeps the base's 1.0 rather than being
## stamped dead for standing outside every circle — otherwise the slot overlay
## would report a free machine as browned out.
func test_a_zero_demand_machine_is_never_stamped() -> void:
	_emitter_at(CELL, 2.0, 10.0)
	var free := _drawing_at(CELL + Vector2i(40, 0), 0.0)

	_automation.step_tick()

	assert_float(free.power_ratio()).is_equal_approx(1.0, 0.0001)
	assert_int(free.acted).is_equal(1)
	assert_float(_automation.power_grid().demand_of(0)).is_equal_approx(0.0, 0.0001)


## ❗️A generator with no fuel joins the HUD's idle tally beside a dry miner: both
## mean "come and feed me", and this one stops the whole factory.
func test_a_dry_emitter_is_counted_by_the_idle_tally() -> void:
	var generator := _emitter_at(CELL, 4.0)
	generator.dry = true
	_automation.register_machine(_idler_at(CELL + Vector2i(6, 0), true))

	_automation.step_tick()

	assert_int(_automation.idle_machines()).is_equal(2)

	generator.dry = false
	_automation.step_tick()

	assert_int(_automation.idle_machines()).is_equal(1)


## ❗️Emitters die with the scene reload without ever being popped, exactly like
## the other three registries — and the grid is derived from their positions, so
## a surviving graph would hand out coverage from generators that are gone.
func test_reset_run_clears_the_emitters_and_drops_the_grid() -> void:
	_emitter_at(CELL, 4.0, 10.0)
	_automation.step_tick()
	assert_object(_automation.power_grid()).is_not_null()

	_automation.reset_run()

	assert_array(_automation.emitters()).is_empty()
	assert_object(_automation.power_grid()).is_null()
	# And the next run's first tick builds a fresh, empty one rather than faulting.
	_automation.step_tick()
	assert_int(_automation.power_grid().component_count()).is_equal(0)
