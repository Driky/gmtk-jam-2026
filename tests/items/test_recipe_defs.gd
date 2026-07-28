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


## Every row must carry all six keys. A row missing `category` or `unlocked_by`
## (3.6b) does not raise anywhere — it makes the crafting tab drop it out of every
## filter, or show a row 3.7 meant to hide.
func test_every_row_carries_all_six_keys() -> void:
	for recipe: Dictionary in RecipeDefs.RECIPES:
		for key: String in ["station", "inputs", "output", "ticks", "category", "unlocked_by"]:
			assert_bool(recipe.has(key)).override_failure_message(
				"Recipe for '%s' is missing the '%s' key" % [recipe.get("output", { }).get("id", "?"), key],
			).is_true()
		assert_bool(recipe.output.has("id") and recipe.output.has("count")).is_true()


## Zero or negative counts are the shapes that make a station craft nothing.
##
## ⚠️ **`ticks` splits by station.** A station row must be positive or it crafts
## infinitely on one tick; a hand row must be **exactly 0**, because the hand path
## does not tick at all and a non-zero duration there would be a number nothing
## reads pretending to be a cost.
func test_every_recipe_has_positive_counts_and_the_right_duration() -> void:
	for recipe: Dictionary in RecipeDefs.RECIPES:
		if recipe.station == RecipeDefs.HAND:
			assert_int(recipe.ticks).override_failure_message(
				"Hand recipe '%s' must be ticks = 0" % recipe.output.id,
			).is_equal(0)
		else:
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


## ❗️The two stations must not overlap: the press eats what the furnace makes,
## and neither takes the other's input. Routing is by id alone, so a press that
## also accepted ore would swallow it forever — `extract_item` never reaches the
## input slot.
func test_the_ammo_press_and_the_furnace_do_not_overlap() -> void:
	assert_bool(RecipeDefs.accepts_input("ammo_press", "copper_bar")).is_true()
	assert_bool(RecipeDefs.accepts_input("ammo_press", "iron_bar")).is_true()
	assert_bool(RecipeDefs.accepts_input("ammo_press", "copper")).is_false()
	assert_bool(RecipeDefs.accepts_input("furnace", "copper_bar")).is_false()


## Every ammo tier must resolve a `projectile`, because that — not anything on
## the turret — is what a turret fires. Ammo whose stats carry none is a turret
## that eats the stack and shoots nothing, with no error anywhere.
func test_every_ammo_output_carries_a_projectile() -> void:
	for recipe: Dictionary in RecipeDefs.for_station("ammo_press"):
		assert_object(ItemDefs.stats_for(recipe.output.id).projectile).override_failure_message(
			"Ammo '%s' resolves no ProjectileStats" % recipe.output.id,
		).is_not_null()


## The filter row the crafting tab builds, and its order.
func test_categories_are_distinct_and_in_table_order() -> void:
	assert_array(RecipeDefs.categories_for_station(RecipeDefs.HAND)).contains_exactly(
		["utility", "logistics", "automation", "power", "defense"],
	)
	assert_array(RecipeDefs.categories_for_station("furnace")).contains_exactly(["components"])
	assert_array(RecipeDefs.categories_for_station("assembler")).is_empty()

# --- The hand station (3.6b) --------------------------------------------------


## The whole point of 3.6b. An empty hand station is a crafting tab with nothing
## to press, and the F3 dropdown back as the only way to obtain a machine.
func test_the_hand_station_has_rows() -> void:
	assert_int(RecipeDefs.for_station(RecipeDefs.HAND).size()).is_greater(0)


## ❗️Hand rows are invisible to a real `CraftingStation` **only because no scene
## authors that `station_id`** — both queries filter on the string alone, so the
## day one does, a furnace starts eating stone and copper and the hand rows show
## up in a machine's selection loop. Nothing in the code prevents it, so this scans
## the scenes rather than trusting it.
func test_no_scene_authors_the_hand_station_id() -> void:
	for path in _scene_paths("res://scenes"):
		var text := FileAccess.get_file_as_string(path)
		assert_bool(text.contains('station_id = "%s"' % RecipeDefs.HAND)).override_failure_message(
			"%s authors station_id = \"hand\" — a machine would run the player's rows" % path,
		).is_false()


## A hand row whose output is not placeable is a crafted item with nowhere to go:
## RMB does nothing with it and it sits in the bag forever.
func test_every_hand_output_is_placeable() -> void:
	for recipe: Dictionary in RecipeDefs.for_station(RecipeDefs.HAND):
		assert_object(ItemDefs.stats_for(recipe.output.id).place_scene).override_failure_message(
			"Hand recipe output '%s' has no place_scene" % recipe.output.id,
		).is_not_null()


## ❗️**The pin on the tool-tier retune.** Every hand input must be reachable by a
## fresh run: either a material a `tool_tier = 1` pickaxe can break, or the output
## of a recipe whose own inputs are (transitively). Price one row in `ice_stone`
## and the tab silently becomes unusable until 4.2 ships a better pickaxe.
func test_every_hand_input_is_reachable_at_tool_tier_one() -> void:
	var reachable := _reachable_from_tier_one()
	for recipe: Dictionary in RecipeDefs.for_station(RecipeDefs.HAND):
		for id: String in recipe.inputs:
			assert_bool(reachable.has(id)).override_failure_message(
				"Hand recipe '%s' needs '%s', which a tier-1 pickaxe cannot reach" % [
					recipe.output.id,
					id,
				],
			).is_true()


## ❗️**The bootstrap set, and it is load-bearing.** All three of these carry
## `power_demand = 1.0`, so smelting needs a generator — a generator (or the
## furnace, or the miner that feeds it) priced in a BAR is a deadlock with no way
## out but the F3 console. Directly mineable inputs only, no crafting step.
func test_the_bootstrap_machines_cost_only_mined_materials() -> void:
	var mined := _tier_one_material_drops()
	for id: String in ["furnace", "generator", "miner"]:
		var recipe := _hand_recipe_for(id)
		assert_bool(recipe.is_empty()).override_failure_message(
			"No hand recipe for the bootstrap machine '%s'" % id,
		).is_false()
		for input_id: String in recipe.inputs:
			assert_bool(mined.has(input_id)).override_failure_message(
				"Bootstrap machine '%s' needs '%s', which must itself be crafted" % [id, input_id],
			).is_true()

# --- Helpers ------------------------------------------------------------------


func _hand_recipe_for(output_id: String) -> Dictionary:
	for recipe: Dictionary in RecipeDefs.for_station(RecipeDefs.HAND):
		if recipe.output.id == output_id:
			return recipe
	return { }


## Item ids a `tool_tier = 1` pickaxe can put in the bag by mining: anything a
## material with `min_tool_tier <= 1` drops. Deposits count — they drop their ore.
func _tier_one_material_drops() -> Dictionary:
	var out: Dictionary = { }
	for id: String in Materials.ORDER:
		var mat: Dictionary = Materials.MATERIALS[id]
		if mat.min_tool_tier <= 1 and mat.drop_id != "":
			out[mat.drop_id] = true
	return out


## The mined set, closed over every recipe in the table — a bar is reachable
## because a furnace smelts one out of ore you can already dig.
func _reachable_from_tier_one() -> Dictionary:
	var out := _tier_one_material_drops()
	var grew := true
	while grew:
		grew = false
		for recipe: Dictionary in RecipeDefs.RECIPES:
			if out.has(recipe.output.id):
				continue
			var have_all := true
			for id: String in recipe.inputs:
				if not out.has(id):
					have_all = false
					break
			if have_all:
				out[recipe.output.id] = true
				grew = true
	return out


func _scene_paths(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := root.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_scene_paths(path))
		elif entry.ends_with(".tscn"):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
