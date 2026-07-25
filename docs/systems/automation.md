# Automation & Deployables

Owner of: the `Deployable` base, placement, all deployable categories, the 10 Hz tick, conveyors/inserters/machines, power grids.

## Deployable base & placement
All placeables share a `Deployable` base scene: grid footprint (**arbitrary W×H per type**, defined in its data), HP, faction, `on_placed/on_removed`, registered into `Terrain`'s entity dict per occupied cell. Placement mode: grid-snapped ghost with validity tint (space empty, supported, in reach, not in a buffer zone), plus the power coverage overlay for powered machines.

## Categories
- **Miner** — placed on deposit tiles; extracts from `reserve` every N ticks into its output slot. Exhausted deposits become air ([terrain.md](terrain.md)), so a miner whose footprint tiles have all emptied shows an alert state (icon/toast) prompting removal.
- **Conveyor** — non-blocking directional scaffold tube; items levitate through. One slot per tile; slot holds a **stack**. Tiered variants move faster.
- **Inserter** — **mandatory for all machine I/O** (locked): picks from the tile behind (conveyor/machine output), drops to the tile in front (conveyor/machine input), one swing per transfer. **Stacking inserters** (higher tier) move whole stacks per swing.
- **Stacker** — conveyor-like; when its output is blocked and the incoming stack matches its held stack's item id, merges them (up to max stack size) — saturated lines densify automatically.
- **Crafting stations** — furnace, assembler, ammo press…; input/output inventories, craft selected recipe when inputs present and powered.
- **Power** — Generator (burns fuel, radiates radius R) and Relay tower (extends/bridges coverage).
- **Defense** — spike traps (contact damage, unpowered) and turrets (auto-target nearest/highest-threat in range, fire the shared projectile system — [player-combat.md](player-combat.md); some consume ammo from an internal slot fed by inserter/hand). Walls are placeable solid tiles, not deployables ([terrain.md](terrain.md)).
- **Utility** — torch, chest, respawn beacon, climbables (profiles owned by [enemies.md](enemies.md)), the Core (pre-placed, unique, big HP pool).

Full jam list: miner, conveyor ×2 tiers, inserter (+ stacking), stacker, furnace, assembler, generator, relay, chest, spike trap, basic turret, ammo turret, beacon, ladder (+ rope/pole). ~16, mostly data on shared bases.

## The 10 Hz tick (locked: tick-based slots)
One fixed 10 Hz tick in `Automation` advances the whole logistics sim deterministically. No physics.

**Conveyors:** stacks are the unit of transport everywhere. Two-phase **mark-then-commit** per tick (correct chain compression, no dupes): a stack advances into the next slot if free; blocked = waits (natural jamming). Rendering: pooled sprite + count label interpolated between slot centers over the tick interval. Throughput levers, all data: (a) tiered conveyors advance every N ticks (per-conveyor cooldown counter); (b) stacking inserters; (c) the Stacker.

**Tick order (fixed, save/load depends on it):** `machines craft → inserters transfer → conveyors advance` — a crafted item can leave the same tick.

**Debug:** hotkey overlay drawing slot occupancy + stack counts (tick bugs are the top-listed risk in [plan.md](../plan.md)).

## Power — radius coverage grids
Every Generator and Relay emits a radius. Emitters are graph nodes, edges where radii overlap; connected components = **grids**. A machine is powered if inside any emitter radius of a grid. Per tick each grid compares demand vs. fueled-generator output; machines run at `min(1, supply/demand)` — **brownouts slow, never hard-stop** (better feel, simpler code). Recompute the graph only on place/remove, never per tick.

UI: coverage circles in placement mode + a **dedicated hotkey toggling a persistent power overlay anytime** (color-coded per grid, supply/demand readouts per generator); lightning icon on unpowered machines. (Screen inventory owned by [ui.md](ui.md).)

Perf: the narrow world caps factory size; hundreds of conveyors at 10 Hz is nothing, even on web.
