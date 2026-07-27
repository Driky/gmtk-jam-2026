## Recipe registry — the RECIPE half of the DB
## [progression.md](../docs/systems/progression.md) assigns to `Items`, landing
## at 3.3 exactly as 2.5 pulled the *item* half forward into `item_defs.gd`.
## Static and pure, mirroring that file, so it resolves in tests without the
## autoload and a crafting station can read it from `on_tick`.
##
## 3.6's crafting tab is a UI over THIS table, not a second one — the roadmap's
## "item/recipe DB" bullet is reconciled down to that UI.
## Owning doc: docs/systems/progression.md
class_name RecipeDefs

## Per recipe: `station` (which machine can run it — `station_id` on the
## `CraftingStation`), `inputs` as `{item_id: count}`, `output` as one
## `{id, count}` stack, and `ticks` at 10 Hz.
##
## ❗️**`inputs` is a MAP from day one**, even though a furnace has one input slot
## and can therefore only ever match a single-input row. Widening the *key* of a
## shipped table later is a rewrite of every consumer; carrying an extra key now
## costs nothing, and 4.2's assembler and ammo press need it.
##
## Numbers are Day-3 stubs; the balance pass is Day 4.
##
## ❗️The ammo press is the SAME `CraftingStation` script with a different
## `station_id` — the bargain this table exists to make, and the reason a second
## machine costs two rows here rather than a second class. It landed at 3.5a
## rather than 4.2 because a turret needs something to eat.
##
## ⚠️ One ammo tier per ORE tier, but only copper and iron ship: they are the two
## ores with a bar recipe today. `gold` and `magmatite` get theirs when their
## bars land (4.2) — two more rows in this table, no new shape.
const RECIPES: Array[Dictionary] = [
	{ station = "furnace", inputs = { copper = 1 }, output = { id = "copper_bar", count = 1 }, ticks = 20 },
	{ station = "furnace", inputs = { iron = 1 }, output = { id = "iron_bar", count = 1 }, ticks = 30 },
	{ station = "ammo_press", inputs = { copper_bar = 1 }, output = { id = "copper_ammo", count = 4 }, ticks = 20 },
	{ station = "ammo_press", inputs = { iron_bar = 1 }, output = { id = "iron_ammo", count = 4 }, ticks = 30 },
]


## Every recipe a station can run, in table order — which is also the order a
## station selects in, so "first match wins" is a property of this file rather
## than of whoever iterates it.
static func for_station(station: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for recipe: Dictionary in RECIPES:
		if recipe.station == station:
			out.append(recipe)
	return out


## Is `id` an input to ANY recipe this station can run?
##
## ❗️Load-bearing, not a convenience: `accept_item` has no port argument, so a
## station routes incoming items **by id**. Without this an inserter would jam a
## furnace full of dirt permanently, and no amount of unjamming would get it out
## — `extract_item` only ever reaches the output slot.
static func accepts_input(station: String, id: String) -> bool:
	for recipe: Dictionary in RECIPES:
		if recipe.station == station and recipe.inputs.has(id):
			return true
	return false
