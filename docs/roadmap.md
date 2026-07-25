# Roadmap — Work Items per Day

Execution checklist derived from the day plan in [plan.md](plan.md). **This file owns no decisions** — every item links to its owning doc; when a decision changes, update the owning doc, then reconcile this checklist. Sequencing rule (from plan.md): implement in day order; within a day, systems before content.

Legend: 🔴 = on a "never cut" path · ✂️n = covered by cut line *n* in [plan.md](plan.md).

---

## Day 1 — Dig loop (playable in-browser by bedtime)

### 1.1 Project setup
- [x] Godot 4.x project: Compatibility renderer, 16×16 tile settings, viewport/stretch config for web.
- [x] Input map: move/jump, mine, place, hotbar 1–0, `I`/`C`/`K`, power-overlay hotkey, debug-overlay hotkey, pause.
- [x] Autoload skeletons registered in fixed order: `Game`, `Terrain`, `Automation`, `Waves`, `Progression`, `Items`, `SaveSystem`, `AudioBus` ([tech-design.md](tech-design.md) codebase map).
- [x] `CREDITS.md` created (pipeline rule: from hour one — [pipeline.md](systems/pipeline.md)).

### 1.2 Web export — hour 2, not hour 90 🔴
- [x] HTML5 export preset (single-threaded, no SharedArrayBuffer requirement); run in an actual browser.
- [x] Private itch.io project created; first build uploaded. Repeat daily (risk mitigation in [plan.md](plan.md)).

### 1.3 Tileset pipeline ([pipeline.md](systems/pipeline.md))
- [x] Commit `assets/templates/terrain_template_16.png` (48-frame shape master).
- [x] `data/materials.gd` — material config, single source of truth.
- [x] `tools/generate_tilesets.gd`: palette-remap PNG generation + TileSet builder (physics, occlusion, custom data layers).
- [x] `scripts/terrain/tile_layout.gd`: derive `LAYOUT` from the template once; pin `variant_hash` ([terrain.md](systems/terrain.md) — never change after first save).

### 1.4 Terrain system ([terrain.md](systems/terrain.md))
- [ ] `Terrain` autoload: TileMapLayer + sparse state dict, full API (`get_tile_data`, `damage_tile`, `set_tile`, `is_solid`, `place_entity`, `get_entity`).
- [ ] `damage_tile` pipeline: damage accumulation + abandon-timeout, drops, deposit `reserve` depletion, XP hook (wired Day 2), `source`-based buffer-zone rejection 🔴.
- [ ] Manual autotiling: 4-bit mask recompute on change, deterministic variants.
- [ ] Debug assert: entity dict ↔ TileMap agreement.

### 1.5 World generation ([world-gen.md](systems/world-gen.md))
- [ ] Seeded pipeline: height-noise surface → 5 biome bands → cave carving → per-biome ore scatter → deposit blobs with `reserve` → bedrock border.
- [ ] Buffer zones: flat dirt, no caves/resources, visual boundary treatment 🔴.
- [ ] Amortized generation (N rows/frame) behind a loading bar (`GENERATING` state).

### 1.6 Player, mining, inventory ([player-combat.md](systems/player-combat.md))
- [ ] Platformer controller with coyote time + jump buffer; stats stubbed until `Progression` exists.
- [ ] Hold-to-mine within reach radius via `Terrain.damage_tile`; tool-tier gating.
- [ ] Item drops as pickups; inventory data model + hotbar; placing mined natural blocks back.
- [ ] Camera follow (clamped to playable width + depth).

### 1.7 Basic HUD ([ui.md](systems/ui.md))
- [ ] HP/mana bars (static values ok), hotbar display, depth readout.

**Exit criteria:** in a browser, dig down through ≥2 biomes, collect drops, place blocks, buffers reject player actions.

---

## Day 2 — Fight loop

### 2.1 Core & state machine ([plan.md](plan.md))
- [ ] Core scene: pre-placed on the flat spawn area, big HP pool, game-over on death.
- [ ] `Game` state machine: `BOOT → MENU → GENERATING → BUILD_PHASE ⇄ WAVE_PHASE → GAME_OVER`.
- [ ] Countdown presentation 🔴: prominent HUD timer, last-10 s audio sting + screen pulse, wave-n announce.
- [ ] Wave-end settle: loot/XP → grace beat → countdown reset. Game-over stats screen (waves, depth, blocks mined).

### 2.2 Flow-field pathfinding ([enemies.md](systems/enemies.md)) 🔴
- [ ] Ground field: Dijkstra from Core, gravity-aware directional costs, dig-weighted solids, deployable HP costs.
- [ ] Region restriction (top ~150 rows), recompute on terrain/deployable change debounced ≤ 0.5 s.
- [ ] Cache untouched-terrain baseline costs at world gen (needed Day 4 for fortification score).

### 2.3 First enemy — walker, fully working ([enemies.md](systems/enemies.md))
- [ ] Enemy base (`CharacterBody2D`) + `EnemyStats` Resource with locomotion capabilities.
- [ ] Locomotion resolution: walk / jump / chew fallback via `Terrain.damage_tile`.
- [ ] Stair-digging on unsafe drops 🔴; fall damage beyond `max_safe_fall`.
- [ ] Threat-table aggro: damage adds threat, decay, Core as default target.

### 2.4 Wave manager v1 ([enemies.md](systems/enemies.md))
- [ ] Budget `B(n)`, trickle spawning from both buffer zones, ~25-alive cap, "Wave n — X remaining" HUD.
- [ ] Fixed unlock-by-wave composition for now (adaptive skew is Day 4, ✂️9 fallback anyway).

### 2.5 Combat ([player-combat.md](systems/player-combat.md))
- [ ] Melee: `Area2D` hitbox arc, damage + knockback.
- [ ] Shared projectile system: pooled scene + `ProjectileStats` — built so turrets (Day 3) and spells (Day 4, ✂️4) reuse it verbatim.
- [ ] Death/respawn: loot-bag drop, respawn at Core after timer (beacon override Day 3).

### 2.6 XP & levels ([progression.md](systems/progression.md))
- [ ] `Progression.grant_xp` from mining/kills/looting; level curve; level-up stats + upgrade point; XP bar in HUD.
- [ ] `Progression.get_stat` multiplier lookup (buffs land Day 3; player reads stats through it now).

### 2.7 Torches & lighting ([terrain.md](systems/terrain.md))
- [ ] CanvasModulate depth-lerp, player light, torch placeable, occlusion shadows, surface ambient.
- [ ] Light cap: off-screen disable + per-vicinity placement cap with toast.

**Exit criteria:** full loop — dig during countdown, survive a walker wave that stair-digs to the Core, level up, die and recover the loot bag.

---

## Day 3 — Factory loop

### 3.1 Deployables & placement ([automation.md](systems/automation.md))
- [ ] `Deployable` base: W×H footprint, HP, faction, `on_placed/on_removed`, entity-dict registration.
- [ ] Placement mode: grid ghost + validity tint (empty, supported, reach, buffer 🔴), rejection toasts.

### 3.2 Automation tick ([automation.md](systems/automation.md)) 🔴
- [ ] 10 Hz deterministic tick; fixed order `machines → inserters → conveyors`.
- [ ] Conveyors: 1-slot stacks, mark-then-commit advance, pooled sprite + count rendering interpolated between slots — items visibly flowing 🔴.
- [ ] Inserters: behind→front single-item swing (stacking inserter is data, Day 4, ✂️6).
- [ ] Debug slot overlay hotkey (top-listed risk in [plan.md](plan.md)).

### 3.3 Production chain
- [ ] Miner on deposits (extracts `reserve` → output slot) → conveyor t1 → inserter → furnace (recipe craft when inputs present + powered).

### 3.4 Power ([automation.md](systems/automation.md))
- [ ] Generator (fuel burn, radius) + relay (✂️5); grid graph on place/remove; brownout `supply/demand` scaling.
- [ ] Coverage circles in placement mode; persistent power-overlay hotkey; unpowered-machine icon.

### 3.5 Defense
- [ ] Basic turret: auto-target, shared projectiles, ammo slot fed by inserter/hand; spike trap.
- [ ] Chest, respawn beacon, ladder (rope/pole Day 4, ✂️8).

### 3.6 Character screen ([ui.md](systems/ui.md))
- [ ] Tabbed window, `I`/`C`/`K` direct shortcuts: inventory + equipment panel (✂️7) + stats readout; crafting tab with category tabs, unlock filtering, greyed-missing-inputs; skill-tree tab node graph.
- [ ] `Items` autoload: item/recipe DB; `gather_available(player_pos)` crafting-range query used by all cost checks ([progression.md](systems/progression.md)).

### 3.7 Skill tree system ([progression.md](systems/progression.md))
- [ ] `SkillNode` Resources (prereqs, costs, recipe unlocks, leveled buffs) + ~10 nodes; buffs live through `get_stat`.

**Exit criteria:** miner → conveyor → inserter → furnace running *during* a wave while a turret fires; power overlay readable; a skill point spent unlocks a recipe.

---

## Day 4 — Content, save, polish

### 4.1 Remaining enemies ([enemies.md](systems/enemies.md))
- [ ] Leaper, digger (mostly `EnemyStats` data on the Day-2 base).
- [ ] Crawler: wall-climb + climbable use; climbable directional profiles + rope/pole (✂️8).
- [ ] Flyer + air flow field (✂️8 fallback: direct steering + chew).
- [ ] Fortification score → reachability-adaptive composition (✂️9); debug-overlay readout, calibrate live.
- [ ] Spitter, boss + arena — stretch only (✂️1).

### 4.2 Content data entry
- [ ] Recipes across tiers (automation/logistics/power/defense/components); conveyor t2, stacking inserter, Stacker (✂️6).
- [ ] Item list fill: bars, components, tools ×3, melee line, bow + arrows, spell tome + spell line (✂️4), ammo, fuel.
- [ ] Fill the tree (breadth is the scope lever, ✂️2). If node count balloons: spreadsheet → Resource import script (risk item, [plan.md](plan.md)).

### 4.3 Save/load ([save.md](systems/save.md)) (✂️3)
- [ ] Serialize: seed + terrain diff, dynamic dict (`reserve`), entities + conveyor slots, player, progression, wave number.
- [ ] Autosave at build-phase start; manual save build-phase only; IndexedDB wipe warning in UI.
- [ ] Round-trip test in browser: save, reload page, continue.

### 4.4 Audio ([pipeline.md](systems/pipeline.md))
- [ ] `AudioBus`: build/wave music crossfade on phase change; pooled SFX (mine/hit/place/pickup — pull earlier into Days 1–2 if slack, they carry feel).
- [ ] No autoplay before first input (web constraint).

### 4.5 Screens & pause ([ui.md](systems/ui.md))
- [ ] Main menu (seed input = stretch), death screen, game-over screen.
- [ ] Pause: interactive menu, gameplay actions blocked via `process_mode`; opening pause closes gameplay screens.

### 4.6 Balance & ship 🔴 (web stability)
- [ ] Tune: countdown length, wave budgets/unlocks, fortification threshold (3–4×), XP curve, hardness/tool gates, brownout feel.
- [ ] Perf pass in-browser: light cap, monster cap, tick cost; split TileMapLayer by depth band only if needed ([terrain.md](systems/terrain.md)).
- [ ] itch.io page (mention single-session runs if ✂️3 fired), final export, public upload.

---

## Standing items (every day)
- [ ] Upload a private itch build at end of day; play it in-browser.
- [ ] New sprites/sounds → `CREDITS.md` immediately.
- [ ] Decision changed while implementing → update its owning doc in the same commit ([tech-design.md](tech-design.md)).
