## Unit tests for the F3 debug menu. The panel is built in code, so this drives
## its public surface rather than clicking Controls.
extends GdUnitTestSuite

const DebugMenuScript := preload("res://scripts/debug/debug_menu.gd")


class GameDouble:
	extends Node

	var skips := 0


	func skip_countdown() -> void:
		skips += 1


class WavesDouble:
	extends Node

	var clears := 0
	var pokes := 0


	func debug_clear_wave() -> void:
		clears += 1


	func debug_poke_nearest() -> void:
		pokes += 1


class OverlayDouble:
	extends CanvasLayer

	var resets := 0


	func reset_stats() -> void:
		resets += 1


const ProgressionScript := preload("res://scripts/progression/progression.gd")


func _make_menu() -> DebugMenu:
	var menu: DebugMenu = auto_free(DebugMenuScript.new())
	menu.game = auto_free(GameDouble.new())
	menu.waves = auto_free(WavesDouble.new())
	menu.items = Items
	menu.progression = auto_free(ProgressionScript.new())
	menu.flow_overlay = auto_free(Node2D.new())
	menu.slot_overlay = auto_free(Node2D.new())
	menu.perf_overlay = auto_free(OverlayDouble.new())
	add_child(menu)
	return menu


func before_test() -> void:
	Items.reset_run()


func after_test() -> void:
	Items.reset_run()
	DebugMenu.is_open = false

# --- Open/close --------------------------------------------------------------


func test_starts_closed() -> void:
	var menu := _make_menu()
	assert_bool(menu.visible).is_false()
	assert_bool(DebugMenu.is_open).is_false()


## Gameplay polls Input directly, so this flag is the only thing stopping a
## click on a debug button from also swinging at the world behind it.
func test_toggle_tracks_the_static_flag() -> void:
	var menu := _make_menu()
	menu.toggle()
	assert_bool(menu.visible).is_true()
	assert_bool(DebugMenu.is_open).is_true()
	menu.toggle()
	assert_bool(menu.visible).is_false()
	assert_bool(DebugMenu.is_open).is_false()


## A scene reload frees the menu; leaving the flag set would make the next run
## silently unclickable.
func test_leaving_the_tree_clears_the_flag() -> void:
	var menu := _make_menu()
	menu.toggle()
	remove_child(menu)
	assert_bool(DebugMenu.is_open).is_false()

# --- Actions -----------------------------------------------------------------


## The loot button exists to make the death bag testable, which only works if
## the haul overflows the 10-slot hotbar into the slots a death actually drops.
func test_test_loot_overflows_the_hotbar() -> void:
	var menu := _make_menu()
	menu.give_test_loot()
	var past_hotbar := 0
	for i in range(Inventory.HOTBAR_SIZE, Inventory.SLOT_COUNT):
		if not Items.player_inventory.get_slot(i).is_empty():
			past_hotbar += 1
	assert_int(past_hotbar).is_greater(0)


## Deposits are terrain features rather than items, and bedrock never drops —
## handing either out would put an unplaceable id in the inventory.
func test_test_loot_skips_deposits_and_bedrock() -> void:
	var menu := _make_menu()
	menu.give_test_loot()
	assert_int(Items.player_inventory.count_of("bedrock")).is_equal(0)
	assert_int(Items.player_inventory.count_of("coal_deposit")).is_equal(0)
	assert_int(Items.player_inventory.count_of("coal")).is_greater(0)


func test_perf_toggle_resets_stats_only_when_switched_on() -> void:
	var menu := _make_menu()
	var overlay: OverlayDouble = menu.perf_overlay
	menu._toggle_perf_overlay(true)
	assert_bool(overlay.visible).is_true()
	assert_int(overlay.resets).is_equal(1)
	menu._toggle_perf_overlay(false)
	assert_bool(overlay.visible).is_false()
	assert_int(overlay.resets).is_equal(1) # Switching off measures nothing new.


func test_flow_overlay_toggle_drives_visibility() -> void:
	var menu := _make_menu()
	menu._toggle_flow_overlay(true)
	assert_bool(menu.flow_overlay.visible).is_true()
	menu._toggle_flow_overlay(false)
	assert_bool(menu.flow_overlay.visible).is_false()


## The automation slot overlay is a ROW, not a hotkey — debug overlays own no
## keybindings of their own (ui.md), despite how the 3.2 roadmap line read.
func test_slot_overlay_toggle_drives_visibility() -> void:
	var menu := _make_menu()
	menu._toggle_slot_overlay(true)
	assert_bool(menu.slot_overlay.visible).is_true()
	menu._toggle_slot_overlay(false)
	assert_bool(menu.slot_overlay.visible).is_false()


## Missing overlays (a stripped build, or a test harness) must not crash the
## panel — every row stays clickable.
func test_toggles_tolerate_missing_overlays() -> void:
	var menu := _make_menu()
	menu.flow_overlay = null
	menu.slot_overlay = null
	menu.perf_overlay = null
	menu._toggle_flow_overlay(true)
	menu._toggle_slot_overlay(true)
	menu._toggle_perf_overlay(true)
	assert_bool(menu.visible).is_false() # Reached here without erroring.


## The button exists to reach a level-up without mining hundreds of blocks, so
## one press has to be worth more than the first level costs.
func test_grant_xp_levels_in_a_single_press() -> void:
	var menu := _make_menu()
	menu.grant_xp()
	assert_int(menu.progression.level).is_greater(1)
	assert_int(menu.progression.upgrade_points).is_greater(0)


func test_kill_player_without_a_player_is_inert() -> void:
	var menu := _make_menu()
	menu.kill_player() # No player in this tree.
	assert_bool(DebugMenu.is_open).is_false()

# --- Give item / full bright (2.7) -------------------------------------------


## Authored items and ordinary blocks both have to be reachable — the row exists
## so any id can be conjured by name, not just the ones with tile art.
func test_giveable_ids_cover_authored_items_and_materials() -> void:
	var ids := DebugMenuScript.giveable_ids()
	assert_bool(ids.has("pickaxe_t1")).is_true()
	assert_bool(ids.has("torch")).is_true()
	assert_bool(ids.has("dirt")).is_true()


## Same rule as give_test_loot: deposits are terrain features rather than items
## and bedrock never drops, so neither may reach the inventory.
func test_giveable_ids_exclude_deposits_and_bedrock() -> void:
	var ids := DebugMenuScript.giveable_ids()
	assert_bool(ids.has("coal_deposit")).is_false()
	assert_bool(ids.has("bedrock")).is_false()


func test_giveable_ids_have_no_duplicates() -> void:
	var ids := DebugMenuScript.giveable_ids()
	var seen: Dictionary = { }
	for id in ids:
		assert_bool(seen.has(id)).is_false()
		seen[id] = true


func test_give_item_adds_the_requested_count() -> void:
	var menu := _make_menu()
	menu.give_item("torch", 7)
	assert_int(Items.player_inventory.count_of("torch")).is_equal(7)


## A SpinBox cannot go below 1, but the method is public and 3.1 will call it —
## a zero or negative count must be a no-op rather than an inventory corruption.
func test_give_item_ignores_a_non_positive_count() -> void:
	var menu := _make_menu()
	menu.give_item("torch", 0)
	menu.give_item("torch", -5)
	menu.give_item("", 10)
	assert_int(Items.player_inventory.count_of("torch")).is_equal(0)


## Hiding the light map IS full bright — no multiply pass means an unlit world.
func test_full_bright_hides_the_light_map() -> void:
	var menu := _make_menu()
	var light_map: Node2D = auto_free(Node2D.new())
	menu.light_map = light_map
	menu._toggle_full_bright(true)
	assert_bool(light_map.visible).is_false()
	menu._toggle_full_bright(false)
	assert_bool(light_map.visible).is_true()


## Every row stays clickable in a stripped build or a test harness.
func test_full_bright_tolerates_a_missing_light_map() -> void:
	var menu := _make_menu()
	menu.light_map = null
	menu._toggle_full_bright(true)
	assert_bool(menu.visible).is_false() # Reached here without erroring.

# --- Factory rig (3.3) -------------------------------------------------------

const TerrainScript := preload("res://scripts/terrain/terrain.gd")
const MinerScene := preload("res://scenes/automation/miner.tscn")
const FurnaceScene := preload("res://scenes/automation/furnace.tscn")
const AmmoPressScene := preload("res://scenes/automation/ammo_press.tscn")
const TurretScene := preload("res://scenes/automation/turret.tscn")
const AutomationScript := preload("res://scripts/automation/automation.gd")
const GameScript := preload("res://scripts/game/game.gd")
const PoolScript := preload("res://scripts/combat/projectile_pool.gd")


## The rig is the only practical way into a production chain in an exported
## build, so what it lays down has to actually be placeable — not merely look
## right in a screenshot.
func test_the_factory_rig_carves_a_pocket_with_a_deposit_a_miner_can_face() -> void:
	var terrain: Node = auto_free(TerrainScript.new())
	add_child(terrain)
	var menu := _make_menu()
	menu.terrain = terrain
	# Stands in for the player: the rig only reads a global_position.
	var player: Node2D = auto_free(Node2D.new())
	player.add_to_group(&"player")
	player.global_position = Vector2(100, 100) * TileLayout.TILE_SIZE
	add_child(player)

	var at: Vector2i = menu.build_factory_rig()

	# The pocket is air with a solid floor, so a support_dirs = 15 machine stands.
	assert_str(terrain.get_material_id(at)).is_equal("")
	assert_bool(terrain.is_solid(at + Vector2i(0, DebugMenuScript.RIG_HEIGHT))).is_true()
	# ❗️The payoff: a 3x2 miner placed against the seam, facing RIGHT, is valid.
	var size := Vector2i(3, 2)
	var origin := at + Vector2i(
		DebugMenuScript.RIG_WIDTH - DebugMenuScript.RIG_ORE_WIDTH - size.x,
		DebugMenuScript.RIG_HEIGHT - 2,
	)
	assert_bool(
		Player.can_place_at(terrain, origin, Rect2i(0, 0, 1, 1), size, 15, Vector2i.RIGHT, true),
	).is_true()
	# And facing away from the seam is not — the rig teaches the rule, not a spot.
	assert_bool(
		Player.can_place_at(terrain, origin, Rect2i(0, 0, 1, 1), size, 15, Vector2i.LEFT, true),
	).is_false()


func test_the_factory_rig_hands_over_the_whole_chain() -> void:
	var terrain: Node = auto_free(TerrainScript.new())
	add_child(terrain)
	var menu := _make_menu()
	menu.terrain = terrain
	var player: Node2D = auto_free(Node2D.new())
	player.add_to_group(&"player")
	player.global_position = Vector2(100, 100) * TileLayout.TILE_SIZE
	add_child(player)

	menu.build_factory_rig()

	for id: String in DebugMenuScript.RIG_KIT:
		assert_int(Items.player_inventory.count_of(id)).override_failure_message(
			"The rig handed over no %s" % id,
		).is_equal(DebugMenuScript.RIG_KIT_COUNT)
	# ❗️A chain with no generator can never run since 3.4, and one with no coal
	# can never start — the rig is the only way into a production chain in an
	# exported build, so both are as structural as the miner.
	assert_bool(DebugMenuScript.RIG_KIT.has("generator")).is_true()
	assert_bool(DebugMenuScript.RIG_KIT.has("relay")).is_true()
	assert_int(Items.player_inventory.count_of(DebugMenuScript.RIG_FUEL)).override_failure_message(
		"The rig handed over no fuel, so nothing it built can ever run",
	).is_equal(DebugMenuScript.RIG_FUEL_COUNT)


## ❗️**The kit has to fit the HOTBAR, not merely the inventory** — and that
## distinction is the whole bug. 3.5a added `ammo_press` and `turret` to the kit,
## pushing it to 12 stacks against a 10-slot hotbar; the last two (relay and the
## coal) landed in inventory slots 11-12, which have no UI until 3.6. The
## generator could not be fuelled, so the rig handed over a chain that could
## never run — the exact failure 3.4 added the generator to prevent.
##
## ⚠️ `count_of()` counts all 40 slots, so the assertion above sailed straight
## past it. Only a browser run caught it. This is the version that would not have.
func test_every_rig_item_lands_within_reach_of_a_hotbar_key() -> void:
	var terrain: Node = auto_free(TerrainScript.new())
	add_child(terrain)
	var menu := _make_menu()
	menu.terrain = terrain
	var player: Node2D = auto_free(Node2D.new())
	player.add_to_group(&"player")
	player.global_position = Vector2(100, 100) * TileLayout.TILE_SIZE
	add_child(player)

	menu.build_factory_rig()

	var wanted := PackedStringArray(DebugMenuScript.RIG_KIT)
	wanted.append(DebugMenuScript.RIG_FUEL)
	var reachable := PackedStringArray()
	for i in Inventory.HOTBAR_SIZE:
		var slot: Dictionary = Items.player_inventory.get_slot(i)
		if not slot.is_empty():
			reachable.append(slot.id)
	for id: String in wanted:
		assert_bool(reachable.has(id)).override_failure_message(
			"'%s' is past hotbar slot %d — unselectable in an exported build, so the "
			% [id, Inventory.HOTBAR_SIZE]
			+ "rig hands over a chain that can never run",
		).is_true()


## ❗️**The pocket has to actually FIT the chain built into it**, and "22 was
## already tight" is exactly the kind of thing that goes stale the next time a
## machine joins the kit. Measured off the AUTHORED footprints rather than
## restated as a number, so widening a machine fails here instead of in a browser.
##
## Right to left from the seam, along the pocket's bottom row:
##   turret · ins · belt · ins · press · ins · belt · ins · furnace · ins · belt ·
##   ins · miner · ore
func test_the_pocket_is_wide_enough_for_the_chain_the_defense_row_builds() -> void:
	var machines := {
		"miner": MinerScene,
		"furnace": FurnaceScene,
		"ammo_press": AmmoPressScene,
		"turret": TurretScene,
	}
	var needed := DebugMenuScript.RIG_ORE_WIDTH
	for id: String in machines:
		needed += Deployable.scene_size(machines[id]).x
	# Three links, each an extractor, a belt tile and a feeder.
	needed += 3 * 3

	assert_int(DebugMenuScript.RIG_WIDTH).override_failure_message(
		"RIG_WIDTH %d cannot hold the %d cells the kit's chain needs"
		% [DebugMenuScript.RIG_WIDTH, needed],
	).is_greater_equal(needed)


## ❗️The kit deliberately STOPS before the defense tail. `ammo_press` and
## `turret` were briefly here and overflowed the hotbar (see above); the
## assembled-chain row covers them now, and both stay reachable through the
## give-item dropdown. Asserting their absence keeps the fix from being quietly
## undone by someone re-adding a row that "obviously belongs".
func test_the_kit_stops_before_the_defense_tail() -> void:
	assert_bool(DebugMenuScript.RIG_KIT.has("ammo_press")).is_false()
	assert_bool(DebugMenuScript.RIG_KIT.has("turret")).is_false()
	# But the chain still has to be reachable SOMEHOW in an exported build.
	var ids := DebugMenuScript.giveable_ids()
	assert_bool(ids.has("ammo_press")).is_true()
	assert_bool(ids.has("turret")).is_true()


## The trap needs no rig row: an `ItemDefs.STATS` entry earns it a give-item row
## for free, which is the whole reason that dropdown exists.
func test_every_defense_deployable_is_reachable_in_an_exported_build() -> void:
	var ids := DebugMenuScript.giveable_ids()
	for id: String in ["turret", "spike_trap", "ammo_press", "copper_ammo", "iron_ammo"]:
		assert_bool(ids.has(id)).override_failure_message(
			"'%s' cannot be obtained in an exported build" % id,
		).is_true()


## ❗️The assembled-chain row is a MEASUREMENT fixture, so what matters is that
## everything it builds is live and fed: a turret that lands unregistered or
## unloaded would silently make the browser perf run measure nothing.
##
## Uses the real autoloads' Automation registry via `on_placed()`, exactly as a
## player placement would.
func test_the_defense_row_builds_a_live_fed_turret_line() -> void:
	var terrain: Node = auto_free(TerrainScript.new())
	add_child(terrain)
	var menu := _make_menu()
	menu.terrain = terrain
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	menu.spawn_parent = root
	var player: Node2D = auto_free(Node2D.new())
	player.add_to_group(&"player")
	player.global_position = Vector2(100, 100) * TileLayout.TILE_SIZE
	add_child(player)

	var built: Dictionary = menu.build_defense_chain()

	assert_int(built.turrets.size()).is_equal(DebugMenuScript.CHAIN_TURRETS)
	assert_int(built.generators.size()).is_equal(DebugMenuScript.CHAIN_GENERATORS)
	for node: Deployable in built.chain:
		assert_object(node).override_failure_message(
			"A chain machine failed to register — its cells were already taken",
		).is_not_null()
	for turret: Deployable in built.turrets:
		assert_object(turret).is_not_null()
		# Loaded, or the perf run measures six turrets doing nothing.
		assert_bool((turret as Turret).is_idle()).override_failure_message(
			"A turret was built empty, so it would never fire during the measurement",
		).is_false()
	for gen: Deployable in built.generators:
		# Fuelled, or the whole line browns out and the figure is meaningless.
		assert_bool((gen as Generator).is_idle()).is_false()

	# Every turret reserved its own pool slots — the thing the browser run exists
	# to stress. Six turrets must push capacity well past the old fixed 32.
	for node: Node in built.turrets:
		assert_int((node as Turret).reserve_shots()).is_greater(0)


## ❗️**The invariant the fixture exists for, and the one a browser run cannot
## assert for itself: every turret must end up POWERED and FIRING.** The first
## in-browser attempt built six turrets showing red bolts — supply 4.0 against
## demand 5.0, with a generator missing — so the "load test" was measuring an
## idle scene. A fixture that quietly builds nothing is worse than no fixture.
func test_the_defense_row_leaves_every_turret_powered_and_shooting() -> void:
	var terrain: Node = auto_free(TerrainScript.new())
	add_child(terrain)
	var game: Node = auto_free(GameScript.new())
	game.state = GameScript.State.BUILD_PHASE
	var automation: Node = auto_free(AutomationScript.new())
	automation.terrain = terrain
	automation.game = game
	add_child(automation)
	automation.set_process(false)
	var pool: ProjectilePool = auto_free(PoolScript.new())
	add_child(pool)

	var menu := _make_menu()
	menu.terrain = terrain
	menu.automation = automation
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	menu.spawn_parent = root
	var player: Node2D = auto_free(Node2D.new())
	player.add_to_group(&"player")
	player.global_position = Vector2(100, 100) * TileLayout.TILE_SIZE
	add_child(player)

	var built: Dictionary = menu.build_defense_chain()
	automation.step_tick() # Lights the generators and solves the grid.

	for turret: Deployable in built.turrets:
		assert_bool(turret.is_powered()).override_failure_message(
			"A turret landed outside every grid — the perf run would measure an idle scene",
		).is_true()
		assert_float(turret.power_ratio()).override_failure_message(
			"A turret is browned out, so the turret line fires at the wrong rate",
		).is_equal(1.0)

	# ...and they actually shoot. A mob in front of the line, one tick, six bolts.
	var mob: Node2D = auto_free(Node2D.new())
	mob.position = (built.turrets[0] as Node2D).global_position
	mob.add_to_group(&"enemies")
	add_child(mob)
	automation.step_tick()

	assert_int(pool.active_count()).override_failure_message(
		"The turret line fired nothing at a mob standing on top of it",
	).is_greater(0)


## No player in the tree (a headless tool, or the beat after a death) must be a
## no-op rather than a crash on a null global_position.
func test_the_factory_rig_is_inert_without_a_player() -> void:
	var terrain: Node = auto_free(TerrainScript.new())
	add_child(terrain)
	var menu := _make_menu()
	menu.terrain = terrain
	assert_vector(menu.build_factory_rig()).is_equal(Vector2i.ZERO)
