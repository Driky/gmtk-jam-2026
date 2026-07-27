# "Countdown" — Design Index

Terraria-style digging × factory automation × wave defense. **This file is the entry point**; every locked decision has exactly ONE owning doc (linked below). Other docs may mention a decision in one line + link, never restate it. When a decision changes, update its owning doc (and this log if the one-liner changed) in the same commit.

## Pitch & Core Loop
A repeating literal countdown (the jam theme). **Build phase:** fixed countdown ticks while the player digs, mines, automates, fortifies. At zero, **wave phase:** monsters spawn at the map edges and push toward the player's **Core**; no timer — the wave ends when cleared, then the countdown restarts. Endless; score = waves survived. Core destroyed = game over. Depth = progression: better ores deeper, pulling the player away from the base they must defend.

## Hard Constraints
- 96 hours, solo. Content is data-driven; cut lines are pre-authorized in [plan.md](plan.md).
- Godot 4.x, **GDScript only** (no C# on web), **HTML5 export** to itch.io.
- **Compatibility renderer**, **single-threaded** (no `Thread`, no SharedArrayBuffer setup).
- Keyboard + mouse only. 16×16 px tiles.
- **Display:** 1280×720 base viewport, `canvas_items` stretch (aspect `keep`), nearest-neighbor filtering. Fullscreen up to 1920×1080 via itch.io's embed fullscreen button (no in-game code needed).

## Codebase Map (autoloads = fixed public API)
| Autoload | Owns | Doc |
|---|---|---|
| `Game` | Phase state machine + countdown timer | [plan.md](plan.md) |
| `Terrain` | World grid — ALL tile access | [systems/terrain.md](systems/terrain.md) |
| `Automation` | 10 Hz tick: conveyors, inserters, machines, power | [systems/automation.md](systems/automation.md) |
| `Waves` | Wave composition, spawning, aggro helpers | [systems/enemies.md](systems/enemies.md) |
| `Progression` | XP, levels, stats, skill tree | [systems/progression.md](systems/progression.md) |
| `Items` | Item/recipe DB, crafting-range queries | [systems/progression.md](systems/progression.md) |
| `SaveSystem` | Serialize/deserialize session | [systems/save.md](systems/save.md) |
| `AudioBus` | Music crossfade, pooled SFX | [systems/pipeline.md](systems/pipeline.md) |

## Glossary
- **Core** — pre-placed base heart; monsters' default target; its death ends the run.
- **Buffer zones** — ~50 flat-dirt tiles beyond each side of the 100-tile playable width; player-immutable, monster-diggable spawn areas.
- **Deposit** — rich ore tile blob with a `reserve`, meant for machine mining.
- **Flow field** — shared Dijkstra cost field from the Core that all wave mobs read; dig-weighted.
- **Stair-digging** — mob behavior: chew a diagonal step down instead of taking fall damage.
- **Conveyor** — 1-slot scaffold tube; slots carry item **stacks**. **Stacker** — merges identical items into stacks under saturation. **Inserter** — mandatory machine I/O device.
- **Fortification score** — spawn-cell path cost vs. baseline; skews waves toward crawlers/flyers.
- **Climbable** — ladder/rope/pole deployable with directional climb profile; biped-only for mobs.

## Decision Log
| Decision (one line) | Owner |
|---|---|
| Fixed countdown build phase; untimed wave; endless + boss stretch; full state machine | [plan.md](plan.md) |
| World 100×~1200 playable + buffer zones, 5 stacked biomes, seeded deterministic gen | [systems/world-gen.md](systems/world-gen.md) |
| Hybrid terrain: TileMapLayer (type) + sparse dict (dynamic state), single `Terrain` API | [systems/terrain.md](systems/terrain.md) |
| Terraria self-merge 48-frame autotile, manual autotiling, coordinate-hash variants | [systems/terrain.md](systems/terrain.md) |
| Lighting: per-tile propagated light grid, drawn 1 px/tile with LINEAR + MULTIPLY | [systems/terrain.md](systems/terrain.md) |
| Deposits render as ore autotile + shader FX overlay layer; reserve-based depletion | [systems/terrain.md](systems/terrain.md) |
| Mined natural blocks placeable back, 1:1 self-drops (processed variants = data later) | [systems/terrain.md](systems/terrain.md) |
| Melee hitbox + ONE shared projectile system (ranged, spells, turrets); death drops loot bag | [systems/player-combat.md](systems/player-combat.md) |
| Capability-driven mobs; two dig-weighted flow fields; stair-digging; dig = universal fallback | [systems/enemies.md](systems/enemies.md) |
| Threat-table aggro (Core default); reachability-adaptive wave composition | [systems/enemies.md](systems/enemies.md) |
| Climbables biped-only, directional profiles (pole = down-only) | [systems/enemies.md](systems/enemies.md) |
| One `Deployable` base (W×H, HP, direction-bitmask support, one `pop_to_pickup` drop path) | [systems/automation.md](systems/automation.md) |
| 10 Hz deterministic tick; 1-slot conveyors carrying stacks; inserters mandatory; tick order fixed | [systems/automation.md](systems/automation.md) |
| Tick iteration row-major by cell (not insertion order); catch-up clamp drops backlog | [systems/automation.md](systems/automation.md) |
| Directional deployables: authored `directional` + runtime `facing`, rotated with R at placement | [systems/automation.md](systems/automation.md) |
| Item transfer is two refusing-by-default virtuals (`accept_item`/`extract_item`); RMB hand-feeds one | [systems/automation.md](systems/automation.md) |
| Miner harvests a separate block beside its footprint (deposits are solid); placement gated on ore there | [systems/automation.md](systems/automation.md) |
| Machines take ore via `Terrain.extract_reserve` (1:1, no drops, no XP), not `damage_tile` | [systems/terrain.md](systems/terrain.md) |
| Recipes are one static table (`data/recipe_defs.gd`), map-shaped inputs; stations route by item id | [systems/progression.md](systems/progression.md) |
| Power = radius coverage grids (generator + relay), brownout `supply/demand` scaling | [systems/automation.md](systems/automation.md) |
| Containers own an `Inventory` at their own slot count (chest = 20); `storage()` is the UI seam | [systems/automation.md](systems/automation.md) |
| Respawn anchor = nearest beacon to the death position by group query, else the Core | [systems/player-combat.md](systems/player-combat.md) |
| One mixed skill tree (recipes + leveled buffs) as Resource nodes; crafting range incl. nearby containers | [systems/progression.md](systems/progression.md) |
| Tabbed character screen (Inventory/Crafting/Tree) with direct hotkeys; power overlay hotkey | [systems/ui.md](systems/ui.md) |
| Pause: menu interactive, gameplay actions blocked | [systems/ui.md](systems/ui.md) |
| Save = seed + diff, autosave at build-phase start only (never serialize live monsters) | [systems/save.md](systems/save.md) |
| Placeholder tilesets generated from template by palette remap; TileSet built from `materials.gd` | [systems/pipeline.md](systems/pipeline.md) |
| 1280×720 base viewport, canvas_items stretch, nearest filtering; fullscreen via itch embed button | this file (Hard Constraints) |
| World camera zoom cycles 1×/1.5×/2× (default 1×) on a hotkey; HUD stays native 720p | [systems/ui.md](systems/ui.md) |
