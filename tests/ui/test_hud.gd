## Unit tests for the HUD (roadmap 1.7): formatting statics, icon lookup, and
## hotbar/bar reaction to an injected Inventory — never the live autoloads.
extends GdUnitTestSuite

const HudScene := preload("res://scenes/ui/hud.tscn")
const HudScript := preload("res://scripts/ui/hud.gd")
const Tileset := preload("res://assets/generated/terrain_tileset.tres")

var _inv: Inventory
var _hud: CanvasLayer


func before_test() -> void:
	_inv = Inventory.new()
	_hud = auto_free(HudScene.instantiate())
	_hud.inventory = _inv
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
