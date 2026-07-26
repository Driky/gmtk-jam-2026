## Item stat registry + the resolution chain behind `Items.stats_for`.
## The item half of the DB that docs/systems/progression.md assigns to `Items` —
## recipes land with it on Day 3 (roadmap 3.6). Static and pure, so it resolves
## in tests without the autoload.
##
## An entry here overrides everything, and the key can be ANY item id — tools,
## weapons, or a plain terrain block. That's the point: making one odd block a
## viable off-label tool or weapon is a single .tres, with no schema change to
## materials.gd (which feeds the tileset generator).
## Owning doc: docs/systems/player-combat.md
class_name ItemDefs

## Fallbacks, deliberately NOT in STATS — they're what an id resolves *to*,
## not something you can hold. Blocks sit a little above bare hands so hitting
## with a fistful of stone is worth something.
const BARE_HAND: ItemStats = preload("res://data/items/bare_hand.tres")
const BLOCK_DEFAULT: ItemStats = preload("res://data/items/block_default.tres")

const PICKAXE_T1: ItemStats = preload("res://data/items/pickaxe_t1.tres")
## Placeholder ranged weapon: exists so the pooled projectile system has a live
## consumer before 3.5's turrets depend on it. Crafted bows (4.2) replace it.
const BOLT_CASTER: ItemStats = preload("res://data/items/bolt_caster.tres")
## The first placeable that is a SCENE rather than a tile — light you carry and
## mount on a wall ([terrain.md](../docs/systems/terrain.md) §Lighting).
const TORCH: ItemStats = preload("res://data/items/torch.tres")
## The first two directional placeables and the first two things that tick
## ([automation.md](../docs/systems/automation.md) §The 10 Hz tick). Tier 2 is a
## second .tres with a lower `ticks_per_move`, not a second script.
const CONVEYOR_T1: ItemStats = preload("res://data/items/conveyor_t1.tres")
const INSERTER: ItemStats = preload("res://data/items/inserter.tres")
## The first MULTI-CELL placeable (3×2) and the first machine that produces
## anything — the thing 3.1's W×H footprint and item-preview ghost existed for
## ([automation.md](../docs/systems/automation.md) §Categories).
const MINER: ItemStats = preload("res://data/items/miner.tres")
## The first crafting station. `station_id` on the scene picks which rows of
## `data/recipe_defs.gd` it runs, so 4.2's assembler is a second .tres, not a
## second script.
const FURNACE: ItemStats = preload("res://data/items/furnace.tres")

## The first CRAFTED items. Authored as `ItemStats` with an `icon_color` and
## nothing else: that alone gets them a HUD icon and a row in the F3 give-item
## dropdown for free. No `place_scene`, so they are not placeable, and they are
## absent from `Materials.LOOT_XP`, so smelting is deliberately not an XP channel
## ([progression.md](../docs/systems/progression.md)).
const COPPER_BAR: ItemStats = preload("res://data/items/copper_bar.tres")
const IRON_BAR: ItemStats = preload("res://data/items/iron_bar.tres")

const STATS: Dictionary = {
	"pickaxe_t1": PICKAXE_T1,
	"bolt_caster": BOLT_CASTER,
	"torch": TORCH,
	"conveyor_t1": CONVEYOR_T1,
	"inserter": INSERTER,
	"miner": MINER,
	"furnace": FURNACE,
	"copper_bar": COPPER_BAR,
	"iron_bar": IRON_BAR,
}


## Authored > block default > bare hand. Never returns null: every id is
## usable, so no call site needs a "no item" branch.
static func stats_for(id: String) -> ItemStats:
	if STATS.has(id):
		return STATS[id]
	if Materials.MATERIALS.has(id):
		return BLOCK_DEFAULT
	return BARE_HAND
