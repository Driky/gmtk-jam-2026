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
- [x] `Terrain` autoload: TileMapLayer + sparse state dict, full API (`get_tile_data`, `damage_tile`, `set_tile`, `is_solid`, `place_entity`, `get_entity`).
- [x] `damage_tile` pipeline: damage accumulation + abandon-timeout, drops, deposit `reserve` depletion, XP hook (wired Day 2), `source`-based buffer-zone rejection 🔴.
- [x] Manual autotiling: 4-bit mask recompute on change, deterministic variants.
- [x] Debug assert: entity dict ↔ TileMap agreement.

### 1.5 World generation ([world-gen.md](systems/world-gen.md))
- [x] Seeded pipeline: height-noise surface → 5 biome bands → cave carving → per-biome ore scatter → deposit blobs with `reserve` → bedrock border.
- [x] Buffer zones: flat dirt, no caves/resources, visual boundary treatment 🔴.
- [x] Amortized generation (N rows/frame) behind a loading bar (`GENERATING` state).

### 1.6 Player, mining, inventory ([player-combat.md](systems/player-combat.md))
- [x] Platformer controller with coyote time + jump buffer; stats stubbed until `Progression` exists.
- [x] Hold-to-mine within reach radius via `Terrain.damage_tile`; tool-tier gating.
- [x] Item drops as pickups; inventory data model + hotbar; placing mined natural blocks back.
- [x] Camera follow (clamped to playable width + depth).

### 1.7 Basic HUD ([ui.md](systems/ui.md))
- [x] HP/mana bars (static values ok), hotbar display, depth readout.

**Exit criteria:** in a browser, dig down through ≥2 biomes, collect drops, place blocks, buffers reject player actions.

---

## Day 2 — Fight loop

### 2.1 Core & state machine ([plan.md](plan.md))
- [x] Core scene: pre-placed on the flat spawn area, big HP pool, game-over on death.
- [x] `Game` state machine: `BOOT → MENU → GENERATING → BUILD_PHASE ⇄ WAVE_PHASE → GAME_OVER`.
- [x] Countdown presentation 🔴: prominent HUD timer, last-10 s audio sting + screen pulse, wave-n announce.
- [x] Wave-end settle: loot/XP → grace beat → countdown reset. Game-over stats screen (waves, depth, blocks mined).

### 2.2 Flow-field pathfinding ([enemies.md](systems/enemies.md)) 🔴
- [x] Ground field: Dijkstra from Core, gravity-aware directional costs, dig-weighted solids, deployable HP costs.
- [x] Region restriction (top ~150 rows), recompute on terrain/deployable change debounced ≤ 0.5 s.
- [x] Cache untouched-terrain baseline costs at world gen (needed Day 4 for fortification score).

### 2.3 First enemy — walker, fully working ([enemies.md](systems/enemies.md))
- [x] Enemy base (`CharacterBody2D`) + `EnemyStats` Resource with locomotion capabilities.
- [x] Locomotion resolution: walk / jump / chew fallback via `Terrain.damage_tile`.
- [x] Stair-digging on unsafe drops 🔴; fall damage beyond `max_safe_fall`.
- [x] Threat-table aggro: damage adds threat, decay, Core as default target.

### 2.4 Wave manager v1 ([enemies.md](systems/enemies.md))
- [x] Budget `B(n)`, trickle spawning from both buffer zones, ~25-alive cap, "Wave n — X remaining" HUD.
- [x] Fixed unlock-by-wave composition for now (adaptive skew is Day 4, ✂️9 fallback anyway).

### 2.5 Combat ([player-combat.md](systems/player-combat.md))
- [x] **LMB = use the active hotbar item**; every combat/mining number is an `ItemStats` Resource, resolved authored > block default > bare hand. Lands the item half of 3.6's DB early — **that "item/recipe DB" bullet is now recipes only, and is 3.6b**.
- [x] Melee: `Area2D` hitbox arc, damage + knockback; instanced on equip, enabled on swing.
- [x] Shared projectile system: pooled scene + `ProjectileStats` — built so turrets (Day 3) and spells (Day 4, ✂️4) reuse it verbatim. ⚠️ Pool size must scale with spawner count before 3.5 — **done at 3.5a**.
- [x] Mobs damage the player: attack of opportunity + contact damage, 0.6 s grace window with a blink ([enemies.md](systems/enemies.md) owns the mob-side rule).
- [x] Death/respawn: loot-bag drop (hotbar kept), respawn at Core after timer (beacon override Day 3).

### 2.6 XP & levels ([progression.md](systems/progression.md))
- [x] `Progression.grant_xp` from mining/kills/looting; level curve; level-up stats + upgrade point; XP bar in HUD.
- [x] `Progression.get_stat` multiplier lookup (buffs land Day 3; player reads stats through it now).
- [x] Anti-farm rule: player-placed blocks pay no XP on either channel, via a `player_placed` tile flag ([terrain.md](systems/terrain.md)) carried into the drop.
- [x] Mob death drops (`EnemyStats.drop_id/drop_count` → world pickups) — the code seam claimed 2.6 while the checklist didn't; loot *content* is still 4.2.

### 2.7 Torches & lighting ([terrain.md](systems/terrain.md))
- [x] **Per-tile propagated light grid** replacing the planned CanvasModulate + PointLight2D + occluders. The cheap model was built, looked at, and cut: it cannot make light seep around a corner or die inside rock, which is the entire reference look ([terrain.md](systems/terrain.md) §Lighting owns the rationale).
- [x] Daylight as a propagated source off `Terrain.surface_row`, so "deeper is darker" is emergent and a dug shaft fades — no depth ramp anywhere.
- [x] Torch placeable (`ItemStats.place_scene` dispatch) + un-deploy with the use verb; buffer-zone rejection toast; give-item and full-bright debug rows.
- [ ] ~~Light cap: off-screen disable + per-vicinity placement cap~~ — **deleted, not deferred.** Both existed only to manage `PointLight2D` limits a grid does not have; a hundred torches cost what one costs.

**Exit criteria:** full loop — dig during countdown, survive a walker wave that stair-digs to the Core, level up, die and recover the loot bag.

---

## Day 3 — Factory loop

### 3.1 Deployables & placement ([automation.md](systems/automation.md))
- [x] `Deployable` base: W×H footprint, HP, faction, `on_placed/on_removed`, entity-dict registration, direction-bitmask support, one `pop_to_pickup` drop path.
- [x] Modeless placement ghost: grid W×H outline + validity tint (empty, supported, reach, buffer 🔴), drawn whenever the selected item is placeable; buffer rejection toast.
- [x] Fold the 2.7 torch into the base, generalizing `as Torch` to `as Deployable` in the un-deploy path and the cursor highlight ([terrain.md](systems/terrain.md) §Lighting placed it as a one-cell special case). Support rules land here too: mining the tile a torch is mounted on now drops it as a pickup.

### 3.2 Automation tick ([automation.md](systems/automation.md)) 🔴
- [x] 10 Hz deterministic tick; fixed order `machines → inserters → conveyors`. Row-major-by-cell iteration and a catch-up clamp landed with it, and the transfer seam (`accept_item`/`extract_item`) is the interface 3.3–3.5 consume.
- [x] Facing: `directional` + runtime `facing`, `rotate_placement` on **R**, ghost arrow — nothing had a direction before this.
- [x] Conveyors: 1-slot stacks, mark-then-commit advance, **one immediate-mode `_draw` layer** interpolated between slots — items visibly flowing 🔴. (Was "pooled sprite + count"; superseded — a pool has a capacity to get wrong, [automation.md](systems/automation.md).)
- [x] Inserters: behind→front single-item swing, give-back on refusal (stacking inserter is data, Day 4, ✂️6).
- [x] RMB hand-feed, one item per click — the only way into the factory before 3.3's miner. The container panel stays 3.6a.
- [x] Debug slot overlay as an **F3 row** (top-listed risk in [plan.md](plan.md)). Was written here as a "hotkey"; reconciled — [ui.md](systems/ui.md) locks that debug overlays own no keybindings.

### 3.3 Production chain
- [x] Miner: 3×2, a harvest block one span along `facing` (the arrow points at the ore), `Terrain.extract_reserve` 1:1 → output slot. Placement is **gated** on a deposit under that block — the footprint can't overlap one, since deposits are solid ([automation.md](systems/automation.md)).
- [x] `data/recipe_defs.gd` + `CraftingStation` (furnace 2×2): id-routed input, output-only extraction, consume-on-completion. **Power only, no fuel slot** — the doc's contradiction resolved; ⚠️ `is_powered()` stubs true until 3.4.
- [x] Idle-machine HUD counter, replacing the miner-alert toast [ui.md](systems/ui.md) anticipated — a count survives being looked away from, a toast does not.
- [x] Slot overlay reads machines too (it was blind to the only things that create items); end-to-end chain test: miner → inserter → belt → inserter → furnace → inserter → belt.

### 3.4 Power ([automation.md](systems/automation.md))
- [x] Generator (fuel burn, radius) + relay (✂️5 **not fired**); grid graph on place/remove; brownout `supply/demand` scaling. The gate on the base is `spend_power_tick()`, a fractional accumulator, so every machine's timing stays in whole ticks. ⚠️ `test_miner.gd` / `test_crafting_station.gd` did **not** stay green on the 1.0 default as expected — both drive `step_tick()`, so both grew a supply in their fixture.
- [x] Coverage circles in placement mode (the ghost's prospective one, the overlay's existing ones); persistent power-overlay hotkey **P** — the one sanctioned exception to [ui.md](systems/ui.md)'s "debug overlays own no keybindings", because this one is player-facing; bolt icon on unpowered and browned-out machines. **Conveyors and inserters draw nothing** and run everywhere free.
- [x] The F3 factory rig hands a generator, a relay and a stack of coal — it had to: with the gate live, the old kit built a chain that could never run, and an exported build has no other way in.

### 3.5 Defense — split into 3.5a / 3.5b / 3.5c
Six new deployables, a shared-pool refactor, a widened support predicate, a new player movement mode and changes to the flow field: too big for one pass. Each sub-step below has a **self-contained step doc** under [steps/](steps/) carrying the file-by-file work, the traps found while researching it, and its own verification — enough that each can be picked up cold. Suggested order **3.5a → 3.5c → 3.5b**: 3.5c is smallest and unblocks 3.6a's container view, and 3.5b is last because it is the only one touching a predicate four systems read *plus* the flow field *plus* mob locomotion.

#### 3.5a Turrets & traps ([steps/3.5a-turrets-and-traps.md](steps/3.5a-turrets-and-traps.md))
- [x] 🔴 **Projectile pool must scale with spawner count before turrets ship** — the 2.5 pool is a fixed 32 and steals in-flight shots once exceeded ([player-combat.md](systems/player-combat.md)). Each spawner reserves its worst case on place; grow-never-shrink. Landed with a per-shot `damage_scale`, the seam a `turret_damage` buff needs.
- [x] `Waves.enemies()` + pure static target selection; basic turret: auto-target nearest in range, shared projectiles, power **and** an ammo slot fed by inserter/hand; spike trap. ⚠️ Two decisions moved against [automation.md](systems/automation.md) as written: turret support is `4` (Down — a standard turret wants a base under it), not the `1` (Up) that doc used it as an example of, and targeting is **nearest, full stop** — "highest-threat" is incoherent for a turret. Both struck in the owning doc. ❗️`pick_target`/`victims` iterate **untyped**: a typed loop variable fails on the *assignment* of a freed instance, before any `is_instance_valid` guard can run.
- [x] **Ammo press pulled forward from 4.2** — it costs no new script ([automation.md](systems/automation.md) §Categories: a `.tscn`, a `station_id` and recipe rows), and it makes the chain `miner → furnace → ammo press → turret`. Ammo tiers ship copper + iron only; gold/magmatite wait on their bars (4.2). The F3 rig grew both new links and widened 22 → 30 to hold the four-machine chain.

#### 3.5b Ladder & climbing ([steps/3.5b-ladder-and-climbing.md](steps/3.5b-ladder-and-climbing.md))
- [x] Ladder + player climb on the (already declared, unused) `move_up`/`move_down` actions; one `is_climbable` export serving four readers, which also resolves the support-stacking clause [automation.md](systems/automation.md) §Deployable base parked at 3.5 — climbables stack **downward only**, because the symmetric version lets two rungs floating in mid-air hold each other up forever with nothing able to report it. The climb is a **latched** early return in `_move` with no state machine, gated on `_stun_left` and decaying the jump buffer itself ([player-combat.md](systems/player-combat.md) §Controller). ⚠️ Two requirements the step doc never had, found by **playing the web build** and fixed after it shipped: a column's **top rung reads as ground** (still a grid query, top rung only — you were bobbing at the lip and a ladder could not get you out of a shaft), and a **jump releases the latch and stays released** (engagement reads a held key, so the next frame was overwriting the jump at `CLIMB_SPEED`).
- [x] **Mobs climb it too** — [enemies.md](systems/enemies.md) §Climbables already locked that, so a player-only ladder would have contradicted its owning doc. Ground-field vertical edge (in **both** copies of the edge logic — the Dijkstra loop and `cost_of_entering`) + the CLIMB locomotion action, plus three blockers that each make the feature silently do nothing alone: the entity probe running before locomotion, the stuck watchdog, and the airborne apex. ⚠️ **One decision moved against [enemies.md](systems/enemies.md) as written:** the "biped-only" clause was struck as a *chewing* rule — **nothing chews a climbable**, and `is_biped` gates **ascending** only, now read at exactly one site. A non-biped goes around, or (4.1) crawls alongside. Nothing observable changes today (walker-only roster), which is why it had to be decided here rather than discovered at 4.1.
- ✂️8 not fired: it reads "ladder only", so rope/pole and the *directional* profiles stay 4.1.

#### 3.5c Chest & respawn beacon ([steps/3.5c-chest-and-beacon.md](steps/3.5c-chest-and-beacon.md))
- [x] Chest — the first N-slot container; reuses `Inventory` via one defaulted `slot_count`, so 3.6a's container view binds the signals the hotbar already uses. The panel itself stays 3.6a ([player-combat.md](systems/player-combat.md) §Hand-feeding). ⚠️ Its contents are invisible to the F3 slot overlay, which walks the tick registries a chest deliberately does not join — accepted, see [automation.md](systems/automation.md) §Categories → Utility.
- [x] Respawn beacon overriding the Core as the respawn anchor, resolved **nearest to the death position** ([player-combat.md](systems/player-combat.md) §Death & respawn). ⚠️ One decision moved against the step doc as written: `support_dirs = 4` (Down), not `15` — the respawn formula assumes ground under the anchor cell, so a ceiling-mounted beacon would drop you into rock. `respawned` also grew an `at_beacon` payload, because the HUD banner named the Core unconditionally and would now be lying ([ui.md](systems/ui.md)).

#### Standing item — GYM scenes for scenario testing ([ui.md](systems/ui.md))
- [ ] Debug row + dropdown loading a pre-made scenario `.tscn` from a gym folder. **This is how scenarios are tested from now on**; debug affordances themselves keep growing as normal. Raised at 3.5a, when every bug in the procedural `build_defense_chain` fixture turned out to be a geometry bug invisible until the game ran. Not scheduled — do it when a second scenario is needed.

### 3.6 Character screen — split into 3.6a / 3.6b ([ui.md](systems/ui.md))
A tabbed window, a 40-slot grid with a new interaction model, an equipment panel with a new player stat behind it, a crafting UI over a table that today holds **no player-craftable rows**, a new input action — and a node graph over a `SkillNode` Resource **3.7 has not written yet**. Too big for one pass, and its last item was asking 3.6 to render a data model that does not exist. Each sub-step below has a **self-contained step doc** under [steps/](steps/) carrying the file-by-file work, the traps found while researching it, and its own verification — enough that each can be picked up cold. Order is **3.6a → 3.6b**, and that is not a preference: 3.6b's crafting tab is a tab *inside* 3.6a's window and consumes its slot widget and its held-stack model. **The skill-tree tab moves to 3.7**, where its data lives.

#### 3.6a Character window & inventory tab ([steps/3.6a-window-and-inventory.md](steps/3.6a-window-and-inventory.md))
- [x] Tabbed window on layer 5 with `I`/`C`/`K` direct shortcuts, and the shared open-screen predicate that blocks gameplay actions *and* movement without pausing ([ui.md](systems/ui.md) §Pause) — the factory has to keep ticking through a wave.
- [x] The 40-slot grid. ❗️**Slots 10–39 are unreachable today**: `hud.gd`'s `_on_slot_changed` early-returns above `HOTBAR_SIZE`, so everything a loot bag hands back past slot 9 goes into a void the player cannot see. Held stack on the cursor + shift-click quick-move ([ui.md](systems/ui.md) §Character screen).
- [x] Equipment panel — 5 armor + 3 accessory slots, no tool/weapon slot ([ui.md](systems/ui.md)) — and the armor damage-reduction stat behind it ([player-combat.md](systems/player-combat.md) §Taking damage). ✂️7 not fired; its wording is rewritten in [plan.md](plan.md).
- [x] Container view on a new `interact` key ([ui.md](systems/ui.md) §Bindings), binding the `Chest.storage()` seam 3.5c left with no reader. Player stats readout.

⚠️ Four decisions moved against the step doc as written:
- **Eight authored equipment pieces, not "~3 samples"** — seven `.tres` (`RING` fills both ring slots), one per `Equipment.slot_accepts` branch, so every branch has live data instead of a synthetic `ItemStats` built inside a test. ⚠️ They sum to 15 but a fully-worn set is **16**: the one ring id is worn twice.
- **The armor curve is `12 / (12 + armor)` floored at 0.20 of the incoming damage**, with both numbers named `# Tuning: 4.6` on the player rather than left implicit — the shape was locked, the constants were not.
- **`Chest.on_removed` reaches the screen by the group `&"character_screen"`**, not by naming `CharacterScreen`: doing so closes a resource-level dependency cycle through `chest.tres`'s `place_scene` that stops the HUD compiling at boot. It binds every deployable, so it is recorded in [automation.md](systems/automation.md).
- **The shell shipped before the predicate** (the step doc's §6 before its §5): `UiState` names `CharacterScreen.is_open`, which does not parse until that class exists. And `main.gd` **binds** the player to the screen rather than showing it — the screen owns its own visibility and starts closed.

#### 3.6b Crafting tab ([steps/3.6b-crafting-tab.md](steps/3.6b-crafting-tab.md))
- [x] `station = "hand"` recipe rows for the deployables ([progression.md](systems/progression.md) §Recipe tiers). ❗️**This is the step that stops the F3 give-item dropdown being the only way to obtain a machine** — `STARTING_KIT` is a pickaxe and torches, and an exported build has no console ([ui.md](systems/ui.md) §Build factory rig).
- [x] Crafting UI over the 3.3 recipe table (`data/recipe_defs.gd`) — the DB itself landed there, as the item half landed at 2.5; `gather_available(player_pos)` plus its two-phase `consume_available` counterpart, used by all cost checks ([progression.md](systems/progression.md) §Crafting range).
- [x] ~~First-time-craft XP~~ — **cut, not deferred** ([progression.md](systems/progression.md) §XP): it needs a `crafted_ids` set plus a `reset_run` line and is worth nothing until there is a reason to craft twice.

⚠️ Four decisions moved against the step doc as written:
- **The tool-tier retune came first, and without it the step's exit criterion is unreachable.** `pickaxe_t1` is `tool_tier = 1` — as is *every* authored item — while `stone` and `iron` were `min_tool_tier = 2`, so a fresh run could never dig past row 250 by hand and the hand recipes would have been priced in ore nothing could mine. `stone`, `iron` and `iron_deposit` drop to tier 1; the gate **moves** to the crystal band rather than disappearing ([terrain.md](systems/terrain.md)).
- **`ticks = 0` on hand rows breaks an existing assertion**, which the step doc expected to stay green. `test_recipe_defs`'s duration check now splits by station: positive for a station row, exactly 0 for a hand row.
- **A `Timer` scoped to the tab's visibility drives the repaint** — the step doc specified greying and the in-range count but never said what refreshes them, and 3.6a's screen has no `_process` by design. Without it, walking toward a chest leaves the row grey ([ui.md](systems/ui.md) §Character screen).
- **`consume_available`'s container order is stated: row-major by `global_position`.** `get_nodes_in_group` is scene-tree order, which [save.md](systems/save.md)'s restore-in-file-order reshuffles ([progression.md](systems/progression.md) §Crafting range).

### 3.7 Skill tree system ([progression.md](systems/progression.md))
- [ ] `SkillNode` Resources (prereqs, costs, recipe unlocks, leveled buffs) + ~10 nodes; buffs live through `get_stat`.
- [ ] The tree tab — a **third tab in 3.6a's existing window**, not a screen of its own, and the step that fills in the `unlocked_by` column 3.6b ships empty on every recipe row.

**Exit criteria:** miner → conveyor → inserter → furnace running *during* a wave while a turret fires; power overlay readable; a skill point spent unlocks a recipe.

---

## Day 4 — Content, save, polish

### 4.1 Remaining enemies ([enemies.md](systems/enemies.md))
- [ ] Leaper, digger (mostly `EnemyStats` data on the Day-2 base).
- [ ] Crawler: wall-climb. ⚠️ It wall-climbs **alongside** a ladder column, it does not eat one — 3.5b made "nothing chews a climbable" unconditional, so the crawler's job here is only the *alongside* half ([enemies.md](systems/enemies.md) §Climbables). Climbable **directional** profiles + rope/pole (✂️8) — the symmetric ladder and the `is_biped` ascend gate shipped at 3.5b, so what is left is the direction-respecting half (rope = up slow, pole = down only), authored beside the existing `is_climbable` bool rather than replacing it.
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
