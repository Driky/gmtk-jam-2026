# Terrain System

Owner of: hybrid grid model, the `Terrain` API, autotiling, lighting, deposit rendering, tile content.

## Hybrid model (locked)
**TileMapLayer is authoritative for tile *type*.** TileSet **custom data layers** carry static per-type properties: `hardness`, `drop_id`, `drop_count`, `is_solid`, `is_ore`, `is_deposit`, `min_tool_tier`.

**A sparse `Dictionary[Vector2i → TileState]` holds dynamic state only:**
- `damage` — accumulated mining damage (cleared on timeout if abandoned, cleared on destroy)
- `reserve` — remaining ore in deposit tiles
- `player_placed` — set by `set_tile(pos, id, player_placed = true)` from the player's place action. Counted in `is_default()`, so an otherwise-pristine placed tile keeps its dict entry instead of being pruned; cleared whenever anything else overwrites the cell. Read on break to veto XP on both channels — the rule and its rationale are [progression.md](progression.md)'s
- `entity` — reference to a deployable occupying this cell ([automation.md](automation.md))

`Terrain` autoload is the **only** code that touches either structure. API sketch: `get_tile_data(pos)`, `damage_tile(pos, amount, tool_tier, source)`, `set_tile(pos, id, player_placed = false)`, `is_solid(pos)`, `can_player_edit(pos)`, `place_entity(pos, node)` / `remove_entity(pos)` / `get_entity(pos)`, hot-path flow-field reads `get_cell_source_id(pos)` / `get_entity_cells()` ([enemies.md](enemies.md)), plus a bulk world-gen seam (`set_cell_raw` / `set_reserve` / `apply_autotile_region` — no per-call autotiling, one amortizable region pass). Everything (player mining, monster digging, explosions, miners) routes through `damage_tile`, so drop logic, XP grants, and deposit depletion live in exactly one place. The `source` argument enforces the buffer-zone rule (owned by [world-gen.md](world-gen.md)) via a one-line x-range check: player-sourced damage and all placement rejected in buffers (invalid ghost + toast); monster digging allowed everywhere.

Signals: `tile_changed(pos)` (structure changed — flow-field debounce hooks here), `entity_changed(pos)` (deployable placed/removed — same debounce), `tile_damaged(pos, ratio)` (mining feedback), `drops_spawned(pos, drop_id, count, source, grants_xp)` (pickup spawner owns drop policy; `grants_xp` travels in the payload because the tile's state is erased immediately after the emit, so it cannot be looked up by the receiver), `tile_broken(pos, material_id, source)` — emitted only when a cell is destroyed outright (normal break, or deposit exhaustion = **one** break for the whole deposit; chips never emit). The blocks-mined run stat ([plan.md](../plan.md) GAME_OVER stats) counts player-sourced `tile_broken`.

**Deposit mining (locked):** each pickaxe "chip" (accumulated damage reaching `hardness`) yields 1 drop and consumes 5 reserve (`DEPOSIT_CHIP_RESERVE_COST`, tuning knob) while the tile persists — the "yields poorly" rule; Miners extract reserve 1:1 ([automation.md](automation.md)). At `reserve ≤ 0` the deposit tile is **destroyed to air, with no bonus drop**.

Collision comes free from the TileSet physics layer. ~240k cells (200×1200) in one TileMapLayer is fine with quadrant batching; if web perf sags, split into 2–3 stacked layers by depth band (cheap retrofit). **Measured, so don't re-litigate it:** a cell write costs ≤0.1 ms in-call, and `physics_quadrant_size` at 8 and 4 both measured identical to the engine default of 16 — the layer is not the source of frame hitches, so it stays at defaults. `navigation_enabled` and `occlusion_enabled` stay on: navigation is wanted post-jam and occlusion is needed by torches (2.7), and neither buys measurable frame time. During play Godot's own `TIME_PHYSICS_PROCESS` sits at ~1 ms; the ~67 ms figure the perf overlay once showed was the one-off cost of creating every tile body when world gen ends, which is why that readout is now a rolling window ([ui.md](ui.md)). Debug builds assert entity-dict ↔ TileMap agreement (drift guard).

## Autotile format (locked): Terraria self-merge, 16×16
Each tile type matches only against *itself* on the 4 cardinal neighbors: 16 bitmask configs × 3 variations = **48 frames per type**, on the fixed layout of the placeholder template. No cross-material blend frames — hard edges between materials (authentic non-mergeable Terraria; avoids pair-wise transition art).

**Manual autotiling in `Terrain`, no Godot terrain sets:** on any tile change, recompute the 4-bit mask for the cell + its 4 neighbors, then `set_cell()` with `atlas_coords = LAYOUT[mask][variant]`, `variant = variant_hash(pos)` — deterministic, so no variant "popping" when mining and stable across save/load. ~30 lines; no peering bits ever authored.

**Single sources of truth** in `res://scripts/terrain/tile_layout.gd`, imported by autotiler and TileSet builder ([pipeline.md](pipeline.md)):
- `LAYOUT: Dictionary[int, Array[Vector2i]]` — mask (bit 1=N, 2=E, 4=S, 8=W; set bit = same-type neighbor) → 3 variant atlas coords. Derived **once** by inspecting `res://assets/templates/terrain_template_16.png`, then never restructured — all generated sheets share the template layout by construction.
- `variant_hash(pos: Vector2i) -> int` — pin one implementation (e.g. `abs(pos.x * 0x9E3779B1 ^ pos.y * 0x85EBCA77) % 3`; NOT engine `hash()`, not version-stable) and **never change it after the first save exists**.

## Deposit rendering
Base ore autotile on the terrain layer + marker tile on a stacked **"deposit FX" TileMapLayer**: semi-transparent sparkle/vein overlay, one `CanvasItem` shader on the layer material animating a pulse via `TIME` (zero per-cell cost; never per-deposit lights). Marker tile swaps at reserve thresholds (50% / 10%) so depletion reads without UI.

## Lighting
Terraria *look* without per-tile flood-fill:
- **Depth tint (locked, 2.7):** one `CanvasModulate` — `DepthTint`, `scripts/terrain/depth_tint.gd`, authored in `scenes/main.tscn` under `Main`. `/root/Terrain/TileMapLayer` and `Main`'s children all draw on the root viewport's default canvas, so a single node tints terrain, player, pickups and mobs together; HUD / GameOverUI / DebugMenu / LoadingUI are `CanvasLayer`s and each own their canvas, so they stay lit for free. It is driven by **the current camera, not the player**: `position_smoothing_speed = 8` lags the camera ~5 rows behind a fall, and the tint is a property of what's on screen. That also means it needs no `bind_*` — during `GENERATING` the current camera is `Main`'s static one at row 0 (white), and `LoadingUI` covers it anyway. Ramp: `Color.WHITE` at or above row **34**, `smoothstep` to `Color(0.045, 0.045, 0.075)` by row **52**. Row 34 is **derived, not taste** — `WorldGen.SURFACE_MEAN + SURFACE_AMPLITUDE + 2`, so the deepest possible surface valley (row 32) still sits at daylight; a world-gen retune that breaks that fails a test. **18 rows of ramp, measured in-browser, not the 36 first written down:** a longer ramp reads as "slightly overcast" for the entire first screen of digging, which is not the Terraria feel — there you dig down a little and it is *dark*. Half a screen means night falls while the surface is still visible above you. It bottoms out **near-black rather than at literal zero**: pickups, loot bags and mobs are unlit `ColorRect`s, and a hard black loses your own death bag outright — you still find it by walking there with your own light. The tint chases its target at `1 - exp(-6·delta)` (frame-rate independent) purely for respawn — row 400 → the Core would otherwise snap the screen white in one frame. Under the game-over pause the node stops with `Main`, so the tint freezes while `GameOverUI` stays lit: free, and correct.
- ❗️**The tint needs a `Backdrop` to bite on, because the viewport clear colour is not a `CanvasItem`.** Air cells show the clear colour straight through, so a `CanvasModulate` alone darkens the tiles and leaves every cave glowing sky-grey — underground reads *brighter* than the rock around it, which is the opposite of the whole feature. Fix: one world-sized `ColorRect` (`Backdrop`, 3200×19200, Godot's default `(0.3, 0.3, 0.3)`) under `Main` at `z_index = -100`, so it draws behind the Terrain autoload's TileMapLayer (autoloads enter the tree first, so tree order alone would put it on top) and gets tinted along with everything else — grey sky at the surface, dark at depth, one extra quad. `light_mask = 0` keeps it out of every light's item list: air must stay black inside a lit cave, and one world-spanning canvas item would otherwise burn a slot in the ~15-lights-per-item budget.
- **Surface ambient is that ramp's bright end — deliberately no node.** A light large enough to cover the surface is a texture sample per lit pixel every frame for a result identical to *not darkening*; a shadow-casting `DirectionalLight2D` runs a shadow pass over every on-screen occluder; and either permanently burns one of the ~15 lights-per-`CanvasItem` slots exactly where the player builds. `CanvasModulate` at `Color.WHITE` costs nothing. Cost of the choice: no "sunlight doesn't reach down this shaft" effect — starting the ramp 2 tiles below the deepest valley buys the same reading.
- `PointLight2D` on player + torch placeables (instanced scenes with a light node, in the deployable system — not TileMap cells).
- **One shared light texture (2.7):** `assets/light_radial.tres` — a `GradientTexture2D`, 256×256, `fill = FILL_RADIAL`, stops `0.0/α1 · 0.55/α0.45 · 1.0/α0`. **Three stops, not two:** the middle one fakes inverse-square falloff, where a linear ramp reads as a flat disc. A resource rather than a generated PNG means no external art (**so no `CREDITS.md` entry**), no `.import` step, and no second generator to drift from `tools/generate_tilesets.gd`. The gradient reaches α0 on the inscribed circle, so a light's **radius = texture width × `texture_scale` ÷ 2** — that identity is what the off-screen notifier rect is derived from. `blend_mode` stays at its default **ADD** (`MIX` washes to grey under a dark modulate) and `shadow_filter` at **NONE** (PCF is per-sample cost for a look nobody notices at 16 px).
- ❗️**A `Light2D` has no texture filter — don't try to set one.** `texture_filter` is inherited from `CanvasItem`, but a light owns no canvas item and there is no `RenderingServer.canvas_light_set_texture_filter`; setting it on a light node is inert. The corollary is the good news: `project.godot`'s `default_texture_filter = 0` (Nearest) reaches canvas items through per-item sampler objects and therefore does **not** reach light textures, which sample with the GL texture object's own default. If a light ever bands, the lever is the gradient's resolution, not a filter property.
- **Player light (2.7):** a `Light` child of `scenes/player.tscn` — `texture_scale 0.75` → a **96 px / 6-tile radius**, comfortably past the 72 px `REACH_RADIUS_PX`, so you can always see what you can reach; cool `(0.85, 0.9, 1.0)` at energy `0.85` against the torch's warm. **`shadow_enabled` stays false**, deliberately: it is the only light that moves every frame, so its shadow map can never be reused (the most expensive light in the game) *and* it looks worst — a light inside a 1-tile tunnel flickers against the occluders it is clipping. For the same reason it is **exempt from the vicinity cap** below. It goes out on death for free, because `Player._die()` already sets `visible = false` and the light is a child; there is deliberately no light code in the player.
- TileSet **occlusion layer** on solid tiles → shadows.

**Budget:** cap active lights (~40–60 on screen); off-screen lights `enabled = false` via VisibleOnScreenNotifier2D. Cap also enforced **at placement per vicinity**: exceeding it turns the ghost invalid **and shows a toast** ("Too many light sources nearby — remove one or spread them out").

## Tile inventory (~20 types, one TileSet)

*Natural base terrain:*
| Tile | Where | Notes |
|---|---|---|
| Grass | Surface top | Cosmetic dirt variant |
| Dirt | Surface, biome 2, buffers | Low hardness; buffer immutability is positional, not a tile property |
| Stone | Biome 3 | Hardness band 2, gates tool tier 2 |
| Ice/Crystal stone | Biome 4 | Hardness band 3 |
| Magma stone | Biome 5 | Hardness band 4, gates top tool tier |
| Wood (trunk) | Surface trees | **Tile-column trees:** chopping the bottom trunk fells the whole column (walk up on destroy, drops per tile) |
| Bedrock | World borders | Indestructible (`min_tool_tier = ∞`) |

*Ores (one per tier) + deposit variants:*
| Ore | Biome | Deposit variant |
|---|---|---|
| Coal | 2 | Coal deposit — generators burn fuel constantly, these matter most |
| Copper | 2 | Copper deposit |
| Iron | 3 | Iron deposit |
| Gold/Crystal | 4 | Crystal deposit |
| Magmatite | 5 | Magmatite deposit — anchors the tier-4 recipe line |

Deposit variants reuse the ore autotile + FX overlay (`is_deposit = true`, `reserve` in dict) — no extra sheets.

*Player-placeable:*
| Tile | Notes |
|---|---|
| Mined natural blocks | **Every minable natural tile can be placed back.** `drop_id` decides self vs. processed variant (stone → cobblestone). **Jam default: 1:1 self-drops**; processed variants are pure data later |
| Wall (crafted) | Sells *hardness* — necessarily, since re-placed dirt is free fortification. Reinforced tier-2 wall as data later |
