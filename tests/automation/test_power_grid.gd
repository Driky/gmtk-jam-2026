## Unit tests for the power solver (roadmap 3.4). Pure geometry and arithmetic —
## no Terrain, no Automation, no scene tree — which is the whole reason
## `PowerGrid` takes parallel arrays instead of nodes.
##
## Radii here are in the same units as the centres; the tile → world conversion
## belongs to `Automation`, so these read in plain numbers.
extends GdUnitTestSuite

const PowerGridScript := preload("res://scripts/automation/power_grid.gd")


func _grid(discs: Array) -> PowerGrid:
	var centres := PackedVector2Array()
	var radii := PackedFloat32Array()
	for disc: Array in discs:
		centres.append(disc[0])
		radii.append(disc[1])
	var grid: PowerGrid = PowerGridScript.new()
	grid.build(centres, radii)
	return grid

# --- Components ---------------------------------------------------------------


func test_no_emitters_is_no_grids() -> void:
	var grid := _grid([])
	assert_int(grid.component_count()).is_equal(0)
	assert_int(grid.grid_of_point(Vector2.ZERO)).is_equal(PowerGrid.NO_GRID)


func test_two_overlapping_discs_are_one_grid() -> void:
	# 8 apart, radii 5 + 5 — they overlap by 2.
	var grid := _grid([[Vector2.ZERO, 5.0], [Vector2(8.0, 0.0), 5.0]])
	assert_int(grid.component_count()).is_equal(1)
	assert_int(grid.component_of(0)).is_equal(grid.component_of(1))


func test_two_disjoint_discs_are_two_grids() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0], [Vector2(100.0, 0.0), 5.0]])
	assert_int(grid.component_count()).is_equal(2)
	assert_int(grid.component_of(0)).is_not_equal(grid.component_of(1))


## ❗️The whole point of a relay: A and C never touch, and connectivity is still
## transitive through B. A pairwise "is this machine near a generator" test would
## get this wrong and look right.
func test_a_chain_a_b_c_is_one_grid_even_though_a_and_c_do_not_touch() -> void:
	var grid := _grid(
		[
			[Vector2.ZERO, 5.0],
			[Vector2(9.0, 0.0), 5.0],
			[Vector2(18.0, 0.0), 5.0],
		],
	)
	assert_float(Vector2.ZERO.distance_to(Vector2(18.0, 0.0))).is_greater(10.0) # A–C are apart.
	assert_int(grid.component_count()).is_equal(1)
	assert_int(grid.component_of(0)).is_equal(grid.component_of(2))


## ❗️Tangency at exactly `rA + rB` CONNECTS. A relay is placed at its reach, so a
## strict `<` would make the intended placement a coin flip on float rounding.
func test_discs_touching_at_exactly_the_sum_of_their_radii_connect() -> void:
	var grid := _grid([[Vector2.ZERO, 4.0], [Vector2(10.0, 0.0), 6.0]])
	assert_int(grid.component_count()).is_equal(1)


func test_discs_a_hair_apart_do_not_connect() -> void:
	var grid := _grid([[Vector2.ZERO, 4.0], [Vector2(10.01, 0.0), 6.0]])
	assert_int(grid.component_count()).is_equal(2)


## Two islands, each of two members — the labeller has to keep counting after it
## finishes the first component rather than lumping the rest together.
func test_two_separate_pairs_are_two_grids_of_two() -> void:
	var grid := _grid(
		[
			[Vector2.ZERO, 5.0],
			[Vector2(8.0, 0.0), 5.0],
			[Vector2(200.0, 0.0), 5.0],
			[Vector2(208.0, 0.0), 5.0],
		],
	)
	assert_int(grid.component_count()).is_equal(2)
	assert_int(grid.component_of(0)).is_equal(grid.component_of(1))
	assert_int(grid.component_of(2)).is_equal(grid.component_of(3))
	assert_int(grid.component_of(0)).is_not_equal(grid.component_of(2))

# --- Point coverage -----------------------------------------------------------


func test_a_point_inside_a_disc_names_its_grid() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0]])
	assert_int(grid.grid_of_point(Vector2(3.0, 0.0))).is_equal(grid.component_of(0))


func test_a_point_outside_every_disc_is_no_grid() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0]])
	assert_int(grid.grid_of_point(Vector2(5.5, 0.0))).is_equal(PowerGrid.NO_GRID)


## Inclusive on the edge, for the tangency reason: "just inside the circle you
## can see" must not be a rounding question.
func test_a_point_exactly_on_the_edge_is_covered() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0]])
	assert_int(grid.grid_of_point(Vector2(5.0, 0.0))).is_equal(grid.component_of(0))


## A point in the overlap belongs to the shared grid whichever disc is found
## first, which is why `grid_of_point` can stop at the first hit.
func test_a_point_in_the_overlap_names_the_shared_grid() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0], [Vector2(8.0, 0.0), 5.0]])
	assert_int(grid.grid_of_point(Vector2(4.0, 0.0))).is_equal(grid.component_of(0))
	assert_int(grid.grid_of_point(Vector2(4.0, 0.0))).is_equal(grid.component_of(1))

# --- Supply, demand, ratio ----------------------------------------------------


func test_supply_above_demand_runs_at_full_rate() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0]])
	grid.add_supply(0, 10.0)
	grid.add_demand(0, 4.0)
	grid.resolve()
	assert_float(grid.ratio_of(0)).is_equal_approx(1.0, 0.0001)


## ❗️Brownouts SLOW, they never hard-stop — half the supply is half the rate,
## not a dead factory ([automation.md](../../docs/systems/automation.md) §Power).
func test_half_the_supply_is_half_the_rate() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0]])
	grid.add_supply(0, 2.0)
	grid.add_demand(0, 4.0)
	grid.resolve()
	assert_float(grid.ratio_of(0)).is_equal_approx(0.5, 0.0001)


## No demand is ratio 1.0, not a division by zero: an empty grid is "fully
## powered" in the only sense that matters — the next machine placed in it runs.
func test_an_empty_grid_resolves_to_full_rather_than_dividing_by_zero() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0]])
	grid.add_supply(0, 10.0)
	grid.resolve()
	assert_float(grid.ratio_of(0)).is_equal_approx(1.0, 0.0001)


func test_a_grid_with_no_supply_resolves_to_zero() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0]])
	grid.add_demand(0, 1.0)
	grid.resolve()
	assert_float(grid.ratio_of(0)).is_equal_approx(0.0, 0.0001)


## Two grids are two independent economies — a starved mine must not brown out
## the base on the other side of the map.
func test_grids_do_not_share_supply() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0], [Vector2(100.0, 0.0), 5.0]])
	var a := grid.component_of(0)
	var b := grid.component_of(1)
	grid.add_supply(a, 10.0)
	grid.add_demand(a, 1.0)
	grid.add_demand(b, 1.0)
	grid.resolve()
	assert_float(grid.ratio_of(a)).is_equal_approx(1.0, 0.0001)
	assert_float(grid.ratio_of(b)).is_equal_approx(0.0, 0.0001)


## `begin_tick` is what makes the pass idempotent: demand is rebuilt from
## scratch, so a machine that stopped drawing needs no event to fire.
func test_begin_tick_clears_the_previous_ticks_totals() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0]])
	grid.add_supply(0, 4.0)
	grid.add_demand(0, 4.0)
	grid.resolve()

	grid.begin_tick()
	grid.add_supply(0, 4.0)
	grid.add_demand(0, 8.0)
	grid.resolve()

	assert_float(grid.supply_of(0)).is_equal_approx(4.0, 0.0001)
	assert_float(grid.demand_of(0)).is_equal_approx(8.0, 0.0001)
	assert_float(grid.ratio_of(0)).is_equal_approx(0.5, 0.0001)


## `NO_GRID` is a legal argument everywhere: an uncovered machine's demand goes
## nowhere and its ratio is 0, with no caller-side branch.
func test_the_no_grid_index_absorbs_writes_and_reads_as_dead() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0]])
	grid.add_supply(PowerGrid.NO_GRID, 99.0)
	grid.add_demand(PowerGrid.NO_GRID, 99.0)
	grid.resolve()
	assert_float(grid.ratio_of(PowerGrid.NO_GRID)).is_equal_approx(0.0, 0.0001)
	assert_float(grid.supply_of(0)).is_equal_approx(0.0, 0.0001)


## Rebuilding replaces the world rather than adding to it — a removed generator
## must not leave its disc behind.
func test_a_rebuild_replaces_the_previous_emitter_set() -> void:
	var grid := _grid([[Vector2.ZERO, 5.0], [Vector2(8.0, 0.0), 5.0]])
	assert_int(grid.component_count()).is_equal(1)

	grid.build(PackedVector2Array([Vector2(8.0, 0.0)]), PackedFloat32Array([5.0]))

	assert_int(grid.emitter_count()).is_equal(1)
	assert_int(grid.component_count()).is_equal(1)
	assert_int(grid.grid_of_point(Vector2.ZERO)).is_equal(PowerGrid.NO_GRID)
