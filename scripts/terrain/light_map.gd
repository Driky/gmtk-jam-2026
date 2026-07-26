## Renders LightGrid over the world (2.7).
##
## The whole trick is here: the light grid is uploaded as a texture at ONE
## PIXEL PER TILE and drawn stretched over the region with LINEAR filtering and
## MULTIPLY blending. Bilinear interpolation between tile centres is what turns
## a blocky grid into Terraria's soft, seeping falloff — for one draw call, no
## shadow passes, and no per-light cost at all. A hundred torches render
## exactly as cheaply as one.
##
## Owning doc: docs/systems/terrain.md
extends Node2D

const TILE := TileLayout.TILE_SIZE
## Above every world node (tiles and Backdrop sit at 0 and -100). The HUD and
## the other UI are CanvasLayers, so they own their own canvas and this cannot
## reach them.
const Z_INDEX := 100
## Daylight. Faintly cool so torchlight reads warm against it without either
## being a saturated colour.
const SKY_COLOR := Color(0.95, 0.97, 1.0)

var grid := LightGrid.new()

var _image: Image = null
var _texture: ImageTexture = null
var _rect := Rect2()


func _ready() -> void:
	top_level = true # World space, independent of Main's transform.
	z_index = Z_INDEX
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # The smoothing IS the look.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = mat


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	# GENERATING writes ~240k cells behind a loading bar; solving light against
	# a half-built world is pure waste and visibly starves the row sweep.
	if Game.state == Game.State.GENERATING:
		return
	_resize_to(camera)
	Perf.begin(&"light.sample")
	grid.sample_terrain(Terrain, Vector2i((_rect.position / TILE).floor()))
	Perf.end()
	Perf.begin(&"light.solve")
	grid.clear()
	# Daylight first, then point sources — order is irrelevant, every seed is a
	# max() against what is already there.
	grid.add_sky(SKY_COLOR)
	for node: Node in get_tree().get_nodes_in_group(&"light_source"):
		var source := node as Node2D
		if source == null or not source.visible:
			continue # A hidden source is off — a dead player stops glowing for free.
		var tint: Variant = source.get(&"light_color")
		grid.add_source(
			Vector2i((source.global_position / TILE).floor()),
			tint if tint is Color else Color.WHITE,
		)
	grid.solve()
	Perf.end()
	Perf.begin(&"light.upload")
	_upload()
	Perf.end()
	queue_redraw()


func _resize_to(camera: Camera2D) -> void:
	var world_size := get_viewport_rect().size / camera.zoom
	var cols := ceili(world_size.x / TILE) + LightGrid.MARGIN * 2 + 1
	var rows := ceili(world_size.y / TILE) + LightGrid.MARGIN * 2 + 1
	var top_left := camera.get_screen_center_position() - world_size * 0.5
	var origin := (top_left / TILE).floor() - Vector2(LightGrid.MARGIN, LightGrid.MARGIN)
	_rect = Rect2(origin * TILE, Vector2(cols, rows) * TILE)
	if cols == grid.cols and rows == grid.rows:
		return
	grid.resize(cols, rows)
	_image = null


## One texel per tile. Texel i's centre lands at (i + 0.5) × TILE from the
## rect's origin — exactly the centre of tile origin + i — so the bilinear
## ramp between two texels is the ramp between two tile centres, with no
## half-pixel correction anywhere.
func _upload() -> void:
	var bytes := grid.to_bytes()
	if _image == null:
		_image = Image.create_from_data(grid.cols, grid.rows, false, Image.FORMAT_RGB8, bytes)
		_texture = ImageTexture.create_from_image(_image)
		return
	_image.set_data(grid.cols, grid.rows, false, Image.FORMAT_RGB8, bytes)
	_texture.update(_image)


func _draw() -> void:
	if _texture == null:
		return
	draw_texture_rect(_texture, _rect, false)
