## Scene-runner integration test: a walker on a real physics floor walks
## toward the Core double, then melees it — verifies the actuation half
## (gravity, move_and_slide, attack cadence) that the pure decide() tests
## can't cover. Terrain reads come from a double; physics from a
## StaticBody2D floor whose top edge matches the double's solid row.
extends GdUnitTestSuite

const TILE := 16.0
const FLOOR_ROW := 10 # Cells (x, 10) are solid; floor top at y = 160.
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")


class TerrainDouble:
	extends Node

	## Core footprint cells -> the core node (entity probe).
	var core: Node2D = null
	var core_cells: Array[Vector2i] = []
	## Anything else registered in a cell (3.5b's ladder column).
	var entities: Dictionary[Vector2i, Node] = { }


	func is_solid(pos: Vector2i) -> bool:
		return pos.y == FLOOR_ROW


	func get_entity(pos: Vector2i) -> Node:
		if pos in core_cells:
			return core
		return entities.get(pos)


	func damage_tile(_pos: Vector2i, _amount: float, _tier: int, _source: int) -> bool:
		return false # Nothing chewable in this arena.


class WavesDouble:
	extends Node

	var flow_field: RefCounted = null # No field -> direct-to-Core fallback.


class CoreDouble:
	extends Node2D

	var hits: Array[float] = []


	func base_cell() -> Vector2i:
		return Vector2i(8, FLOOR_ROW - 1)


	func take_damage(amount: float) -> void:
		hits.append(amount)


func _build_arena() -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	# Physics floor matching the double's solid row: top edge at FLOOR_ROW*16.
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40.0 * TILE, TILE)
	shape.shape = rect
	body.add_child(shape)
	body.position = Vector2(20.0 * TILE, FLOOR_ROW * TILE + TILE / 2.0)
	root.add_child(body)

	var core := CoreDouble.new()
	core.add_to_group(&"core")
	core.position = Vector2(8.5 * TILE, (FLOOR_ROW - 1) * TILE)
	root.add_child(core)

	var terrain := TerrainDouble.new()
	terrain.core = core
	terrain.core_cells = [Vector2i(8, FLOOR_ROW - 1), Vector2i(8, FLOOR_ROW - 2)]
	root.add_child(terrain)
	var waves := WavesDouble.new()
	root.add_child(waves)

	var enemy: Enemy = EnemyScene.instantiate()
	enemy.stats = EnemyStats.new()
	enemy.terrain = terrain
	enemy.waves = waves
	# Standing on the floor 5 tiles left of the Core column.
	enemy.position = Vector2(3.5 * TILE, FLOOR_ROW * TILE - 7.0)
	root.add_child(enemy)
	return { "root": root, "enemy": enemy, "core": core }


func test_walker_walks_to_core_and_melees_it() -> void:
	var arena := _build_arena()
	var runner := scene_runner(arena.root)
	var enemy: Enemy = arena.enemy
	var core: CoreDouble = arena.core
	var start_x: float = enemy.position.x

	await runner.simulate_frames(30)
	assert_float(enemy.position.x).is_greater(start_x) # Walking toward the Core.

	# 5 tiles at 40 px/s is 2 s of physics-time travel plus a swing cooldown
	# headless simulate_frames advances physics at roughly half the frame
	# count, so budget generously.
	await runner.simulate_frames(500)
	assert_int(core.hits.size()).is_greater_equal(2)
	assert_float(core.hits[0]).is_equal(enemy.stats.damage)
	# The mob parked next to the Core instead of running past it.
	assert_float(absf(enemy.position.x - core.position.x)).is_less(3.0 * TILE)

## The 3.5b exit criterion's mob half, on real physics: a walker at the foot of
## a ladder column with the Core straight above it must **climb** — not stand at
## the bottom chewing (the `_attackable_entity` skip), not hang on it forever
## (the stuck watchdog counting CLIMB as movement), and not take fall damage
## coming back down (the airborne-apex reset).
##
## The column is six rungs; the Core double sits at the top, so `_direct_dir`
## reads UP and the mob never needs a flow field.
const LadderScene := preload("res://scenes/automation/ladder.tscn")
const COLUMN_X := 8
const COLUMN_TOP := FLOOR_ROW - 6


class HighCoreDouble:
	extends Node2D

	var hits: Array[float] = []


	func base_cell() -> Vector2i:
		return Vector2i(COLUMN_X, COLUMN_TOP)


	func take_damage(amount: float) -> void:
		hits.append(amount)


func _build_ladder_arena() -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40.0 * TILE, TILE)
	shape.shape = rect
	body.add_child(shape)
	body.position = Vector2(20.0 * TILE, FLOOR_ROW * TILE + TILE / 2.0)
	root.add_child(body)

	var core := HighCoreDouble.new()
	core.add_to_group(&"core")
	core.position = Vector2((COLUMN_X + 0.5) * TILE, COLUMN_TOP * TILE)
	root.add_child(core)

	var terrain := TerrainDouble.new()
	terrain.core = core
	terrain.core_cells = [Vector2i(COLUMN_X, COLUMN_TOP)]
	# Rungs from the floor row up to (but not into) the Core's cell.
	for y in range(COLUMN_TOP + 1, FLOOR_ROW):
		var rung: Ladder = LadderScene.instantiate()
		rung.setup(Vector2i(COLUMN_X, y))
		root.add_child(rung)
		terrain.entities[Vector2i(COLUMN_X, y)] = rung
	root.add_child(terrain)
	var waves := WavesDouble.new()
	root.add_child(waves)

	var enemy: Enemy = EnemyScene.instantiate()
	enemy.stats = EnemyStats.new()
	enemy.terrain = terrain
	enemy.waves = waves
	# Standing on the floor, in the column, directly under the bottom rung.
	enemy.position = Vector2((COLUMN_X + 0.5) * TILE, FLOOR_ROW * TILE - 7.0)
	root.add_child(enemy)
	return { "root": root, "enemy": enemy, "core": core }


func test_walker_climbs_a_ladder_column_instead_of_chewing_it() -> void:
	var arena := _build_ladder_arena()
	var runner := scene_runner(arena.root)
	var enemy: Enemy = arena.enemy
	var start_y: float = enemy.position.y

	await runner.simulate_frames(60)
	assert_float(enemy.position.y).is_less(start_y) # Off the floor and rising.

	await runner.simulate_frames(500)
	# It rode the column to the top rung rather than stalling partway up.
	assert_int(enemy.cell().y).is_less_equal(COLUMN_TOP + 1)
	# ...and is swinging at the Core from up there, which is the whole point: a
	# ladder the player left up is a route into the base.
	assert_int((arena.core as HighCoreDouble).hits.size()).is_greater_equal(1)
	# ❗️Full HP after five tiles of vertical travel. Without the CLIMB actuation's
	# `_air_top_y = INF`, every frame off the floor accumulates an apex and the
	# first touchdown bills the whole column as a fall.
	assert_float(enemy.current_hp).is_equal(enemy.stats.max_hp)
