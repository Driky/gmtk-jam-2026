# Player & Combat

Owner of: player controller, mining interaction, inventory & pickups, placement, combat systems, death/respawn.

## Controller & stats
`CharacterBody2D`, standard platformer controller with coyote time + jump buffer (30 minutes that make the whole jam feel better). Stats read from `Progression.get_stat`: max HP, max mana, move speed.

**HP/mana stub (1.7):** `current_hp` / `current_mana` on the player — clamped setters emitting `health_changed(current, max_value)` / `mana_changed(current, max_value)`, seeded from `Progression.get_stat` in `_ready`. Combat (Day 2) only mutates the fields; HUD binding is owned by [ui.md](ui.md).

**Locked numbers (1.6 — feel defaults, tune freely):** move 110 px/s instant (no accel) · gravity 1200, max fall 700 px/s (< 1 tile/frame at 60 fps — no tunneling) · jump −370 (~3.6-tile apex: clears 3, not 4) · coyote 0.10 s · jump buffer 0.12 s · collision box 12×22 px (fits 1-wide tunnels).

**Camera:** on the player scene; limits computed from `WorldConfig` (playable band × world height — never hardcoded pixels), position smoothing speed 8. Zoom cycling owned by [ui.md](ui.md).

## The use verb & item stats (locked, 2.5)
**LMB is one verb: use the active hotbar item.** A `SWING` item (tool, melee weapon, block, bare hand) mines the hovered tile *and* arcs at whatever is in front of you — both effects on every use, so there is no targeting rule for the player to infer. A `PROJECTILE` item fires instead. Placement stays on RMB.

**Every combat and mining number is an `ItemStats` Resource, never a constant on the player**: `use_kind`, `use_cooldown`, `mining_power`, `tool_tier`, `melee_damage`, `knockback`, and an optional `hitbox_scene` (+ `arc_degrees` / `active_window` for the default arc). That makes a tool a design space rather than a fixed upgrade curve — a fast, low-damage, high-knockback pickaxe is a "mine while shoving mobs off you" tool, and a heavy slow one is a weapon that also digs.

Resolution — `Items.stats_for(id)`, table in `data/item_defs.gd`: **authored `.tres` > `BLOCK_DEFAULT` > `BARE_HAND`**, never null, so no call site needs a "no item" branch. Keys are *any* item id, blocks included, so making one odd block a viable off-label weapon is a single resource with no schema change to `materials.gd`. Blocks sit a little above bare hands. Starters: bare hand mines 2.0 hardness/s, a block 3.0, `pickaxe_t1` 4.0 (the pre-2.5 flat value, so minute-one dig feel is unchanged). Tool tiers gate deeper blocks via `min_tool_tier` ([terrain.md](terrain.md)).

**Buff seam:** every read goes through an `effective_*` accessor that multiplies by `Progression.get_stat` (`mining_speed`, `melee_damage`, `knockback`; `swing_speed` *divides* `use_cooldown`). `get_stat` returns a neutral 1.0 for unknown names, so 3.7 buffs and any later debuff land without touching an item or a call site.

## Mining
Hold-to-mine on the targeted tile (under mouse) within **reach 4.5 tiles** (player center → tile center, no line-of-sight check); calls `Terrain.damage_tile` per physics tick with the item's effective mining power × delta.

**Feedback:** `MiningCursor` draws the hovered tile's outline (white actionable / red rejected — the buffer-zone cue) + a damage-ratio fill from `Terrain.tile_damaged`. HUD-proper feedback is 1.7.

## Inventory & pickups (locked)
- **Inventory:** pure data model (`Inventory`, RefCounted) — **40 slots, stack 99, hotbar = slots 0–9**, `selected_slot` + change signals for the HUD (1.7) and character screen (3.6). The player instance lives on the **`Items` autoload** (`Items.player_inventory`) so crafting-range queries (3.6) and save (4.3) never need a player reference.
- **Pickups:** plain Node2D (no physics body/Area2D — near-zero per-node web cost), tinted from the material's `base_color`; manual gravity 600 + settle on solid tiles; magnet at 40 px (200 px/s), collect at 12 px into the player inventory; leftover stays in-world when full; no despawn. If wave-time counts hurt web perf, add merge-on-settle or a cap (revisit Day 2).
- **Drop policy** (spawner owns it, hooked on `Terrain.drops_spawned`): **PLAYER and MONSTER sources spawn pickups; MACHINE never does** — machines buffer output internally ([automation.md](automation.md)).

## Placement (locked)
`place` puts the selected hotbar item down as a tile when the item id is a material id (1:1 self-drops — [terrain.md](terrain.md)). Validity: in reach + `can_player_edit` + target is air + no entity + not overlapping the player's collision box + **cardinally adjacent to ≥ 1 solid tile — no floating blocks**.

## Combat — three styles, two systems (locked)
- **Melee:** `Area2D` hitbox arc swept through the aim direction; damage + knockback, both from the item. **Instanced on equip, enabled on swing** — never instanced per swing; the swap is keyed on the hitbox *scene*, so cycling between two items that share the default arc can't interrupt a sweep. Default arc: 90° over a 0.15 s window at ~1.75 tiles' reach, **one hit per target per swing** (a 0.15 s window is ~9 physics frames — a naive per-frame poll would deal 9× damage). Bodies already overlapping when the arc switches on never emit `body_entered`, so frame 0 is polled: a mob standing on top of you is hittable. The hitbox reports the body; **the swinger resolves damage**, since only it knows which item swung and what `Progression` multiplies it by. Shape sets are indexed by swing **step**, so a combo (wide sweep, then narrow lunge) is a scene with two sets plus a caller passing step 1 — the combo *system* (input chaining, timing windows) is not built.
- **Projectiles — ONE system shared by ranged weapons, spells, and turrets:** a pooled projectile scene parameterized by a `ProjectileStats` Resource (speed, damage, knockback, gravity, lifetime, pierce, radius, colour). Ranged consumes ammo items; spells consume mana; turrets ([automation.md](automation.md)) reuse it verbatim. One implementation serves three features. Fixed pool of 32, instanced once — nothing is allocated or freed while shots fly, so a turret line can't allocate mid-wave; under saturation the round-robin steals the oldest shot rather than growing. Reached via `ProjectilePool.fire(...)`, a static entry point registered by the pool node itself, so turrets need no node path and the fixed autoload map in [tech-design.md](../tech-design.md) stays untouched. **`faction` picks the collision mask** (player-fired = world|enemies, monster-fired = world|player), which lets one Area2D do both jobs: anything with `take_damage` is a target, anything else is a stop — so terrain needs no separate raycast. A shot never hits its own `source`. `lifetime` is the backstop that guarantees a shot into open sky returns to the pool.
  - ❗️**`monitorable` must stay true on any combat area.** Setting it false silently stops an `Area2D` detecting `StaticBody2D` at all — `body_entered` never fires and `get_overlapping_bodies()` comes back empty — while `CharacterBody2D` keeps working, which is what makes it so easy to miss. Terrain is static tile bodies, so a projectile with `monitorable = false` flies through the world. Cost an hour to find; don't re-litigate it.
  - Contact is resolved by **polling `get_overlapping_bodies()`**, not `body_entered`, in both the projectile and the swing arc: pooled/reused areas depend on no signal timing that way, and a body already overlapping at launch needs no special case.

## Death & respawn
Carried inventory drops into a **loot bag** entity at the death position (persists, retrievable); respawn at the Core — or a crafted **beacon** override — after a short timer. Hotbar-equipped items kept (kindness tweak; confirm during tuning). Core destruction, not player death, is the game-over condition ([plan.md](../plan.md)).
