## Unit tests for climbables (roadmap 3.5b) — the `is_climbable` predicate and
## the ONE rule it carries beyond "you can climb it": a climbable is held up by
## the climbable **below** it. Fresh Terrain + Automation per test, `_process`
## off, so the suite drives the support drain itself.
##
## The clause lives on the `Deployable` base and is carried by the export, not by
## the `Ladder` class — 4.1's rope and pole get the whole rule by authoring one
## bool — so the clause tests run against a bare climbable `Deployable`, and only
## the authoring section reads the scene.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const DeployableScript := preload("res://scripts/automation/deployable.gd")
const GameScript := preload("res://scripts/game/game.gd")
const LadderScene := preload("res://scenes/automation/ladder.tscn")

## Playable (x in [50, 150)) and far from world edges. The floor sits one below.
const ORIGIN := Vector2i(100, 100)
const FLOOR_CELL := Vector2i(100, 101)

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


## A registered 1×1 climbable at `cell`, mounting in every direction like the
## authored ladder.
func _rung(cell: Vector2i, climbable := true) -> Deployable:
	var node: Deployable = auto_free(DeployableScript.new())
	node.is_climbable = climbable
	node.item_id = "ladder"
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	return node

# --- The predicate ------------------------------------------------------------


## `climbable_at` is what the player's climb, the flow field, `EnemyLocomotion`
## and `Enemy._attackable_entity` all ask — through `as Deployable`, so a plain
## `Node2D` (the Core) answers false with no special case anywhere.
func test_climbable_at_reads_the_export_off_whatever_holds_the_cell() -> void:
	assert_bool(Deployable.climbable_at(_terrain, ORIGIN)).is_false()
	_rung(ORIGIN)
	assert_bool(Deployable.climbable_at(_terrain, ORIGIN)).is_true()

	var plain := ORIGIN + Vector2i(2, 0)
	_rung(plain, false)
	assert_bool(Deployable.climbable_at(_terrain, plain)).is_false()

	var core: Node2D = auto_free(Node2D.new())
	assert_bool(_terrain.place_entity(ORIGIN + Vector2i(4, 0), core)).is_true()
	assert_bool(Deployable.climbable_at(_terrain, ORIGIN + Vector2i(4, 0))).is_false()

# --- The support clause -------------------------------------------------------


## The base case the whole column rests on: rung 0 needs a real floor, exactly as
## a torch does.
func test_the_bottom_rung_still_needs_a_solid_tile() -> void:
	assert_bool(
		Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, Deployable.SUPPORT_ALL, true),
	).is_false()
	_terrain.set_tile(FLOOR_CELL, "dirt")
	assert_bool(
		Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, Deployable.SUPPORT_ALL, true),
	).is_true()


## ❗️The orientation test the `SUPPORT_OFFSETS` comment demands, in the one place
## it is a 50/50 with no error either way: a rung is held by the one BELOW it and
## not by the one above. Inverting this builds columns downward from a ceiling —
## a game that mostly works, right up until you try to climb out of a hole.
func test_a_rung_is_held_by_the_one_below_and_not_by_the_one_above() -> void:
	_rung(ORIGIN + Vector2i.DOWN)
	assert_bool(
		Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, Deployable.SUPPORT_ALL, true),
	).is_true()

	var under_a_ceiling := ORIGIN + Vector2i(3, 0)
	_rung(under_a_ceiling + Vector2i.UP)
	assert_bool(
		Deployable.is_supported_at(
			_terrain,
			under_a_ceiling,
			Vector2i.ONE,
			Deployable.SUPPORT_ALL,
			true,
		),
	).is_false()


## ❗️The acyclicity test. A symmetric clause ("a climbable neighbour holds me
## up") lets two rungs floating in mid-air each point at the other and both claim
## support forever — and `is_supported_at` is a one-step predicate, not a
## reachability query, so nothing would ever report it. Reading only downward
## makes the relation strictly increase in y toward a solid anchor.
func test_two_rungs_floating_in_mid_air_do_not_hold_each_other_up() -> void:
	var lower := _rung(ORIGIN + Vector2i.DOWN)
	var upper := _rung(ORIGIN)
	# The upper one has the lower one under it, and still falls: the lower one
	# has nothing at all.
	assert_bool(lower.is_supported(_terrain)).is_false()
	_automation.drain_support_queue()
	assert_int(_spawner.drops.size()).is_equal(2)
	assert_bool(upper.is_queued_for_deletion()).is_true()
	_terrain.debug_validate()


## The defaulted-argument guarantee: pass nothing and the clause is not there at
## all, so 3.1's every call site keeps its exact 3.1 answer.
func test_a_non_climbable_deployable_is_unaffected_by_the_clause() -> void:
	_rung(ORIGIN + Vector2i.DOWN)
	assert_bool(
		Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, Deployable.SUPPORT_ALL),
	).is_false()
	# And a climbable under a NON-climbable holds nothing up either: the clause is
	# about what is standing, not only about what it stands on.
	assert_bool(
		Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, Deployable.SUPPORT_ALL, false),
	).is_false()


## `support_dirs` keeps meaning exactly what it says. The clause is a DOWNWARD
## support direction, so a climbable that does not mount downward cannot gain
## one — and `SUPPORT_NONE` still opts out by construction.
func test_the_clause_is_gated_on_the_down_bit() -> void:
	_rung(ORIGIN + Vector2i.DOWN)
	assert_bool(
		Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, 1, true), # Up only.
	).is_false()
	assert_bool(
		Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, Deployable.SUPPORT_DOWN, true),
	).is_true()
	assert_bool(
		Deployable.is_supported_at(
			_terrain,
			ORIGIN,
			Vector2i.ONE,
			Deployable.SUPPORT_NONE,
			true,
		),
	).is_true()

# --- The cascade --------------------------------------------------------------


## ❗️The exit criterion's third hand-check, as a unit test: mine the floor under
## rung 0 and the WHOLE column comes down in one drain, bottom-up, each rung
## popping exactly once.
##
## No new machinery is needed for it and that is the point — `_on_cell_changed`
## probes the changed cell and its four cardinal neighbours, so popping rung 0
## enqueues rung 1 by construction, and `drain_support_queue` loops rather than
## recursing.
func test_a_floor_anchored_column_pops_entirely_in_one_drain() -> void:
	const RUNGS := 20
	_terrain.set_tile(FLOOR_CELL, "dirt")
	for i in RUNGS:
		_rung(FLOOR_CELL + Vector2i(0, -1 - i))
	_automation.drain_support_queue()
	assert_int(_spawner.drops.size()).is_equal(0) # The column is standing.

	_terrain.damage_tile(FLOOR_CELL, 999.0, 99, TerrainScript.Source.PLAYER)
	_automation.drain_support_queue()

	assert_int(_spawner.drops.size()).is_equal(RUNGS)
	for i in RUNGS:
		assert_object(_terrain.get_entity(FLOOR_CELL + Vector2i(0, -1 - i))).is_null()
	assert_int(_automation.pending_checks()).is_equal(0)
	_terrain.debug_validate()


## Taking ONE rung out of the middle drops everything above it and leaves
## everything below standing — the column is a chain, not a set.
func test_removing_a_middle_rung_drops_only_what_was_above_it() -> void:
	_terrain.set_tile(FLOOR_CELL, "dirt")
	var rungs: Array[Deployable] = []
	for i in 6:
		rungs.append(_rung(FLOOR_CELL + Vector2i(0, -1 - i)))
	_automation.drain_support_queue()

	rungs[2].pop_to_pickup()
	_automation.drain_support_queue()

	assert_int(_spawner.drops.size()).is_equal(4) # The one removed, plus three above.
	for i in 2:
		assert_object(_terrain.get_entity(FLOOR_CELL + Vector2i(0, -1 - i))).is_same(rungs[i])
	for i in range(2, 6):
		assert_object(_terrain.get_entity(FLOOR_CELL + Vector2i(0, -1 - i))).is_null()
	_terrain.debug_validate()

# --- Authoring ----------------------------------------------------------------


## The ghost's input. Same anti-drift contract as `scene_size`: read off an
## authored instance, so the ghost's green and the click's acceptance are one
## answer rather than two copies of it. Missing this makes every rung above the
## first tint red exactly where the click accepts.
func test_the_scene_authors_a_climbable_that_mounts_downward() -> void:
	var live: Deployable = auto_free(LadderScene.instantiate())
	assert_bool(live.is_climbable).is_true()
	assert_bool(Deployable.scene_is_climbable(LadderScene)).is_equal(live.is_climbable)
	assert_vector(live.size).is_equal(Vector2i.ONE)
	assert_float(live.power_demand).is_equal(0.0)
	assert_bool(live.directional).is_false()
	assert_str(live.item_id).is_equal("ladder")
	# SUPPORT_ALL, so a ladder mounts against a wall as happily as on a floor —
	# and the Down bit the stacking clause is gated on is one of the four.
	assert_int(Deployable.scene_support_dirs(LadderScene)).is_equal(Deployable.SUPPORT_ALL)
	assert_int(live.support_dirs & Deployable.SUPPORT_DOWN).is_not_equal(0)


## The ghost and the click ask the same question through `placement_is_climbable`
## — the cache half of the `MiningCursor` wiring. A block is never climbable.
func test_placement_is_climbable_answers_off_the_item_id() -> void:
	assert_bool(Player.placement_is_climbable("ladder")).is_true()
	assert_bool(Player.placement_is_climbable("torch")).is_false()
	assert_bool(Player.placement_is_climbable("dirt")).is_false()
	assert_bool(Player.placement_is_climbable("")).is_false()


## The whole ghost invariant, end to end: `can_place_at` accepts rung 1 standing
## on rung 0 — the answer the cursor draws green — and refuses the same cell with
## the climbable flag dropped, which is exactly the bug the wiring prevents.
func test_can_place_at_accepts_a_rung_standing_on_a_rung() -> void:
	_terrain.set_tile(FLOOR_CELL, "dirt")
	_rung(ORIGIN)
	var above := ORIGIN + Vector2i.UP
	var away := Rect2i(Vector2i.ZERO, Vector2i.ONE) # Player nowhere near.
	assert_bool(
		Player.can_place_at(
			_terrain,
			above,
			away,
			Vector2i.ONE,
			Deployable.SUPPORT_ALL,
			Vector2i.RIGHT,
			false,
			true,
		),
	).is_true()
	assert_bool(
		Player.can_place_at(
			_terrain,
			above,
			away,
			Vector2i.ONE,
			Deployable.SUPPORT_ALL,
			Vector2i.RIGHT,
			false,
		),
	).is_false()
