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

Collision comes free from the TileSet physics layer. ~240k cells (200×1200) in one TileMapLayer is fine with quadrant batching; if web perf sags, split into 2–3 stacked layers by depth band (cheap retrofit). **Measured, so don't re-litigate it:** a cell write costs ≤0.1 ms in-call, and `physics_quadrant_size` at 8 and 4 both measured identical to the engine default of 16 — the layer is not the source of frame hitches, so it stays at defaults. `navigation_enabled` stays on (wanted post-jam). **`occlusion_enabled` is off** as of 2.7 — it was only ever on because torches were going to cast shadows, and the lighting model that needed that is gone (§Lighting). ⚠️ The old claim here that "occlusion buys no measurable frame time" was **measured with zero lights on screen**, which is the one condition under which occluders are guaranteed free; it was never re-tested under lit conditions and should not be quoted as evidence for turning it back on. During play Godot's own `TIME_PHYSICS_PROCESS` sits at ~1 ms; the ~67 ms figure the perf overlay once showed was the one-off cost of creating every tile body when world gen ends, which is why that readout is now a rolling window ([ui.md](ui.md)). Debug builds assert entity-dict ↔ TileMap agreement (drift guard).

## Autotile format (locked): Terraria self-merge, 16×16
Each tile type matches only against *itself* on the 4 cardinal neighbors: 16 bitmask configs × 3 variations = **48 frames per type**, on the fixed layout of the placeholder template. No cross-material blend frames — hard edges between materials (authentic non-mergeable Terraria; avoids pair-wise transition art).

**Manual autotiling in `Terrain`, no Godot terrain sets:** on any tile change, recompute the 4-bit mask for the cell + its 4 neighbors, then `set_cell()` with `atlas_coords = LAYOUT[mask][variant]`, `variant = variant_hash(pos)` — deterministic, so no variant "popping" when mining and stable across save/load. ~30 lines; no peering bits ever authored.

**Single sources of truth** in `res://scripts/terrain/tile_layout.gd`, imported by autotiler and TileSet builder ([pipeline.md](pipeline.md)):
- `LAYOUT: Dictionary[int, Array[Vector2i]]` — mask (bit 1=N, 2=E, 4=S, 8=W; set bit = same-type neighbor) → 3 variant atlas coords. Derived **once** by inspecting `res://assets/templates/terrain_template_16.png`, then never restructured — all generated sheets share the template layout by construction.
- `variant_hash(pos: Vector2i) -> int` — pin one implementation (e.g. `abs(pos.x * 0x9E3779B1 ^ pos.y * 0x85EBCA77) % 3`; NOT engine `hash()`, not version-stable) and **never change it after the first save exists**.

## Deposit rendering
Base ore autotile on the terrain layer + marker tile on a stacked **"deposit FX" TileMapLayer**: semi-transparent sparkle/vein overlay, one `CanvasItem` shader on the layer material animating a pulse via `TIME` (zero per-cell cost; never per-deposit lights). Marker tile swaps at reserve thresholds (50% / 10%) so depletion reads without UI.

## Lighting (locked, 2.7) — per-tile propagated light

**Terraria's actual model, not an approximation of it.** The first attempt was the cheap one this doc used to specify — `CanvasModulate` for depth + `PointLight2D` per source + TileSet occluders for shadows — and it was **cut after being built and looked at**. It cannot produce the reference look at any setting: a `PointLight2D` draws a hard radial disc in *screen* space and knows nothing about tiles, so light neither seeps around a corner nor dies inside rock, and the only tile-awareness on offer is hard-edged shadow casting, which Terraria does not do. That is a ceiling, not a tuning problem, so the model changed. `CanvasModulate`, `PointLight2D`, occlusion shadows, the shared gradient texture, the vicinity light cap and the off-screen light disable are all **gone** — see §Budget for why the cap went with them.

**The grid.** `scripts/terrain/light_grid.gd` keeps one RGB value per tile over the on-screen region plus a **16-tile margin** (so a source just off-screen still bleeds in and the region edge never shows as a straight line). Light is propagated by **four directional scanline sweeps × 2 passes** — light entering a cell is the best neighbour value attenuated by what that cell is made of. One sweep set already bends light around a corner because each sweep reads the previous one's output; the second cleans up concave pockets. Attenuation is **0.91 per air tile, 0.56 per solid tile**: that contrast is the whole reason a cave reads as a cave instead of a disc.

**The render, which is the trick that makes it cheap.** The grid is uploaded as a texture at **one pixel per tile** and drawn over the world stretched, with **`TEXTURE_FILTER_LINEAR`** and **`CanvasItemMaterial.BLEND_MODE_MUL`** (`scripts/terrain/light_map.gd`, `LightMap` in `main.tscn` at `z_index = 100`). Bilinear interpolation between texel centres *is* the soft seeping falloff — there is no blur pass and no shader. Texel *i*'s centre lands at `(i + 0.5) × TILE` from the rect origin, exactly the centre of tile `origin + i`, so no half-pixel correction exists anywhere. Consequences worth stating plainly: **one draw call, no shadow passes, and zero per-light cost — a hundred torches render exactly as cheaply as one.** The HUD and other UI are `CanvasLayer`s with their own canvas, so this cannot reach them.

**Daylight is a source, not a curve.** Every cell at or above its column's surface row is seeded at full strength and propagation does the rest, so daylight fills open sky, stops a few tiles into the dirt, and fades down a dug shaft on its own. **"Deeper is darker" is emergent — there is no depth ramp anywhere in the model**, and the `CanvasModulate` depth-lerp that used to own this bullet is deleted along with its constants and tests.
- ❗️**This requires `Terrain.surface_row(x)`** (written once by world gen through `set_surface_rows`, [world-gen.md](world-gen.md) owns how the heights are chosen). A dug shaft and open sky are *both air*; nothing else distinguishes them, and without the surface row a player sinks one shaft and owns a permanently lit column. Terraria solves the same problem with background walls, which this game does not have. Columns with no generated terrain report `-1` and get **no** daylight: dark is the safe wrong answer, a lit void is not.
- When the surface sits **above** the solved window, the column is seeded on its top row with whatever daylight survives the gap (`0.91^gap`, given up past 64 tiles where it can no longer move a single output byte). Without that term, scrolling down past the surface snaps an open shaft from lit to black in one frame.

**`Backdrop` is still required, and for the original reason:** the viewport clear colour is not a `CanvasItem`, so air cells show it straight through and every cave glows sky-grey while the rock goes dark — underground reading *brighter* than the surface, the exact opposite of the feature. One world-sized `ColorRect` (3200×19200, Godot's default `(0.3, 0.3, 0.3)`) under `Main` at `z_index = -100` — behind the Terrain autoload's TileMapLayer, which tree order alone would not achieve since autoloads enter the tree first. The multiply pass then darkens it with everything else.

**Sources** are nodes in the `light_source` group carrying a `light_color`; the grid reads `global_position` and skips any source that is not `visible`. The player is one (cool `(0.85, 0.9, 1.0)`), so a corpse stops glowing for free via the `visible = false` that `Player._die()` already does — there is deliberately no light code in the player. Daylight is faintly cool `(0.95, 0.97, 1.0)` so torchlight reads warm against it without either being a saturated colour.

**Torch = a one-cell entity scene** (`scenes/torch.tscn`, `scripts/terrain/torch.gd`), registered in the terrain entity dict so nothing else can claim the cell, and found by the grid through the `light_source` group. It owns **no light node and no visibility notifier** — there are no per-light budgets left to manage. Placement is [player-combat.md](player-combat.md) §Placement's; removal is its §Un-deploying (LMB, hit-counted, mob-shielded).
- ❗️**It deliberately has no `current_hp`.** `flow_field.gd` reads `ent.get("current_hp")` and skips entities returning null, so a torch adds *exactly zero* cost to the field and mobs walk through it. Don't "fix" this — 3.1 giving torches HP is what makes them start costing the field, which is the intended 3.1 behaviour.
- **3.1 folds this into `Deployable`**: HP, faction, W×H footprint, `on_placed`/`on_removed`, ghost + validity tint. This is the one-cell special case that ships before that base exists, not a second placement system.
- **Accepted, not solved:** mining the tile a torch is mounted on leaves it floating. The engine is safe (`damage_tile` on air returns false, and `set_tile`'s entity assert cannot fire because `can_place_at` already rejects an occupied cell), so it is cosmetic only. Support rules and "unsupported deployables pop into a pickup" belong with `on_removed` in 3.1 — not a support system on Day 2.

**Gotchas paid for in full, so nobody re-pays them:**
- ❗️**Never compare a `PackedFloat32Array` read against a float literal.** The read widens back to a float64 that does *not* equal the float64 it was written from, so `_atten[i] == AIR_ATTEN` is always false. That silently disabled the entire daylight pass and rendered a plausible-looking all-dark world. Solidity therefore lives in its own `PackedByteArray`, which is cheaper anyway.
- ❗️World gen lays a **solid bedrock lid across row 0** ([world-gen.md](world-gen.md) border). Any "walk down the column while air" sky rule stops dead on it and no daylight ever enters the world. Seeding from `surface_row` sidesteps this entirely — but a future rewrite that goes back to scanning must know.
- `occlusion_enabled` on the TileMapLayer is now **false**. Nothing casts shadows, and leaving it on builds an occluder instance for every solid cell for nobody to read. The generated TileSet still carries occluder polygons ([pipeline.md](pipeline.md)); they are inert, and regenerating the sheet to strip them is churn for no gain.

**Budget — measured in-browser, not estimated.** Unamortized full-res (112×77 = 8,624 cells at 1× zoom, the worst case since zoom > 1 shows *less* world), against a synthetic world: **sample 1.4 ms · solve 7.0 ms · upload 0.6 ms**. **Amortized, in the real game, in a browser: `fps 60`, worst frame by section `light.solve 3.2 · light.sample 3.1 · light.upload 1.3 ms`** — no single frame pays more than ~3 ms. Note the sample pass costs ~2× its synthetic figure against the real `Terrain` (a native call per cell); it is the first thing to make incremental if the budget ever tightens, since only the newly-exposed rows and columns actually change as the region scrolls. Half-res is 2.0 ms total. **wasm runs this at ~1.0× desktop speed** — there is no web penalty, because the solve is flat `PackedFloat32Array` arithmetic rather than the heap/`Dictionary`/native-call mix that makes the flow field cost 57 ms ([enemies.md](enemies.md)). **The solve is amortized across six frames** — one phase seeds (re-aim the region, sample terrain, lay down sources), four run two sweeps each, one uploads — so the light refreshes at ~10 Hz with no frame paying more than ~2 ms. Everything after the seed phase is pure arithmetic on a snapshot, which is what makes it safe to pause between sweeps; `LightGrid.sweep(i)` is the seam, and a test pins stepped sweeps to the same answer as `solve()`. The drawn rect is **latched at seed time**, not read live: the grid holds light for the region it was sampled for, so drawing it against the live camera rect would slide a stale solve across the world as you walk. The first solve runs whole in a single frame, since amortizing from cold would show ~100 ms of *unlit* (i.e. fully bright) world exactly as the loading screen hides. Remaining fallback ladder if it ever matters: half-res grid (1 sample per 2×2 tiles; the bilinear upscale hides it) → drop `PASSES` to 1 → widen the phase count. **The vicinity light cap and the off-screen light disable are deleted, not deferred** — both existed solely to manage `PointLight2D` limits (the ~15-lights-per-`CanvasItem` ceiling and per-light shadow passes) that a grid does not have. The toast for *buffer-zone* rejection survives, since that rule is about placement, not light ([ui.md](ui.md)).

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
