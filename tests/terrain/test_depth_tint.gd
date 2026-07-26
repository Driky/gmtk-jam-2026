## Unit tests for the depth tint (roadmap 2.7). depth_color is pure and static,
## so none of this needs a viewport, a camera or the scene.
extends GdUnitTestSuite

const DepthTintScript := preload("res://scripts/terrain/depth_tint.gd")


## The spawn area must never start dark. This is the test that catches a Day-4
## world-gen retune (4.6 balance pass) silently pushing the surface below the
## ramp's bright end — the constant is DERIVED from world gen, not chosen.
func test_bright_end_clears_the_deepest_possible_surface_valley() -> void:
	assert_float(DepthTintScript.SURFACE_ROW).is_greater_equal(
		float(WorldGen.SURFACE_MEAN + WorldGen.SURFACE_AMPLITUDE),
	)


func test_surface_rows_are_untinted() -> void:
	assert_that(DepthTintScript.depth_color(0.0)).is_equal(Color.WHITE)
	assert_that(DepthTintScript.depth_color(-20.0)).is_equal(Color.WHITE) # Above the world.
	assert_that(DepthTintScript.depth_color(DepthTintScript.SURFACE_ROW)).is_equal(Color.WHITE)


## Approx per channel, not is_equal on the Color: `lerp` at weight 1.0 lands a
## float32 ulp off the constant, and the printed values look identical.
func test_deep_rows_bottom_out_at_the_floor_color() -> void:
	_assert_floor(DepthTintScript.depth_color(DepthTintScript.DARK_ROW))
	# Nothing gets darker than the floor, however deep you dig.
	_assert_floor(DepthTintScript.depth_color(1199.0))


func _assert_floor(color: Color) -> void:
	var floor_color: Color = DepthTintScript.FLOOR_COLOR
	assert_float(color.r).is_equal_approx(floor_color.r, 0.0001)
	assert_float(color.g).is_equal_approx(floor_color.g, 0.0001)
	assert_float(color.b).is_equal_approx(floor_color.b, 0.0001)


## A DIM floor, not black: pickups, loot bags and mobs are unlit ColorRects, so
## a black floor means losing your own death bag.
func test_the_floor_is_dim_rather_than_black() -> void:
	assert_float(DepthTintScript.FLOOR_COLOR.v).is_greater(0.0)


## The one structural assumption behind a single tint node: the Terrain
## autoload's TileMapLayer draws on the SAME canvas as Main's children, so one
## CanvasModulate covers terrain, player, pickups and mobs together. A
## CanvasLayer anywhere in that chain would silently exempt the tiles and the
## world would darken around unlit terrain.
func test_the_terrain_layer_shares_the_tinted_world_canvas() -> void:
	var tint: CanvasModulate = auto_free(CanvasModulate.new())
	add_child(tint)
	var layer: Node2D = Terrain.get_node("TileMapLayer")
	assert_bool(tint.get_canvas() == layer.get_canvas()).is_true()


## …and the flip side: the HUD, game-over screen and debug panel are
## CanvasLayers, so they own their canvas and stay legible at any depth for
## free. That's why no UI code appears anywhere in the lighting work.
func test_a_canvas_layer_is_immune_to_the_tint() -> void:
	var tint: CanvasModulate = auto_free(CanvasModulate.new())
	add_child(tint)
	var ui: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(ui)
	var label: Control = auto_free(Control.new())
	ui.add_child(label)
	assert_bool(label.get_canvas() == tint.get_canvas()).is_false()


func test_the_ramp_is_monotonic() -> void:
	var previous := 2.0
	for row in range(0, 120, 2):
		var value := DepthTintScript.depth_color(float(row)).v
		assert_float(value).is_less_equal(previous)
		previous = value
	assert_float(previous).is_less(1.0) # It actually ramped somewhere.
