## Unit tests for the HUD (roadmap 1.7 + 2.1 phase widgets + the 2.4 remaining
## readout + the 2.6 XP bar): formatting statics, icon lookup, and reaction to
## an injected Inventory/Game/Waves/Progression — never the live autoloads.
extends GdUnitTestSuite

const HudScene := preload("res://scenes/ui/hud.tscn")
const HudScript := preload("res://scripts/ui/hud.gd")
const GameScript := preload("res://scripts/game/game.gd")
const ProgressionScript := preload("res://scripts/progression/progression.gd")
const Tileset := preload("res://assets/generated/terrain_tileset.tres")


## Just the wave-progress surface the HUD reads (roadmap 2.4).
class WavesStub:
	extends Node

	signal wave_progress_changed(left: int)

	var count := 0


	func remaining() -> int:
		return count


	func set_remaining(value: int) -> void:
		count = value
		wave_progress_changed.emit(value)


## Just the idle-machine surface the HUD reads (roadmap 3.3) — a real Automation
## would drag Terrain and Game in behind it for one integer.
class AutomationStub:
	extends Node

	signal idle_machines_changed(count: int)

	var idle := 0


	func idle_machines() -> int:
		return idle


	func set_idle(value: int) -> void:
		idle = value
		idle_machines_changed.emit(value)


var _inv: Inventory
var _game: Node
var _waves: WavesStub
var _progression: Node
var _automation: AutomationStub
var _hud: CanvasLayer


func after_test() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.free()
	_hud = null


func before_test() -> void:
	_inv = Inventory.new()
	_game = auto_free(GameScript.new())
	_waves = auto_free(WavesStub.new())
	# A real Progression, just not the autoload one — the HUD reads its curve
	# and level, so a stub would only re-implement it.
	_progression = auto_free(ProgressionScript.new())
	# Not auto_free: one test frees the HUD itself to prove the static seam is
	# inert without one, and auto_free would then double-free it.
	_hud = HudScene.instantiate()
	_hud.inventory = _inv
	_hud.game = _game
	_hud.waves = _waves
	_hud.progression = _progression
	_automation = auto_free(AutomationStub.new())
	_hud.automation = _automation
	add_child(_hud)

# --- Elevation formatting ----------------------------------------------------


func test_biome_name_at_band_edges() -> void:
	assert_str(HudScript.biome_name(0)).is_equal("surface")
	assert_str(HudScript.biome_name(39)).is_equal("surface")
	assert_str(HudScript.biome_name(40)).is_equal("dirt_caves")
	assert_str(HudScript.biome_name(1199)).is_equal("magma")


func test_biome_name_clamps_out_of_range() -> void:
	assert_str(HudScript.biome_name(-5)).is_equal("surface")
	assert_str(HudScript.biome_name(99999)).is_equal("magma")


func test_elevation_text_format() -> void:
	assert_str(HudScript.elevation_text(655.0)).is_equal("Elevation: 40 — dirt_caves")

# --- Icon lookup -------------------------------------------------------------


func test_icon_for_material_uses_full_mask_frame() -> void:
	var icon: Texture2D = HudScript.icon_for("dirt")
	assert_object(icon).is_instanceof(AtlasTexture)
	var src: TileSetAtlasSource = Tileset.get_source(Materials.ORDER.find("dirt"))
	var expected := Rect2(src.get_tile_texture_region(TileLayout.LAYOUT[15][0], 0))
	assert_that((icon as AtlasTexture).region).is_equal(expected)


func test_icon_for_deposit_resolves() -> void:
	# Deposits reuse their ore's sheet but still own an atlas source.
	assert_object(HudScript.icon_for("iron_deposit")).is_instanceof(AtlasTexture)


func test_icon_for_unknown_id_falls_back_to_swatch() -> void:
	var icon: Texture2D = HudScript.icon_for("not_a_thing")
	assert_object(icon).is_not_null()
	assert_object(icon).is_instanceof(ImageTexture)


func test_icon_cache_returns_same_instance() -> void:
	assert_object(HudScript.icon_for("stone")).is_same(HudScript.icon_for("stone"))

# --- Hotbar display ----------------------------------------------------------


func test_add_item_updates_slot_zero() -> void:
	_inv.add_item("dirt", 10)
	assert_str(_hud._slot_counts[0].text).is_equal("10")
	assert_object(_hud._slot_icons[0].texture).is_not_null()


func test_emptied_slot_clears_display() -> void:
	_inv.add_item("dirt", 10)
	_inv.remove_from_slot(0, 10)
	assert_str(_hud._slot_counts[0].text).is_equal("")
	assert_object(_hud._slot_icons[0].texture).is_null()


func test_selection_highlight_moves() -> void:
	assert_that(_hud._slot_bgs[0].color).is_equal(HudScript.SELECTED_BG)
	_inv.selected_slot = 3
	assert_that(_hud._slot_bgs[3].color).is_equal(HudScript.SELECTED_BG)
	assert_that(_hud._slot_bgs[0].color).is_equal(HudScript.NORMAL_BG)


func test_key_labels_run_1_to_9_then_0() -> void:
	var bg: ColorRect = _hud._slot_bgs[Inventory.HOTBAR_SIZE - 1]
	var key := bg.get_child(1) as Label # Child order: icon, key, count.
	assert_str(key.text).is_equal("0")


func test_non_hotbar_slot_change_leaves_hotbar_untouched() -> void:
	for i in Inventory.HOTBAR_SIZE:
		_inv.add_item("dirt", Inventory.STACK_SIZE)
	_inv.add_item("dirt", 5) # Overflows into slot 10 — beyond the hotbar.
	assert_str(_hud._slot_counts[Inventory.HOTBAR_SIZE - 1].text).is_equal("99")
	assert_int(_hud._slot_counts.size()).is_equal(Inventory.HOTBAR_SIZE)

# --- Bars --------------------------------------------------------------------


func test_health_bar_updates() -> void:
	_hud._on_health_changed(30.0, 100.0)
	assert_float(_hud._hp_bar.max_value).is_equal(100.0)
	assert_float(_hud._hp_bar.value).is_equal(30.0)
	assert_str(_hud._hp_label.text).is_equal("30 / 100")


func test_mana_bar_updates_and_rounds_label() -> void:
	_hud._on_mana_changed(12.5, 50.0)
	assert_float(_hud._mana_bar.value).is_equal(12.5)
	assert_str(_hud._mana_label.text).is_equal("13 / 50")

# --- Countdown / phase label (2.1) ---------------------------------------------


func test_format_time() -> void:
	assert_str(HudScript.format_time(240)).is_equal("4:00")
	assert_str(HudScript.format_time(69)).is_equal("1:09")
	assert_str(HudScript.format_time(9)).is_equal("0:09")
	assert_str(HudScript.format_time(0)).is_equal("0:00")


func test_countdown_tick_updates_phase_label() -> void:
	_game.countdown_tick.emit(240)
	assert_str(_hud._phase_label.text).is_equal("4:00")
	assert_that(_hud._phase_label.modulate).is_equal(Color.WHITE)
	assert_float(_hud._pulse_overlay.color.a).is_equal(0.0)


func test_final_window_pulses_and_reddens() -> void:
	_game.countdown_tick.emit(11)
	assert_that(_hud._phase_label.modulate).is_equal(Color.WHITE)
	assert_float(_hud._pulse_overlay.color.a).is_equal(0.0)
	_game.countdown_tick.emit(10)
	assert_that(_hud._phase_label.modulate).is_equal(HudScript.FINAL_COLOR)
	# Assert the immediate set (approx: Color stores float32) — the tween
	# fades it later.
	assert_float(_hud._pulse_overlay.color.a).is_equal_approx(HudScript.PULSE_ALPHA, 0.001)


func test_wave_text() -> void:
	assert_str(HudScript.wave_text(3, 7)).is_equal("Wave 3 — 7 remaining")


func test_wave_started_switches_label_and_announces() -> void:
	_game.set_state(GameScript.State.WAVE_PHASE)
	_waves.count = 5
	_game.wave_started.emit(3)
	assert_str(_hud._phase_label.text).is_equal("Wave 3 — 5 remaining")
	assert_that(_hud._phase_label.modulate).is_equal(Color.WHITE)
	assert_bool(_hud._wave_banner.visible).is_true()
	assert_str(_hud._wave_banner.text).is_equal("Wave 3")
	assert_float(_hud._wave_banner.modulate.a).is_equal(1.0)


func test_wave_progress_counts_down() -> void:
	_game.set_state(GameScript.State.WAVE_PHASE)
	_waves.count = 5
	_game.wave_started.emit(3)
	_waves.set_remaining(4)
	assert_str(_hud._phase_label.text).is_equal("Wave 3 — 4 remaining")


## A mob dying during the grace beat must not overwrite the countdown that
## _on_countdown_tick just wrote.
func test_progress_outside_wave_phase_leaves_the_countdown_alone() -> void:
	_game.set_state(GameScript.State.WAVE_PHASE)
	_game.wave_started.emit(3)
	_game.set_state(GameScript.State.BUILD_PHASE)
	_game.countdown_tick.emit(240)
	_waves.set_remaining(0)
	assert_str(_hud._phase_label.text).is_equal("4:00")


func test_wave_cleared_announces() -> void:
	_game.wave_cleared.emit(2)
	assert_bool(_hud._wave_banner.visible).is_true()
	assert_str(_hud._wave_banner.text).is_equal("Wave 2 cleared!")

# --- Core bar (2.1) ------------------------------------------------------------


func test_core_bar_updates() -> void:
	_hud._on_core_health_changed(400.0, 1000.0)
	assert_float(_hud._core_bar.max_value).is_equal(1000.0)
	assert_float(_hud._core_bar.value).is_equal(400.0)

# --- XP bar (2.6) --------------------------------------------------------------


func test_xp_text_format() -> void:
	assert_str(HudScript.xp_text(3, 42.7, 289.977)).is_equal("Lv 3 — 42 / 290")


## Seeded in _ready, not on the first grant: a run resumed mid-level (4.3)
## must not show an empty bar until something dies.
func test_xp_bar_is_seeded_before_any_grant() -> void:
	assert_float(_hud._xp_bar.value).is_equal(0.0)
	assert_float(_hud._xp_bar.max_value).is_equal_approx(ProgressionScript.xp_to_level(1), 0.001)
	assert_str(_hud._xp_label.text).is_equal("Lv 1 — 0 / 50")


func test_granting_xp_fills_the_bar() -> void:
	_progression.grant_xp("mining", 20.0)
	assert_float(_hud._xp_bar.value).is_equal_approx(20.0, 0.001)
	assert_str(_hud._xp_label.text).is_equal("Lv 1 — 20 / 50")


## Crossing a level rebases the bar onto the next, costlier level.
func test_leveling_rebases_the_bar_and_announces() -> void:
	_progression.grant_xp("mining", 60.0)
	assert_float(_hud._xp_bar.value).is_equal_approx(10.0, 0.001)
	assert_float(_hud._xp_bar.max_value).is_equal_approx(ProgressionScript.xp_to_level(2), 0.001)
	assert_bool(_hud._wave_banner.visible).is_true()
	assert_str(_hud._wave_banner.text).is_equal("Level 2!")

# --- Rejection toast (2.7) ---------------------------------------------------


func test_toast_shows_the_message() -> void:
	_hud.toast("nope")
	assert_bool(_hud._toast.visible).is_true()
	assert_str(_hud._toast.text).is_equal("nope")
	assert_float(_hud._toast.modulate.a).is_equal(1.0)


## ❗️Placement polls input every physics frame, so a held RMB against a buffer
## fires this 60x/second. Without absorbing identical repeats the tween restarts
## every frame and the toast never fades — it would ship visibly broken.
func test_repeated_identical_toasts_do_not_restart_the_fade() -> void:
	_hud.toast("same")
	var first: Tween = _hud._toast_tween
	_hud.toast("same")
	_hud.toast("same")
	assert_object(_hud._toast_tween).is_same(first)


## A different message must interrupt, or a stale rejection outlives the one
## that actually matters.
func test_a_different_message_replaces_the_toast() -> void:
	_hud.toast("first")
	var first: Tween = _hud._toast_tween
	_hud.toast("second")
	assert_object(_hud._toast_tween).is_not_same(first)
	assert_str(_hud._toast.text).is_equal("second")


## The static seam exists so unrelated call sites need no node path. It has to
## be inert with no HUD in the tree, or every headless test that touches
## placement would crash.
func test_static_show_toast_is_inert_without_a_hud() -> void:
	_hud.free() # The suite's HUD leaves the tree, clearing the static instance.
	_hud = null
	Hud.show_toast("nobody is listening")
	assert_bool(true).is_true() # Reached here without erroring.


## The banner and the toast are separate widgets with separate tweens: a
## rejected click must never blot out a wave announcement.
func test_a_toast_does_not_disturb_the_wave_banner() -> void:
	_game.wave_started.emit(4)
	_hud.toast("rejected")
	assert_bool(_hud._wave_banner.visible).is_true()
	assert_str(_hud._wave_banner.text).is_equal("Wave 4")

# --- Idle machines (3.3) -----------------------------------------------------


## Hidden at zero: a factory with nothing wrong shows nothing at all.
func test_the_idle_alert_is_hidden_with_no_idle_machines() -> void:
	assert_bool(_hud._idle_alert.visible).is_false()


## ❗️A PERSISTENT count, not a toast. A miner runs its deposit dry while you
## are somewhere else — a toast fires at a screen nobody is looking at, where a
## count is still there when you come back.
func test_the_idle_alert_appears_with_a_count_and_goes_away_again() -> void:
	_automation.set_idle(2)
	assert_bool(_hud._idle_alert.visible).is_true()
	assert_str(_hud._idle_alert.text).is_equal(Hud.idle_text(2))

	_automation.set_idle(0)
	assert_bool(_hud._idle_alert.visible).is_false()


## ASCII, singular/plural. The bundled Open Sans has no U+26A0, so a real
## warning sign would render as a blank box.
func test_idle_text_reads_as_a_warning_in_both_numbers() -> void:
	assert_str(Hud.idle_text(1)).is_equal("[!] 1 idle machine")
	assert_str(Hud.idle_text(3)).is_equal("[!] 3 idle machines")


## Seeded in _ready like the XP bar, so a run resumed with an already-exhausted
## miner shows the alert immediately rather than on the next transition.
func test_the_idle_alert_is_seeded_from_the_current_count() -> void:
	_hud.free()
	var automation: AutomationStub = auto_free(AutomationStub.new())
	automation.idle = 1
	_hud = HudScene.instantiate()
	_hud.inventory = _inv
	_hud.game = _game
	_hud.waves = _waves
	_hud.progression = _progression
	_hud.automation = automation
	add_child(_hud)
	assert_bool(_hud._idle_alert.visible).is_true()
