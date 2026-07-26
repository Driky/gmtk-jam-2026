## Unit tests for placement validity + tile-rect math (roadmap 1.6) and the
## HP/mana stub (roadmap 1.7). Terrain is a fresh instance per test — never
## the live autoload.
extends GdUnitTestSuite

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const PlayerScript := preload("res://scripts/player/player.gd")
const PlayerScene := preload("res://scenes/player.tscn")

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
	player.respawned.connect(func() -> void: respawns.append(true))
	player.take_damage(9999.0)
	player._tick_respawn(Player.RESPAWN_TIME + 0.01)
	assert_bool(player.is_dead()).is_false()
	assert_float(player.current_hp).is_equal(Progression.get_stat("max_hp"))
	# Landing straight into a mob's mouth would make the timer a punishment.
	assert_bool(player.is_invulnerable()).is_true()
	assert_int(respawns.size()).is_equal(1)
	assert_bool(player.visible).is_true()

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
