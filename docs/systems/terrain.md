# Terrain System

Owner of: hybrid grid model, the `Terrain` API, autotiling, lighting, deposit rendering, tile content.

## Hybrid model (locked)
**TileMapLayer is authoritative for tile *type*.** TileSet **custom data layers** carry static per-type properties: `hardness`, `drop_id`, `drop_count`, `is_solid`, `is_ore`, `is_deposit`, `min_tool_tier`.

**A sparse `Dictionary[Vector2i → TileState]` holds dynamic state only:**
- `damage` — accumulated mining damage (cleared on timeout if abandoned, cleared on destroy)
- `reserve` — remaining ore in deposit tiles
- `entity` — reference to a deployable occupying this cell ([automation.md](automation.md))

`Terrain` autoload is the **only** code that touches either structure. API sketch: `get_tile_data(pos)`, `damage_tile(pos, amount, tool_tier, source)`, `set_tile(pos, id)`, `is_solid(pos)`, `can_player_edit(pos)`, `place_entity(pos, node)` / `remove_entity(pos)` / `get_entity(pos)`, plus a bulk world-gen seam (`set_cell_raw` / `set_reserve` / `apply_autotile_region` — no per-call autotiling, one amortizable region pass). Everything (player mining, monster digging, explosions, miners) routes through `damage_tile`, so drop logic, XP grants, and deposit depletion live in exactly one place. The `source` argument enforces the buffer-zone rule (owned by [world-gen.md](world-gen.md)) via a one-line x-range check: player-sourced damage and all placement rejected in buffers (invalid ghost + toast); monster digging allowed everywhere.

**Deposit mining (locked):** each pickaxe "chip" (accumulated damage reaching `hardness`) yields 1 drop and consumes 5 reserve (`DEPOSIT_CHIP_RESERVE_COST`, tuning knob) while the tile persists — the "yields poorly" rule; Miners extract reserve 1:1 ([automation.md](automation.md)). At `reserve ≤ 0` the deposit tile is **destroyed to air, with no bonus drop**.

Collision comes free from the TileSet physics layer. ~240k cells (200×1200) in one TileMapLayer is fine with quadrant batching; if web perf sags, split into 2–3 stacked layers by depth band (cheap retrofit). Debug builds assert entity-dict ↔ TileMap agreement (drift guard).

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
- `CanvasModulate` darkens; intensity lerps with camera depth.
- `PointLight2D` on player + torch placeables (instanced scenes with a light node, in the deployable system — not TileMap cells).
- TileSet **occlusion layer** on solid tiles → shadows. Surface gets a large ambient region.

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
