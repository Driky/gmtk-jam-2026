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
## Placeholder ranged weapon: existed so the pooled projectile system had a live
## consumer before 3.5's turrets depended on it. ✅ That job is done — the turret
## is that consumer — so 3.5a dropped it from `STARTING_KIT`, where it was
## costing one of ten hotbar slots. Kept as an authored item (and so a give-item
## row) because it is still the only way to exercise the player's own ranged
## path by hand. Crafted bows (4.2) replace it.
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

## The two emitters (3.4) and the first thing that gives coal a consumer. The
## relay is the SAME script as the generator's base with no supply and a bigger
## radius — a `.tscn` and a `.tres`, not a second class
## ([automation.md](../docs/systems/automation.md) §Power).
const GENERATOR: ItemStats = preload("res://data/items/generator.tres")
const RELAY: ItemStats = preload("res://data/items/relay.tres")

## The first CRAFTED items. Authored as `ItemStats` with an `icon_color` and
## nothing else: that alone gets them a HUD icon and a row in the F3 give-item
## dropdown for free. No `place_scene`, so they are not placeable, and they are
## absent from `Materials.LOOT_XP`, so smelting is deliberately not an XP channel
## ([progression.md](../docs/systems/progression.md)).
const COPPER_BAR: ItemStats = preload("res://data/items/copper_bar.tres")
const IRON_BAR: ItemStats = preload("res://data/items/iron_bar.tres")

## The second crafting station, and proof the `station_id` bargain holds: the
## press is `crafting_station.gd` with a different string and two rows in
## `data/recipe_defs.gd`. Pulled forward from 4.2 at 3.5a because a turret needs
## something to eat ([automation.md](../docs/systems/automation.md) §Categories).
const AMMO_PRESS: ItemStats = preload("res://data/items/ammo_press.tres")

## Turret ammo. Crafted items like the bars, with one addition: a `projectile`,
## which is what the TURRET fires — read off the ammo rather than authored on
## the turret, so an ammo tier is a `.tres` pair and there is no second table.
## `use_kind` stays SWING: ammo is not a weapon in the player's hand.
const COPPER_AMMO: ItemStats = preload("res://data/items/copper_ammo.tres")
const IRON_AMMO: ItemStats = preload("res://data/items/iron_ammo.tres")

## The first thing the player builds that fights, and the first deployable whose
## support is NOT all four: a standard turret wants a horizontal base under it
## ([automation.md](../docs/systems/automation.md) §Deployable base).
const TURRET: ItemStats = preload("res://data/items/turret.tres")
## The cheapest defense there is: no power, no ammo, no targeting. Same
## `support_dirs = 4` as the turret — it is a floor tile that bites.
const SPIKE_TRAP: ItemStats = preload("res://data/items/spike_trap.tres")

## The two Utility deployables (3.5c) — the only category that neither ticks nor
## fights ([automation.md](../docs/systems/automation.md) §Categories). The chest
## is the first N-slot container and what 3.6's container view binds to; the
## beacon overrides where you respawn.
const CHEST: ItemStats = preload("res://data/items/chest.tres")
const BEACON: ItemStats = preload("res://data/items/beacon.tres")

## The third Utility deployable and the first CLIMBABLE (3.5b): the one thing the
## player builds that changes how the world is traversed — by the player and, by
## design, by any biped in a wave ([enemies.md](../docs/systems/enemies.md)
## §Climbables). 4.1's rope and pole are a `.tscn` and a `.tres` on the same
## `is_climbable` export, not a second script.
const LADDER: ItemStats = preload("res://data/items/ladder.tres")

## The first WEARABLE items (3.6a): one authored piece per equipment slot, so
## every `Equipment.slot_accepts` branch has live data behind it rather than a
## synthetic `ItemStats` built inside a test. Seven rather than eight because
## `RING` is one authored value that fits both ring slots
## ([ui.md](../docs/systems/ui.md) §Character screen).
##
## Authored like the bars — `icon_color`, modest melee/mining, no `place_scene` —
## plus an `equip_slot` and an `armor` value. ⚠️ The seven rows sum to 15 but a
## fully-equipped player carries **16**, because `copper_ring` fills both ring
## slots; 16 is the figure the mitigation curve is read against
## ([player-combat.md](../docs/systems/player-combat.md) §Taking damage).
##
## ⚠️ Deliberately absent from `Materials.LOOT_XP`, like the bars and the ammo:
## crafted and equipment items are not an XP channel
## ([progression.md](../docs/systems/progression.md) §XP).
const COPPER_HELMET: ItemStats = preload("res://data/items/copper_helmet.tres")
const COPPER_CHESTPLATE: ItemStats = preload("res://data/items/copper_chestplate.tres")
const COPPER_GREAVES: ItemStats = preload("res://data/items/copper_greaves.tres")
const COPPER_BOOTS: ItemStats = preload("res://data/items/copper_boots.tres")
const COPPER_CLOAK: ItemStats = preload("res://data/items/copper_cloak.tres")
const COPPER_RING: ItemStats = preload("res://data/items/copper_ring.tres")
const COPPER_AMULET: ItemStats = preload("res://data/items/copper_amulet.tres")

const STATS: Dictionary = {
	"pickaxe_t1": PICKAXE_T1,
	"bolt_caster": BOLT_CASTER,
	"torch": TORCH,
	"conveyor_t1": CONVEYOR_T1,
	"inserter": INSERTER,
	"miner": MINER,
	"furnace": FURNACE,
	"generator": GENERATOR,
	"relay": RELAY,
	"copper_bar": COPPER_BAR,
	"iron_bar": IRON_BAR,
	"ammo_press": AMMO_PRESS,
	"copper_ammo": COPPER_AMMO,
	"iron_ammo": IRON_AMMO,
	"turret": TURRET,
	"spike_trap": SPIKE_TRAP,
	"chest": CHEST,
	"beacon": BEACON,
	"ladder": LADDER,
	# Each earns an F3 give-item row for free — `giveable_ids` iterates this table.
	"copper_helmet": COPPER_HELMET,
	"copper_chestplate": COPPER_CHESTPLATE,
	"copper_greaves": COPPER_GREAVES,
	"copper_boots": COPPER_BOOTS,
	"copper_cloak": COPPER_CLOAK,
	"copper_ring": COPPER_RING,
	"copper_amulet": COPPER_AMULET,
}


## Authored > block default > bare hand. Never returns null: every id is
## usable, so no call site needs a "no item" branch.
static func stats_for(id: String) -> ItemStats:
	if STATS.has(id):
		return STATS[id]
	if Materials.MATERIALS.has(id):
		return BLOCK_DEFAULT
	return BARE_HAND
