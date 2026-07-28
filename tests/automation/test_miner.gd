## Unit tests for the Miner (roadmap 3.3) — the first thing in the game that
## produces an item without a click. Fresh Terrain + Automation per test,
## _process off, so the suite drives `step_tick()` itself.
##
## The cases here are the ones a plausible implementation gets wrong: the
## harvest block's orientation (a silent 50/50, exactly like the inserter's
## behind/front and the support bitmask's Up/Down bit), the 1:1 extraction that
## separates a machine from a pickaxe chip, and the exhaustion tail — where the
## ore must reach the slot and never the floor.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const MinerScene := preload("res://scenes/automation/miner.tscn")

## Playable (x in [50, 150)) and far from world edges.
const ORIGIN := Vector2i(100, 100)
## The authored footprint, restated so a test reads without opening the scene.
const SIZE := Vector2i(3, 2)
## Deliberately huge: this suite is about extraction, not about geometry, so the
## fixture's only job is "there is power here".
const POWER_RADIUS := 64.0


## ❗️Since 3.4 a miner on no grid does not extract at all, so every test here
## needs a supply. Kept as a local double rather than the real generator: this
## suite has no business modelling a fuel economy, and the repo already
## duplicates small doubles per suite (`SpawnerDouble`) rather than sharing them.
class Supply:
	extends PowerEmitter

	func power_supply() -> float:
		return 100.0


## One flat multiplier for every stat (3.7). Injected rather than reaching for the
## autoload, so this suite drives `resource_yield` without spending a skill point.
class ProgressionDouble:
	extends Node

	var multiplier := 1.0


	func get_stat(_stat_name: String) -> float:
		return multiplier


var _terrain: Node
var _automation: Node
var _drops: Array = []
var _broken: Array = []


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
	_drops = []
	_broken = []
	_terrain.drops_spawned.connect(
		func(pos: Vector2i, id: String, count: int, source: int, grants_xp: bool) -> void:
			_drops.append([pos, id, count, source, grants_xp]),
	)
	_terrain.tile_broken.connect(
		func(pos: Vector2i, material_id: String, source: int) -> void:
			_broken.append([pos, material_id, source]),
	)
	_power_the_world()


func _power_the_world() -> void:
	var node: Supply = auto_free(Supply.new())
	node.automation = _automation
	node.power_radius = POWER_RADIUS
	node.setup(ORIGIN)
	add_child(node)
	node.on_placed()


## A miner at `cell` facing `dir`, with `deposit` filling its whole harvest block
## unless a test lays the ore out itself. `yield_multiplier` is what the injected
## `Progression` reports for `resource_yield` — 1.0 is an unbuffed run.
func _miner(
		cell := ORIGIN,
		dir := Vector2i.RIGHT,
		deposit := "coal_deposit",
		yield_multiplier := 1.0,
) -> Miner:
	if deposit != "":
		for ore: Vector2i in Deployable.harvest_cells_at(cell, SIZE, dir):
			_terrain.set_tile(ore, deposit)
	var node: Miner = auto_free(MinerScene.instantiate())
	node.automation = _automation
	var progression: ProgressionDouble = auto_free(ProgressionDouble.new())
	progression.multiplier = yield_multiplier
	node.progression = progression
	node.facing = dir
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	return node

# --- Geometry ----------------------------------------------------------------


## ❗️All four facings in one world, the orientation test this repo demands of
## every silent 50/50. A harvest block on the wrong side gives a miner that never
## finds ore, with no error anywhere — and one that overlaps its own footprint
## gives a miner that cannot be placed at all.
func test_the_harvest_block_is_one_span_along_each_of_the_four_facings() -> void:
	var facings: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	var expected: Array[Vector2i] = [
		Vector2i(3, 0), # RIGHT: one footprint WIDTH sideways.
		Vector2i(0, 2), # DOWN: one footprint HEIGHT down.
		Vector2i(-3, 0),
		Vector2i(0, -2),
	]
	for i in facings.size():
		# Spaced well clear of each other so no two miners share a cell.
		var at := ORIGIN + Vector2i(i * 12, 0)
		var node := _miner(at, facings[i], "")
		assert_array(node.harvest_cells()).contains_exactly(
			Deployable.footprint_at(at + expected[i], SIZE),
		)

# --- Extraction --------------------------------------------------------------


## 1:1 into the output slot, against the pickaxe's 5-reserve-for-1-drop. That
## contrast is the entire reason a machine does not route through `damage_tile`.
func test_it_extracts_reserve_one_for_one_into_its_output_slot() -> void:
	var node := _miner()
	var ore: Vector2i = node.harvest_cells()[0]
	_terrain.set_reserve(ore, 50)

	_automation.step_tick()

	assert_str(node.slot().id).is_equal("coal")
	assert_int(node.slot().count).is_equal(node.extract_count)
	assert_int(_terrain.get_tile_data(ore).reserve).is_equal(50 - node.extract_count)


## Row-major within the block, so a miner straddling two deposits drains them in
## a defined order rather than one that depends on the tick.
func test_it_takes_the_first_deposit_cell_in_row_major_order() -> void:
	var node := _miner(ORIGIN, Vector2i.RIGHT, "")
	var cells := node.harvest_cells()
	for cell: Vector2i in cells:
		_terrain.set_tile(cell, "stone")
	_terrain.set_tile(cells[2], "copper_deposit")
	_terrain.set_tile(cells[4], "iron_deposit")

	_automation.step_tick()

	assert_str(node.slot().id).is_equal("copper")


## One extraction per `extract_ticks`, and not one a tick sooner.
func test_it_waits_out_its_cooldown_between_extractions() -> void:
	var node := _miner()

	_automation.step_tick()
	assert_int(node.slot().count).is_equal(1)
	for i in node.extract_ticks - 1:
		_automation.step_tick()
	assert_int(node.slot().count).is_equal(1) # Still cooling down.
	_automation.step_tick()
	assert_int(node.slot().count).is_equal(2)


## ❗️Back-pressure, and the reason room is checked BEFORE extracting: the seam
## has no way to put ore back in the ground, so a full slot has to leave the
## reserve untouched rather than extract into nothing.
func test_a_full_output_stalls_extraction_instead_of_losing_ore() -> void:
	var node := _miner()
	var ore: Vector2i = node.harvest_cells()[0]
	_terrain.set_reserve(ore, 50)
	node._slot = { id = "coal", count = Inventory.STACK_SIZE }

	for i in node.extract_ticks + 1:
		_automation.step_tick()

	assert_int(node.slot().count).is_equal(Inventory.STACK_SIZE)
	assert_int(_terrain.get_tile_data(ore).reserve).is_equal(50)

# --- resource_yield (3.7) -----------------------------------------------------


## ❗️**The point of the buff: more ore per unit of RESERVE.** A ×1.5 miner over
## ten extractions hands out fifteen and the deposit is down by ten — because the
## cursor inspector puts "Copper Deposit — 43 ore left" on screen, and a reserve
## billed for the bonus would make that readout a lie.
func test_a_buffed_miner_outputs_more_ore_than_it_took_from_the_ground() -> void:
	var node := _miner(ORIGIN, Vector2i.RIGHT, "coal_deposit", 1.5)
	var ore: Vector2i = node.harvest_cells()[0]
	_terrain.set_reserve(ore, 50)

	for i in node.extract_ticks * 9 + 1:
		_automation.step_tick()

	assert_int(node.slot().count).is_equal(15)
	assert_int(_terrain.get_tile_data(ore).reserve).is_equal(40)


## ⚠️ Bit-identical to the miner that existed before 3.7 — the property the
## accumulator is built around, not the arithmetic.
func test_an_unbuffed_miner_is_unchanged() -> void:
	var node := _miner()
	var ore: Vector2i = node.harvest_cells()[0]
	_terrain.set_reserve(ore, 50)

	for i in node.extract_ticks * 9 + 1:
		_automation.step_tick()

	assert_int(node.slot().count).is_equal(10)
	assert_int(_terrain.get_tile_data(ore).reserve).is_equal(40)


## ❗️A stalled miner must not bank a bonus per stalled TICK: the credit would
## grow while the line is jammed and dump a pile the moment it drains.
func test_a_full_output_stalls_without_burning_credit() -> void:
	var node := _miner(ORIGIN, Vector2i.RIGHT, "coal_deposit", 1.5)
	var ore: Vector2i = node.harvest_cells()[0]
	_terrain.set_reserve(ore, 50)
	node._slot = { id = "coal", count = Inventory.STACK_SIZE }

	for i in node.extract_ticks * 5:
		_automation.step_tick()

	assert_float(node.yield_credit()).is_equal_approx(0.0, 0.0001)
	assert_int(_terrain.get_tile_data(ore).reserve).is_equal(50)


## A second ore in the block must not be merged onto a mismatched stack — one
## slot cannot hold two ids, and taking it anyway would destroy it.
func test_it_refuses_a_second_ore_while_holding_a_different_one() -> void:
	var node := _miner(ORIGIN, Vector2i.RIGHT, "")
	var cells := node.harvest_cells()
	_terrain.set_tile(cells[0], "iron_deposit")
	node._slot = { id = "coal", count = 1 }

	_automation.step_tick()

	assert_str(node.slot().id).is_equal("coal")
	assert_int(node.slot().count).is_equal(1)


## ❗️The anti-farm rule, and the whole reason `extract_reserve` exists beside
## `damage_tile`: a drained deposit becomes air and emits ONE machine-sourced
## break, and the ore it gave up never touches the floor — so it pays nothing on
## either XP channel.
func test_a_drained_deposit_becomes_air_with_no_drops() -> void:
	var node := _miner(ORIGIN, Vector2i.RIGHT, "")
	var ore: Vector2i = Deployable.harvest_cells_at(ORIGIN, SIZE, Vector2i.RIGHT)[0]
	_terrain.set_tile(ore, "coal_deposit")
	_terrain.set_reserve(ore, 2)

	for i in node.extract_ticks * 2 + 1:
		_automation.step_tick()

	assert_str(_terrain.get_material_id(ore)).is_equal("")
	assert_array(_drops).is_empty()
	assert_array(_broken).contains_exactly([[ore, "coal_deposit", TerrainScript.Source.MACHINE]])
	assert_int(node.slot().count).is_equal(2)

# --- Idle --------------------------------------------------------------------


## One state for "ran dry" and "never had a deposit". Recomputed per tick,
## because the deposit disappears *underneath* a perfectly placed miner the
## moment its reserve hits zero.
func test_it_reports_idle_only_once_the_block_holds_no_deposit() -> void:
	var node := _miner(ORIGIN, Vector2i.RIGHT, "")
	var ore: Vector2i = node.harvest_cells()[0]
	_terrain.set_tile(ore, "coal_deposit")
	_terrain.set_reserve(ore, 1)

	_automation.step_tick()
	assert_bool(node.is_idle()).is_false()

	_automation.step_tick() # The deposit is now air.
	assert_bool(node.is_idle()).is_true()


func test_a_miner_over_bare_rock_is_idle_from_the_first_tick() -> void:
	var node := _miner(ORIGIN, Vector2i.RIGHT, "stone")
	_automation.step_tick()
	assert_bool(node.is_idle()).is_true()
	assert_bool(node.slot_empty()).is_true()

# --- The transfer seam -------------------------------------------------------


func test_an_inserter_can_take_the_output_but_nothing_can_push_into_it() -> void:
	var node := _miner()
	_automation.step_tick()

	# A miner is not a chest: the base's refusing default stands.
	assert_int(node.accept_item("coal", 1)).is_equal(0)
	var taken: Dictionary = node.extract_item(1)
	assert_str(taken.id).is_equal("coal")
	assert_int(taken.count).is_equal(1)
	assert_bool(node.slot_empty()).is_true()


## Whatever it was holding lands beside it, through the one drop path.
func test_take_cargo_hands_over_the_output_slot_and_empties_it() -> void:
	var node := _miner()
	_automation.step_tick()

	var cargo := node.take_cargo()

	assert_int(cargo.size()).is_equal(1)
	assert_str(cargo[0].id).is_equal("coal")
	assert_bool(node.slot_empty()).is_true()

# --- Placement ---------------------------------------------------------------


## ❗️The placement predicate is what delivers "placed on the deposit" — the
## footprint cannot overlap the ore, because deposits are solid and
## `place_entity` rejects solid cells.
func test_the_placement_predicate_rejects_bare_rock_and_accepts_a_deposit() -> void:
	for cell: Vector2i in Deployable.harvest_cells_at(ORIGIN, SIZE, Vector2i.RIGHT):
		_terrain.set_tile(cell, "stone")
	var nowhere := Rect2i(0, 0, 1, 1)
	assert_bool(
		Player.can_place_at(_terrain, ORIGIN, nowhere, SIZE, 15, Vector2i.RIGHT, true),
	).is_false()

	_terrain.set_tile(ORIGIN + Vector2i(3, 1), "coal_deposit")

	assert_bool(
		Player.can_place_at(_terrain, ORIGIN, nowhere, SIZE, 15, Vector2i.RIGHT, true),
	).is_true()


## The ghost reads the same authoring the placement does — a miner that drew no
## harvest outline would let the player rotate blind.
func test_the_scene_authors_a_three_by_two_that_harvests_and_points() -> void:
	var live: Miner = auto_free(MinerScene.instantiate())
	assert_vector(live.size).is_equal(SIZE)
	assert_bool(live.harvests_deposits).is_true()
	assert_bool(live.directional).is_true()
	assert_str(live.item_id).is_equal("miner")
	assert_vector(Deployable.scene_size(MinerScene)).is_equal(live.size)
	assert_bool(Deployable.scene_harvests(MinerScene)).is_true()
	assert_bool(Player.placement_harvests("miner")).is_true()

# --- Registration ------------------------------------------------------------


func test_a_placed_miner_joins_the_tick_and_a_popped_one_leaves_it() -> void:
	var node := _miner()
	assert_int(_automation.machines().size()).is_equal(1)
	node.pop_to_pickup()
	assert_int(_automation.machines().size()).is_equal(0)
	_automation.step_tick() # Must not touch the freed node.
	assert_int(_automation.tick_count).is_equal(1)
