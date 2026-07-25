# Player & Combat

Owner of: player controller, mining interaction, inventory & pickups, placement, combat systems, death/respawn.

## Controller & stats
`CharacterBody2D`, standard platformer controller with coyote time + jump buffer (30 minutes that make the whole jam feel better). Stats read from `Progression.get_stat`: max HP, max mana, move speed.

**HP/mana stub (1.7):** `current_hp` / `current_mana` on the player — clamped setters emitting `health_changed(current, max_value)` / `mana_changed(current, max_value)`, seeded from `Progression.get_stat` in `_ready`. Combat (Day 2) only mutates the fields; HUD binding is owned by [ui.md](ui.md).

**Locked numbers (1.6 — feel defaults, tune freely):** move 110 px/s instant (no accel) · gravity 1200, max fall 700 px/s (< 1 tile/frame at 60 fps — no tunneling) · jump −370 (~3.6-tile apex: clears 3, not 4) · coyote 0.10 s · jump buffer 0.12 s · collision box 12×22 px (fits 1-wide tunnels).

**Camera:** on the player scene; limits computed from `WorldConfig` (playable band × world height — never hardcoded pixels), position smoothing speed 8. Zoom cycling owned by [ui.md](ui.md).

## Tools & mining
Hold-to-mine on the targeted tile (under mouse) within **reach 4.5 tiles** (player center → tile center, no line-of-sight check); calls `Terrain.damage_tile` per physics tick with `tool_power × get_stat("mining_speed") × delta`. Tool tiers gate deeper blocks via `min_tool_tier` ([terrain.md](terrain.md)).

**Tool stub (1.6):** `tool_tier = 1`, `tool_power = 4.0` hardness/s as fields on the player — the equipment system (3.6/4.2) replaces them with equipped-tool stats.

**Feedback:** `MiningCursor` draws the hovered tile's outline (white actionable / red rejected — the buffer-zone cue) + a damage-ratio fill from `Terrain.tile_damaged`. HUD-proper feedback is 1.7.

## Inventory & pickups (locked)
- **Inventory:** pure data model (`Inventory`, RefCounted) — **40 slots, stack 99, hotbar = slots 0–9**, `selected_slot` + change signals for the HUD (1.7) and character screen (3.6). The player instance lives on the **`Items` autoload** (`Items.player_inventory`) so crafting-range queries (3.6) and save (4.3) never need a player reference.
- **Pickups:** plain Node2D (no physics body/Area2D — near-zero per-node web cost), tinted from the material's `base_color`; manual gravity 600 + settle on solid tiles; magnet at 40 px (200 px/s), collect at 12 px into the player inventory; leftover stays in-world when full; no despawn. If wave-time counts hurt web perf, add merge-on-settle or a cap (revisit Day 2).
- **Drop policy** (spawner owns it, hooked on `Terrain.drops_spawned`): **PLAYER and MONSTER sources spawn pickups; MACHINE never does** — machines buffer output internally ([automation.md](automation.md)).

## Placement (locked)
`place` puts the selected hotbar item down as a tile when the item id is a material id (1:1 self-drops — [terrain.md](terrain.md)). Validity: in reach + `can_player_edit` + target is air + no entity + not overlapping the player's collision box + **cardinally adjacent to ≥ 1 solid tile — no floating blocks**.

## Combat — three styles, two systems (locked)
- **Melee:** animated `Area2D` hitbox arc in aim direction; damage + small knockback.
- **Projectiles — ONE system shared by ranged weapons, spells, and turrets:** a pooled projectile scene parameterized by a `ProjectileStats` Resource (speed, damage, gravity, pierce, AoE, sprite, on-hit effect). Ranged consumes ammo items; spells consume mana; turrets ([automation.md](automation.md)) reuse it verbatim. One implementation serves three features.

## Death & respawn
Carried inventory drops into a **loot bag** entity at the death position (persists, retrievable); respawn at the Core — or a crafted **beacon** override — after a short timer. Hotbar-equipped items kept (kindness tweak; confirm during tuning). Core destruction, not player death, is the game-over condition ([plan.md](../plan.md)).
