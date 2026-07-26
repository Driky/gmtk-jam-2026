## Per-tile propagated light — the Terraria model (2.7).
##
## A light value per tile over the on-screen region + a margin, propagated with
## four directional scanline sweeps (the same approximation Terraria uses in
## place of a true flood fill): light entering a cell is the best neighbour
## value attenuated by what that cell is made of — air barely dims it, rock
## kills it fast. Light therefore seeps around corners and dies inside walls,
## which is the shape a PointLight2D cannot make at any setting.
##
## Rendered as a 1-pixel-per-tile texture upscaled with LINEAR filtering and
## multiplied over the world: bilinear interpolation between tile centres IS
## the soft blobby falloff, for one draw call and no shadow passes.
##
## Owning doc: docs/systems/terrain.md
class_name LightGrid
extends RefCounted

## Per-tile survival factor. Air keeps most of the light (≈25 tiles of reach),
## rock kills it in a handful — that contrast is what makes a cave read as a
## cave rather than a disc.
const AIR_ATTEN := 0.91
const SOLID_ATTEN := 0.56
## Tiles of slack beyond the viewport, so a source just off-screen still bleeds
## in and the region edge never shows as a straight line.
const MARGIN := 16
## Sweep sets. One set already bends light around a corner (each sweep reads
## the previous one's output); a second cleans up concave pockets.
const PASSES := 2
## Beyond this many tiles of air, surviving daylight is under 1/255 and cannot
## change a single output byte — so the residual-sky term stops there.
const SKY_MAX_GAP := 64

var cols := 0
var rows := 0
var origin := Vector2i.ZERO

## Channels kept as separate flat arrays: PackedFloat32Array indexing is the
## fastest thing GDScript has, and one interleaved array costs a multiply per
## access in the innermost loop in the game.
var _r := PackedFloat32Array()
var _g := PackedFloat32Array()
var _b := PackedFloat32Array()
## Per-cell attenuation, sampled from terrain. Re-sampled only when the region
## moves or terrain changes — the sample pass is a native call per cell and is
## measured separately from the solve for exactly that reason.
var _atten := PackedFloat32Array()
## Solidity as its own byte array rather than something derived from _atten.
## ❗️Never test `_atten[i] == AIR_ATTEN`: reading a PackedFloat32Array widens
## a float32 back to a float64 that does NOT compare equal to the float64
## literal it was written from, so such a test is always false. That silently
## disabled the entire sky pass once — one byte per cell is cheaper anyway.
var _solid := PackedByteArray()
## Per COLUMN (not per cell): the world row of that column's topmost terrain
## tile. Cells at or above it are open sky; everything below has to be reached
## by propagation. This is the only thing separating a dug shaft from daylight
## — both are air ([terrain.md](../../docs/systems/terrain.md) §Lighting).
var _sky_row := PackedInt32Array()


func resize(new_cols: int, new_rows: int) -> void:
	if new_cols == cols and new_rows == rows:
		return
	cols = new_cols
	rows = new_rows
	var count := cols * rows
	_r.resize(count)
	_g.resize(count)
	_b.resize(count)
	_atten.resize(count)
	_solid.resize(count)
	_sky_row.resize(cols)


## Read solidity for the whole region. Separate from solve() because it can be
## cached across frames while the solve cannot.
func sample_terrain(terrain: Node, new_origin: Vector2i) -> void:
	origin = new_origin
	var i := 0
	var cell := Vector2i.ZERO
	for x in cols:
		_sky_row[x] = terrain.surface_row(origin.x + x)
	for y in rows:
		cell.y = origin.y + y
		for x in cols:
			cell.x = origin.x + x
			# get_cell_source_id, not is_solid: one native call instead of a
			# GDScript hop into one. This loop is ~8.6k calls a solve, so the
			# hop is the difference between a cheap pass and a visible one.
			var solid: bool = terrain.get_cell_source_id(cell) != -1
			_solid[i] = 1 if solid else 0
			_atten[i] = SOLID_ATTEN if solid else AIR_ATTEN
			i += 1


func clear() -> void:
	_r.fill(0.0)
	_g.fill(0.0)
	_b.fill(0.0)


## Seed a source in world-cell space. Out-of-region sources are dropped rather
## than clamped — clamping would smear a light onto the region edge.
func add_source(cell: Vector2i, color: Color) -> void:
	var x := cell.x - origin.x
	var y := cell.y - origin.y
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return
	var i := y * cols + x
	if color.r > _r[i]:
		_r[i] = color.r
	if color.g > _g[i]:
		_g[i] = color.g
	if color.b > _b[i]:
		_b[i] = color.b


## Daylight, as a source rather than a global modulate — that is what makes it
## fill open sky, stop a few tiles into the dirt, and fade down a shaft.
##
## Every cell at or above its column's surface row is seeded at full strength
## propagation carries it from there, so a sealed cave is dark and a dug shaft
## dims with depth on its own. There is no depth ramp anywhere in this model:
## "deeper is darker" is emergent, not a curve someone tuned.
##
## When the surface sits ABOVE the solved window, the column is seeded on its
## top row with whatever daylight survives the gap. Without that term, scrolling
## down past the surface would snap an open shaft from lit to black in one frame.
func add_sky(sky: Color) -> void:
	if sky.r <= 0.0 and sky.g <= 0.0 and sky.b <= 0.0:
		return
	for x in cols:
		var surface := _sky_row[x]
		if surface < 0:
			continue # No world gen here — no daylight, rather than a lit void.
		var gap := origin.y - surface
		if gap > 0:
			if gap <= SKY_MAX_GAP:
				_seed(x, sky, pow(AIR_ATTEN, float(gap)))
			continue
		var last := mini(surface - origin.y, rows - 1)
		var i := x
		for _y in last + 1:
			_seed(i, sky, 1.0)
			i += cols


func _seed(i: int, color: Color, scale: float) -> void:
	var v := color.r * scale
	if v > _r[i]:
		_r[i] = v
	v = color.g * scale
	if v > _g[i]:
		_g[i] = v
	v = color.b * scale
	if v > _b[i]:
		_b[i] = v


## Four directional sweeps × PASSES. Every channel is updated in one loop body
## so the index maths and the attenuation fetch are paid once, not three times.
func solve() -> void:
	for _pass in PASSES:
		_sweep_right()
		_sweep_left()
		_sweep_down()
		_sweep_up()


func _sweep_right() -> void:
	for y in rows:
		var base := y * cols
		for x in range(1, cols):
			var i := base + x
			var a := _atten[i]
			var v := _r[i - 1] * a
			if v > _r[i]:
				_r[i] = v
			v = _g[i - 1] * a
			if v > _g[i]:
				_g[i] = v
			v = _b[i - 1] * a
			if v > _b[i]:
				_b[i] = v


func _sweep_left() -> void:
	for y in rows:
		var base := y * cols
		for x in range(cols - 2, -1, -1):
			var i := base + x
			var a := _atten[i]
			var v := _r[i + 1] * a
			if v > _r[i]:
				_r[i] = v
			v = _g[i + 1] * a
			if v > _g[i]:
				_g[i] = v
			v = _b[i + 1] * a
			if v > _b[i]:
				_b[i] = v


func _sweep_down() -> void:
	for y in range(1, rows):
		var base := y * cols
		for x in cols:
			var i := base + x
			var j := i - cols
			var a := _atten[i]
			var v := _r[j] * a
			if v > _r[i]:
				_r[i] = v
			v = _g[j] * a
			if v > _g[i]:
				_g[i] = v
			v = _b[j] * a
			if v > _b[i]:
				_b[i] = v


func _sweep_up() -> void:
	for y in range(rows - 2, -1, -1):
		var base := y * cols
		for x in cols:
			var i := base + x
			var j := i + cols
			var a := _atten[i]
			var v := _r[j] * a
			if v > _r[i]:
				_r[i] = v
			v = _g[j] * a
			if v > _g[i]:
				_g[i] = v
			v = _b[j] * a
			if v > _b[i]:
				_b[i] = v


## One byte per channel per tile, ready for ImageTexture.update(). Built from a
## PackedByteArray rather than set_pixel: set_pixel is a call per tile and
## costs more than the whole solve.
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(cols * rows * 3)
	var o := 0
	for i in cols * rows:
		out[o] = int(clampf(_r[i], 0.0, 1.0) * 255.0)
		out[o + 1] = int(clampf(_g[i], 0.0, 1.0) * 255.0)
		out[o + 2] = int(clampf(_b[i], 0.0, 1.0) * 255.0)
		o += 3
	return out


func get_value(cell: Vector2i) -> Color:
	var x := cell.x - origin.x
	var y := cell.y - origin.y
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return Color.BLACK
	var i := y * cols + x
	return Color(_r[i], _g[i], _b[i])
