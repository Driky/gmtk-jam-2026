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
## deposits reuse their ore's sheet, no extra art).
const MATERIALS: Dictionary = {
	"grass": {
		base_color = Color(0.36, 0.65, 0.26), hardness = 1.0, drop_id = "dirt",
		drop_count = 1, min_tool_tier = 1, is_solid = true, is_ore = false, is_deposit = false,
	},
	"dirt": {
		base_color = Color(0.56, 0.4, 0.26), hardness = 1.0, drop_id = "dirt",
		drop_count = 1, min_tool_tier = 1, is_solid = true, is_ore = false, is_deposit = false,
	},
	"stone": {
		base_color = Color(0.5, 0.5, 0.52), hardness = 2.0, drop_id = "stone",
		drop_count = 1, min_tool_tier = 2, is_solid = true, is_ore = false, is_deposit = false,
	},
	"ice_stone": {
		base_color = Color(0.62, 0.78, 0.9), hardness = 3.0, drop_id = "ice_stone",
		drop_count = 1, min_tool_tier = 3, is_solid = true, is_ore = false, is_deposit = false,
	},
	"magma_stone": {
		base_color = Color(0.55, 0.2, 0.14), hardness = 4.0, drop_id = "magma_stone",
		drop_count = 1, min_tool_tier = 4, is_solid = true, is_ore = false, is_deposit = false,
	},
	"wood": {
		base_color = Color(0.52, 0.34, 0.18), hardness = 1.5, drop_id = "wood",
		drop_count = 1, min_tool_tier = 1, is_solid = true, is_ore = false, is_deposit = false,
	},
	"bedrock": {
		base_color = Color(0.2, 0.2, 0.23), hardness = 999.0, drop_id = "",
		drop_count = 0, min_tool_tier = 99, is_solid = true, is_ore = false, is_deposit = false,
	},
	"coal": {
		base_color = Color(0.28, 0.28, 0.32), hardness = 1.5, drop_id = "coal",
		drop_count = 1, min_tool_tier = 1, is_solid = true, is_ore = true, is_deposit = false,
	},
	"copper": {
		base_color = Color(0.8, 0.45, 0.2), hardness = 1.5, drop_id = "copper",
		drop_count = 1, min_tool_tier = 1, is_solid = true, is_ore = true, is_deposit = false,
	},
	"iron": {
		base_color = Color(0.76, 0.71, 0.66), hardness = 2.5, drop_id = "iron",
		drop_count = 1, min_tool_tier = 2, is_solid = true, is_ore = true, is_deposit = false,
	},
	"gold": {
		base_color = Color(0.9, 0.75, 0.25), hardness = 3.5, drop_id = "gold",
		drop_count = 1, min_tool_tier = 3, is_solid = true, is_ore = true, is_deposit = false,
	},
	"magmatite": {
		base_color = Color(0.95, 0.36, 0.1), hardness = 4.5, drop_id = "magmatite",
		drop_count = 1, min_tool_tier = 4, is_solid = true, is_ore = true, is_deposit = false,
	},
	"coal_deposit": {
		base_color = Color(0.28, 0.28, 0.32), hardness = 1.5, drop_id = "coal",
		drop_count = 1, min_tool_tier = 1, is_solid = true, is_ore = true, is_deposit = true,
		sheet = "coal",
	},
	"copper_deposit": {
		base_color = Color(0.8, 0.45, 0.2), hardness = 1.5, drop_id = "copper",
		drop_count = 1, min_tool_tier = 1, is_solid = true, is_ore = true, is_deposit = true,
		sheet = "copper",
	},
	"iron_deposit": {
		base_color = Color(0.76, 0.71, 0.66), hardness = 2.5, drop_id = "iron",
		drop_count = 1, min_tool_tier = 2, is_solid = true, is_ore = true, is_deposit = true,
		sheet = "iron",
	},
	"gold_deposit": {
		base_color = Color(0.9, 0.75, 0.25), hardness = 3.5, drop_id = "gold",
		drop_count = 1, min_tool_tier = 3, is_solid = true, is_ore = true, is_deposit = true,
		sheet = "gold",
	},
	"magmatite_deposit": {
		base_color = Color(0.95, 0.36, 0.1), hardness = 4.5, drop_id = "magmatite",
		drop_count = 1, min_tool_tier = 4, is_solid = true, is_ore = true, is_deposit = true,
		sheet = "magmatite",
	},
	"wall": {
		base_color = Color(0.66, 0.66, 0.72), hardness = 3.0, drop_id = "wall",
		drop_count = 1, min_tool_tier = 1, is_solid = true, is_ore = false, is_deposit = false,
	},
}
