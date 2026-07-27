## Unit tests for the spike trap (roadmap 3.5a) — the cheapest defense there is.
## Fresh Terrain + Automation per test, _process off, so the suite drives
## `step_tick()` itself.
##
## The cases here are the ones a plausible implementation gets wrong: the support
## bitmask's Up/Down (a silent 50/50 that produces a trap mounted on ceilings with
## no error anywhere), and the ONE global cooldown — a per-victim table would make
## a pit with four mobs in it behave completely differently.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const SpikeTrapScene := preload("res://scenes/automation/spike_trap.tscn")

## Playable (x in [50, 150)) and far from world edges.
const ORIGIN := Vector2i(100, 100)
const TILE := TileLayout.TILE_SIZE


## The aggro helper, stubbed: the trap only ever asks `enemies()` for a list.
class WavesDouble:
	extends Node

	var mobs: Array[Node] = []


	func enemies() -> Array[Node]:
		return mobs


class MobDouble:
	extends Node2D

	var hits: Array[float] = []
	var attackers: Array[Node] = []


	func take_damage(amount: float, attacker: Node2D = null) -> void:
		hits.append(amount)
		attackers.append(attacker)


var _terrain: Node
var _automation: Node
var _waves: WavesDouble


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
	_waves = auto_free(WavesDouble.new())
	add_child(_waves)


## ❗️No `Supply` double anywhere in this suite, and that is the point: an
## unpowered machine must tick on a world with no generator in it at all.
func _trap(cell := ORIGIN) -> SpikeTrap:
	_terrain.set_tile(cell + Vector2i.DOWN, "dirt")
	var node: SpikeTrap = auto_free(SpikeTrapScene.instantiate())
	node.automation = _automation
	node.waves = _waves
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	return node


## A mob standing in the middle of `at`'s cell.
func _mob_on(at: SpikeTrap) -> MobDouble:
	return _mob_at(at.trigger_area().get_center())


func _mob_at(world_pos: Vector2) -> MobDouble:
	var node: MobDouble = auto_free(MobDouble.new())
	node.position = world_pos
	add_child(node)
	_waves.mobs.append(node)
	return node

# --- Authoring ----------------------------------------------------------------


## ❗️**`support_dirs = 4` is DOWN** — a solid tile BELOW, so a trap is a floor
## tile. `deployable.gd` warns that inverting Up/Down produces a game that mostly
## works with no error anywhere, so this asserts the predicate, not the number.
func test_a_trap_needs_a_floor_under_it_and_not_a_ceiling_over_it() -> void:
	var dirs := Deployable.scene_support_dirs(SpikeTrapScene)
	assert_int(dirs).is_equal(4)

	_terrain.set_tile(ORIGIN + Vector2i.DOWN, "dirt")
	assert_bool(Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, dirs)).is_true()

	_terrain.set_tile(ORIGIN + Vector2i.DOWN, "")
	_terrain.set_tile(ORIGIN + Vector2i.UP, "dirt")
	assert_bool(Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, dirs)).is_false()


## Unpowered is the whole pitch: it is the defense you can afford before the
## first generator is up.
func test_the_scene_authors_an_unpowered_one_by_one() -> void:
	var live: SpikeTrap = auto_free(SpikeTrapScene.instantiate())
	assert_vector(live.size).is_equal(Vector2i.ONE)
	assert_float(live.power_demand).is_equal(0.0)
	assert_bool(live.directional).is_false()
	assert_str(live.item_id).is_equal("spike_trap")

# --- Trigger geometry (pure) --------------------------------------------------


func test_victims_catches_only_what_is_inside_the_area() -> void:
	var inside: MobDouble = auto_free(MobDouble.new())
	inside.position = Vector2(8.0, 8.0)
	var outside: MobDouble = auto_free(MobDouble.new())
	outside.position = Vector2(40.0, 8.0)

	var caught := SpikeTrap.victims([inside, outside], Rect2(0.0, 0.0, 16.0, 16.0))

	assert_int(caught.size()).is_equal(1)
	assert_object(caught[0]).is_same(inside)


## ⚠️ Same freed-instance trap as `Turret.pick_target`: a dead mob lingers in the
## `enemies` group for a frame.
func test_victims_skips_freed_instances() -> void:
	var doomed := MobDouble.new()
	var alive: MobDouble = auto_free(MobDouble.new())
	alive.position = Vector2(8.0, 8.0)
	var candidates: Array = [doomed, alive]
	doomed.free()

	var caught := SpikeTrap.victims(candidates, Rect2(0.0, 0.0, 16.0, 16.0))

	assert_int(caught.size()).is_equal(1)
	assert_object(caught[0]).is_same(alive)


## The box is the trap's own footprint in world space — a trap is laid in a line,
## so each one biting exactly its own cell is the behaviour that composes.
func test_the_trigger_area_is_the_traps_own_cell() -> void:
	var node := _trap()
	assert_vector(node.trigger_area().position).is_equal(Vector2(ORIGIN) * TILE)
	assert_vector(node.trigger_area().size).is_equal(Vector2(TILE, TILE))

# --- Biting -------------------------------------------------------------------


## ❗️No generator anywhere in this world. `spend_power_tick()` is a no-op
## returning true at demand 0, which is what lets the trap call it anyway so a
## powered variant later is data rather than a code change.
func test_it_bites_a_mob_standing_on_it_with_no_power_in_the_world() -> void:
	var node := _trap()
	var mob := _mob_on(node)

	_automation.step_tick()

	assert_array(mob.hits).contains_exactly([node.damage])


## Attributed to the trap, so it draws threat and mobs stop to chew it — the
## torch precedent, and why a trap has HP worth authoring.
func test_the_bite_is_attributed_to_the_trap() -> void:
	var node := _trap()
	var mob := _mob_on(node)

	_automation.step_tick()

	assert_object(mob.attackers[0]).is_same(node)


func test_a_mob_standing_beside_it_is_untouched() -> void:
	var node := _trap()
	var mob := _mob_at(node.trigger_area().get_center() + Vector2(TILE * 2.0, 0.0))

	for i in node.damage_ticks * 3:
		_automation.step_tick()

	assert_array(mob.hits).is_empty()


## ❗️**ONE global cooldown, not a per-victim table.** A pit with four mobs in it
## is the case that matters: they all take the same bite on the same tick.
func test_one_bite_hits_everything_standing_on_it() -> void:
	var node := _trap()
	var mobs: Array[MobDouble] = []
	for i in 4:
		mobs.append(_mob_on(node))

	_automation.step_tick()

	for mob: MobDouble in mobs:
		assert_array(mob.hits).contains_exactly([node.damage])


func test_it_rearms_on_its_own_cooldown() -> void:
	var node := _trap()
	var mob := _mob_on(node)

	_automation.step_tick()
	assert_int(mob.hits.size()).is_equal(1)
	for i in node.damage_ticks - 1:
		_automation.step_tick()
	assert_int(mob.hits.size()).is_equal(1) # Still rearming.
	_automation.step_tick()
	assert_int(mob.hits.size()).is_equal(2)


## ❗️Enemies only, and delivered by *what it is handed* rather than by a faction
## check: the trap asks for the enemy group and never sees the player. A trap
## that hurt the player would be a death with no readable cause.
func test_it_never_sees_anything_that_is_not_in_the_enemy_group() -> void:
	var node := _trap()
	var bystander: MobDouble = auto_free(MobDouble.new())
	bystander.position = node.trigger_area().get_center()
	add_child(bystander) # Deliberately NOT registered with the aggro stub.

	for i in node.damage_ticks * 3:
		_automation.step_tick()

	assert_array(bystander.hits).is_empty()

# --- Registration -------------------------------------------------------------


func test_a_placed_trap_joins_the_tick_and_a_popped_one_leaves_it() -> void:
	var node := _trap()
	assert_int(_automation.machines().size()).is_equal(1)
	node.pop_to_pickup()
	assert_int(_automation.machines().size()).is_equal(0)
	_automation.step_tick() # Must not touch the freed node.
	assert_int(_automation.tick_count).is_equal(1)
