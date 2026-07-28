## Material config — single source of truth for every terrain tile type.
## Owning doc: docs/systems/pipeline.md; tile inventory in docs/systems/terrain.md.
## Adding a tile type = one entry here + rerun tools/generate_tilesets.sh.
## Numbers are Day-1 stubs; balancing pass is Day 4.
class_name Materials

## Index in ORDER = TileSet atlas source id (deterministic across reruns).
const ORDER: Array[String] = [
	"grass",
	"dirt",
	"stone",
	"ice_stone",
	"magma_stone",
	"wood",
	"bedrock",
	"coal",
	"copper",
	"iron",
	"gold",
	"magmatite",
	"coal_deposit",
	"copper_deposit",
	"iron_deposit",
	"gold_deposit",
	"magmatite_deposit",
	"wall",
]

## Per material: base_color (placeholder ramp source), hardness, drop_id
## ("" = no drop), drop_count, min_tool_tier (99 = unminable), is_solid,
## is_ore, is_deposit, optional sheet (reuse another material's PNG —
## deposits reuse their ore's sheet, no extra art). Deposits also carry
## base_reserve (starting ore reserve; read by Terrain, not baked into the
## TileSet).
##
## ❗️**The tier gate starts at the CRYSTAL band, not the stone band (3.6b)** —
## `stone` and `iron` (and `iron_deposit`, which mirrors its ore like every other
## deposit here) are tier 1, so a starting `pickaxe_t1` can reach every input the
## hand recipes are priced in. `ice_stone`/`gold` (3) and `magma_stone`/`magmatite`
## (4) are untouched, so the gate moved rather than disappeared
## ([terrain.md](../docs/systems/terrain.md) §Tile inventory owns the rule).
const MATERIALS: Dictionary = {
	"grass": {
		base_color = Color(0.36, 0.65, 0.26),
		hardness = 1.0,
		drop_id = "dirt",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = false,
		is_deposit = false,
	},
	"dirt": {
		base_color = Color(0.56, 0.4, 0.26),
		hardness = 1.0,
		drop_id = "dirt",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = false,
		is_deposit = false,
	},
	"stone": {
		base_color = Color(0.5, 0.5, 0.52),
		hardness = 2.0,
		drop_id = "stone",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = false,
		is_deposit = false,
	},
	"ice_stone": {
		base_color = Color(0.62, 0.78, 0.9),
		hardness = 3.0,
		drop_id = "ice_stone",
		drop_count = 1,
		min_tool_tier = 3,
		is_solid = true,
		is_ore = false,
		is_deposit = false,
	},
	"magma_stone": {
		base_color = Color(0.55, 0.2, 0.14),
		hardness = 4.0,
		drop_id = "magma_stone",
		drop_count = 1,
		min_tool_tier = 4,
		is_solid = true,
		is_ore = false,
		is_deposit = false,
	},
	"wood": {
		base_color = Color(0.52, 0.34, 0.18),
		hardness = 1.5,
		drop_id = "wood",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = false,
		is_deposit = false,
	},
	"bedrock": {
		base_color = Color(0.2, 0.2, 0.23),
		hardness = 999.0,
		drop_id = "",
		drop_count = 0,
		min_tool_tier = 99,
		is_solid = true,
		is_ore = false,
		is_deposit = false,
	},
	"coal": {
		base_color = Color(0.28, 0.28, 0.32),
		hardness = 1.5,
		drop_id = "coal",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = true,
		is_deposit = false,
	},
	"copper": {
		base_color = Color(0.8, 0.45, 0.2),
		hardness = 1.5,
		drop_id = "copper",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = true,
		is_deposit = false,
	},
	"iron": {
		base_color = Color(0.76, 0.71, 0.66),
		hardness = 2.5,
		drop_id = "iron",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = true,
		is_deposit = false,
	},
	"gold": {
		base_color = Color(0.9, 0.75, 0.25),
		hardness = 3.5,
		drop_id = "gold",
		drop_count = 1,
		min_tool_tier = 3,
		is_solid = true,
		is_ore = true,
		is_deposit = false,
	},
	"magmatite": {
		base_color = Color(0.95, 0.36, 0.1),
		hardness = 4.5,
		drop_id = "magmatite",
		drop_count = 1,
		min_tool_tier = 4,
		is_solid = true,
		is_ore = true,
		is_deposit = false,
	},
	"coal_deposit": {
		base_color = Color(0.28, 0.28, 0.32),
		hardness = 1.5,
		drop_id = "coal",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = true,
		is_deposit = true,
		base_reserve = 50,
		sheet = "coal",
	},
	"copper_deposit": {
		base_color = Color(0.8, 0.45, 0.2),
		hardness = 1.5,
		drop_id = "copper",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = true,
		is_deposit = true,
		base_reserve = 50,
		sheet = "copper",
	},
	"iron_deposit": {
		base_color = Color(0.76, 0.71, 0.66),
		hardness = 2.5,
		drop_id = "iron",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = true,
		is_deposit = true,
		base_reserve = 50,
		sheet = "iron",
	},
	"gold_deposit": {
		base_color = Color(0.9, 0.75, 0.25),
		hardness = 3.5,
		drop_id = "gold",
		drop_count = 1,
		min_tool_tier = 3,
		is_solid = true,
		is_ore = true,
		is_deposit = true,
		base_reserve = 50,
		sheet = "gold",
	},
	"magmatite_deposit": {
		base_color = Color(0.95, 0.36, 0.1),
		hardness = 4.5,
		drop_id = "magmatite",
		drop_count = 1,
		min_tool_tier = 4,
		is_solid = true,
		is_ore = true,
		is_deposit = true,
		base_reserve = 50,
		sheet = "magmatite",
	},
	"wall": {
		base_color = Color(0.66, 0.66, 0.72),
		hardness = 3.0,
		drop_id = "wall",
		drop_count = 1,
		min_tool_tier = 1,
		is_solid = true,
		is_ore = false,
		is_deposit = false,
	},
}

## XP for collecting one of an item — the "looting" channel
## ([progression.md](../docs/systems/progression.md) owns the rule; this is its
## data). Deliberately ONE compact table rather than a field on each MATERIALS
## entry: it's the curve, and the Day-4 balance pass wants to read it top to
## bottom in one glance.
##
## Keyed by ITEM id (a drop id), not tile id — which is why deposits are absent:
## they drop their base ore and are never collected as themselves. An id with no
## entry is worth 0, so mob drops and authored items opt in rather than leak XP.
##
## Shape: ore beats rock, and rarer ore beats common ore, by a wide margin. This
## is the channel that pays for digging deep, so the top of it has to be worth
## leaving the Core for.
const LOOT_XP: Dictionary = {
	dirt = 1.0,
	stone = 1.0,
	wood = 2.0,
	ice_stone = 2.0,
	magma_stone = 2.0,
	wall = 2.0,
	coal = 4.0,
	copper = 6.0,
	iron = 12.0,
	gold = 25.0,
	magmatite = 40.0,
}


## Loot XP for one unit of `id`; 0 for anything not in the table.
static func loot_xp(id: String) -> float:
	var value: float = LOOT_XP.get(id, 0.0)
	return value
