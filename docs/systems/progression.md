# Progression & Items

Owner of: XP, levels, the skill tree, recipe tiers, crafting range, item content.

## XP & levels
All sources route through `Progression.grant_xp(source, amount)`: mining (per hardness), kills, looting, first-time crafts. Curve: `xp_to_level(L) = 50 * L^1.6` (tune). Level-up grants flat stats (+HP, +mana, +move speed) and **1 upgrade point**.

## Skill tree (locked: one mixed tree)
Nodes are `SkillNode` Resource files: `id`, `prerequisites[]`, `point_cost`, optional `resource_cost{item: count}`, `max_level`, and effects — either `unlock_recipes[]` or **leveled buffs** (`mining_speed +10%/lvl`, `crafting_yield`, `resource_yield`, `crafting_speed`, `turret_damage`…). Buffs apply as multipliers read via one lookup, `Progression.get_stat(name)` — no scattered special cases. Tree UI ([ui.md](ui.md)): node graph with hand-placed positions stored in the Resource.

**Tree size is the designated scope lever** — see cut lines in [plan.md](../plan.md).

## Recipe tiers
Recipes span tiers across automation / logistics / power / defense / components, unlocked by tree progress. Recipe specifics are decided during implementation as data (Resources), not pre-designed.

## Crafting range
All crafting-cost checks — hand crafting, player-initiated station crafting, and tree `resource_cost` unlocks — draw from player inventory **plus containers within a radius of the player**, via one reused query: `Items.gather_available(player_pos)`.

## Item list (jam targets)
Ores, bars, coal, components (gear, circuit-ish), tools ×3 tiers, 1 melee weapon line, 1 bow + arrows, 1 spell tome, ammo, fuel. Equipment slots (armor/accessories) exist in the UI; stat-granting armor content is optional (cut line in [plan.md](../plan.md)).
