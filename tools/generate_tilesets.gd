@tool
## Placeholder tileset generator: palette-remaps the shape-master template into
## one PNG per material, then builds terrain_tileset.tres (atlas sources,
## physics/occlusion polygons, custom data layers) from data/materials.gd.
## Run via tools/generate_tilesets.sh — the .tres phase needs the PNGs imported
## first, hence two passes. Owning doc: docs/systems/pipeline.md
extends SceneTree

const TileLayoutScript := preload("res://scripts/terrain/tile_layout.gd")
const MaterialsScript := preload("res://data/materials.gd")

const TEMPLATE_PATH := "res://assets/templates/terrain_template_16.png"
const TILES_DIR := "res://assets/generated/tiles"
const TILESET_PATH := "res://assets/generated/terrain_tileset.tres"

## Custom data layers mirror the materials.gd config (docs/systems/terrain.md).
const CUSTOM_DATA_LAYERS := [
	["material_id", TYPE_STRING],
	["hardness", TYPE_FLOAT],
	["drop_id", TYPE_STRING],
	["drop_count", TYPE_INT],
	["is_solid", TYPE_BOOL],
	["is_ore", TYPE_BOOL],
	["is_deposit", TYPE_BOOL],
	["min_tool_tier", TYPE_INT],
]

## Fraction of an edge's opaque pixels that must be border-colored for the
## edge to count as "open" when re-deriving the mask table (drift guard).
const EDGE_BORDER_THRESHOLD := 0.4


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ok := false
	if "--pngs" in args:
		ok = _generate_pngs()
	elif "--tileset" in args:
		ok = _build_tileset()
	else:
		push_error("Usage: godot --headless --script res://tools/generate_tilesets.gd -- [--pngs|--tileset]")
	quit(0 if ok else 1)


# --- PNG phase ---------------------------------------------------------------


func _generate_pngs() -> bool:
	var template := Image.load_from_file(ProjectSettings.globalize_path(TEMPLATE_PATH))
	if template == null:
		push_error("Cannot load template: " + TEMPLATE_PATH)
		return false

	var palette := _extract_palette(template)
	_snap_to_palette(template, palette)
	if not _verify_layout(template, palette[0]):
		return false

	var dir_ok := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TILES_DIR))
	if dir_ok != OK:
		push_error("Cannot create " + TILES_DIR)
		return false

	var lum_max: float = palette[palette.size() - 1].get_luminance()
	var count := 0
	for id: String in MaterialsScript.ORDER:
		var mat: Dictionary = MaterialsScript.MATERIALS[id]
		if mat.has("sheet"):
			continue
		var base: Color = mat.base_color
		var ramp := {}
		for pal_color: Color in palette:
			var v := base.v * pal_color.get_luminance() / lum_max
			ramp[pal_color.to_rgba32()] = Color.from_hsv(base.h, base.s, v)
		var out := Image.create_empty(template.get_width(), template.get_height(), false, Image.FORMAT_RGBA8)
		for y in template.get_height():
			for x in template.get_width():
				var p := template.get_pixel(x, y)
				if p.a == 0.0:
					continue
				var mapped: Color = ramp[Color(p.r, p.g, p.b, 1.0).to_rgba32()]
				mapped.a = p.a
				out.set_pixel(x, y, mapped)
		var path := "%s/tile_%s.png" % [TILES_DIR, id]
		if out.save_png(ProjectSettings.globalize_path(path)) != OK:
			push_error("Failed to save " + path)
			return false
		count += 1
	print("Generated %d tile sheets in %s" % [count, TILES_DIR])
	return true


## Unique opaque colors, sorted darkest → brightest.
func _extract_palette(img: Image) -> Array[Color]:
	var seen := {}
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a > 0.0:
				seen[Color(p.r, p.g, p.b, 1.0).to_rgba32()] = true
	var palette: Array[Color] = []
	for rgba: int in seen:
		palette.append(Color.hex(rgba))
	palette.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
	return palette


## Nearest-of-palette snap so stray anti-aliased/compressed pixels can't go
## unmapped (pipeline.md). A pristine template is a no-op.
func _snap_to_palette(img: Image, palette: Array[Color]) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a == 0.0:
				continue
			var best := palette[0]
			var best_d := 1e9
			for pal in palette:
				var d: float = (
					(p.r - pal.r) ** 2 + (p.g - pal.g) ** 2 + (p.b - pal.b) ** 2
				)
				if d < best_d:
					best_d = d
					best = pal
			img.set_pixel(x, y, Color(best.r, best.g, best.b, p.a))
	# Palettes stay small; snapping 234x90 pixels is instant.


## Drift guard: re-derive each LAYOUT cell's neighbor mask from the template's
## border edges and assert the pinned table still matches.
func _verify_layout(img: Image, border_color: Color) -> bool:
	var pitch: int = TileLayoutScript.TILE_SIZE + TileLayoutScript.SEPARATION
	var border := border_color.to_rgba32()
	for mask: int in TileLayoutScript.LAYOUT:
		for coord: Vector2i in TileLayoutScript.LAYOUT[mask]:
			var ox := coord.x * pitch
			var oy := coord.y * pitch
			var derived := 0
			var edges := [
				[1, Vector2i(ox, oy), Vector2i(1, 0)],  # N
				[2, Vector2i(ox + 15, oy), Vector2i(0, 1)],  # E
				[4, Vector2i(ox, oy + 15), Vector2i(1, 0)],  # S
				[8, Vector2i(ox, oy), Vector2i(0, 1)],  # W
			]
			for edge: Array in edges:
				var border_px := 0
				var opaque_px := 0
				for i in 16:
					var pos: Vector2i = edge[1] + edge[2] * i
					var p := img.get_pixel(pos.x, pos.y)
					if p.a == 0.0:
						continue
					opaque_px += 1
					if Color(p.r, p.g, p.b, 1.0).to_rgba32() == border:
						border_px += 1
				if opaque_px == 0 or float(border_px) / opaque_px <= EDGE_BORDER_THRESHOLD:
					derived |= edge[0]
			if derived != mask:
				push_error(
					"Template drift at cell %s: LAYOUT says mask %d, template borders say %d. LAYOUT must never be restructured (docs/systems/terrain.md)."
					% [coord, mask, derived]
				)
				return false
	return true


# --- TileSet phase -----------------------------------------------------------


func _build_tileset() -> bool:
	var tile_size: int = TileLayoutScript.TILE_SIZE
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.add_occlusion_layer()
	for i in CUSTOM_DATA_LAYERS.size():
		ts.add_custom_data_layer()
		ts.set_custom_data_layer_name(i, CUSTOM_DATA_LAYERS[i][0])
		ts.set_custom_data_layer_type(i, CUSTOM_DATA_LAYERS[i][1])

	var square := PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)
	])

	for source_id in MaterialsScript.ORDER.size():
		var id: String = MaterialsScript.ORDER[source_id]
		var mat: Dictionary = MaterialsScript.MATERIALS[id]
		var sheet_id: String = mat.get("sheet", id)
		var texture: Texture2D = load("%s/tile_%s.png" % [TILES_DIR, sheet_id])
		if texture == null:
			push_error("Missing generated sheet for '%s' — run the --pngs phase (+ import) first." % sheet_id)
			return false
		var src := TileSetAtlasSource.new()
		src.resource_name = id
		src.texture = texture
		src.separation = Vector2i(TileLayoutScript.SEPARATION, TileLayoutScript.SEPARATION)
		src.texture_region_size = Vector2i(tile_size, tile_size)
		# Attach to the TileSet BEFORE writing tile data — TileData resolves
		# custom-data/physics layers through its owning TileSet.
		ts.add_source(src, source_id)
		for mask: int in TileLayoutScript.LAYOUT:
			for coord: Vector2i in TileLayoutScript.LAYOUT[mask]:
				src.create_tile(coord)
				var td := src.get_tile_data(coord, 0)
				td.set_custom_data("material_id", id)
				td.set_custom_data("hardness", mat.hardness)
				td.set_custom_data("drop_id", mat.drop_id)
				td.set_custom_data("drop_count", mat.drop_count)
				td.set_custom_data("is_solid", mat.is_solid)
				td.set_custom_data("is_ore", mat.is_ore)
				td.set_custom_data("is_deposit", mat.is_deposit)
				td.set_custom_data("min_tool_tier", mat.min_tool_tier)
				if mat.is_solid:
					td.add_collision_polygon(0)
					td.set_collision_polygon_points(0, 0, square)
					var occluder := OccluderPolygon2D.new()
					occluder.polygon = square
					td.set_occluder(0, occluder)

	if ResourceSaver.save(ts, TILESET_PATH) != OK:
		push_error("Failed to save " + TILESET_PATH)
		return false
	print("Built %s: %d sources x 48 tiles" % [TILESET_PATH, MaterialsScript.ORDER.size()])
	return true
