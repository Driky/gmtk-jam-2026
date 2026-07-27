## Unit tests for the Turret (roadmap 3.5a) — the first thing the player builds
## that fights. Fresh Terrain + Automation per test, _process off, so the suite
## drives `step_tick()` itself.
##
## The split with `test_projectile.gd` is deliberate: that suite owns flight and
## contact (it needs real physics frames), this one owns the DECISION to fire.
## So "did it shoot" is asserted against the pool, never against a mob's HP.
##
## The cases here are the ones a plausible implementation gets wrong: the
## support bitmask's Up/Down (a silent 50/50 with no error anywhere), the idle
## poll burning the cooldown (a turret whose DPS depends on when a mob wandered
## in), and spending a round on ammo that resolves no projectile.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const PoolScript := preload("res://scripts/combat/projectile_pool.gd")
const TurretScene := preload("res://scenes/automation/turret.tscn")

## Playable (x in [50, 150)) and far from world edges.
const ORIGIN := Vector2i(100, 100)
const TILE := TileLayout.TILE_SIZE
## Deliberately huge: this suite is about shooting, not about geometry, so the
## fixture's only job is "there is power here".
const POWER_RADIUS := 64.0
const AMMO := "copper_ammo"


## ❗️A turret on no grid does not tick at all, so every test here needs a supply
## — the same local double `test_miner.gd` and `test_crafting_station.gd` keep.
class Supply:
	extends PowerEmitter

	func power_supply() -> float:
		return 100.0


## The aggro helper, stubbed: this suite has no business spawning real mobs, and
## the turret only ever asks `enemies()` for a list.
class WavesDouble:
	extends Node

	var mobs: Array[Node] = []


	func enemies() -> Array[Node]:
		return mobs


## A mob: a position and a `take_damage`, which is all `pick_target` and the
## threat attribution need.
class MobDouble:
	extends Node2D

	var hits: Array[float] = []


	func take_damage(amount: float, _attacker: Node2D = null) -> void:
		hits.append(amount)


## Neutral buffs, so a stat change elsewhere can never move this suite's numbers.
class ProgressionDouble:
	extends Node

	func get_stat(_stat_name: String) -> float:
		return 1.0


var _terrain: Node
var _automation: Node
var _waves: WavesDouble
var _pool: ProjectilePool


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
	_pool = auto_free(PoolScript.new())
	add_child(_pool)
	_power_the_world()


func _power_the_world() -> void:
	var node: Supply = auto_free(Supply.new())
	node.automation = _automation
	node.power_radius = POWER_RADIUS
	node.setup(ORIGIN)
	add_child(node)
	node.on_placed()


## A turret at `cell`, standing on a floor so its support rule is satisfied like
## a real placement. Pass a cell beyond `POWER_RADIUS` of `ORIGIN` to build one
## no grid reaches.
func _turret(cell := ORIGIN) -> Turret:
	_terrain.set_tile(cell + Vector2i.DOWN, "dirt")
	var node: Turret = auto_free(TurretScene.instantiate())
	node.automation = _automation
	node.waves = _waves
	node.progression = auto_free(ProgressionDouble.new())
	node.setup(cell)
	add_child(node)
	assert_bool(node.register(_terrain)).is_true()
	node.on_placed()
	return node


## A mob `tiles` to the right of the turret's centre, registered with the aggro
## stub. Returned so a test can move or free it.
func _mob(from: Turret, tiles: float) -> MobDouble:
	var node: MobDouble = auto_free(MobDouble.new())
	node.position = from.global_position + Vector2(tiles * TILE, 0.0)
	add_child(node)
	_waves.mobs.append(node)
	return node


## Every projectile the pool currently has in the air.
func _shots() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child: Node in _pool.get_children():
		var shot := child as Projectile
		if shot != null and shot.is_active():
			out.append(shot)
	return out

# --- Authoring ----------------------------------------------------------------


## ❗️**`support_dirs = 4` is DOWN**, i.e. a solid tile BELOW: a standard turret
## needs a horizontal base under it. Inverting Up/Down here produces a game that
## mostly works with no error anywhere (`deployable.gd`), which is why this is
## asserted against the predicate rather than against the number alone.
func test_the_scene_authors_a_one_by_one_that_stands_on_a_base() -> void:
	var live: Turret = auto_free(TurretScene.instantiate())
	assert_vector(live.size).is_equal(Vector2i.ONE)
	assert_int(live.support_dirs).is_equal(4)
	assert_bool(live.directional).is_false() # It auto-targets; an arrow would lie.
	assert_float(live.power_demand).is_greater(0.0)
	assert_str(live.item_id).is_equal("turret")


func test_a_floor_holds_it_up_and_a_ceiling_does_not() -> void:
	var dirs := Deployable.scene_support_dirs(TurretScene)

	_terrain.set_tile(ORIGIN + Vector2i.DOWN, "dirt")
	assert_bool(Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, dirs)).is_true()

	_terrain.set_tile(ORIGIN + Vector2i.DOWN, "")
	_terrain.set_tile(ORIGIN + Vector2i.UP, "dirt")
	assert_bool(Deployable.is_supported_at(_terrain, ORIGIN, Vector2i.ONE, dirs)).is_false()

# --- Target selection (pure) --------------------------------------------------


func test_pick_target_takes_the_nearest_in_range() -> void:
	var near: MobDouble = auto_free(MobDouble.new())
	near.position = Vector2(30.0, 0.0)
	var far: MobDouble = auto_free(MobDouble.new())
	far.position = Vector2(90.0, 0.0)

	var picked := Turret.pick_target([far, near], Vector2.ZERO, 200.0)

	assert_object(picked).is_same(near)


func test_pick_target_ignores_anything_past_the_range() -> void:
	var mob: MobDouble = auto_free(MobDouble.new())
	mob.position = Vector2(300.0, 0.0)

	assert_object(Turret.pick_target([mob], Vector2.ZERO, 100.0)).is_null()
	assert_object(Turret.pick_target([], Vector2.ZERO, 100.0)).is_null()


## ⚠️ A freed mob lingers in the `enemies` group for a frame, so the selector has
## to filter rather than trusting the list it was handed.
func test_pick_target_skips_freed_instances() -> void:
	var doomed := MobDouble.new()
	doomed.position = Vector2(10.0, 0.0)
	var alive: MobDouble = auto_free(MobDouble.new())
	alive.position = Vector2(50.0, 0.0)
	var candidates: Array = [doomed, alive]
	doomed.free()

	assert_object(Turret.pick_target(candidates, Vector2.ZERO, 200.0)).is_same(alive)

# --- The transfer seam --------------------------------------------------------


func test_it_takes_ammo_and_refuses_everything_else() -> void:
	var node := _turret()
	assert_int(node.accept_item(AMMO, 4)).is_equal(4)
	assert_int(node.accept_item("copper_bar", 4)).is_equal(0)
	assert_int(node.accept_item("dirt", 4)).is_equal(0)
	assert_int(node.ammo_slot().count).is_equal(4)


## One slot cannot hold two ids, and taking the second anyway would destroy it.
func test_a_second_ammo_tier_is_refused_while_the_slot_holds_another() -> void:
	var node := _turret()
	node.accept_item(AMMO, 1)
	assert_int(node.accept_item("iron_ammo", 1)).is_equal(0)
	assert_str(node.ammo_slot().id).is_equal(AMMO)


func test_the_ammo_slot_caps_at_one_stack() -> void:
	var node := _turret()
	assert_int(node.accept_item(AMMO, Inventory.STACK_SIZE + 10)).is_equal(Inventory.STACK_SIZE)
	assert_int(node.accept_item(AMMO, 1)).is_equal(0)


## ❗️Ammo loaded is SPENT, not stored — the generator's rule. An inserter
## pointed at a turret takes nothing back out of it.
func test_an_inserter_can_never_pull_the_ammo_back_out() -> void:
	var node := _turret()
	node.accept_item(AMMO, 4)
	assert_bool(node.extract_item(4).is_empty()).is_true()
	assert_int(node.ammo_slot().count).is_equal(4)


## Taking the turret down is the one way the ammo comes back.
func test_take_cargo_hands_over_the_ammo_and_empties_the_slot() -> void:
	var node := _turret()
	node.accept_item(AMMO, 7)

	var cargo := node.take_cargo()

	assert_int(cargo.size()).is_equal(1)
	assert_str(cargo[0].id).is_equal(AMMO)
	assert_int(cargo[0].count).is_equal(7)
	assert_bool(node.ammo_slot().is_empty()).is_true()

# --- Firing -------------------------------------------------------------------


func test_it_fires_one_round_at_a_mob_in_range() -> void:
	var node := _turret()
	node.accept_item(AMMO, 5)
	_mob(node, 3.0)

	_automation.step_tick()

	assert_int(_pool.active_count()).is_equal(1)
	assert_int(node.ammo_slot().count).is_equal(4)
	assert_object(node.target()).is_not_null()


## ❗️The shot comes off the AMMO, not off the turret: an ammo tier is a `.tres`
## pair and nothing about the tier lives on this script.
func test_the_projectile_is_the_ammos_own_stats() -> void:
	var node := _turret()
	node.accept_item("iron_ammo", 1)
	_mob(node, 3.0)

	_automation.step_tick()

	var shots := _shots()
	assert_int(shots.size()).is_equal(1)
	assert_object(shots[0].stats).is_same(ItemDefs.stats_for("iron_ammo").projectile)
	# Its own faction, so a turret's bolt passes through the player.
	assert_int(shots[0].collision_mask).is_equal(
		Projectile.mask_for(Projectile.Faction.PLAYER),
	)
	# And it is attributed to the turret, so the turret tanks its own aggro.
	assert_object(shots[0].source).is_same(node)


func test_an_empty_turret_fires_nothing_and_reports_idle() -> void:
	var node := _turret()
	_mob(node, 3.0)

	_automation.step_tick()

	assert_int(_pool.active_count()).is_equal(0)
	assert_bool(node.is_idle()).is_true()


func test_a_loaded_turret_is_not_idle() -> void:
	var node := _turret()
	node.accept_item(AMMO, 1)
	assert_bool(node.is_idle()).is_false()


func test_it_holds_fire_when_the_only_mob_is_out_of_range() -> void:
	var node := _turret()
	node.accept_item(AMMO, 5)
	_mob(node, node.range_tiles + 4.0)

	_automation.step_tick()

	assert_int(_pool.active_count()).is_equal(0)
	assert_int(node.ammo_slot().count).is_equal(5)
	assert_object(node.target()).is_null()


func test_it_waits_out_its_cooldown_between_shots() -> void:
	var node := _turret()
	node.accept_item(AMMO, Inventory.STACK_SIZE)
	_mob(node, 3.0)

	_automation.step_tick()
	assert_int(node.ammo_slot().count).is_equal(Inventory.STACK_SIZE - 1)
	for i in node.fire_ticks - 1:
		_automation.step_tick()
	assert_int(node.ammo_slot().count).is_equal(Inventory.STACK_SIZE - 1) # Still cooling.
	_automation.step_tick()
	assert_int(node.ammo_slot().count).is_equal(Inventory.STACK_SIZE - 2)


## ❗️**The idle poll must not burn the cooldown.** A turret whose cooldown ran
## down against an empty sky would fire late — and its DPS would depend on *when*
## a mob happened to wander in rather than on its fire rate. It has to shoot on
## the very tick the mob arrives.
func test_polling_an_empty_sky_does_not_spend_the_cooldown() -> void:
	var node := _turret()
	node.accept_item(AMMO, 5)

	for i in node.fire_ticks * 3:
		_automation.step_tick()
	assert_int(_pool.active_count()).is_equal(0)

	_mob(node, 3.0)
	_automation.step_tick()

	assert_int(_pool.active_count()).is_equal(1)


## Same rule from the other side: an unloaded turret that is then fed shoots on
## the tick the ammo lands, not `fire_ticks` later.
func test_an_ammo_drought_does_not_spend_the_cooldown_either() -> void:
	var node := _turret()
	_mob(node, 3.0)
	for i in node.fire_ticks * 3:
		_automation.step_tick()

	node.accept_item(AMMO, 1)
	_automation.step_tick()

	assert_int(_pool.active_count()).is_equal(1)


## A brownout reads as a slower rate of fire; no power at all reads as silence.
## That is the shared gate working rather than a special case in the turret.
func test_an_unpowered_turret_never_fires() -> void:
	# Well beyond the fixture supply's coverage, so no grid reaches it.
	var node := _turret(ORIGIN + Vector2i(0, roundi(POWER_RADIUS) * 4))
	node.accept_item(AMMO, 5)
	_mob(node, 3.0)

	for i in node.fire_ticks * 3:
		_automation.step_tick()

	assert_bool(node.is_powered()).is_false()
	assert_int(_pool.active_count()).is_equal(0)
	assert_int(node.ammo_slot().count).is_equal(5)


## ❗️A `.tres` that resolves no `ProjectileStats` must cost nothing: firing
## nothing is recoverable, silently eating the stack is not.
func test_ammo_that_resolves_no_projectile_fires_nothing_and_keeps_the_stack() -> void:
	var node := _turret()
	node.ammo_ids = PackedStringArray(["copper_bar"]) # A real item, but not ammo.
	node.accept_item("copper_bar", 3)
	_mob(node, 3.0)

	_automation.step_tick()

	assert_int(_pool.active_count()).is_equal(0)
	assert_int(node.ammo_slot().count).is_equal(3)

# --- Pool reservation ---------------------------------------------------------


## ❗️Why the pool refactor had to land first: without this the turret's shots
## come out of the player's 32 and start stealing bolts already in flight.
func test_placing_a_turret_reserves_its_worst_case_and_removing_it_releases() -> void:
	var base := _pool.pool_size()

	var node := _turret()
	var claimed := node.reserve_shots()

	assert_int(claimed).is_greater(0)
	assert_int(_pool.reserved()).is_equal(claimed)
	assert_int(_pool.pool_size()).is_equal(base + claimed)

	node.pop_to_pickup()

	assert_int(_pool.reserved()).is_equal(0)
	assert_int(_pool.pool_size()).is_equal(base + claimed) # Never shrinks.


## The worst case is fire rate × flight time, computed from the AUTHORED ammo
## list because `on_placed` runs before a single round is loaded.
func test_the_reservation_covers_the_longest_lived_ammo_at_the_full_fire_rate() -> void:
	var node: Turret = auto_free(TurretScene.instantiate())
	node.fire_ticks = 5 # Two shots a second.
	node.ammo_ids = PackedStringArray([AMMO])

	var flight: float = ItemDefs.stats_for(AMMO).projectile.lifetime
	var expected := ceili(flight / (5.0 * AutomationScript.TICK_INTERVAL)) + 1

	assert_int(node.reserve_shots()).is_equal(expected)


## A turret whose ammo list resolves nothing still reserves the shot leaving the
## barrel, so the arithmetic can never hand back zero.
func test_the_reservation_is_never_zero() -> void:
	var node: Turret = auto_free(TurretScene.instantiate())
	node.ammo_ids = PackedStringArray([])

	assert_int(node.reserve_shots()).is_greater(0)

# --- Registration -------------------------------------------------------------


func test_a_placed_turret_joins_the_tick_and_a_popped_one_leaves_it() -> void:
	var node := _turret()
	assert_int(_automation.machines().size()).is_equal(1)
	node.pop_to_pickup()
	assert_int(_automation.machines().size()).is_equal(0)
	_automation.step_tick() # Must not touch the freed node.
	assert_int(_automation.tick_count).is_equal(1)
