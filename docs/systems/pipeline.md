# Asset & Audio Pipeline

Owner of: placeholder tileset generation, the TileSet builder, sourced assets, audio, what ships in the web export.

## What ships in the export (locked)
`scenes/dev/` holds scenes that exist to *look at something* rather than to run in the game — tileset/autotile previews, one-off visual harnesses. Nothing in the shipped game may reference them. Put dev scenes here rather than leaving them loose in `scenes/`.

**`.gitignore` does not keep anything out of the build.** `export_filter="all_resources"` sweeps every file on disk, tracked or not, so the web preset's `exclude_filter` is the only gate. It carries `addons/godot_ai/**`, `addons/gdUnit4/**`, `tests/**`, `scenes/dev/**`, `reports/**`, `build/**`. The last two were found shipping on 2026-07-26: gdUnit's HTML reports (a fresh `report_NNN/` per test run, so the build grew every time the suite ran) and the previous export packing its own output back into itself. Removing them took the `.pck` from 1.44 MB to 0.55 MB. **Anything a tool writes into the project directory ships until this filter says otherwise** — verify with `grep "Storing File" ` on the export log, not by assuming.

## Placeholder tilesets — template palette remap
The 48-frame template sheet (16×16 tiles, green/blue master) is committed at `res://assets/templates/terrain_template_16.png` and is the *shape master* for all terrain tiles. `res://tools/generate_tilesets.gd` (`@tool`, `Image` API, no external deps):
1. Extract the template's unique opaque colors, rank by luminance. **Snap with tolerance** (nearest-of-palette) so stray anti-aliased/compressed pixels don't go unmapped.
2. Per material, build a same-length shade ramp from its `base_color`: HSV with the base's hue/saturation, value = the base's value scaled by each rank's *relative* template luminance (brightest rank = the base color itself, so dark materials stay dark; the black outline maps to black). Alpha preserved verbatim.
3. Save to `res://assets/generated/tiles/tile_<material_id>.png` — same pixel layout as the template by construction. Generated output is always reproducible from config + template.

## TileSet builder
Same tool script consumes the material config — **`res://data/materials.gd`** (single source of truth), one entry per material:
```
"stone": { base_color: Color(0.5,0.5,0.52), hardness: 2.0, drop_id: "stone",
           min_tool_tier: 2, is_solid: true, is_ore: false, is_deposit: false }
```
It (a) generates the placeholder PNG, (b) builds/updates `res://assets/generated/terrain_tileset.tres`: one atlas source per material, per-tile full-square physics + occlusion polygons (only where `is_solid`), custom data layers mirroring config. No peering bits — manual autotiling ([terrain.md](terrain.md)) consumes the shared `LAYOUT` from `tile_layout.gd`. **Adding a tile type = one config entry + rerun.** Real art later replaces PNGs on the same layout without touching the pipeline. `Terrain` reads the same `materials.gd` for anything not baked into custom data — config authored exactly once.

## Sourced assets
CC/free packs + own edits for everything non-terrain (characters, deployables, UI). Keep `CREDITS.md` from hour one. Hunting grounds: Kenney (UI/SFX), itch.io CC0 packs, OpenGameArt; prefer 16px-native packs; palette-swap edits unify styles.

## Audio
CC music: 2 tracks (build-calm, wave-tense) crossfaded by `AudioBus` on phase change; CC SFX pack. Add mining/hit/place/pickup SFX early — they carry game feel. Web constraint: browsers block audio until first user input (itch's click-to-play covers it; don't autoplay on boot), and 4.3+ web Sample-mode audio lacks AudioEffect/reverb — keep the mix simple.
