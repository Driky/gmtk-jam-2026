## Autotile layout shared by the manual autotiler and the TileSet builder.
## Owning doc: docs/systems/terrain.md
class_name TileLayout

const TILE_SIZE := 16
const SEPARATION := 2
const GRID_COLUMNS := 13
const GRID_ROWS := 5

## 4-bit neighbor mask → 3 variant atlas coords on the template grid.
## Bits (set = same-type neighbor): 1 = N, 2 = E, 4 = S, 8 = W.
## Derived ONCE from terrain_template_16.png (an edge with the dashed black
## border = open side); the generator re-derives and asserts this on every run.
## Never restructure — all generated sheets share this layout by construction.
const LAYOUT: Dictionary = {
	0: [Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 3)],
	1: [Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3)],
	2: [Vector2i(9, 0), Vector2i(9, 1), Vector2i(9, 2)],
	3: [Vector2i(0, 4), Vector2i(2, 4), Vector2i(4, 4)],
	4: [Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0)],
	5: [Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2)],
	6: [Vector2i(0, 3), Vector2i(2, 3), Vector2i(4, 3)],
	7: [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
	8: [Vector2i(12, 0), Vector2i(12, 1), Vector2i(12, 2)],
	9: [Vector2i(1, 4), Vector2i(3, 4), Vector2i(5, 4)],
	10: [Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4)],
	11: [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)],
	12: [Vector2i(1, 3), Vector2i(3, 3), Vector2i(5, 3)],
	13: [Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2)],
	14: [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	15: [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
}


## Deterministic variant pick — NEVER change after the first save exists
## (variants would "pop" on load); pinned per docs/systems/terrain.md.
static func variant_hash(pos: Vector2i) -> int:
	return absi(pos.x * 0x9E3779B1 ^ pos.y * 0x85EBCA77) % 3
