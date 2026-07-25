# Enemies & Waves

Owner of: mob capabilities, flow-field pathfinding, stair-digging, climbable profiles, aggro, wave composition, roster.

`CharacterBody2D` per monster, one base script + per-type `EnemyStats` Resource: HP, speed, damage, XP, drops, sprites, plus **locomotion capabilities** — `move_class` (ground/fly), `jump_height` (0 = walker, 1–2 = short-jumper, 4+ = big-jumper clearing low walls), `climb_speed` (0 = can't wall-climb), `is_biped` (gates climbable use), `dig_power`, `max_safe_fall` (tiles).

**Design principle: capabilities are speed, digging is correctness.** Every mob can dig, so no terrain state can ever soft-lock a mob; capabilities only make mobs faster.

## Pathfinding — two shared dig-weighted flow fields
Computed **once per movement class**, not per mob:
- **Ground field.** Dijkstra outward from the Core, gravity-aware directional costs: *down* through air ≈ free (falling); *up/sideways* through air traversable only adjacent to a solid surface (wall-climbers) or through a climbable; solid tiles cost `1 + hardness/reference_dig_power`; deployables cost by HP.
- **Air field.** Flyers: air = 1, solids = chew cost (~20 lines atop the ground-field infra).

Restricted to the active wave region (top ~150 rows ≈ 30k cells total — sub-millisecond); recomputed on terrain/deployable change, debounced ≤ 0.5 s. **Accepted simplification:** fields use *reference* capabilities, so a mob may be routed toward a climbable it can't use — the dig fallback absorbs the error. No per-capability field variants.

## Locomotion resolution (per mob, per frame)
Read the gradient at the current cell, resolve against capabilities in order: level/sideways → walk; up ≤ `jump_height` → jump; beyond → wall-climb if `climb_speed > 0`, or use a climbable if present and `is_biped`; otherwise → **chew** the blocker via `Terrain.damage_tile` (same pipeline as the player, gated by `dig_power`).

**Fall handling:** falls beyond `max_safe_fall` damage mobs. When the gradient points down an unsafe drop, the mob **stair-digs**: chew one block down-and-forward, descend, re-evaluate, repeat until the drop is safe. Flyers/big-jumpers with high `max_safe_fall` skip it. Pit traps stay viable: hard-walled spike pits cost real chew time, and fall damage enables drop-trap designs.

## Climbables (ladder, rope, fireman pole)
Deployables with a **directional climb profile**: ladder = up/down full speed; rope = up slow / down normal; pole = **down only, fast**. Ground field treats climbable cells as cheap vertical edges respecting direction. **Biped-only** for mobs — so player ladders are biped highways during waves (remove pre-wave, hide behind hatches, or favor poles, which mobs can never ascend). Deliberate emergent texture.

## Aggro
Per-monster threat table `{node: threat}`; damage received adds threat to the attacker (player or turret). Highest threat above threshold overrides the Core target (direct local chase + chew, no field); threat decays so mobs resume pushing the Core. Turrets naturally tank.

## Wave composition — reachability-adaptive
Budget `B(n) = base * growth^n` spent on types unlocked by wave number, spawned in trickles from both buffer zones ([world-gen.md](world-gen.md)). The wave manager reuses the ground field: at wave start, sample cost-to-Core at spawn cells vs. the untouched-terrain baseline (cached at world gen). This **fortification score** skews spawn weights toward **crawlers and flyers** when approaches are heavily sealed (even wave 1 in extreme cases); on open terrain flyers stay locked until mid waves. Tuning: the threshold must tolerate normal defenses (trigger around ratio > 3–4×); expose the score on the debug overlay for live calibration.

## Roster
Walker (baseline biped) · leaper (big-jumper) · digger (tanky, high dig power) · crawler (wall-climber + climbable user; counters trench bases) · flyer (mid-wave / fortification response) · spitter (stretch) · boss (stretch). Concurrent-spawn cap ~25 alive (perf).
