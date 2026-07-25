## Biome band tables for world generation: base material, cave threshold, ore
## scatter rates, deposit blob specs per depth band. All numbers are Day-1
## stubs, balanced Day 4. Owning doc: docs/systems/world-gen.md
class_name Biomes

## row_begin inclusive, row_end exclusive. cave_threshold compares against
## noise in [-1, 1] — 2.0 means "never carves". ores maps material → per-cell
## probability. Deposit size is (min, max) cells per blob.
const BANDS: Array[Dictionary] = [
	{
		name = "surface",
		row_begin = 0,
		row_end = 40,
		material = "dirt",
		cave_threshold = 2.0,
		ores = { },
		deposits = [],
	},
	{
		name = "dirt_caves",
		row_begin = 40,
		row_end = 250,
		material = "dirt",
		cave_threshold = 0.45,
		ores = { coal = 0.02, copper = 0.02 },
		deposits = [
			{ material = "coal_deposit", count = 4, size = Vector2i(8, 14) },
			{ material = "copper_deposit", count = 3, size = Vector2i(8, 14) },
		],
	},
	{
		name = "stone",
		row_begin = 250,
		row_end = 550,
		material = "stone",
		cave_threshold = 0.38,
		ores = { iron = 0.025 },
		deposits = [
			{ material = "iron_deposit", count = 4, size = Vector2i(10, 16) },
		],
	},
	{
		name = "crystal",
		row_begin = 550,
		row_end = 850,
		material = "ice_stone",
		cave_threshold = 0.35,
		ores = { gold = 0.02 },
		deposits = [
			{ material = "gold_deposit", count = 3, size = Vector2i(10, 16) },
		],
	},
	{
		name = "magma",
		row_begin = 850,
		row_end = 1200,
		material = "magma_stone",
		cave_threshold = 0.33,
		ores = { magmatite = 0.02 },
		deposits = [
			{ material = "magmatite_deposit", count = 3, size = Vector2i(12, 18) },
		],
	},
]
