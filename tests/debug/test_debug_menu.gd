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


## Missing overlays (a stripped build, or a test harness) must not crash the
## panel — every row stays clickable.
func test_toggles_tolerate_missing_overlays() -> void:
	var menu := _make_menu()
	menu.flow_overlay = null
	menu.perf_overlay = null
	menu._toggle_flow_overlay(true)
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
