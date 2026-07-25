# Game Flow, 96-Hour Plan, Cut Lines & Risks

Owner of: the `Game` state machine, win/lose conditions, the day plan, cut lines, risks.

## Game state machine
```
BOOT → MENU → GENERATING → BUILD_PHASE ⇄ WAVE_PHASE → GAME_OVER
```
- **BUILD_PHASE:** fixed countdown (e.g. 4:00) prominent in HUD; last 10 s = audio sting + screen pulse. Automation runs. Timer 0 → announce wave n.
- **WAVE_PHASE:** no timer; HUD shows "Wave n — X remaining". Automation keeps running (factories work during combat — that's the fantasy). All spawned dead → loot/XP settle → grace beat → BUILD_PHASE, countdown reset.
- **GAME_OVER:** Core HP ≤ 0. Stats: waves survived, depth reached, blocks mined.

Endless, score = waves survived; optional final boss is a stretch. Fixed countdown for the jam — the state machine makes scaling/player-influenced timers a data tweak later. Pause behavior owned by [systems/ui.md](systems/ui.md).

## 96-hour plan
**Day 1 — dig loop (playable by bedtime):** project setup, **web export tested at hour 2, not hour 90**, tileset pipeline ([systems/pipeline.md](systems/pipeline.md)), terrain gen + hybrid system with manual autotiling, player controller, mining + drops + inventory, camera, basic HUD.
**Day 2 — fight loop:** Core, countdown state machine, flow-field pathfinding, one enemy fully working (field / climb / chew / aggro), melee + shared projectile system, death/respawn, XP + levels, torches + lighting.
**Day 3 — factory loop:** placement system, miner → conveyor → inserter → furnace chain, power (generator + relay + grids + overlay hotkey), turret + trap, tabbed character screen, skill tree system + ~10 nodes.
**Day 4 — content, save, polish:** remaining enemies, recipe/tier data entry, tree filled out, save/load, audio pass, balancing, itch page, buffer for web-export gremlins.

Sequencing rule: implement in day order; within a day, systems before content.

## Cut lines (pre-authorized, in firing order; cutting one also prunes its dependencies)
1. Boss, spitter enemy, biome 5.
2. Skill tree breadth (keep one deep path per branch) — *the designated scope lever*.
3. Save system → single-session runs (announce on itch page).
4. Spell line (keep melee + bow; mana stat still shown).
5. Relay towers (generator radius only).
6. Conveyor tier 2, stacking inserter, Stacker.
7. Equipment panel → tool/weapon slots only.
8. Rope/pole climbables (ladder only) + the air field (flyers → direct steering + chew).
9. Reachability-adaptive spawn skew (fixed unlock waves for crawler/flyer instead).

**Never cut:** countdown presentation (the theme) · visible items flowing through conveyors (the genre) · ground flow field + stair-digging (trench-proof, pit-proof waves) · buffer zones · web export stability.

## Risks & mitigations
- **Web export surprises** → export + play in-browser from day 1; upload a private itch build daily.
- **Automation tick bugs** (ordering, dupes, stack merges) → two-phase mark/commit; debug slot overlay.
- **"Large" tree scope** → all content as Resources; optional spreadsheet → Resource import script.
- **Perf: lights** → cap + off-screen disable ([systems/terrain.md](systems/terrain.md)). **Perf: monsters** → ~25 alive cap.
- **Terrain source-of-truth drift** → single-manager API + debug asserts.
- **Fortification-score tuning** → debug readout, calibrate live on day 4.
