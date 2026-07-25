# World Generation

Owner of: map dimensions, biome layout, generation pipeline, **buffer zones**.

Seeded, deterministic per seed (save system depends on this — [save.md](save.md)), generated once at new-game, fully in memory: ~200 × 1200 tiles ≈ 240k cells including buffers. Generation is amortized across frames behind a loading bar (N rows per frame — web is single-threaded).

## Layered biomes (top → bottom, tuned depths)
1. **Surface** (rows 0–40): grass/dirt, trees, flat-ish spawn area for the Core.
2. **Dirt & Caves** (40–250): copper, coal, small caves.
3. **Stone Depths** (250–550): iron, denser caves, tougher blocks.
4. **Crystal/Ice** (550–850): gold/crystal; ambient hazard enemies optional (cut first).
5. **Deep Magma** (850–1200): Magmatite, hardest blocks, boss arena (stretch).

## Pipeline
Height-noise surface → biome bands by depth → cave carving (2–3 octaves noise threshold + a few random-walk tunnels) → ore scattering per biome (Poisson-ish, per-biome tables) → **deposits**: rare large blobs of deposit tiles with high per-tile `reserve`, intended for machine mining (pickaxe can chip them but yields poorly; a Miner extracts until reserve hits zero) → bedrock border on all edges.

## Buffer zones (locked decision — owned here)
Beyond the 100-tile playable width, **~50 extra tiles each side** of deliberately boring terrain: flat dirt matching surface height, no caves, no resources. **Player-immutable** (no mining, no building — enforced by `Terrain.damage_tile`'s `source` argument, see [terrain.md](terrain.md)), but **monsters dig freely**: wave mobs spawn in the buffers and stair-dig safe descents through terrain the player cannot booby-trap, wall off, or excavate into a kill-pit. The playable/buffer boundary reads at a glance via a subtle semi-transparent tint overlay on each buffer (ColorRects in the main scene; marker posts remain a fallback if the tint reads poorly).

With ~100 playable tiles, both buffers are always near the base — two-front wave pressure is inherent to the map shape, by design.
