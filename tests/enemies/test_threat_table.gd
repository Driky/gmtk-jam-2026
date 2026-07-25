## Unit tests for ThreatTable (roadmap 2.3 aggro).
extends GdUnitTestSuite

var _table: ThreatTable
var _attacker_a: Node2D
var _attacker_b: Node2D


func before_test() -> void:
	_table = ThreatTable.new()
	_attacker_a = auto_free(Node2D.new())
	_attacker_b = auto_free(Node2D.new())


func test_threat_accumulates_per_attacker() -> void:
	_table.add_threat(_attacker_a, 5.0)
	_table.add_threat(_attacker_a, 5.0)
	assert_that(_table.top_target(8.0)).is_same(_attacker_a)


func test_below_threshold_is_null() -> void:
	_table.add_threat(_attacker_a, 5.0)
	assert_that(_table.top_target(8.0)).is_null()


func test_decay_erases_at_zero() -> void:
	_table.add_threat(_attacker_a, 10.0)
	_table.decay(2.0, 4.0) # 8 points of decay -> 2 left.
	assert_that(_table.top_target(8.0)).is_null()
	assert_that(_table.top_target(1.0)).is_same(_attacker_a)
	_table.decay(1.0, 4.0) # Drops to <= 0 -> erased entirely.
	assert_that(_table.top_target(0.0)).is_null()


func test_top_target_picks_highest() -> void:
	_table.add_threat(_attacker_a, 10.0)
	_table.add_threat(_attacker_b, 20.0)
	assert_that(_table.top_target(8.0)).is_same(_attacker_b)


func test_freed_attacker_is_pruned() -> void:
	var doomed := Node2D.new()
	_table.add_threat(doomed, 50.0)
	doomed.free()
	assert_that(_table.top_target(8.0)).is_null()
