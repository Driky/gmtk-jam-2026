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
## `{id, count}` stack, `ticks` at 10 Hz, `category` (what the crafting tab's
## filter row groups on) and `unlocked_by` (3.7's skill node id).
##
## ❗️**`category` and `unlocked_by` are on EVERY row from 3.6b, filled or not.**
## `unlocked_by = ""` means always available, so 3.7 fills the column in as data
## with no consumer change — the same argument `inputs` makes two paragraphs down.
##
## ⚠️ **Category names are [automation.md](../docs/systems/automation.md)
## §Categories' own** — `automation` / `logistics` / `power` / `defense` /
## `utility` — plus `components` for what a station makes. One taxonomy for both
## halves of the game rather than a crafting one beside a deployable one.
##
## ❗️**There is no name field.** A recipe is named by `Hud.item_name` of its
## output, which is already the one place that question is answered; a second name
## is a second thing for `ItemStats.display_name` to drift from.
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
##
## ❗️**`station = "hand"` is what makes the game obtainable (3.6b).** Until these
## rows existed every deployable reached the player only through the F3 give-item
## dropdown or the factory rig, and an exported build has no console. They cost no
## new mechanism: the two queries below already filter on that string, and `ticks`
## is ignored on the hand path — which is why every hand row is `ticks = 0`.
##
## ❗️**Hand rows are invisible to a real `CraftingStation` only because no scene
## authors `station_id = "hand"`.** Both queries filter on that string alone, so a
## furnace would eat their inputs the day one does. Pinned by a test rather than
## left to luck.
##
## ❗️**The bootstrap set is load-bearing.** `furnace`, `generator` and `miner` are
## priced in `stone` and `copper` ONLY — never bars — because all three carry
## `power_demand = 1.0`: smelting needs a generator, so a generator costing a bar
## would be a deadlock with no way out but the console.
## ❗️**`unlocked_by` is filled in at 3.7, and it decides what a NEW RUN can
## build.** Three hand rows stay free forever — `pickaxe_t1`, `ladder`, `torch`:
## a tool, a way back up, and light. Everything else is behind a skill node, so
## obtainability moved off "there is a hand row for it" and onto the tree's roots
## ([progression.md](../docs/systems/progression.md) §Recipe tiers).
##
## ⚠️ **A STATION row carries no gate, deliberately.** It is gated by owning the
## station: you cannot smelt without a furnace, and `mechanization` is what
## unlocks one. A second gate here would be the same fact stored twice, free to
## drift — exactly what `unlocked_by` beating `unlock_recipes[]` was about.
##
## ❗️**The `pickaxe_t1` row is NEW at 3.7.** `STARTING_KIT` was the only source of
## a pickaxe; with the rest of the table gated, "what can I make at level 1" needs
## a better answer than light. ⚠️ It is also the first hand output with **no
## `place_scene`** — a tool you hold, not a thing you put down — which splits
## 3.6b's "every hand output is placeable" assertion in two.
const RECIPES: Array[Dictionary] = [
	{ station = "furnace", inputs = { copper = 1 }, output = { id = "copper_bar", count = 1 }, ticks = 20, category = "components", unlocked_by = "" },
	{ station = "furnace", inputs = { iron = 1 }, output = { id = "iron_bar", count = 1 }, ticks = 30, category = "components", unlocked_by = "" },
	{ station = "ammo_press", inputs = { copper_bar = 1 }, output = { id = "copper_ammo", count = 4 }, ticks = 20, category = "components", unlocked_by = "" },
	{ station = "ammo_press", inputs = { iron_bar = 1 }, output = { id = "iron_ammo", count = 4 }, ticks = 30, category = "components", unlocked_by = "" },
	{ station = "hand", inputs = { stone = 5, coal = 2 }, output = { id = "pickaxe_t1", count = 1 }, ticks = 0, category = "utility", unlocked_by = "" },
	{ station = "hand", inputs = { coal = 1, stone = 1 }, output = { id = "torch", count = 4 }, ticks = 0, category = "utility", unlocked_by = "" },
	{ station = "hand", inputs = { stone = 4 }, output = { id = "ladder", count = 3 }, ticks = 0, category = "utility", unlocked_by = "" },
	{ station = "hand", inputs = { stone = 12 }, output = { id = "chest", count = 1 }, ticks = 0, category = "utility", unlocked_by = "storage" },
	{ station = "hand", inputs = { copper = 6, coal = 4 }, output = { id = "beacon", count = 1 }, ticks = 0, category = "utility", unlocked_by = "deep_delving" },
	{ station = "hand", inputs = { stone = 2, copper = 1 }, output = { id = "conveyor_t1", count = 2 }, ticks = 0, category = "logistics", unlocked_by = "logistics_i" },
	{ station = "hand", inputs = { stone = 2, copper = 2 }, output = { id = "inserter", count = 1 }, ticks = 0, category = "logistics", unlocked_by = "logistics_i" },
	{ station = "hand", inputs = { stone = 10, copper = 5 }, output = { id = "miner", count = 1 }, ticks = 0, category = "automation", unlocked_by = "mechanization" },
	{ station = "hand", inputs = { stone = 12 }, output = { id = "furnace", count = 1 }, ticks = 0, category = "automation", unlocked_by = "mechanization" },
	{ station = "hand", inputs = { stone = 10, copper_bar = 4 }, output = { id = "ammo_press", count = 1 }, ticks = 0, category = "automation", unlocked_by = "emplacements" },
	{ station = "hand", inputs = { stone = 8, copper = 4 }, output = { id = "generator", count = 1 }, ticks = 0, category = "power", unlocked_by = "power_grid" },
	{ station = "hand", inputs = { stone = 4, copper = 2 }, output = { id = "relay", count = 1 }, ticks = 0, category = "power", unlocked_by = "power_grid" },
	{ station = "hand", inputs = { stone = 4, iron = 2 }, output = { id = "spike_trap", count = 1 }, ticks = 0, category = "defense", unlocked_by = "traps" },
	{ station = "hand", inputs = { copper_bar = 4, iron_bar = 4 }, output = { id = "turret", count = 1 }, ticks = 0, category = "defense", unlocked_by = "emplacements" },
]

## The player's own station id, and the one place that string is spelled. No
## scene may author it as a `station_id` — see the table's header.
const HAND := "hand"


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


## Every recipe a skill node unlocks, **in table order** — the third query beside
## `for_station` and `categories_for_station`, and for the same reason: the order
## a node's unlocks are listed in is a property of this file, not of the tooltip
## that prints them.
##
## ❗️**This is why `SkillNode` carries no `unlock_recipes[]`.** A node unlocking a
## recipe and a recipe naming its gate are one edge; storing it on both sides is
## one fact with two writable copies, free to drift the first time a recipe moves
## branch ([progression.md](../docs/systems/progression.md) §Skill tree).
static func unlocked_by(node_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if node_id == "":
		return out
	for recipe: Dictionary in RECIPES:
		if recipe.unlocked_by == node_id:
			out.append(recipe)
	return out


## The distinct categories a station's rows use, **in table order** — what the
## crafting tab builds its filter row from. Here rather than in the UI so the
## order is a property of this file, exactly as `for_station`'s is.
static func categories_for_station(station: String) -> PackedStringArray:
	var out := PackedStringArray()
	for recipe: Dictionary in RECIPES:
		if recipe.station == station and not out.has(recipe.category):
			out.append(recipe.category)
	return out
