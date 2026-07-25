## Unit tests for the Core (roadmap 2.1).
## Terrain is a fresh instance per test — never the live autoload.
extends GdUnitTestSuite

const CoreScene := preload("res://scenes/core.tscn")
const TerrainScript := preload("res://scripts/terrain/terrain.gd")

## Matches the world-gen flat spawn area: center column 100, surface ~24.
const CX := 100
const SURFACE_ROW := 24

var _core: Node2D
var _terrain: Node
var _health_events: Array = []
var _died_count := 0


func before_test() -> void:
	_core = auto_free(CoreScene.instantiate())
	_core.setup(CX, SURFACE_ROW)
	add_child(_core)
	_terrain = auto_free(TerrainScript.new())
	add_child(_terrain)
	_health_events = []
	_died_count = 0
	_core.health_changed.connect(
		func(current: float, max_value: float) -> void:
			_health_events.append([current, max_value]),
	)
	_core.died.connect(func() -> void: _died_count += 1)

# --- Geometry ------------------------------------------------------------------


func test_footprint_is_3x2_air_block_on_surface() -> void:
	var cells: Array[Vector2i] = _core.footprint()
	assert_array(cells).has_size(6)
	for x in range(CX - 1, CX + 2):
		for y in [SURFACE_ROW - 2, SURFACE_ROW - 1]:
			assert_array(cells).contains([Vector2i(x, y)])


func test_base_cell_bottom_center() -> void:
	assert_vector(_core.base_cell()).is_equal(Vector2i(CX, SURFACE_ROW - 1))


func test_in_core_group() -> void:
	assert_bool(_core.is_in_group("core")).is_true()

# --- Damage --------------------------------------------------------------------


func test_take_damage_emits_and_clamps() -> void:
	_core.take_damage(100.0)
	assert_array(_health_events).contains_exactly([[_core.MAX_HP - 100.0, _core.MAX_HP]])
	_core.take_damage(_core.MAX_HP * 2.0)
	assert_float(_core.current_hp).is_equal(0.0)


func test_died_emits_exactly_once() -> void:
	_core.take_damage(_core.MAX_HP)
	_core.take_damage(50.0) # dead — ignored, no second emit
	assert_int(_died_count).is_equal(1)
	assert_array(_health_events).has_size(1)

# --- Footprint registration ----------------------------------------------------


func test_register_footprint_claims_all_cells() -> void:
	assert_bool(_core.register_footprint(_terrain)).is_true()
	for cell: Vector2i in _core.footprint():
		assert_object(_terrain.get_entity(cell)).is_same(_core)
	_terrain.debug_validate()


func test_register_footprint_rolls_back_on_solid_cell() -> void:
	_terrain.set_tile(Vector2i(CX + 1, SURFACE_ROW - 1), "dirt")
	assert_bool(_core.register_footprint(_terrain)).is_false()
	for cell: Vector2i in _core.footprint():
		assert_object(_terrain.get_entity(cell)).is_null()
	_terrain.debug_validate()
