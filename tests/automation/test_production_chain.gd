## The 3.3 exit criterion, end to end (roadmap 3.3): a deposit becomes bars on a
## belt with nobody clicking anything.
##
##     miner → inserter → belt → inserter → furnace → inserter → belt
##
## and since 3.5a all the way to something that shoots:
##
##     → inserter → ammo press → inserter → belt → inserter → turret
##
## Every piece has its own suite; this one exists because the *seams between
## them* are where a factory that looks right produces nothing — a station that
## hands its input back, an inserter that never sees a machine as a source, a
## tick order that stalls a hand-off by a tick each hop.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const MinerScene := preload("res://scenes/automation/miner.tscn")
const FurnaceScene := preload("res://scenes/automation/furnace.tscn")
const ConveyorScene := preload("res://scenes/automation/conveyor.tscn")
const InserterScene := preload("res://scenes/automation/inserter.tscn")
const GeneratorScene := preload("res://scenes/automation/generator.tscn")
const AmmoPressScene := preload("res://scenes/automation/ammo_press.tscn")
const TurretScene := preload("res://scenes/automation/turret.tscn")
const PoolScript := preload("res://scripts/combat/projectile_pool.gd")

## Playable (x in [50, 150)) and far from world edges.
const ORIGIN := Vector2i(80, 100)
## Where the chain's power comes from — above the line, well inside its own reach
## of every machine on it.
const POWER_CELL := ORIGIN + Vector2i(2, -3)
## Far enough that no footprint cell of the chain is inside the disc, so the
## negative twin is genuinely "out of radius" rather than "just barely".
const FAR_POWER_CELL := ORIGIN + Vector2i(60, 0)
## Tiles; covers the whole line from POWER_CELL — widened at 3.5a when the line
## grew a press and a turret on the far end.
const POWER_RADIUS := 20.0
## More than enough coal for RUN_TICKS, so these tests measure the chain rather
## than the fuel burn — `test_generator.gd` owns that.
const FUEL_STACK := 20
## Generous: the chain has three cooldowns in series (miner 10, three inserters
## at 5) plus a 20-tick smelt, and this asserts arrival, not throughput.
const RUN_TICKS := 200
## The 3.5a tail adds a 20-tick press and three more inserter hops behind the
## 3.3 chain, so the full run to a loaded turret needs its own budget.
const LONG_RUN_TICKS := 500


## The turret asks its aggro helper for targets; this suite has no business
## spawning real mobs into a fixture that is about item flow.
class WavesDouble:
	extends Node

	var mobs: Array[Node] = []


	func enemies() -> Array[Node]:
		return mobs


class MobDouble:
	extends Node2D

	func take_damage(_amount: float, _attacker: Node2D = null) -> void:
		pass


var _terrain: Node
var _automation: Node
var _game: Node
var _waves: WavesDouble
var _pool: ProjectilePool


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)
	_game = auto_free(GameScript.new()) # Out of the tree: only `state` is read.
	_game.state = GameScript.State.BUILD_PHASE
	_automation = auto_free(AutomationScript.new())
	_automation.terrain = _terrain
	_automation.game = _game
	add_child(_automation)
	_automation.set_process(false)
	_waves = auto_free(WavesDouble.new())
	add_child(_waves)
	_pool = auto_free(PoolScript.new())
	add_child(_pool)


## A real generator, hand-fed real coal. ❗️Deliberately not a supply double: the
## bootstrap this whole tier rests on is "mine coal by hand, feed the generator,
## the factory runs", and a double would test the chain against a power source
## the player cannot build.
func _power_at(cell: Vector2i) -> Generator:
	var node: Generator = auto_free(GeneratorScene.instantiate())
	node.automation = _automation
	# Widened from the authored 8: this fixture is about the chain, not reach.
	node.power_radius = POWER_RADIUS
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	assert_int(node.accept_item("coal", FUEL_STACK)).is_equal(FUEL_STACK)
	return node


func _place(scene: PackedScene, cell: Vector2i, dir := Vector2i.RIGHT) -> Deployable:
	var node: Deployable = auto_free(scene.instantiate())
	node.automation = _automation
	node.facing = dir
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	return node


## The whole chain, laid out on one row (y = 100; the miner and the furnace are
## two rows tall, everything else is one).
##
##   x:  74..76  77..79  80   81  82   83   84..85  86   87
##       ore     MINER   ins  belt belt ins  FURNACE ins  belt
##
## The miner faces LEFT so its harvest block lands on the ore at x 74–76; every
## inserter faces RIGHT, so each picks from the cell behind and drops in front.
##
## ❗️Both belts hand off through an INSERTER, never straight into the furnace:
## a belt facing a machine JAMS ([automation.md](../../docs/systems/automation.md)
## §Categories → Inserter), and that rule is deliberately unchanged at 3.3. The
## jam is what the second inserter then pulls from.
##
## ❗️**Since 3.4 the chain also needs POWER.** The miner and the furnace both
## draw, and `is_powered()` is no longer a stub — so an emitter over the line is
## as structural to this fixture as the floor under it. `power_cell` is a
## parameter for exactly one reason: the negative twin below moves it out of
## range and asserts the chain produces nothing.
func _build(power_cell := POWER_CELL) -> Dictionary:
	_power_at(power_cell)
	var miner_cell := ORIGIN + Vector2i(-3, 0) # 3×2 at x 77..79, rows 100–101.
	for ore: Vector2i in Deployable.harvest_cells_at(miner_cell, Vector2i(3, 2), Vector2i.LEFT):
		_terrain.set_tile(ore, "copper_deposit")
	# A floor under the whole line, so the two supported machines stand for the
	# same reason they would in a real placement.
	for x in range(-4, 16):
		_terrain.set_tile(ORIGIN + Vector2i(x, 2), "dirt")
	var chain := {
		miner = _place(MinerScene, miner_cell, Vector2i.LEFT),
		feed_in = _place(InserterScene, ORIGIN),
		belt_a = _place(ConveyorScene, ORIGIN + Vector2i(1, 0)),
		belt_b = _place(ConveyorScene, ORIGIN + Vector2i(2, 0)),
		feed_furnace = _place(InserterScene, ORIGIN + Vector2i(3, 0)),
		furnace = _place(FurnaceScene, ORIGIN + Vector2i(4, 0)),
		feed_out = _place(InserterScene, ORIGIN + Vector2i(6, 0)),
		belt_out = _place(ConveyorScene, ORIGIN + Vector2i(7, 0)),
	}
	return chain


## The 3.5a tail, bolted onto the 3.3 chain rather than replacing it:
##
##   x:  8    9..10   11   12    13   14
##       ins  PRESS   ins  belt  ins  TURRET
##
## The press picks bars off `belt_out` and the turret is fed the ammo the same
## way every other machine is fed — through the seam, with nobody clicking.
func _build_defense_tail(chain: Dictionary) -> Dictionary:
	chain.feed_press = _place(InserterScene, ORIGIN + Vector2i(8, 0))
	chain.press = _place(AmmoPressScene, ORIGIN + Vector2i(9, 0))
	chain.feed_ammo = _place(InserterScene, ORIGIN + Vector2i(11, 0))
	chain.belt_ammo = _place(ConveyorScene, ORIGIN + Vector2i(12, 0))
	chain.feed_turret = _place(InserterScene, ORIGIN + Vector2i(13, 0))
	var turret: Turret = _place(TurretScene, ORIGIN + Vector2i(14, 0))
	turret.waves = _waves
	chain.turret = turret
	return chain


func _run(ticks := RUN_TICKS) -> void:
	for i in ticks:
		_automation.step_tick()

# --- The chain ---------------------------------------------------------------


## ❗️The 3.3 exit criterion. Nothing here is hand-fed: the only thing that puts
## an item into the factory is the miner eating the deposit.
func test_ore_becomes_bars_at_the_far_end_with_nobody_clicking() -> void:
	var chain := _build()

	_run()

	var out: Conveyor = chain.belt_out
	assert_bool(out.slot_empty()).override_failure_message(
		"Nothing reached the end of the chain in %d ticks" % RUN_TICKS,
	).is_false()
	assert_str(out.slot().id).is_equal("copper_bar")


## ❗️**The negative twin, and the reason the one above proves anything.** Same
## chain, same ore, same 200 ticks — with the power moved out of reach. Without
## this the end-to-end test would pass just as happily against an `is_powered()`
## that still returned `true` unconditionally.
func test_the_same_chain_out_of_radius_produces_nothing() -> void:
	var chain := _build(FAR_POWER_CELL)

	_run()

	var miner: Miner = chain.miner
	assert_bool(miner.is_powered()).is_false()
	assert_bool(miner.slot_empty()).override_failure_message(
		"An unpowered miner extracted ore",
	).is_true()
	assert_bool((chain.belt_out as Conveyor).slot_empty()).is_true()


## And the gate is not one-way: the chain that was dead comes back the moment a
## generator lands in reach, with no re-placement of anything.
func test_the_dead_chain_starts_the_moment_power_arrives() -> void:
	var chain := _build(FAR_POWER_CELL)
	_run(20)
	assert_bool((chain.miner as Miner).slot_empty()).is_true()

	_power_at(POWER_CELL)
	_run()

	assert_str((chain.belt_out as Conveyor).slot().get("id", "")).is_equal("copper_bar")


## The intermediate hop has to move too — a belt that never receives means the
## inserter is reading the wrong neighbour, which the end-state assertion above
## could hide if the furnace happened to be reachable another way.
func test_the_ore_travels_the_belt_between_the_miner_and_the_furnace() -> void:
	var chain := _build()

	# Long enough for one extraction plus a couple of hand-offs, and well short
	# of the 20-tick smelt, so the ore is still visibly in transit.
	_run(15)

	var furnace: CraftingStation = chain.furnace
	var moved: bool = (
		not (chain.belt_a as Conveyor).slot_empty()
		or not (chain.belt_b as Conveyor).slot_empty()
		or not furnace.input_slot().is_empty()
	)
	assert_bool(moved).override_failure_message(
		"The ore never left the miner",
	).is_true()


## ❗️The fantasy, and the one gate that could quietly break it: the factory
## keeps running once the countdown hits zero and the wave starts
## ([automation.md](../../docs/systems/automation.md) §The 10 Hz tick).
func test_the_chain_keeps_running_during_a_wave() -> void:
	var chain := _build()
	_game.state = GameScript.State.WAVE_PHASE

	for i in RUN_TICKS:
		_automation.advance(AutomationScript.TICK_INTERVAL)

	assert_int(_automation.tick_count).is_greater(0)
	assert_str((chain.belt_out as Conveyor).slot().get("id", "")).is_equal("copper_bar")


## And the same gate the other way: nothing ticks outside the two live phases, so
## a factory does not run through the game-over screen.
func test_the_chain_is_frozen_outside_the_live_phases() -> void:
	var chain := _build()
	_game.state = GameScript.State.GAME_OVER

	for i in RUN_TICKS:
		_automation.advance(AutomationScript.TICK_INTERVAL)

	assert_int(_automation.tick_count).is_equal(0)
	assert_bool((chain.belt_out as Conveyor).slot_empty()).is_true()


## Back-pressure end to end: cut the chain at the last hop and everything behind
## it fills and stops, rather than spilling items on the floor or eating them.
func test_a_blocked_tail_jams_the_chain_without_losing_anything() -> void:
	var chain := _build()
	(chain.feed_out as Deployable).pop_to_pickup() # Nothing takes the bars out.

	_run()

	var furnace: CraftingStation = chain.furnace
	assert_int(furnace.output_slot().count).is_greater(0)
	assert_bool((chain.belt_out as Conveyor).slot_empty()).is_true()

# --- The defense tail (3.5a) --------------------------------------------------


## ❗️**The 3.5a exit criterion, minus the physics.** A deposit becomes loaded
## ammo inside a turret with nobody clicking anything — four machines, five
## inserters and three belts, and the only thing putting an item into the factory
## is still the miner eating the deposit.
##
## The shot itself is asserted below rather than here: contact needs real physics
## frames, and this fixture drives `step_tick()` by hand.
func test_a_deposit_becomes_loaded_ammo_in_a_turret_with_nobody_clicking() -> void:
	var chain := _build_defense_tail(_build())

	_run(LONG_RUN_TICKS)

	var turret: Turret = chain.turret
	assert_bool(turret.ammo_slot().is_empty()).override_failure_message(
		"No ammo reached the turret in %d ticks" % LONG_RUN_TICKS,
	).is_false()
	assert_str(turret.ammo_slot().id).is_equal("copper_ammo")
	assert_bool(turret.is_idle()).is_false()


## And the loop closes: the turret the factory loaded shoots at a mob, using the
## projectile its ammo carries. This is the whole point of the tail — a chain
## that ends in a full ammo slot and never fires would pass the test above.
func test_the_turret_the_factory_loaded_actually_fires() -> void:
	var chain := _build_defense_tail(_build())
	_run(LONG_RUN_TICKS)
	var turret: Turret = chain.turret
	var loaded: int = turret.ammo_slot().count

	var mob: MobDouble = auto_free(MobDouble.new())
	mob.position = turret.global_position + Vector2(TileLayout.TILE_SIZE * 2.0, 0.0)
	add_child(mob)
	_waves.mobs.append(mob)
	_automation.step_tick()

	assert_int(_pool.active_count()).is_equal(1)
	assert_int(turret.ammo_slot().count).is_equal(loaded - 1)


## ❗️The fantasy again, one link further out: the turret is fed BY the factory
## while the wave is on, so a defense that runs dry mid-wave refills itself.
func test_the_factory_keeps_feeding_the_turret_during_a_wave() -> void:
	var chain := _build_defense_tail(_build())
	_game.state = GameScript.State.WAVE_PHASE

	for i in LONG_RUN_TICKS:
		_automation.advance(AutomationScript.TICK_INTERVAL)

	assert_str((chain.turret as Turret).ammo_slot().get("id", "")).is_equal("copper_ammo")


## The negative twin, for the tail: no power, no ammo, and therefore a turret
## that is idle rather than one that quietly fires on an empty slot.
func test_an_unpowered_tail_leaves_the_turret_empty_and_idle() -> void:
	var chain := _build_defense_tail(_build(FAR_POWER_CELL))

	_run(LONG_RUN_TICKS)

	var turret: Turret = chain.turret
	assert_bool(turret.ammo_slot().is_empty()).is_true()
	assert_bool(turret.is_idle()).is_true()
	assert_int(_pool.active_count()).is_equal(0)
