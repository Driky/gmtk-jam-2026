# Progression & Items

Owner of: XP, levels, the skill tree, recipe tiers, crafting range, item content.

## XP & levels
All sources route through `Progression.grant_xp(source, amount)`. The caller decides the amount, so each source stays independently tunable; `source` is only tallied (`xp_by_source`), never branched on — that tally is what the Day-4 balance pass reads to answer "where is XP actually coming from".

| Source | Amount |
| --- | --- |
| Mining | **Flat per block broken** (`MINING_XP_PER_BLOCK`), *not* per hardness — depth is rewarded through what a block drops, not through how long it took to break, so a slow tool can't out-earn a fast one |
| Looting | Per-material `loot_xp` (data/materials.gd) when a dropped item is **collected**: ore beats non-ore, rarer ore beats common ore. This is the channel that makes digging deeper pay |
| Kills | `EnemyStats.xp` |
| First-time crafts | Reserved (3.6) |

**Automation is worth zero on both channels (3.3).** ❗️Machine-extracted ore pays nothing: `Terrain.extract_reserve` deliberately emits no `drops_spawned` (the ore goes into the machine, never onto the floor), so it misses the looting channel by construction, and the mining channel is already gated on `source == Source.PLAYER`. Both halves are code that existed before the miner did — the anti-farm rule falls out rather than being enforced. Without it a miner is an XP fountain you walk away from, which is the one thing a factory must never be. **Smelting pays nothing either**: bars are absent from `loot_xp`, so a furnace line is not a second channel. First-time crafts (3.6) remain the only crafting XP planned.

**Player-placed blocks are worth zero on both channels** — no mining XP when re-broken, and their drop grants no loot XP. Without it, walling and re-mining the same block is the cheapest XP in the game. Enforced by a `player_placed` flag on the tile ([terrain.md](terrain.md)) carried into the drop. Recovering your own loot bag likewise grants nothing: bags hand items straight to the inventory and never spawn pickups, so they miss the loot channel by construction ([player-combat.md](player-combat.md)).

Curve: `xp_to_level(L) = 50 * L^1.6` (tune — expect it to be too generous first playtest). Level-up grants flat stats (+HP, +mana, +move speed) and **1 upgrade point**; the player's *current* HP/mana rise by the same delta as the maximum, so a level-up is a reward rather than a mid-wave heal button.

## Skill tree (locked: one mixed tree)
Nodes are `SkillNode` Resource files: `id`, `prerequisites[]`, `point_cost`, optional `resource_cost{item: count}`, `max_level`, and effects — either `unlock_recipes[]` or **leveled buffs** (`mining_speed +10%/lvl`, `crafting_yield`, `resource_yield`, `crafting_speed`, `turret_damage`…). Buffs apply as multipliers read via one lookup, `Progression.get_stat(name)` — no scattered special cases. That lookup is one formula serving both kinds of stat it has to carry (absolute values like `max_hp`, multipliers like `mining_speed`): `(base + per_level_flat * (level - 1)) * multiplier`. Base defaults to 1.0 and per-level to 0.0, so an unknown stat reads a neutral 1.0 — which is what lets `ItemStats.effective_*` ask for buffs that don't exist yet. Tree UI ([ui.md](ui.md)): node graph with hand-placed positions stored in the Resource.

**Tree size is the designated scope lever** — see cut lines in [plan.md](../plan.md).

## Recipe tiers
Recipes span tiers across automation / logistics / power / defense / components, unlocked by tree progress. Recipe specifics are decided during implementation as data, not pre-designed.

**The table landed at 3.3 as `data/recipe_defs.gd`** — static and pure, mirroring `data/item_defs.gd` exactly, which is where 2.5 put the *item* half of this DB. Per row: `station` (matched against a `CraftingStation`'s authored `station_id`), `inputs` as `{item_id: count}`, one `output` `{id, count}` stack, and `ticks` at 10 Hz. Two queries: `for_station(station)` (table order, which is also selection order, so "first match wins" is a property of the file rather than of whoever iterates it) and `accepts_input(station, id)` — the id-routing predicate a station's `accept_item` is built on ([automation.md](automation.md) §Categories).
- ❗️**`inputs` is a map from day one**, even though a one-input-slot furnace can only ever match a single-input row. Widening the *key* of a shipped table later is a rewrite of every consumer; carrying the extra key now costs nothing, and 4.2's assembler needs it.
- **3.6 is the crafting UI over this table, not a second one.** The roadmap's "item/recipe DB" bullet reconciles down to that UI.
- Crafted outputs are authored `ItemStats` `.tres` with an `icon_color` and no `place_scene`, so they resolve a HUD icon and a give-item row for free and are not placeable. They are **absent from `LOOT_XP`** — see §XP.

## Crafting range
All crafting-cost checks — hand crafting, player-initiated station crafting, and tree `resource_cost` unlocks — draw from player inventory **plus containers within a radius of the player**, via one reused query: `Items.gather_available(player_pos)`.

## Item list (jam targets)
Ores, bars, coal, components (gear, circuit-ish), tools ×3 tiers, 1 melee weapon line, 1 bow + arrows, 1 spell tome, ammo, fuel. Equipment slots (armor/accessories) exist in the UI; stat-granting armor content is optional (cut line in [plan.md](../plan.md)).
