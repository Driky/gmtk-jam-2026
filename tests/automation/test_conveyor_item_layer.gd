## Unit tests for the conveyor item renderer's interpolation (roadmap 3.2).
##
## Only the static, pure part — the `_draw` itself needs a viewport and is checked
## in the editor/browser. This is the piece that can be wrong in a way a
## screenshot hides: an item that snaps cell to cell instead of flowing fails the
## never-cut bullet, and a lerp with its arguments the wrong way round looks
## almost right.
extends GdUnitTestSuite

const ItemLayer := preload("res://scripts/automation/conveyor_item_layer.gd")
const TILE := TileLayout.TILE_SIZE

const FROM := Vector2i(100, 100)
const TO := Vector2i(101, 100)


func _centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


## At alpha 0 the item sits on the cell it came FROM, not the one it is now
## logically in — the renderer trails the sim by one tick interval, which is what
## makes the motion smooth instead of a snap.
func test_at_alpha_zero_the_item_is_on_the_source_cell() -> void:
	assert_vector(ItemLayer.item_position(FROM, TO, 0.0)).is_equal(_centre(FROM))


func test_at_alpha_one_the_item_has_arrived() -> void:
	assert_vector(ItemLayer.item_position(FROM, TO, 1.0)).is_equal(_centre(TO))


func test_halfway_is_the_midpoint_of_the_two_centres() -> void:
	assert_vector(ItemLayer.item_position(FROM, TO, 0.5)).is_equal(
		_centre(FROM).lerp(_centre(TO), 0.5),
	)


## A belt that did not move has prev_cell == cell, so its lerp is a no-op at
## every alpha — that is how a jammed item renders parked rather than jittering.
func test_a_stationary_item_does_not_move_at_any_alpha() -> void:
	assert_vector(ItemLayer.item_position(FROM, FROM, 0.0)).is_equal(_centre(FROM))
	assert_vector(ItemLayer.item_position(FROM, FROM, 0.7)).is_equal(_centre(FROM))


## ❗️A catch-up frame can leave the accumulator above one interval, and an
## unclamped alpha would fling the item past its destination.
func test_an_out_of_range_alpha_is_clamped() -> void:
	assert_vector(ItemLayer.item_position(FROM, TO, 3.7)).is_equal(_centre(TO))
	assert_vector(ItemLayer.item_position(FROM, TO, -1.0)).is_equal(_centre(FROM))
