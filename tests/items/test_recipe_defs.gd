## Unit tests for the recipe table (roadmap 3.3). RecipeDefs is static and pure,
## mirroring ItemDefs, so none of this needs an autoload.
##
## The point of the suite is the DANGLING ID: a recipe naming an item that does
## not resolve produces a furnace that silently never crafts, or one that outputs
## an item with no icon — neither of which raises anything.
extends GdUnitTestSuite

func _ids() -> PackedStringArray:
	return DebugMenu.giveable_ids()

# --- Integrity ---------------------------------------------------------------


## Every input and output id must be something the rest of the game can resolve:
## an authored item, or an ordinary material that drops as itself.
func test_every_recipe_id_resolves_to_a_real_item() -> void:
	var known := _ids()
	for recipe: Dictionary in RecipeDefs.RECIPES:
		for id: String in recipe.inputs:
			assert_bool(known.has(id)).override_failure_message(
				"Recipe input '%s' is not a real item id" % id,
			).is_true()
		assert_bool(known.has(recipe.output.id)).override_failure_message(
			"Recipe output '%s' is not a real item id" % recipe.output.id,
		).is_true()


## An output has to resolve an icon, or a crafted bar shows up as an empty slot
## in the hotbar and on the belt.
func test_every_output_resolves_an_icon() -> void:
	for recipe: Dictionary in RecipeDefs.RECIPES:
		assert_object(Hud.icon_for(recipe.output.id)).is_not_null()


## Zero or negative counts and ticks are the shapes that make a station either
## craft nothing or craft infinitely on one tick.
func test_every_recipe_has_positive_counts_and_a_positive_duration() -> void:
	for recipe: Dictionary in RecipeDefs.RECIPES:
		assert_int(recipe.ticks).is_greater(0)
		assert_int(recipe.output.count).is_greater(0)
		assert_bool(recipe.inputs.is_empty()).is_false()
		for id: String in recipe.inputs:
			assert_int(recipe.inputs[id]).is_greater(0)


## Smelting is deliberately NOT an XP channel — bars are absent from LOOT_XP, so
## picking one up pays nothing on the looting channel
## ([progression.md](../../docs/systems/progression.md)).
func test_crafted_outputs_pay_no_loot_xp() -> void:
	for recipe: Dictionary in RecipeDefs.RECIPES:
		assert_float(Materials.loot_xp(recipe.output.id)).is_equal(0.0)

# --- Queries -----------------------------------------------------------------


func test_for_station_returns_only_that_stations_rows() -> void:
	var rows := RecipeDefs.for_station("furnace")
	assert_int(rows.size()).is_greater(0)
	for recipe: Dictionary in rows:
		assert_str(recipe.station).is_equal("furnace")
	assert_array(RecipeDefs.for_station("assembler")).is_empty()


## ❗️The id-routing predicate a crafting station's `accept_item` is built on:
## true for anything smeltable, false for everything else, so an inserter cannot
## jam a furnace full of dirt.
func test_accepts_input_is_true_only_for_a_real_input() -> void:
	assert_bool(RecipeDefs.accepts_input("furnace", "copper")).is_true()
	assert_bool(RecipeDefs.accepts_input("furnace", "iron")).is_true()
	assert_bool(RecipeDefs.accepts_input("furnace", "dirt")).is_false()
	# An OUTPUT is not an input: a furnace must not eat its own bars.
	assert_bool(RecipeDefs.accepts_input("furnace", "copper_bar")).is_false()
	# Nor may a station accept another station's inputs.
	assert_bool(RecipeDefs.accepts_input("assembler", "copper")).is_false()
