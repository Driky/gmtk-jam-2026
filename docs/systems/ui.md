# UI

Owner of: all screens, shortcuts, overlays, pause behavior.

## Character screen — one window, three tabs (locked)
Navigable via tab buttons and cycling keys; each tab ALSO has a direct shortcut (`I` inventory, `C` crafting, `K` skill tree) that opens the window on that tab, or switches tab if open:
- **Inventory tab:** grid inventory + hotbar assignment, **equipment panel** (tool, weapon slots, armor/accessory slots), **player stats readout** (HP, mana, move speed, active buff multipliers). Container view opens alongside when interacting with a chest.
- **Crafting tab:** recipes in **category tabs** (Tools & Weapons / Automation / Logistics / Power / Defense / Components…) for findability; filtered by unlocks, greyed when inputs missing (with missing-item highlight); search box if time allows.
- **Skill tree tab:** node graph ([progression.md](progression.md)).

## World camera zoom (locked)
`Z` cycles the world camera zoom **1× → 1.5× → 2×** (default **1×**). Affects only the game world; HUD/UI stays native 720p ([tech-design.md](../tech-design.md) display constraint). Implemented on the player camera ([player-combat.md](player-combat.md), Day 1 step 1.6).

## HUD (1.7, locked)
`scenes/ui/hud.tscn` (CanvasLayer + `scripts/ui/hud.gd`), instanced in main.tscn, hidden until `main.gd::_finish_generation()` shows it and hands over the player via `bind_player` (same ownership moment as the LoadingUI toggle). Native 720p, stock Controls, no theme resource. Testability: the HUD takes its `Inventory` via a settable property defaulting to `Items.player_inventory`; formatting and icon lookup are static funcs.
- **Bars (top-left):** HP red, mana blue ProgressBars with a centered "current / max" label, driven by the player's `health_changed` / `mana_changed` signals ([player-combat.md](player-combat.md) HP/mana stub).
- **Hotbar (bottom-center):** 10 slots (Inventory 0–9), key labels 1–9 then 0, item icon + count, selected slot highlighted via `selected_changed`. Icons: the fully-surrounded autotile frame (`TileLayout.LAYOUT[15][0]`) cut as an AtlasTexture from `terrain_tileset.tres` (atlas source id = `Materials.ORDER` index); ids without tile art fall back to a 16×16 `base_color` swatch (gray when unknown).
- **Elevation (top-right):** `Elevation: <row> — <biome name>` — row is the **raw tile row** (`floori(global_position.y / 16)`, not depth-below-surface), biome from `Biomes.BANDS`; label repaints only on row change. Also feeds the game-over stats screen (2.1).
- **Phase label (top-center, 2.1):** big countdown `M:SS` during BUILD_PHASE (from `Game.countdown_tick`), `Wave n — X remaining` during WAVE_PHASE (2.4, refreshed on `Waves.wave_progress_changed` — the count itself is owned by [enemies.md](enemies.md); the label reads `Waves.remaining()` rather than the signal payload, since Waves is an autoload and handles `wave_started` first). Last-`FINAL_WINDOW` seconds: label turns red + scale-pops and a full-screen `PulseOverlay` ColorRect flashes (alpha tween, no shaders — Compatibility-safe). Countdown *presentation* behavior is owned by [plan.md](../plan.md); this section owns the widgets.
- **Wave banner (centered, 2.1):** announce on `wave_started` / `wave_cleared`, hold-then-fade tween.
- **Core HP (under phase label, 2.1):** slim bar, seeded/driven via `bind_core(core)` (mirrors `bind_player`). HUD takes its `Game` via a settable `game` property defaulting to the autoload (test seam).

Later HUD residents (owned by their systems): XP bar + level (2.6).

**Debug overlays** (hidden by default, instanced by `main.gd`, never in a player's way): **F3** flow-field heat map ([enemies.md](enemies.md)) · **F4** perf readout (`scripts/debug/perf_overlay.gd`) — frame pacing, flow-field solve cost, and tile-write cost, existing because the browser has no editor profiler and web perf is the never-cut risk in [plan.md](../plan.md). Its headline figure is the **worst frame in a rolling window**, not mean FPS: a periodic hitch is invisible in an average. It also splits the worst frame by whether a cell write happened near it (**dirty** vs **clean**), which is what attributes a hitch to the tile-change path or exonerates it. Toggling it on resets every accumulator — including baselining Terrain's monotonic write counters, since world gen writes ~240k cells before a run starts. Counters live on `Terrain` (`cell_writes`, `cell_write_usec`, `cell_write_peak_usec`), fed by the single `_write_cell`/`_erase_cell` seam so no mutation escapes them. The last two lines are `scripts/debug/perf.gd` (`Perf.begin`/`end` named sections, ranked by **worst single frame** — an average buries a once-a-second spike) and Godot's own `TIME_PROCESS` / `TIME_PHYSICS_PROCESS` peaks. That last pair is the one that matters: when named sections sum to ~15 ms but `TIME_PHYSICS_PROCESS` peaks at 67 ms, the cost is in the physics *server*, not in any script — which is how the TileMapLayer collision rebuild was finally identified. Sections are frame-bounded via `Engine.get_process_frames()`, so `Perf` needs no autoload slot and cannot be mis-ordered against the code it measures.

## Other screens
Pause menu · placement mode overlay · **power overlay** on its own hotkey, togglable anytime ([automation.md](automation.md)) · debug overlay (slot occupancy, fortification score) · death & game-over screens · main menu with seed input (stretch: seedless "New Run" only). Keyboard + mouse only. Toasts for rejected placements (buffer zone, light cap — [terrain.md](terrain.md)).

## Pause (locked)
`SceneTree.paused` + `process_mode`: gameplay pauses; the pause menu stays **fully interactive** (resume, settings, save during build phase, quit). Forbidden while paused: *gameplay* actions — placing/removing deployables, inventory/crafting manipulation, skill-tree spending. Enforcement: opening pause closes gameplay screens; gameplay input handlers live under paused `process_mode`.
