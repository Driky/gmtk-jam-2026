## Unit tests for the per-tile light propagation (roadmap 2.7). Runs against a
## terrain double, so every case states its own world in three lines and none of
## it needs world gen, a camera or a viewport.
extends GdUnitTestSuite

const LightGridScript := preload("res://scripts/terrain/light_grid.gd")

const WHITE := Color(1.0, 1.0, 1.0)
const TORCH := Color(1.0, 0.78, 0.45)


## Just the two reads LightGrid makes of the world.
class FakeTerrain:
	extends Node

	var solid: Dictionary = { }
	## Column → topmost terrain row. Missing columns report "no world gen".
	var heights: Dictionary = { }
	var default_surface := -1


	func get_cell_source_id(pos: Vector2i) -> int:
		return 0 if solid.has(pos) else -1


	func surface_row(x: int) -> int:
		return heights.get(x, default_surface)


	## Fill a solid rect, so a test reads as a picture of its world.
	func fill(rect: Rect2i) -> void:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				solid[Vector2i(x, y)] = true


	func set_surface(from_x: int, to_x: int, row: int) -> void:
		for x in range(from_x, to_x):
			heights[x] = row


var _terrain: FakeTerrain


func before_test() -> void:
	_terrain = auto_free(FakeTerrain.new())


func _grid(cols: int, rows: int, origin: Vector2i) -> LightGrid:
	var grid := LightGridScript.new()
	grid.resize(cols, rows)
	grid.sample_terrain(_terrain, origin)
	grid.clear()
	return grid

# --- Daylight ----------------------------------------------------------------


## The regression that matters most: this silently returned an all-black world
## when the solid test was `_atten[i] == AIR_ATTEN`, because reading a
## PackedFloat32Array widens to a float64 that never equals the literal.
func test_sky_fills_an_open_column_to_full_strength() -> void:
	_terrain.set_surface(0, 16, 10)
	var grid := _grid(16, 16, Vector2i(0, 0))
	grid.add_sky(WHITE)
	grid.solve()
	assert_float(grid.get_value(Vector2i(8, 0)).v).is_equal_approx(1.0, 0.01)
	assert_float(grid.get_value(Vector2i(8, 10)).v).is_equal_approx(1.0, 0.01)


## A column with no generated terrain is dark, not a lit void — dark is the safe
## wrong answer when world gen hasn't run.
func test_columns_without_world_gen_get_no_daylight() -> void:
	var grid := _grid(8, 8, Vector2i(0, 0)) # default_surface stays -1.
	grid.add_sky(WHITE)
	grid.solve()
	assert_float(grid.get_value(Vector2i(4, 4)).v).is_equal(0.0)


## Daylight has to stop a few tiles into the rock — that fade is the whole
## surface read in the reference art.
func test_daylight_dies_a_few_tiles_into_solid_ground() -> void:
	_terrain.set_surface(0, 16, 4)
	_terrain.fill(Rect2i(0, 5, 16, 20))
	var grid := _grid(16, 24, Vector2i(0, 0))
	grid.add_sky(WHITE)
	grid.solve()
	var just_under := grid.get_value(Vector2i(8, 5)).v
	var deeper := grid.get_value(Vector2i(8, 9)).v
	assert_float(just_under).is_greater(deeper)
	assert_float(deeper).is_less(0.15) # Five tiles of rock is effectively dark.


## The rule that separates a dug shaft from open sky. Both are air; only the
## surface row tells them apart, and without it a shaft stays at noon forever.
func test_a_shaft_dims_with_depth_while_open_sky_does_not() -> void:
	_terrain.set_surface(0, 16, 4)
	_terrain.fill(Rect2i(0, 5, 16, 30))
	for y in range(5, 30): # Sink a 1-wide shaft.
		_terrain.solid.erase(Vector2i(8, y))
	var grid := _grid(16, 32, Vector2i(0, 0))
	grid.add_sky(WHITE)
	grid.solve()
	var top := grid.get_value(Vector2i(8, 6)).v
	var middle := grid.get_value(Vector2i(8, 16)).v
	var bottom := grid.get_value(Vector2i(8, 28)).v
	assert_float(top).is_greater(middle)
	assert_float(middle).is_greater(bottom)
	assert_float(bottom).is_less(0.15)
	# …while the open sky above is still at full strength.
	assert_float(grid.get_value(Vector2i(8, 3)).v).is_equal_approx(1.0, 0.01)


## Scrolling below the surface must fade, not snap: with the surface above the
## solved window the column still carries whatever daylight survived the gap.
func test_daylight_carries_into_a_window_below_the_surface() -> void:
	_terrain.set_surface(0, 16, 0)
	var grid := _grid(16, 8, Vector2i(0, 10)) # Ten tiles of air above the window.
	grid.add_sky(WHITE)
	grid.solve()
	var value := grid.get_value(Vector2i(8, 10)).v
	assert_float(value).is_greater(0.0)
	assert_float(value).is_less(1.0)


func test_daylight_gives_up_far_below_the_surface() -> void:
	_terrain.set_surface(0, 16, 0)
	var grid := _grid(16, 8, Vector2i(0, LightGridScript.SKY_MAX_GAP + 5))
	grid.add_sky(WHITE)
	grid.solve()
	assert_float(grid.get_value(Vector2i(8, LightGridScript.SKY_MAX_GAP + 5)).v).is_equal(0.0)

# --- Point sources -----------------------------------------------------------


## The behaviour a PointLight2D cannot produce at any setting: light bending
## around a corner instead of being clipped by it.
func test_light_seeps_around_a_corner() -> void:
	_terrain.fill(Rect2i(0, 0, 16, 16))
	for x in range(2, 10): # Horizontal leg.
		_terrain.solid.erase(Vector2i(x, 2))
	for y in range(2, 10): # Vertical leg, meeting it at (9, 2).
		_terrain.solid.erase(Vector2i(9, y))
	var grid := _grid(16, 16, Vector2i(0, 0))
	grid.add_source(Vector2i(2, 2), TORCH)
	grid.solve()
	var around_the_corner := grid.get_value(Vector2i(9, 8)).v
	assert_float(around_the_corner).is_greater(0.0)
	# Dimmer than a straight line of the same length — it paid the corner.
	assert_float(around_the_corner).is_less(grid.get_value(Vector2i(8, 2)).v)


## Rock is what makes a cave a cave: sealed pockets stay black however close a
## torch is in straight-line distance.
func test_solid_rock_blocks_a_nearby_torch() -> void:
	_terrain.fill(Rect2i(0, 0, 16, 16))
	_terrain.solid.erase(Vector2i(2, 8))
	_terrain.solid.erase(Vector2i(12, 8))
	var grid := _grid(16, 16, Vector2i(0, 0))
	grid.add_source(Vector2i(2, 8), TORCH)
	grid.solve()
	assert_float(grid.get_value(Vector2i(2, 8)).v).is_greater(0.9)
	assert_float(grid.get_value(Vector2i(12, 8)).v).is_less(0.01)


## Warm sources have to stay warm — a monochrome solve would lose this, and it
## is the whole reason the grid carries three channels.
func test_a_source_keeps_its_colour_as_it_travels() -> void:
	var grid := _grid(16, 16, Vector2i(0, 0))
	grid.add_source(Vector2i(8, 8), TORCH)
	grid.solve()
	var near := grid.get_value(Vector2i(10, 8))
	assert_float(near.r).is_greater(near.b)


## Out of region is dropped rather than clamped — clamping would smear a light
## the player cannot see onto the edge of the one they can.
func test_sources_outside_the_region_are_dropped() -> void:
	var grid := _grid(8, 8, Vector2i(0, 0))
	grid.add_source(Vector2i(-5, 4), WHITE)
	grid.add_source(Vector2i(40, 4), WHITE)
	grid.solve()
	assert_float(grid.get_value(Vector2i(0, 4)).v).is_equal(0.0)
	assert_float(grid.get_value(Vector2i(7, 4)).v).is_equal(0.0)


func test_reads_outside_the_region_are_black_rather_than_an_error() -> void:
	var grid := _grid(8, 8, Vector2i(0, 0))
	assert_that(grid.get_value(Vector2i(-1, -1))).is_equal(Color.BLACK)

# --- Upload ------------------------------------------------------------------


## Three bytes per tile in RGB order, which is what Image.create_from_data reads
## — a mismatch here is a garbled screen, not a crash.
func test_bytes_are_three_per_tile_and_clamped() -> void:
	var grid := _grid(4, 3, Vector2i(0, 0))
	grid.add_source(Vector2i(1, 1), Color(2.0, 0.0, 0.0)) # Over-bright on purpose.
	var bytes := grid.to_bytes()
	assert_int(bytes.size()).is_equal(4 * 3 * 3)
	var offset := (1 * 4 + 1) * 3
	assert_int(bytes[offset]).is_equal(255) # Clamped, not wrapped to 0.
	assert_int(bytes[offset + 2]).is_equal(0)


## The amortization contract: LightMap spreads a solve over several frames by
## calling sweep() itself, so running the sweeps one at a time must land on the
## same answer as solve() in one go. If these ever diverge, the light flickers
## in a way no screenshot would explain.
func test_stepping_the_sweeps_matches_solving_in_one_go() -> void:
	_terrain.fill(Rect2i(0, 0, 16, 16))
	for x in range(2, 12):
		_terrain.solid.erase(Vector2i(x, 6))
	for y in range(6, 12):
		_terrain.solid.erase(Vector2i(11, y))

	var whole := _grid(16, 16, Vector2i(0, 0))
	whole.add_source(Vector2i(2, 6), TORCH)
	whole.solve()

	var stepped := _grid(16, 16, Vector2i(0, 0))
	stepped.add_source(Vector2i(2, 6), TORCH)
	for i in LightGridScript.SWEEPS:
		stepped.sweep(i)

	for cell: Vector2i in [Vector2i(6, 6), Vector2i(11, 10), Vector2i(3, 3)]:
		assert_float(stepped.get_value(cell).v).is_equal_approx(
			whole.get_value(cell).v,
			0.0001,
		)
