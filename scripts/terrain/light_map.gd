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

## A whole solve costs ~9 ms, which is over half a frame — so it is spread
## across frames instead: one phase seeds, four run two sweeps each, one
## uploads. Six frames ≈ 100 ms, i.e. the light refreshes at ~10 Hz with no
## single frame paying more than about 2 ms. Terraria updates lighting on a
## similar cadence; the bilinear upscale and the 16-tile margin between them
## make the latency invisible.
const SWEEPS_PER_PHASE := 2
const SWEEP_PHASES := LightGrid.SWEEPS / SWEEPS_PER_PHASE
const PHASES := SWEEP_PHASES + 2 # + seed + upload.

var grid := LightGrid.new()

var _image: Image = null
var _texture: ImageTexture = null
## Latched at seed time, NOT read live: the grid holds light for the region it
## was sampled for, so it must be drawn where it was computed. Using the live
## camera rect instead would slide a stale solve across the world as you walk.
var _rect := Rect2()
var _phase := 0
## The first solve runs whole, in one frame. Amortizing from cold would show
## ~100 ms of unlit (i.e. fully bright) world at the moment the loading screen
## hides — the one frame where a 9 ms cost is free and a flash is not.
var _primed := false


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
	# Hidden means "full bright": with no multiply pass the world renders unlit,
	# which is exactly the debug view (ui.md). Solving while invisible would
	# burn ~2 ms a frame to produce a texture nobody samples, and dropping
	# _primed makes switching back re-solve whole rather than fading in.
	if not visible:
		_primed = false
		return
	if not _primed:
		_primed = true
		_seed(camera)
		Perf.begin(&"light.solve")
		grid.solve()
		Perf.end()
		_publish()
		return
	if _phase == 0:
		_seed(camera)
	elif _phase <= SWEEP_PHASES:
		Perf.begin(&"light.solve")
		var first := (_phase - 1) * SWEEPS_PER_PHASE
		for i in SWEEPS_PER_PHASE:
			grid.sweep(first + i)
		Perf.end()
	else:
		_publish()
	_phase = (_phase + 1) % PHASES


## Phase 0: re-aim the region at the camera, read the world, lay down every
## source. Everything after this is pure arithmetic on the snapshot, which is
## what makes the remaining phases safe to spread across frames.
func _seed(camera: Camera2D) -> void:
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
	Perf.end()


func _publish() -> void:
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
