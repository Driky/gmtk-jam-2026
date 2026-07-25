# Player & Combat

Owner of: player controller, mining interaction, combat systems, death/respawn.

## Controller & stats
`CharacterBody2D`, standard platformer controller with coyote time + jump buffer (30 minutes that make the whole jam feel better). Stats read from `Progression`: max HP, max mana, move speed.

## Tools & mining
Hold-to-mine on the targeted tile within reach radius; calls `Terrain.damage_tile` per tick with tool power. Tool tiers gate deeper blocks via `min_tool_tier` ([terrain.md](terrain.md)).

## Combat — three styles, two systems (locked)
- **Melee:** animated `Area2D` hitbox arc in aim direction; damage + small knockback.
- **Projectiles — ONE system shared by ranged weapons, spells, and turrets:** a pooled projectile scene parameterized by a `ProjectileStats` Resource (speed, damage, gravity, pierce, AoE, sprite, on-hit effect). Ranged consumes ammo items; spells consume mana; turrets ([automation.md](automation.md)) reuse it verbatim. One implementation serves three features.

## Death & respawn
Carried inventory drops into a **loot bag** entity at the death position (persists, retrievable); respawn at the Core — or a crafted **beacon** override — after a short timer. Hotbar-equipped items kept (kindness tweak; confirm during tuning). Core destruction, not player death, is the game-over condition ([plan.md](../plan.md)).
