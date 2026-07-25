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
		func(_pos: Vector2i, drop_id: String, _count: int, _source: int) -> void:
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
