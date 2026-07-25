# Save System

Owner of: save format, autosave rules, web persistence.

Full world persist between sessions. Single file at `user://save.dat` — JSON, or `var_to_bytes` binary if JSON grows too large. On web, `user://` maps to IndexedDB: works transparently, but browsers can wipe it — warn in UI.

## What serializes
- **Terrain — seed + diff (locked):** save the world seed + a dict of changed cells (mined, placed). Regenerate from seed, replay diffs — tiny files even after heavy digging. Depends on deterministic world gen ([world-gen.md](world-gen.md)) and on the pinned `variant_hash` ([terrain.md](terrain.md)).
- **Dynamic tile dict:** deposit `reserve` and `player_placed` must persist (dropping the latter would turn every reloaded wall into farmable XP — [terrain.md](terrain.md)); in-progress mining `damage` may be dropped.
- **Entities:** deployables (type id, pos, rotation, inventories, internal state e.g. craft progress), conveyor slot contents (stacks), loot bags.
- **Player:** position, stats, inventory, hotbar, equipment. **Progression:** XP, level, spent nodes. **Game:** wave number.

## Autosave rule (locked)
**Save only during BUILD_PHASE** — autosave at the start of every build phase; manual save allowed only during build. This dodges serializing live monsters entirely.
