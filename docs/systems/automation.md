# Automation & Deployables

Owner of: the `Deployable` base, placement, all deployable categories, the 10 Hz tick, conveyors/inserters/machines, power grids.

## Deployable base & placement
All placeables share a `Deployable` base (`scripts/automation/deployable.gd`): grid footprint (**arbitrary W×H per type**, authored as an export), HP, faction, `on_placed/on_removed`, registered into `Terrain`'s entity dict per occupied cell. **The origin cell is the TOP-LEFT one**, so a footprint grows right and down from `cell()`. Registration is **all-or-nothing with rollback** (the `Core.register_footprint` rule, verbatim): a partial claim would leave cells nothing can ever occupy again. The Core keeps its own copy of that loop rather than becoming a `Deployable` — *not* being one is exactly what keeps it un-removable, with no special case anywhere. Placement feedback is a **modeless, always-on ghost**: no toggle, no binding, no "placement mode" to enter — a grid-snapped W×H ghost with a validity tint (space empty, supported, in reach, not in a buffer zone) draws whenever the selected hotbar item is placeable, and nothing draws when it is not. `Player.placement_size(item_id)` is the whole question; `ZERO` means "not placeable". The power coverage overlay (3.4) joins the same ghost for powered machines.

**Support is a direction bitmask** (`@export_flags("Up","Right","Down","Left")` → 1/2/4/8), not a fixed rule: a torch is all four (mounts on a wall, a floor *or* a ceiling), a ceiling lamp or turret is `1` (Up), and `0` opts out entirely — that deployable never pops. This generalizes 2.7's cardinal-adjacency placement rule rather than replacing it, and one **static** predicate (`Deployable.is_supported_at`, terrain injected) serves both placement validity and the post-mine re-check, so the two cannot drift.
- **Support means a solid TILE neighbour — a deployable never holds up another deployable.** Chain depth is therefore 1 and cascades are a rare special case rather than the norm. If ladders want to stack on each other, that second clause lands at 3.5.
- **One supported cell holds the whole footprint up.** A 2×2 resting a single corner on a ledge is standing, not floating — anything stricter would make big machines unplaceable on real terrain.
- Placement asks the other four questions (editable, air, unoccupied, clear of the player) **per cell**, then support **once for the footprint** — `Player.can_place_at`, with `size`/`support_dirs` **defaulted** to a 1×1 that mounts anywhere, which is the block rule unchanged. That default is why every block call site stayed a three-argument call and the 2.7 behaviour is preserved by construction rather than by re-testing.

**One drop path.** A removal swing, a mob destroying it (`hp <= 0`) and lost support all converge on `pop_to_pickup()`. **Nothing the player built is ever destroyed outright** — it falls on the floor as a pickup carrying `grants_xp = false` ([progression.md](progression.md): place → remove → place must not be a looting-XP fountain). So a wave that eats your torch line costs you a walk rather than the torches. `pop_to_pickup` is **idempotent** and frees its cells **eagerly**, both for the reasons in [player-combat.md](player-combat.md) §Un-deploying.

The **2.7 torch was a one-cell special case that landed before this base existed** and folded in here at 3.1 — it already registered in the entity dict and was placed/removed through the same player verbs ([terrain.md](terrain.md) §Lighting, [player-combat.md](player-combat.md) §Placement / §Un-deploying). It stays at `scripts/terrain/torch.gd`: this doc owns the *base*, terrain.md owns *that torch as a light source*.

## Support & popping (3.1)
`Automation` connects **one handler to both `Terrain.tile_changed` and `Terrain.entity_changed`** (the `Waves` listener precedent). Mine the tile a torch is mounted on and the torch drops as a pickup instead of hanging in mid-air.

**Cost: O(1) per changed cell.** A deployable is only affected by a tile it *touches* and is registered per occupied cell, so the handler probes exactly **five cells** (`pos` + 4 cardinal neighbours) with `get_entity` and enqueues the hits. `get_entity_cells()` is never called, and world gen costs **zero** because `set_cell_raw` emits no signal at all.

❗️**The queue is a work queue, not a debounce timer, and it is required even at chain depth 1.** A support check is four `is_solid` calls, not a 57 ms field solve ([enemies.md](enemies.md)) — there is nothing to amortize. What needs taming is **re-entrancy**: `pop_to_pickup` calls `remove_entity` per cell, which emits `entity_changed`, which lands straight back in the same handler. So the handler *only enqueues* (array + dedupe dict) and `_process` drains with `while not _queue.is_empty()`. Pops during the drain append to the array being drained — **that append is the cascade**; recursion would blow the stack on a long chain and is never used. Idempotency comes from `pop_to_pickup`'s own flag, so a machine queued through four of its cells still drops one item.

Termination is provable — every step either does nothing or permanently removes one deployable, and only a removal can enqueue more — and a debug-only `assert(guard < MAX_DRAIN_STEPS)` backstops a future predicate that breaks the argument. Coalescing is the dedupe dict: fifty changes around one torch cost one check.

`Automation.reset_run()` clears the queue and is called from `main.gd`'s restart, per tech-design.md's standing convention. ❗️A cell surviving a restart would re-check something else entirely in the new world.

## Categories
- **Miner** — placed on deposit tiles; extracts from `reserve` every N ticks into its output slot. Exhausted deposits become air ([terrain.md](terrain.md)), so a miner whose harvest tiles have all emptied shows an alert state (icon/toast) prompting removal.
  - ❗️**"On deposit tiles" means its HARVEST AREA, not its footprint.** All five `*_deposit` materials are `is_solid`, and `Terrain.place_entity` rejects a solid cell — the "entity cells are air" invariant is baked into three places in `terrain.gd` (the `place_entity` guard plus two asserts) and two consumers depend on it by name (`Enemy._attackable_entity`, [enemies.md](enemies.md) §Locomotion). **Do not relax `place_entity`.** 3.1 records this rather than resolving it; 3.3 gives the Miner a separate `harvest_cells()` alongside its air-cell footprint.
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

UI: coverage circles drawn with the placement ghost + a **dedicated hotkey toggling a persistent power overlay anytime** (color-coded per grid, supply/demand readouts per generator); lightning icon on unpowered machines. (Screen inventory owned by [ui.md](ui.md).)

Perf: the narrow world caps factory size; hundreds of conveyors at 10 Hz is nothing, even on web.
