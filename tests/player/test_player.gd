## Unit tests for placement validity + tile-rect math (roadmap 1.6) and the
## HP/mana stub (roadmap 1.7). Terrain is a fresh instance per test — never
## the live autoload.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const PlayerScript := preload("res://scripts/player/player.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const BeaconScene := preload("res://scenes/automation/respawn_beacon.tscn")

## Playable, far from edges; NOWHERE is a rect that overlaps nothing relevant.
const P := Vector2i(100, 100)
const NOWHERE := Rect2i(0, 0, 1, 1)

var _terrain: Node


func before_test() -> void:
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)

# --- can_place_at ------------------------------------------------------------


func test_rejects_floating_placement() -> void:
	# All four neighbors are air — adjacency rule fails.
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_false()


func test_accepts_air_adjacent_to_solid() -> void:
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_true()


func test_rejects_solid_target() -> void:
	_terrain.set_tile(P, "dirt")
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_false()


func test_rejects_buffer_zone() -> void:
	var buffer_pos := Vector2i(10, 100)
	_terrain.set_tile(buffer_pos + Vector2i.DOWN, "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, buffer_pos, NOWHERE)).is_false()


func test_rejects_entity_occupied_cell() -> void:
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	var node: Node2D = auto_free(Node2D.new())
	_terrain.place_entity(P, node)
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_false()


func test_rejects_cell_overlapping_player() -> void:
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	var occupied := Rect2i(P, Vector2i(1, 1))
	assert_bool(PlayerScript.can_place_at(_terrain, P, occupied)).is_false()

# --- Multi-cell footprints (3.1) ---------------------------------------------

## A 2×2 anchored at P, resting on a floor under its bottom-left cell.
const BIG := Vector2i(2, 2)


func _floor_under_a_two_by_two() -> void:
	_terrain.set_tile(P + Vector2i(0, 2), "dirt")


func test_accepts_a_supported_two_by_two() -> void:
	_floor_under_a_two_by_two()
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE, BIG)).is_true()


## Every cell has to be free, not just the origin — a machine half-buried in
## rock is the failure the all-or-nothing register exists to prevent, and the
## ghost has to say no before the claim ever runs.
func test_rejects_a_two_by_two_when_any_one_cell_is_solid() -> void:
	_floor_under_a_two_by_two()
	_terrain.set_tile(P + Vector2i(1, 1), "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE, BIG)).is_false()


func test_rejects_a_two_by_two_when_any_one_cell_is_occupied() -> void:
	_floor_under_a_two_by_two()
	var blocker: Node2D = auto_free(Node2D.new())
	_terrain.place_entity(P + Vector2i(1, 0), blocker)
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE, BIG)).is_false()


## The buffer test is per-cell too: a footprint that only CLIPS the buffer with
## its far column still edits a cell the world refuses to hand over.
func test_rejects_a_two_by_two_reaching_into_a_buffer() -> void:
	var edge := Vector2i(49, 100) # Column 50 is the first playable one.
	_terrain.set_tile(edge + Vector2i(0, 2), "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, edge, NOWHERE, BIG)).is_false()


func test_rejects_a_two_by_two_overlapping_the_player() -> void:
	_floor_under_a_two_by_two()
	var occupied := Rect2i(P + Vector2i(1, 1), Vector2i(1, 2))
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE, BIG)).is_true()
	assert_bool(PlayerScript.can_place_at(_terrain, P, occupied, BIG)).is_false()


## ❗️Direction bits reach placement, not just the re-check. A ceiling-only
## machine (dirs = 1, Up) must refuse a floor, or the two disagree the moment
## the support pass runs and it pops the frame after it is placed.
func test_an_up_only_deployable_needs_a_ceiling() -> void:
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE, Vector2i.ONE, 1)).is_false()
	_terrain.set_tile(P + Vector2i.UP, "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE, Vector2i.ONE, 1)).is_true()


## Zero dirs is the opt-out — a machine that mounts on nothing places in a void.
func test_a_zero_support_deployable_places_in_mid_air() -> void:
	assert_bool(
		PlayerScript.can_place_at(
			_terrain,
			P,
			NOWHERE,
			Vector2i.ONE,
			Deployable.SUPPORT_NONE,
		),
	).is_true()

# --- The harvest gate (3.3) --------------------------------------------------

## A 3×2 at P, facing RIGHT, so its harvest block is the 3×2 starting at P+(3,0).
const MINER_SIZE := Vector2i(3, 2)


func _harvest_gate(facing: Vector2i) -> bool:
	return PlayerScript.can_place_at(
		_terrain,
		P,
		NOWHERE,
		MINER_SIZE,
		Deployable.SUPPORT_ALL,
		facing,
		true,
	)


## ❗️This clause is the ONLY thing standing in for "placed on the deposit" —
## the footprint cannot overlap the ore, because deposits are solid and
## `place_entity` rejects solid cells. Bare rock under the harvest block is a red
## ghost and a refused click.
func test_a_harvesting_placement_needs_a_deposit_in_its_harvest_block() -> void:
	for cell: Vector2i in Deployable.harvest_cells_at(P, MINER_SIZE, Vector2i.RIGHT):
		_terrain.set_tile(cell, "stone")
	assert_bool(_harvest_gate(Vector2i.RIGHT)).is_false()
	_terrain.set_tile(P + Vector2i(3, 1), "coal_deposit")
	assert_bool(_harvest_gate(Vector2i.RIGHT)).is_true()


## Rotating away from the ore has to invalidate the placement, or R would be
## cosmetic and every miner would be placeable anywhere near a deposit.
func test_the_harvest_gate_follows_the_facing() -> void:
	_terrain.set_tile(P + Vector2i(3, 1), "coal_deposit")
	assert_bool(_harvest_gate(Vector2i.RIGHT)).is_true()
	assert_bool(_harvest_gate(Vector2i.LEFT)).is_false()
	assert_bool(_harvest_gate(Vector2i.UP)).is_false()
	assert_bool(_harvest_gate(Vector2i.DOWN)).is_false()


## The gate defaults OFF, so every non-harvesting call site — every block, torch,
## belt and inserter — is untouched by construction rather than by re-testing.
func test_a_non_harvesting_placement_ignores_the_deposit_rule() -> void:
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_true()

# --- What the ghost asks (3.1) -----------------------------------------------


## The ghost is modeless: there is no toggle, only this question. ZERO means
## "draw nothing", which is what a pickaxe has to answer or hovering with a tool
## would paint a placement outline over every tile you meant to mine.
func test_placement_size_answers_for_each_kind_of_item() -> void:
	assert_vector(PlayerScript.placement_size("dirt")).is_equal(Vector2i.ONE)
	assert_vector(PlayerScript.placement_size("torch")).is_equal(Vector2i.ONE)
	assert_vector(PlayerScript.placement_size("pickaxe_t1")).is_equal(Vector2i.ZERO)
	assert_vector(PlayerScript.placement_size("")).is_equal(Vector2i.ZERO) # Bare hands.


## A scene placeable's mounting rule comes off the scene; a block keeps the
## cardinal-adjacency default, so the ghost and the click agree for both paths.
func test_placement_support_dirs_follows_the_item() -> void:
	assert_int(PlayerScript.placement_support_dirs("torch")).is_equal(
		Deployable.scene_support_dirs(TorchScene),
	)
	assert_int(PlayerScript.placement_support_dirs("dirt")).is_equal(Deployable.SUPPORT_ALL)


## Only a directional scene placeable gets an arrow. A block never points
## anywhere, and neither does a torch.
func test_placement_directional_follows_the_item() -> void:
	assert_bool(PlayerScript.placement_directional("conveyor_t1")).is_true()
	assert_bool(PlayerScript.placement_directional("torch")).is_false()
	assert_bool(PlayerScript.placement_directional("dirt")).is_false()
	assert_bool(PlayerScript.placement_directional("")).is_false()


## ❗️The ghost's prospective coverage circle comes off the SCENE, so it cannot
## draw a radius different from the one the placed generator will actually emit.
## A relay reaches further than a generator, and neither a furnace nor a block
## emits anything.
func test_placement_power_radius_follows_the_item() -> void:
	assert_float(PlayerScript.placement_power_radius("generator")).is_greater(0.0)
	assert_float(PlayerScript.placement_power_radius("relay")).is_greater(
		PlayerScript.placement_power_radius("generator"),
	)
	assert_float(PlayerScript.placement_power_radius("furnace")).is_equal_approx(0.0, 0.0001)
	assert_float(PlayerScript.placement_power_radius("dirt")).is_equal_approx(0.0, 0.0001)
	assert_float(PlayerScript.placement_power_radius("")).is_equal_approx(0.0, 0.0001)


## The other half of "is this item power-relevant": what it would DRAW. Together
## these two decide whether the overlay shows existing coverage while you hold it.
func test_placement_power_demand_follows_the_item() -> void:
	assert_float(PlayerScript.placement_power_demand("furnace")).is_greater(0.0)
	assert_float(PlayerScript.placement_power_demand("miner")).is_greater(0.0)
	# ❗️Belts and inserters draw nothing and run everywhere — the decision that
	# costs no code ([automation.md](../../docs/systems/automation.md) §Power).
	assert_float(PlayerScript.placement_power_demand("conveyor_t1")).is_equal_approx(0.0, 0.0001)
	assert_float(PlayerScript.placement_power_demand("inserter")).is_equal_approx(0.0, 0.0001)
	assert_float(PlayerScript.placement_power_demand("torch")).is_equal_approx(0.0, 0.0001)
	assert_float(PlayerScript.placement_power_demand("")).is_equal_approx(0.0, 0.0001)

# --- Placement facing (3.2) --------------------------------------------------


## R cycles clockwise on screen and wraps. The order is what "R again" means
## while laying a line, so it is pinned rather than left to the array literal.
func test_rotate_placement_cycles_clockwise_and_wraps() -> void:
	var player: Player = auto_free(PlayerScene.instantiate())
	assert_vector(player.place_facing).is_equal(Vector2i.RIGHT)
	player.rotate_placement()
	assert_vector(player.place_facing).is_equal(Vector2i.DOWN)
	player.rotate_placement()
	assert_vector(player.place_facing).is_equal(Vector2i.LEFT)
	player.rotate_placement()
	assert_vector(player.place_facing).is_equal(Vector2i.UP)
	player.rotate_placement()
	assert_vector(player.place_facing).is_equal(Vector2i.RIGHT)

# --- tile_rect_at ------------------------------------------------------------


func test_tile_rect_spans_two_rows_when_centered() -> void:
	# Center of column 100, feet on row 101: 12×22 box covers rows 99-100.
	var rect: Rect2i = PlayerScript.tile_rect_at(Vector2(1608.0, 1600.0))
	assert_vector(rect.position).is_equal(Vector2i(100, 99))
	assert_vector(rect.size).is_equal(Vector2i(1, 2))


func test_tile_rect_flush_edge_claims_single_column() -> void:
	# Right edge exactly on the x=1616 tile boundary must not claim column 101.
	var rect: Rect2i = PlayerScript.tile_rect_at(Vector2(1610.0, 1608.0))
	assert_int(rect.position.x).is_equal(100)
	assert_int(rect.size.x).is_equal(1)

# --- Mine → place round trip -------------------------------------------------


func test_mined_drop_id_places_back() -> void:
	var drops: Array = []
	_terrain.drops_spawned.connect(
		func(_pos: Vector2i, drop_id: String, _count: int, _source: int, _xp: bool) -> void:
			drops.append(drop_id),
	)
	_terrain.set_tile(P, "grass")
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	_terrain.damage_tile(P, 99.0, 1, TerrainScript.Source.PLAYER)
	assert_array(drops).contains_exactly(["dirt"]) # Grass drops dirt.
	assert_bool(Materials.MATERIALS.has(drops[0])).is_true()
	assert_bool(PlayerScript.can_place_at(_terrain, P, NOWHERE)).is_true()
	_terrain.set_tile(P, drops[0])
	assert_bool(_terrain.is_solid(P)).is_true()
	assert_str(_terrain.get_material_id(P)).is_equal("dirt")

# --- HP/mana stub (1.7) ------------------------------------------------------


## Uses the scene, not a bare script: once in the tree the player reads its own
## Visual and Hurtbox children, so a script-only instance isn't a real player.
## The pure setter tests below stay script-only — they never enter the tree.
func test_ready_seeds_full_hp_and_mana() -> void:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	assert_float(player.current_hp).is_equal(Progression.get_stat("max_hp"))
	assert_float(player.current_mana).is_equal(Progression.get_stat("max_mana"))


func test_current_hp_clamps_and_signals() -> void:
	var player: CharacterBody2D = auto_free(PlayerScript.new())
	var max_hp := Progression.get_stat("max_hp")
	var events: Array = []
	player.health_changed.connect(
		func(current: float, max_value: float) -> void:
			events.append([current, max_value]),
	)
	player.current_hp = 30.0
	player.current_hp = -10.0 # Clamped to 0.
	player.current_hp = max_hp + 999.0 # Clamped to max.
	assert_float(player.current_hp).is_equal(max_hp)
	assert_array(events).contains_exactly(
		[[30.0, max_hp], [0.0, max_hp], [max_hp, max_hp]],
	)


func test_current_mana_clamps() -> void:
	var player: CharacterBody2D = auto_free(PlayerScript.new())
	var max_mana := Progression.get_stat("max_mana")
	player.current_mana = max_mana + 5.0
	assert_float(player.current_mana).is_equal(max_mana)
	player.current_mana = -1.0
	assert_float(player.current_mana).is_equal(0.0)

# --- Taking damage (2.5) -----------------------------------------------------


func _hurtable_player() -> Player:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	return player


func test_take_damage_reduces_hp() -> void:
	var player := _hurtable_player()
	var before := player.current_hp
	player.take_damage(10.0)
	assert_float(player.current_hp).is_equal(before - 10.0)


## The grace window is what stops a mob's swing and its contact damage both
## landing on the same frame — a mob would otherwise deal double.
func test_second_hit_inside_the_grace_window_is_ignored() -> void:
	var player := _hurtable_player()
	var before := player.current_hp
	player.take_damage(10.0)
	player.take_damage(10.0)
	assert_float(player.current_hp).is_equal(before - 10.0)
	assert_bool(player.is_invulnerable()).is_true()


func test_damage_lands_again_once_the_window_expires() -> void:
	var player := _hurtable_player()
	var before := player.current_hp
	player.take_damage(10.0)
	player._tick_invulnerability(Player.INVULN_TIME + 0.01)
	assert_bool(player.is_invulnerable()).is_false()
	player.take_damage(10.0)
	assert_float(player.current_hp).is_equal(before - 20.0)


## The blink has to end on a fully opaque player — leaving it dimmed would look
## like a permanent status effect.
func test_blink_restores_full_alpha_when_the_window_ends() -> void:
	var player := _hurtable_player()
	player.take_damage(10.0)
	for i in 20:
		player._tick_invulnerability(Player.BLINK_PERIOD)
	assert_float(player.is_invulnerable() as float).is_equal(0.0)
	assert_float((player.get_node("Visual") as ColorRect).modulate.a).is_equal(1.0)


func test_knockback_shoves_away_and_stuns() -> void:
	var player := _hurtable_player()
	player.apply_knockback(Vector2(-3.0, 0.0), 140.0) # Raw offset, not normalized.
	assert_float(player.velocity.x).is_equal_approx(-140.0, 0.001)
	assert_float(player.velocity.y).is_equal(-Player.HURT_LIFT)


## Zero direction (a mob exactly on top of the player) must not make a NaN
## velocity, which would corrupt the body permanently.
func test_knockback_survives_a_zero_direction() -> void:
	var player := _hurtable_player()
	player.apply_knockback(Vector2.ZERO, 140.0)
	assert_bool(is_nan(player.velocity.x)).is_false()


## Input must not overwrite the shove on the tick it lands, or a hit reads as
## weightless.
func test_stun_suppresses_input_driven_movement() -> void:
	var player := _hurtable_player()
	player.apply_knockback(Vector2.RIGHT, 140.0)
	player._move(1.0 / 60.0)
	assert_float(player.velocity.x).is_equal_approx(140.0, 0.001)


func test_damage_is_ignored_once_dead() -> void:
	var player := _hurtable_player()
	player.take_damage(9999.0)
	assert_float(player.current_hp).is_equal(0.0)
	player._tick_invulnerability(Player.INVULN_TIME + 0.01)
	player.take_damage(10.0)
	assert_float(player.current_hp).is_equal(0.0)

# --- Death & respawn (2.5) ---------------------------------------------------


func test_lethal_damage_kills_and_emits_the_respawn_timer() -> void:
	var player := _hurtable_player()
	var announced: Array[float] = []
	player.died.connect(func(seconds: float) -> void: announced.append(seconds))
	player.take_damage(9999.0)
	assert_bool(player.is_dead()).is_true()
	assert_array(announced).contains_exactly([Player.RESPAWN_TIME])


## The death-drop split: you respawn still able to dig and fight, and it's the
## bulk haul that's at risk.
func test_death_drops_past_the_hotbar_and_keeps_it() -> void:
	Items.reset_run()
	var inventory := Items.player_inventory
	# Fill every hotbar slot, then spill one stack past it.
	inventory.add_item("dirt", Inventory.STACK_SIZE * Inventory.HOTBAR_SIZE)
	inventory.add_item("stone", 5)
	var player := _hurtable_player()
	player.take_damage(9999.0)
	assert_int(inventory.count_of("dirt")).is_equal(
		Inventory.STACK_SIZE * Inventory.HOTBAR_SIZE,
	) # Hotbar kept.
	assert_int(inventory.count_of("stone")).is_equal(0) # Went to the bag.
	var bags := get_tree().get_nodes_in_group(&"loot_bags")
	assert_int(bags.size()).is_equal(1)
	assert_int((bags[0] as LootBag).contents[0].count).is_equal(5)
	(bags[0] as Node).queue_free()
	Items.reset_run()


## Nothing outside the hotbar means nothing worth walking back for — an empty
## bag would just be litter on the path.
func test_no_bag_when_only_the_hotbar_is_carried() -> void:
	Items.reset_run()
	Items.player_inventory.add_item("dirt", 3)
	var player := _hurtable_player()
	player.take_damage(9999.0)
	assert_array(get_tree().get_nodes_in_group(&"loot_bags")).is_empty()
	Items.reset_run()


## Being dead must not also mean being hittable — a corpse taking hits would
## re-enter _die and drop a second bag.
func test_a_dead_player_takes_no_further_damage() -> void:
	var player := _hurtable_player()
	player.take_damage(9999.0)
	player._invuln_left = 0.0
	player.take_damage(10.0)
	assert_float(player.current_hp).is_equal(0.0)


func test_respawn_restores_full_hp_and_grants_grace() -> void:
	var player := _hurtable_player()
	# Array, not an int: GDScript lambdas capture value types by COPY, so a
	# `count += 1` inside one increments a copy and the assert reads 0 forever.
	var respawns: Array[bool] = []
	player.respawned.connect(func(at_beacon: bool) -> void: respawns.append(at_beacon))
	player.take_damage(9999.0)
	player._tick_respawn(Player.RESPAWN_TIME + 0.01)
	assert_bool(player.is_dead()).is_false()
	assert_float(player.current_hp).is_equal(Progression.get_stat("max_hp"))
	# Landing straight into a mob's mouth would make the timer a punishment.
	assert_bool(player.is_invulnerable()).is_true()
	assert_int(respawns.size()).is_equal(1)
	assert_bool(player.visible).is_true()

# --- The respawn anchor (3.5c) ------------------------------------------------
#
# Net-new coverage: nothing before 3.5c put anything in the `core` group or
# asserted a respawn POSITION, so `_tick_respawn`'s move was dead under test.


## The Core, duck-typed. `core.gd` has no `class_name` and the anchor contract is
## exactly one method, which is why the beacon answers `base_cell()` too rather
## than adding a second shape for `_tick_respawn` to branch on.
class CoreDouble:
	extends Node2D

	var anchor := Vector2i.ZERO


	func base_cell() -> Vector2i:
		return anchor


func _core_at(cell: Vector2i) -> CoreDouble:
	var node: CoreDouble = auto_free(CoreDouble.new())
	node.anchor = cell
	node.add_to_group(&"core")
	add_child(node)
	return node


## No terrain and no registration: the anchor query is a GROUP query over world
## positions, so joining the tree is the whole of what a beacon has to do.
func _beacon_at(cell: Vector2i) -> RespawnBeacon:
	var node: RespawnBeacon = auto_free(BeaconScene.instantiate())
	node.setup(cell)
	add_child(node)
	return node


## Feet on top of the anchor cell, clear of the surface tile — the 2.5 formula,
## now shared by both anchors.
func _feet_on(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.0)) * Player.TILE - Vector2(0.0, 12.0)


func _die_at(player: Player, world_pos: Vector2) -> void:
	# Respawning grants grace, so a second death in the same test has to get past
	# it — the same clearing `test_a_dead_player_takes_no_further_damage` does.
	player._invuln_left = 0.0
	player.global_position = world_pos
	player.take_damage(9999.0)
	player._tick_respawn(Player.RESPAWN_TIME + 0.01)


## Unchanged from 2.5: no beacon, no choice.
func test_with_no_beacon_you_respawn_at_the_core() -> void:
	_core_at(Vector2i(20, 60))
	var player := _hurtable_player()

	_die_at(player, Vector2(9000.0, 9000.0))

	assert_vector(player.global_position).is_equal(_feet_on(Vector2i(20, 60)))


## ❗️**Nearest to WHERE YOU FELL**, not most-recently-placed: build beacons across
## the map and you come back at the one you died closest to. Both beacons are
## further from the Core than from each other, so a Core-first implementation and
## a first-in-group implementation both fail this.
func test_you_respawn_at_the_beacon_nearest_to_where_you_died() -> void:
	_core_at(Vector2i(20, 60))
	var far := Vector2i(60, 100)
	var near := Vector2i(140, 100)
	_beacon_at(far)
	_beacon_at(near)
	var player := _hurtable_player()

	_die_at(player, Vector2(near) * Player.TILE + Vector2(0.0, 30.0))

	assert_vector(player.global_position).is_equal(_feet_on(near))


## ❗️The read has to happen BEFORE the move. Measuring from the post-respawn
## position would make every death after the first one sticky at whatever beacon
## you last used, no matter where you actually fell.
func test_the_distance_is_measured_from_the_corpse_not_from_the_last_respawn() -> void:
	_core_at(Vector2i(20, 60))
	var first := Vector2i(60, 100)
	var second := Vector2i(140, 100)
	_beacon_at(first)
	_beacon_at(second)
	var player := _hurtable_player()

	_die_at(player, Vector2(first) * Player.TILE)
	assert_vector(player.global_position).is_equal(_feet_on(first))

	_die_at(player, Vector2(second) * Player.TILE)
	assert_vector(player.global_position).is_equal(_feet_on(second))


## Removing your last beacon must fall back rather than strand you: the group is
## what makes that automatic, and `pick_target`'s validity filter is what covers
## the frame between `queue_free` and the actual delete.
func test_removing_the_last_beacon_falls_back_to_the_core() -> void:
	_core_at(Vector2i(20, 60))
	var beacon := _beacon_at(Vector2i(140, 100))
	var player := _hurtable_player()

	_die_at(player, Vector2(140.0, 100.0) * Player.TILE)
	assert_vector(player.global_position).is_equal(_feet_on(Vector2i(140, 100)))

	beacon.pop_to_pickup()
	await get_tree().process_frame

	_die_at(player, Vector2(140.0, 100.0) * Player.TILE)
	assert_vector(player.global_position).is_equal(_feet_on(Vector2i(20, 60)))


## The HUD announces off this payload, so the banner would otherwise say "at the
## Core" while you stand at a beacon halfway across the map.
func test_the_respawn_signal_reports_which_anchor_it_was() -> void:
	_core_at(Vector2i(20, 60))
	var player := _hurtable_player()
	# Array, not a bool: lambdas capture value types by COPY (see above).
	var at_beacon: Array[bool] = []
	player.respawned.connect(func(flag: bool) -> void: at_beacon.append(flag))

	_die_at(player, Vector2(140.0, 100.0) * Player.TILE)
	_beacon_at(Vector2i(140, 100))
	_die_at(player, Vector2(140.0, 100.0) * Player.TILE)

	assert_array(at_beacon).contains_exactly([false, true])


## No anchor at all — no Core, no beacon — leaves you where you fell rather than
## teleporting you to the origin. 2.5's guard, still load-bearing.
func test_with_nothing_to_anchor_to_you_stay_where_you_fell() -> void:
	var player := _hurtable_player()
	var fell_at := Vector2(1234.0, 567.0)

	_die_at(player, fell_at)

	assert_vector(player.global_position).is_equal(fell_at)

# --- Level-up (2.6) ----------------------------------------------------------


## Drives the LIVE Progression: the player wires to the autoload in _ready, and
## a stub would prove nothing about that wiring. Bracketed by reset_run() so it
## hands the singleton back the way it found it.
func test_level_up_grants_the_delta_rather_than_healing() -> void:
	Progression.reset_run()
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	player.take_damage(40.0)
	var hp_before := player.current_hp
	var max_before := Progression.get_stat("max_hp")

	Progression.grant_xp("kills", Progression.xp_to_level(1))

	var gained := Progression.get_stat("max_hp") - max_before
	assert_float(gained).is_greater(0.0)
	assert_float(player.current_hp).is_equal_approx(hp_before + gained, 0.001)
	# Still wounded — a level-up must not double as a heal button.
	assert_float(player.current_hp).is_less(Progression.get_stat("max_hp"))
	Progression.reset_run()


func test_level_up_raises_mana_the_same_way() -> void:
	Progression.reset_run()
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	player.current_mana = 10.0
	var max_before := Progression.get_stat("max_mana")

	Progression.grant_xp("kills", Progression.xp_to_level(1))

	var gained := Progression.get_stat("max_mana") - max_before
	assert_float(player.current_mana).is_equal_approx(10.0 + gained, 0.001)
	Progression.reset_run()

# --- Un-deploying with the use verb (2.7) ------------------------------------

const TorchScene := preload("res://scenes/torch.tscn")
const ConveyorScene := preload("res://scenes/automation/conveyor.tscn")


## Records what the real spawner would have dropped, without the autoload
## wiring or a Pickup in the tree.
class SpawnerDouble:
	extends Node

	var drops: Array = []


	func spawn_at(world_pos: Vector2, id: String, count: int, grants_xp := true) -> void:
		drops.append({ pos = world_pos, id = id, count = count, grants_xp = grants_xp })


var _spawner: SpawnerDouble


func _torch_at(cell: Vector2i) -> Torch:
	var torch: Torch = TorchScene.instantiate()
	torch.setup(cell)
	add_child(torch)
	torch.register(_terrain)
	return torch


## Player standing on the cell, so the target is trivially within reach.
func _swinger_at(cell: Vector2i) -> Player:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	player.global_position = (Vector2(cell) + Vector2(0.5, 0.5)) * Player.TILE
	return player


func _make_spawner() -> SpawnerDouble:
	_spawner = auto_free(SpawnerDouble.new())
	_spawner.add_to_group(&"pickup_spawner")
	add_child(_spawner)
	return _spawner


func test_a_swing_un_deploys_a_torch_and_pops_it_out_as_a_pickup() -> void:
	var spawner := _make_spawner()
	var torch := _torch_at(P)
	var player := _swinger_at(P)
	assert_bool(player._hit_deployable(_terrain, P)).is_true()
	assert_object(_terrain.get_entity(P)).is_null()
	assert_int(spawner.drops.size()).is_equal(1)
	assert_str(spawner.drops[0].id).is_equal("torch")
	# Queued, not gone: queue_free runs at end of frame. That deferral is the
	# entire reason remove() clears the terrain entry eagerly instead.
	assert_bool(torch.is_queued_for_deletion()).is_true()


## place → remove → place must not be an XP fountain, so the dropped pickup
## carries the same veto a player-placed block's drop does.
func test_an_un_deployed_torch_pays_no_xp() -> void:
	var spawner := _make_spawner()
	_torch_at(P)
	_swinger_at(P)._hit_deployable(_terrain, P)
	assert_bool(spawner.drops[0].grants_xp).is_false()


## The rule that lets removal share the busy button at all: a mob in swing range
## shields whatever is behind it, so a fight next to your torches costs nothing.
func test_a_mob_in_swing_range_shields_the_deployable() -> void:
	_make_spawner()
	_torch_at(P)
	var player := _swinger_at(P)
	var mob: Node2D = auto_free(Node2D.new())
	mob.add_to_group(&"enemies")
	add_child(mob)
	mob.global_position = player.global_position + Vector2(Player.MELEE_PRECEDENCE_PX - 4.0, 0.0)
	assert_bool(player._hit_deployable(_terrain, P)).is_false()
	assert_object(_terrain.get_entity(P)).is_not_null() # Survived the fight.


func test_a_mob_out_of_swing_range_does_not_shield_it() -> void:
	_make_spawner()
	_torch_at(P)
	var player := _swinger_at(P)
	var mob: Node2D = auto_free(Node2D.new())
	mob.add_to_group(&"enemies")
	add_child(mob)
	mob.global_position = player.global_position + Vector2(Player.MELEE_PRECEDENCE_PX + 40.0, 0.0)
	assert_bool(player._hit_deployable(_terrain, P)).is_true()


## `as Deployable` is the whole mechanism keeping the Core un-removable — the
## Core is a plain Node2D that registers its own footprint, and there is
## deliberately no special case for it anywhere.
func test_a_non_deployable_entity_is_not_removable() -> void:
	_make_spawner()
	var core: Node2D = auto_free(Node2D.new())
	core.add_to_group(&"core")
	_terrain.place_entity(P, core)
	assert_bool(_swinger_at(P)._hit_deployable(_terrain, P)).is_false()
	assert_object(_terrain.get_entity(P)).is_same(core)


func test_removal_respects_reach() -> void:
	_make_spawner()
	_torch_at(P)
	var player := _swinger_at(P)
	player.global_position = Vector2.ZERO # Miles away; target_tile follows the mouse.
	assert_bool(player._hit_deployable(_terrain, P)).is_false()
	assert_object(_terrain.get_entity(P)).is_not_null()


## Hit counting, not damage accumulation — a swing is a discrete beat, and
## "three hits" is something a player can feel and count. A torch is one.
func test_a_torch_comes_off_in_one_hit() -> void:
	var torch := _torch_at(P)
	assert_bool(torch.take_removal_hit()).is_true()
	assert_float(torch.removal_ratio()).is_equal(1.0)


## A tougher deployable must survive its first hits, and report progress for the
## cursor highlight while it does. Raises the count on the instance, since the
## torch is deliberately a one-hit item — `removal_hits` is a per-type export
## now, which is how 3.3's furnace gets to be heavier than a stick.
func test_a_multi_hit_deployable_reports_progress_before_coming_off() -> void:
	var torch := _torch_at(P)
	torch.removal_hits = 3
	for i in torch.removal_hits - 1:
		assert_bool(torch.take_removal_hit()).is_false()
	assert_float(torch.removal_ratio()).is_less(1.0)
	assert_bool(torch.take_removal_hit()).is_true()

# --- Placing a scene (3.1) ---------------------------------------------------

const DeployableScript := preload("res://scripts/automation/deployable.gd")

const BIG_FOOTPRINT := Vector2i(2, 2)
## Somewhere the player can stand without ever overlapping the footprint at P.
const CLEAR_OF_P := Vector2i(120, 120)


## Reports when on_placed ran and what the tree looked like at the time.
class Observer:
	extends Deployable

	var placed_calls := 0
	var parent_at_placed: Node = null


	func on_placed() -> void:
		placed_calls += 1
		parent_at_placed = get_parent()


## A 2×2 built from the base script, packed so `instantiate()` reproduces the
## real authoring path: the player reads `size`/`support_dirs` off the INSTANCE,
## so only a scene is a faithful input here.
func _big_scene() -> PackedScene:
	var template := DeployableScript.new()
	template.size = BIG_FOOTPRINT
	template.item_id = "torch"
	var scene := PackedScene.new()
	scene.pack(template)
	template.free()
	return scene


## The floor the 2×2 at P rests on, under its bottom-left cell.
func _placeable_ground() -> void:
	_terrain.set_tile(P + Vector2i(0, 2), "dirt")


func _place_big(player: Player) -> Deployable:
	player._place_scene(_terrain, P, _big_scene())
	return _terrain.get_entity(P) as Deployable


func test_placing_a_scene_claims_its_whole_footprint_and_costs_one_item() -> void:
	Items.reset_run()
	Items.player_inventory.add_item("torch", 2)
	_placeable_ground()
	var placed := _place_big(_swinger_at(CLEAR_OF_P))
	assert_object(placed).is_not_null()
	for cell: Vector2i in Deployable.footprint_at(P, BIG_FOOTPRINT):
		assert_object(_terrain.get_entity(cell)).is_same(placed)
	# One item for the whole machine, whatever its footprint.
	assert_int(Items.player_inventory.count_of("torch")).is_equal(1)
	placed.pop_to_pickup()
	Items.reset_run()


## An invalid target must not consume the item — the whole reason the order is
## reversed from the block path.
func test_an_unsupported_placement_consumes_nothing() -> void:
	Items.reset_run()
	Items.player_inventory.add_item("torch", 1)
	# No solid anywhere: the 2×2 would be floating.
	var placed := _place_big(_swinger_at(CLEAR_OF_P))
	assert_object(placed).is_null()
	assert_int(Items.player_inventory.count_of("torch")).is_equal(1)
	Items.reset_run()


## on_placed is the hook 3.4's power graph lands on, so it has to run with the
## node actually in the world — an override that walks the tree for neighbouring
## emitters would see nothing if it fired before add_child.
func test_on_placed_runs_after_the_node_is_in_the_tree() -> void:
	Items.reset_run()
	Items.player_inventory.add_item("torch", 1)
	_placeable_ground()
	var template := Observer.new()
	template.size = BIG_FOOTPRINT
	template.item_id = "torch"
	var scene := PackedScene.new()
	scene.pack(template)
	template.free()

	var player := _swinger_at(CLEAR_OF_P)
	player._place_scene(_terrain, P, scene)
	var placed: Observer = _terrain.get_entity(P)
	assert_int(placed.placed_calls).is_equal(1)
	assert_object(placed.parent_at_placed).is_same(player.get_parent())
	placed.pop_to_pickup()
	Items.reset_run()

# --- Hand-feeding (3.2) ------------------------------------------------------


func _fed_belt() -> Conveyor:
	var belt: Conveyor = auto_free(ConveyorScene.instantiate())
	belt.setup(P)
	add_child(belt)
	assert_bool(belt.register(_terrain)).is_true()
	return belt


## RMB on an occupied cell deposits into the deployable rather than failing the
## placement. One item, and one item only, per click.
func test_a_hand_feed_moves_exactly_one_item_into_the_deployable() -> void:
	Items.reset_run()
	Items.player_inventory.add_item("stone", 5)
	var belt := _fed_belt()

	assert_bool(_swinger_at(P).hand_feed(belt, Items.player_inventory.selected_item())).is_true()

	assert_int(belt.slot().count).is_equal(1)
	assert_int(Items.player_inventory.count_of("stone")).is_equal(4)
	Items.reset_run()


## ❗️A refusal has to leave the inventory alone: the offer goes out before the
## item is consumed, so a full belt costs nothing rather than eating the stack.
func test_a_refused_hand_feed_consumes_nothing() -> void:
	Items.reset_run()
	Items.player_inventory.add_item("stone", 5)
	var belt := _fed_belt()
	belt.accept_item("dirt", 1) # A mismatched id the belt cannot merge.

	assert_bool(_swinger_at(P).hand_feed(belt, Items.player_inventory.selected_item())).is_false()

	assert_int(Items.player_inventory.count_of("stone")).is_equal(5)
	Items.reset_run()


## The payoff of the refusing default on the base: feeding a torch is a no-op,
## with no "can this take items" test anywhere in the player.
func test_a_hand_feed_into_a_torch_consumes_nothing() -> void:
	Items.reset_run()
	Items.player_inventory.add_item("stone", 5)
	var torch := _torch_at(P)

	assert_bool(_swinger_at(P).hand_feed(torch, Items.player_inventory.selected_item())).is_false()

	assert_int(Items.player_inventory.count_of("stone")).is_equal(5)
	Items.reset_run()


## ❗️The claim happens BEFORE the item is consumed, so a consume that fails has
## to give back EVERY cell — one leaked cell of a 2×2 is a hole nothing can ever
## occupy again, and nothing in the game would report it.
func test_a_failed_consume_rolls_back_every_footprint_cell() -> void:
	Items.reset_run() # Empty inventory: consume_selected must fail.
	_placeable_ground()
	assert_object(_place_big(_swinger_at(CLEAR_OF_P))).is_null()
	for cell: Vector2i in Deployable.footprint_at(P, BIG_FOOTPRINT):
		assert_object(_terrain.get_entity(cell)).is_null()
	_terrain.debug_validate()


## A removed cell has to be re-placeable on the SAME frame — queue_free defers
## to end of frame, so an entity entry cleared only by _exit_tree would still
## be there when the player re-places into it.
func test_a_removed_cell_is_free_immediately() -> void:
	_make_spawner()
	_torch_at(P)
	_swinger_at(P)._hit_deployable(_terrain, P)
	var replacement: Torch = auto_free(TorchScene.instantiate())
	replacement.setup(P)
	assert_bool(replacement.register(_terrain)).is_true()

# --- Climbing (3.5b) ---------------------------------------------------------

const LadderScene := preload("res://scenes/automation/ladder.tscn")
const CLIMB_STEP := 1.0 / 60.0


## A player standing in the middle of cell `cell`, with a registered ladder in
## the same cell. `_try_climb` floors the player's CENTRE to a cell, so the
## position has to be the cell centre rather than its corner.
##
## `rungs` builds a column DOWNWARD from `cell` — so `cell` is always the TOP
## rung, which is the one the ladder-top floor cares about.
func _climber_at(cell: Vector2i, with_ladder := true, rungs := 1) -> Player:
	if with_ladder:
		for i in rungs:
			var ladder: Ladder = auto_free(LadderScene.instantiate())
			ladder.setup(cell + Vector2i.DOWN * i)
			add_child(ladder)
			assert_bool(ladder.register(_terrain)).is_true()
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	player.global_position = (Vector2(cell) + Vector2(0.5, 0.5)) * TileLayout.TILE_SIZE
	return player


## Hold `action` for the body of `callable`, then let go. `Input.action_press`
## is the only way to exercise the latch without a real keyboard, and a leaked
## held action would poison every later test in the run.
func _while_holding(action: StringName, body: Callable) -> void:
	Input.action_press(action)
	body.call()
	Input.action_release(action)


## ❗️The latch. Standing in a ladder cell is NOT climbing — otherwise walking
## past a ladder on flat ground, or brushing one mid-jump, sticks you to it.
func test_standing_in_a_ladder_cell_with_no_input_does_not_climb() -> void:
	var player := _climber_at(P)
	assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false()


func test_holding_up_in_a_ladder_cell_climbs_at_climb_speed() -> void:
	var player := _climber_at(P)
	_while_holding(
		&"move_up",
		func() -> void:
			assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_true()
			assert_float(player.velocity.y).is_equal_approx(-Player.CLIMB_SPEED, 0.001),
	)


func test_holding_down_in_a_ladder_cell_descends() -> void:
	var player := _climber_at(P)
	_while_holding(
		&"move_down",
		func() -> void:
			assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_true()
			assert_float(player.velocity.y).is_equal_approx(Player.CLIMB_SPEED, 0.001),
	)


## Once engaged, the latch holds with no key down — that is what lets you stop
## halfway up a shaft and hang there instead of sliding back down.
func test_the_latch_holds_once_engaged_and_hangs_still() -> void:
	var player := _climber_at(P)
	_while_holding(&"move_up", func() -> void: player._try_climb(_terrain, CLIMB_STEP))
	assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_true()
	assert_float(player.velocity.y).is_equal(0.0)


## And it drops the moment you are out of the cell, so nothing keeps hanging in
## mid-air after the column ends.
func test_leaving_the_ladder_cell_drops_the_latch() -> void:
	var player := _climber_at(P)
	_while_holding(&"move_up", func() -> void: player._try_climb(_terrain, CLIMB_STEP))
	player.global_position += Vector2(0.0, -4.0 * TileLayout.TILE_SIZE)
	assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false()


## A cell with no ladder in it is not climbable however hard you hold up — and a
## non-climbable deployable in the cell is not one either.
func test_a_torch_is_not_a_ladder() -> void:
	var player := _climber_at(P, false)
	_torch_at(P)
	_while_holding(
		&"move_up",
		func() -> void: assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false(),
	)


## ❗️A hit knocks you off. `apply_knockback` writes `velocity.y = -HURT_LIFT`,
## so an unguarded climb would erase the lift on the tick it lands — the same
## bug `_stun_left` already guards `velocity.x` against.
func test_a_hit_knocks_you_off_the_ladder_instead_of_erasing_the_lift() -> void:
	var player := _climber_at(P)
	_while_holding(
		&"move_up",
		func() -> void:
			assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_true()
			player.apply_knockback(Vector2.RIGHT, 140.0)
			assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false()
			assert_float(player.velocity.y).is_equal(-Player.HURT_LIFT),
	)


## ❗️The climb's early return skips the gravity block, which is where the jump
## buffer normally ages out. Without a decay of its own, climbing for a while
## after a stray jump press fires an instant buffered jump the moment you step
## off the top.
func test_the_jump_buffer_still_decays_while_climbing() -> void:
	var player := _climber_at(P)
	_while_holding(&"move_up", func() -> void: player._try_climb(_terrain, CLIMB_STEP))
	player._jump_buffer = Player.JUMP_BUFFER
	# One frame longer than the buffer: it must be spent, not banked.
	player._try_climb(_terrain, Player.JUMP_BUFFER + CLIMB_STEP)
	assert_float(player._jump_buffer).is_equal(0.0)


## Jumping off releases the latch and hands the frame back to the EXISTING
## coyote + buffer path, which is why stepping off a ladder needs no second
## jump implementation.
func test_a_buffered_jump_releases_the_climb() -> void:
	var player := _climber_at(P)
	_while_holding(&"move_up", func() -> void: player._try_climb(_terrain, CLIMB_STEP))
	player._jump_buffer = Player.JUMP_BUFFER
	assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false()
	assert_float(player._coyote).is_equal(Player.COYOTE_TIME)

# --- Standing on top of a column (3.5b follow-up) ----------------------------


## A player standing ON TOP of the top rung of a column: feet flush with the
## rung cell's top edge, centre in the cell ABOVE it.
func _stander_on(cell: Vector2i, rungs := 1) -> Player:
	var player := _climber_at(cell, true, rungs)
	player.global_position.y = cell.y * TileLayout.TILE_SIZE - Player.COLLISION_EXTENTS.y
	return player


## The virtual floor: a falling player is caught at the rung's top edge, not one
## frame past it, and arrives with no residual downward velocity.
func test_falling_onto_a_column_top_clamps_the_feet_and_zeroes_velocity() -> void:
	var player := _climber_at(P)
	var edge := float(P.y * TileLayout.TILE_SIZE)
	player.global_position.y = edge - Player.COLLISION_EXTENTS.y - 2.0
	player.velocity.y = 300.0
	assert_bool(player._stand_on_climbable(_terrain, CLIMB_STEP)).is_true()
	assert_float(player.global_position.y).is_equal_approx(edge - Player.COLLISION_EXTENTS.y, 0.001)
	assert_float(player.velocity.y).is_equal(0.0)


## ❗️**Top rung only**, which is the whole of "falling down a shaft is never
## interrupted". Without the second lookup every rung is a platform and a drop
## down your own column stops at the first one.
func test_a_rung_with_another_rung_above_it_does_not_catch_a_fall() -> void:
	var player := _stander_on(P, 2)
	var edge := float((P.y + 1) * TileLayout.TILE_SIZE)
	player.global_position.y = edge - Player.COLLISION_EXTENTS.y - 2.0
	player.velocity.y = 300.0
	assert_bool(player._stand_on_climbable(_terrain, CLIMB_STEP)).is_false()


## Jumping UP through a column is not landing on it.
func test_rising_through_a_column_top_does_not_catch() -> void:
	var player := _climber_at(P)
	player.global_position.y = float(P.y * TileLayout.TILE_SIZE) - Player.COLLISION_EXTENTS.y
	player.velocity.y = Player.JUMP_VELOCITY
	assert_bool(player._stand_on_climbable(_terrain, CLIMB_STEP)).is_false()


## Standing still re-satisfies the crossing test every frame, so the floor holds
## you there rather than needing an "am I standing" flag of its own.
func test_standing_still_on_a_column_top_keeps_holding() -> void:
	var player := _stander_on(P)
	assert_bool(player._stand_on_climbable(_terrain, CLIMB_STEP)).is_true()
	assert_float(player.global_position.y).is_equal_approx(
		float(P.y * TileLayout.TILE_SIZE) - Player.COLLISION_EXTENTS.y,
		0.001,
	)


## ❗️The climb is asked FIRST in `_move`, so pressing `S` on top of a column
## descends instead of standing on it. Without this the top rung would be a floor
## you could never get off downwards.
func test_climbing_suppresses_the_ladder_top_floor() -> void:
	var player := _stander_on(P)
	_while_holding(
		&"move_down",
		func() -> void: assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_true(),
	)
	assert_bool(player._stand_on_climbable(_terrain, CLIMB_STEP)).is_false()


## `S` from on top of a column is the only way back onto the ladder, so this
## branch is load-bearing rather than a guard.
func test_down_from_on_top_of_a_column_engages_the_climb() -> void:
	var player := _stander_on(P)
	_while_holding(
		&"move_down",
		func() -> void:
			assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_true()
			assert_float(player.velocity.y).is_equal_approx(Player.CLIMB_SPEED, 0.001),
	)


## ❗️And `W` from up there must NOT re-grab — it would sink you into the rung
## under your feet, which is the bobbing bug in a new costume.
func test_up_from_on_top_of_a_column_does_not_re_engage() -> void:
	var player := _stander_on(P)
	_while_holding(
		&"move_up",
		func() -> void: assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false(),
	)


## Climbing out of the top drops the latch one pixel above the standing position.
## ❗️Zeroing `velocity.y` there is what stops the player hopping ~3 px at
## CLIMB_SPEED and settling over several frames.
func test_climbing_out_of_the_top_drops_the_latch_and_zeroes_velocity() -> void:
	var player := _climber_at(P)
	_while_holding(&"move_up", func() -> void: player._try_climb(_terrain, CLIMB_STEP))
	assert_float(player.velocity.y).is_equal_approx(-Player.CLIMB_SPEED, 0.001)
	# Both probes clear: centre above the rung, feet past its top edge.
	player.global_position.y = (
		float(P.y * TileLayout.TILE_SIZE) - Player.COLLISION_EXTENTS.y - 2.0
	)
	assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false()
	assert_float(player.velocity.y).is_equal(0.0)

# --- Jumping off a ladder (3.5b follow-up) -----------------------------------


## ❗️Dropping the latch is not enough on its own: `_try_climb` engages on a HELD
## key, so the frame after the jump re-latches on the `W` you never let go of and
## overwrites the jump at CLIMB_SPEED — you never leave the ladder.
func test_a_buffered_jump_locks_out_the_key_that_was_already_held() -> void:
	var player := _climber_at(P)
	Input.action_press(&"move_up")
	# ❗️A frame has to pass first, or `is_action_just_pressed` is still true for
	# this very press — which is exactly the one that must NOT count as fresh.
	await get_tree().physics_frame
	await get_tree().process_frame
	player._try_climb(_terrain, CLIMB_STEP)
	player._jump_buffer = Player.JUMP_BUFFER
	assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false()
	assert_bool(player._climb_locked).is_true()
	# The next frame, still holding `W`: the jump survives.
	assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false()
	assert_bool(player._climbing).is_false()
	Input.action_release(&"move_up")


## And a fresh press is the only thing that clears it — so you re-grab mid-fall
## by letting go and pressing again, which is the whole of "the lock has no other
## clear condition".
func test_a_fresh_press_clears_the_lock_and_re_grabs_mid_fall() -> void:
	var player := _climber_at(P)
	player._climb_locked = true
	player.velocity.y = 200.0
	_while_holding(
		&"move_up",
		func() -> void:
			assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_true()
			assert_bool(player._climb_locked).is_false()
			assert_float(player.velocity.y).is_equal_approx(-Player.CLIMB_SPEED, 0.001),
	)


## ⚠️ The lock does NOT suppress the ladder-top floor. Standing on a column's top
## rung and pressing jump is an ordinary platform jump that lands you back on it,
## which is what "reads as ground" means; going down is `S`.
func test_the_jump_lock_does_not_suppress_the_ladder_top_floor() -> void:
	var player := _stander_on(P)
	player._climb_locked = true
	assert_bool(player._stand_on_climbable(_terrain, CLIMB_STEP)).is_true()

# --- Armor mitigation (3.6a) -------------------------------------------------
#
# A pure static, so every case below runs with no world, no equipment model and
# no autoload — which is the reason the arithmetic was pulled out of
# `take_damage` in the first place.


## Bare: armor changes nothing, so 2.5's numbers are preserved by construction.
func test_no_armor_leaves_damage_untouched() -> void:
	assert_float(PlayerScript.mitigate(8.0, 0.0)).is_equal_approx(8.0, 0.0001)
	assert_float(PlayerScript.mitigate(0.0, 0.0)).is_equal_approx(0.0, 0.0001)


## ⚠️ **Non-increasing, not strictly decreasing.** Once the floor binds, more armor
## buys nothing at all — a test asserting strict monotonicity would be asserting a
## curve with no floor, which is the design this one is not.
func test_mitigation_is_non_increasing_in_armor() -> void:
	var previous := PlayerScript.mitigate(8.0, 0.0)
	for armor in range(1, 400):
		var current := PlayerScript.mitigate(8.0, float(armor))
		assert_float(current).override_failure_message(
			"armor %d let MORE damage through than %d" % [armor, armor - 1],
		).is_less_equal(previous)
		previous = current


## Strictly decreasing while there is still room above the floor — the half point
## is inside that range, so this is the half of the curve that has to move.
func test_mitigation_strictly_decreases_below_the_floor() -> void:
	var previous := PlayerScript.mitigate(8.0, 0.0)
	for armor in range(1, 48):
		var current := PlayerScript.mitigate(8.0, float(armor))
		if current <= 8.0 * PlayerScript.MIN_DAMAGE_FRACTION:
			break
		assert_float(current).is_less(previous)
		previous = current


## The named knob, said out loud: at ARMOR_HALF_POINT a hit lands at half.
func test_the_half_point_halves_the_hit() -> void:
	assert_float(
		PlayerScript.mitigate(8.0, PlayerScript.ARMOR_HALF_POINT),
	).is_equal_approx(4.0, 0.0001)


func test_mitigation_never_exceeds_the_incoming_damage() -> void:
	for armor in range(0, 200):
		assert_float(PlayerScript.mitigate(8.0, float(armor))).is_less_equal(8.0)


## The floor, and why it is a fraction: absurd armor still lets 20% through.
func test_mitigation_never_falls_below_the_floor_fraction() -> void:
	var floor_value: float = 8.0 * PlayerScript.MIN_DAMAGE_FRACTION
	for armor in [0.0, 12.0, 100.0, 10000.0, 1e30]:
		assert_float(PlayerScript.mitigate(8.0, armor)).is_greater_equal(floor_value)
	assert_float(PlayerScript.mitigate(8.0, 1e30)).is_equal_approx(floor_value, 0.0001)


## ❗️`debug_menu.gd`'s kill row clears the grace window and passes `INF`. A
## multiplicative floor keeps `INF * 0.20 == INF`; a flat subtraction with a
## constant minimum would have made the row silently stop killing.
func test_infinite_damage_stays_lethal_at_any_armor() -> void:
	assert_float(PlayerScript.mitigate(INF, 0.0)).is_equal(INF)
	assert_float(PlayerScript.mitigate(INF, 16.0)).is_equal(INF)
	assert_float(PlayerScript.mitigate(INF, 1e30)).is_equal(INF)


## ⚠️ A negative armor total cannot happen through the model, but the curve must
## not amplify a hit if one ever did.
func test_negative_armor_does_not_amplify_a_hit() -> void:
	assert_float(PlayerScript.mitigate(8.0, -50.0)).is_equal_approx(8.0, 0.0001)


## The one number that decides whether combat still exists when you are geared: a
## walker's 8 through the full authored set (16 armor) still hurts.
func test_a_walkers_hit_still_lands_through_the_full_authored_set() -> void:
	var equipment := Equipment.new()
	equipment.equip(Equipment.Slot.HELMET, "copper_helmet")
	equipment.equip(Equipment.Slot.CHEST, "copper_chestplate")
	equipment.equip(Equipment.Slot.LEGS, "copper_greaves")
	equipment.equip(Equipment.Slot.FEET, "copper_boots")
	equipment.equip(Equipment.Slot.BACK, "copper_cloak")
	equipment.equip(Equipment.Slot.RING_1, "copper_ring")
	equipment.equip(Equipment.Slot.RING_2, "copper_ring")
	equipment.equip(Equipment.Slot.NECKLACE, "copper_amulet")
	var taken := PlayerScript.mitigate(8.0, equipment.armor_total())
	assert_float(taken).is_greater(0.0)
	assert_float(taken).is_less(8.0)

# --- Movement while a screen is open (3.6a) ----------------------------------
#
# ❗️**Blocking movement is not an early return.** Skipping `_move` skips the
# gravity block AND `move_and_slide()`, so the player would freeze in mid-air. The
# input READS are what get zeroed, and these are the five sites.


## Never leave either flag set for the next suite — the player reads them.
func _with_screen_open(body: Callable) -> void:
	CharacterScreen.is_open = true
	body.call()
	CharacterScreen.is_open = false


func test_a_held_direction_does_not_move_you_while_a_screen_is_open() -> void:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	_while_holding(
		&"move_right",
		func() -> void:
			player._move(CLIMB_STEP)
			assert_float(player.velocity.x).is_greater(0.0)
			_with_screen_open(
				func() -> void:
					player._move(CLIMB_STEP)
					assert_float(player.velocity.x).is_equal(0.0),
			),
	)


## ❗️**The Space bug.** `jump` is Space and a focused `Button` consumes
## `ui_accept`, so pressing Space over a tab button would activate it *and* jump.
func test_space_does_not_jump_while_a_screen_is_open() -> void:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	_terrain.set_tile(P + Vector2i.DOWN, "dirt")
	player.global_position = (Vector2(P) + Vector2(0.5, 0.5)) * TileLayout.TILE_SIZE
	_while_holding(
		&"jump",
		func() -> void:
			_with_screen_open(
				func() -> void:
					player._move(CLIMB_STEP)
					# No buffered press left behind either, or it fires on close.
					assert_float(player._jump_buffer).is_equal(0.0)
					assert_float(player.velocity.y).is_greater_equal(0.0),
			),
	)


## ❗️Gravity still runs, which is the whole reason this is not a guard at the top of
## `_step`: a suppressed `_move` would leave the player hanging in mid-air.
func test_gravity_still_applies_while_a_screen_is_open() -> void:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	player.global_position = (Vector2(P) + Vector2(0.5, 0.5)) * TileLayout.TILE_SIZE
	_with_screen_open(
		func() -> void:
			player._move(CLIMB_STEP)
			assert_float(player.velocity.y).is_greater(0.0),
	)


func test_a_held_climb_key_does_not_grab_a_ladder_while_a_screen_is_open() -> void:
	var player := _climber_at(P)
	_while_holding(
		&"move_up",
		func() -> void:
			_with_screen_open(
				func() -> void:
					assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_false()
					assert_float(player.velocity.y).is_equal(0.0),
			)
			# ...and it grabs again the moment the screen closes.
			assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_true(),
	)


## The climb branch decays the jump buffer itself, so the suppression has to reach
## that read too — otherwise stepping off the top fires a jump you never pressed.
func test_the_climb_branchs_jump_read_is_suppressed_too() -> void:
	var player := _climber_at(P)
	player._climbing = true
	_while_holding(
		&"jump",
		func() -> void:
			_with_screen_open(
				func() -> void:
					assert_bool(player._try_climb(_terrain, CLIMB_STEP)).is_true()
					assert_float(player._jump_buffer).is_equal(0.0),
			),
	)


## ⚠️ The regression pin on the two-predicate split: the debug menu has always let
## you walk around while its panel is up, and that must not change.
func test_the_debug_menu_still_allows_movement() -> void:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	DebugMenu.is_open = true
	_while_holding(
		&"move_right",
		func() -> void:
			player._move(CLIMB_STEP)
			assert_float(player.velocity.x).is_greater(0.0),
	)
	DebugMenu.is_open = false
