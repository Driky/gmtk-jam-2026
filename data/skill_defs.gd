## Skill-tree registry — the third table beside `data/item_defs.gd` and
## `data/recipe_defs.gd`, and built exactly like them: `const` preloads, one
## dictionary, two queries. Static and pure, so it resolves in a test without the
## `Progression` autoload and without a scene.
##
## ❗️**A node carries no recipe list.** A node unlocking a recipe and a recipe
## naming its gate are one edge; `unlocked_by` on the recipe row is where it
## lives, so "what does this node unlock" is `RecipeDefs.unlocked_by(node_id)` —
## a query, never a second authored list to drift from the first (see
## `scripts/progression/skill_node.gd`).
##
## ❗️**No `place_scene`, no scene reference of any kind.** This registry closes
## none of the resource cycles 3.6a paid for, which is why the character screen
## can preload it directly.
##
## Owning doc: docs/systems/progression.md
class_name SkillDefs

## The canvas the authored `position`s are laid out in, in pixels, and the size
## every node button is drawn at. ❗️Here rather than in the UI for the same
## reason `for_station`'s ORDER is here: a position that falls outside the canvas
## renders invisible rather than broken, so the rect the test checks against and
## the rect the tab scrolls have to be one number.
const CANVAS_SIZE := Vector2(980.0, 340.0)
const NODE_SIZE := Vector2(176.0, 46.0)

# --- Industry -----------------------------------------------------------------
#
# The branch that carries the factory, and with it the Day-3 exit criterion.
#
# ❗️**`power_grid` sits BETWEEN `logistics_i` and `mechanization`**, which is the
# tree restating a rule `recipe_defs.gd` already keeps: the miner and the furnace
# both carry `power_demand = 1.0`, so unlocking them first hands the player two
# machines that cannot run and nothing to run them off. Same argument that prices
# the generator in mined materials only.
const STORAGE: SkillNode = preload("res://data/skills/storage.tres")
const LOGISTICS_I: SkillNode = preload("res://data/skills/logistics_i.tres")
const POWER_GRID: SkillNode = preload("res://data/skills/power_grid.tres")
const MECHANIZATION: SkillNode = preload("res://data/skills/mechanization.tres")

## ❗️**Both yield leaves sit behind `mechanization`, and that is not flavour.**
## `resource_yield` and `crafting_yield` are read by the MINER and the CRAFTING
## STATION (automation.md §Deployable base), never by the player's own dig or a
## hand craft — so a `rich_veins` bought before you own a miner is a point spent
## on nothing. The tree's shape is what makes that trap purchase impossible.
const RICH_VEINS: SkillNode = preload("res://data/skills/rich_veins.tres")
const EFFICIENT_ASSEMBLY: SkillNode = preload("res://data/skills/efficient_assembly.tres")
const MASS_PRODUCTION: SkillNode = preload("res://data/skills/mass_production.tres")

# --- Defense ------------------------------------------------------------------
#
# Opens on the spike trap: the cheapest thing in the game that fights — no power,
# no ammo, no targeting — so the branch's first point is affordable at level 2.
const TRAPS: SkillNode = preload("res://data/skills/traps.tres")
const EMPLACEMENTS: SkillNode = preload("res://data/skills/emplacements.tres")
const ARMAMENTS: SkillNode = preload("res://data/skills/armaments.tres")

# --- Excavation ---------------------------------------------------------------
#
# ⚠️ **The respawn beacon is here rather than on Defense.** It is what you plant
# when you are mining far from the Core, and the thing it protects is *you*, not
# the base.
const PROSPECTING: SkillNode = preload("res://data/skills/prospecting.tres")
const DEEP_DELVING: SkillNode = preload("res://data/skills/deep_delving.tres")
## ⚠️ The one node that raises a MAXIMUM rather than a rate, and the reason
## `Progression.node_unlocked` exists: the player has to absorb the gain through
## the same path a level-up does, or its level-up cache goes stale and the next
## level grants this node's increment a second time
## ([player-combat.md](../docs/systems/player-combat.md) §Death & respawn).
const CONDITIONING: SkillNode = preload("res://data/skills/conditioning.tres")

## Authored order, which is also draw order — a property of this file, exactly as
## `RecipeDefs.for_station`'s selection order is a property of that one.
##
## ⚠️ Each key is ALSO stored as `id` on the Resource it points at. A `.tres`
## whose `id` disagrees with its key resolves through one path and not the other,
## so a test pins the two together.
const NODES: Dictionary = {
	"storage": STORAGE,
	"logistics_i": LOGISTICS_I,
	"power_grid": POWER_GRID,
	"mechanization": MECHANIZATION,
	"rich_veins": RICH_VEINS,
	"efficient_assembly": EFFICIENT_ASSEMBLY,
	"mass_production": MASS_PRODUCTION,
	"traps": TRAPS,
	"emplacements": EMPLACEMENTS,
	"armaments": ARMAMENTS,
	"prospecting": PROSPECTING,
	"deep_delving": DEEP_DELVING,
	"conditioning": CONDITIONING,
}


## The node, or `null` for an id that names nothing. ⚠️ Unlike `ItemDefs.stats_for`
## there is no fallback and there must not be one: a mistyped node id is a bug in
## the table or in a recipe's `unlocked_by`, not something to paper over with a
## neutral node that would silently grant nothing forever.
static func node_for(id: String) -> SkillNode:
	return NODES.get(id, null)


## Every node in authored order.
static func all() -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for id: String in NODES:
		out.append(NODES[id])
	return out
