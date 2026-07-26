## Unit tests for the item-stat resolution chain and the buff seam (roadmap
## 2.5). ItemDefs is static and pure, so none of this needs the Items autoload.
extends GdUnitTestSuite

const ItemStatsScript := preload("res://scripts/items/item_stats.gd")


## Stands in for Progression: every stat reads as `value`, so a test can prove
## a multiplier is applied without depending on the real stat table.
class StubProgression:
	extends Node
	var value := 1.0


	func get_stat(_stat_name: String) -> float:
		return value

# --- Resolution chain --------------------------------------------------------


func test_authored_id_wins() -> void:
	assert_object(ItemDefs.stats_for("pickaxe_t1")).is_same(ItemDefs.PICKAXE_T1)


func test_material_id_falls_back_to_block_default() -> void:
	assert_object(ItemDefs.stats_for("dirt")).is_same(ItemDefs.BLOCK_DEFAULT)


func test_empty_id_falls_back_to_bare_hand() -> void:
	assert_object(ItemDefs.stats_for("")).is_same(ItemDefs.BARE_HAND)


func test_unknown_id_falls_back_to_bare_hand() -> void:
	assert_object(ItemDefs.stats_for("not_an_item")).is_same(ItemDefs.BARE_HAND)


## The chain is only meaningful if the tiers actually differ — a regression that
## flattened them would otherwise pass every test above.
func test_tiers_are_ordered_pickaxe_over_block_over_hand() -> void:
	assert_float(ItemDefs.PICKAXE_T1.mining_power).is_greater(ItemDefs.BLOCK_DEFAULT.mining_power)
	assert_float(ItemDefs.BLOCK_DEFAULT.mining_power).is_greater(ItemDefs.BARE_HAND.mining_power)


## Preserves the pre-2.5 dig feel: the starter tool matches the old flat
## Player.tool_power of 4.0 hardness/s.
func test_starter_pickaxe_matches_the_legacy_tool_power() -> void:
	assert_float(ItemDefs.PICKAXE_T1.mining_power).is_equal(4.0)

# --- Buff seam ---------------------------------------------------------------


func test_multipliers_scale_every_stat() -> void:
	var progression: StubProgression = auto_free(StubProgression.new())
	progression.value = 2.0
	var stats: ItemStats = ItemStatsScript.new()
	stats.mining_power = 4.0
	stats.melee_damage = 5.0
	stats.knockback = 100.0
	assert_float(stats.effective_mining_power(progression)).is_equal(8.0)
	assert_float(stats.effective_melee_damage(progression)).is_equal(10.0)
	assert_float(stats.effective_knockback(progression)).is_equal(200.0)


## Faster swings are a higher stat, so the cooldown divides rather than scales.
func test_swing_speed_shortens_the_cooldown() -> void:
	var progression: StubProgression = auto_free(StubProgression.new())
	progression.value = 2.0
	var stats: ItemStats = ItemStatsScript.new()
	stats.use_cooldown = 0.4
	assert_float(stats.effective_cooldown(progression)).is_equal(0.2)


## A zero/negative multiplier from a pathological debuff must not divide by
## zero and freeze the player mid-swing.
func test_cooldown_clamps_a_degenerate_multiplier() -> void:
	var progression: StubProgression = auto_free(StubProgression.new())
	progression.value = 0.0
	var stats: ItemStats = ItemStatsScript.new()
	stats.use_cooldown = 0.4
	assert_float(stats.effective_cooldown(progression)).is_less(1000.0)

# --- Placement dispatch (2.7) ------------------------------------------------


## The seam Day 3's deployables land on: an item names a scene, and the player
## places that instead of writing a tile. No branch in the player per item.
func test_torch_resolves_to_a_place_scene() -> void:
	var stats := ItemDefs.stats_for("torch")
	assert_object(stats.place_scene).is_not_null()
	assert_object(stats).is_same(ItemDefs.TORCH)


## A plain block must keep the tile-writing path — a non-null place_scene on
## BLOCK_DEFAULT would turn every mined block into a scene instance.
func test_a_plain_block_has_no_place_scene() -> void:
	assert_object(ItemDefs.stats_for("dirt").place_scene).is_null()
	assert_object(ItemDefs.BARE_HAND.place_scene).is_null()


## The HUD swatch path: "torch" is not a material, so icon_for falls through to
## the authored icon_color rather than looking for tile art that does not exist.
func test_torch_is_not_a_material_id() -> void:
	assert_bool(Materials.MATERIALS.has("torch")).is_false()
