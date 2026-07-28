## Unit tests for XP, levels and the stat lookup (roadmap 2.6).
## Runs against a fresh instance per test — never mutates the live autoload.
extends GdUnitTestSuite

const ProgressionScript := preload("res://scripts/progression/progression.gd")

var _progression: Node
var _xp_events: Array = []
var _level_events: Array = []


func before_test() -> void:
	_progression = auto_free(ProgressionScript.new())
	_xp_events = []
	_level_events = []
	_progression.xp_changed.connect(
		func(current: float, needed: float, level: int) -> void:
			_xp_events.append([current, needed, level]),
	)
	_progression.leveled_up.connect(
		func(level: int, points: int) -> void: _level_events.append([level, points]),
	)

# --- Curve ---------------------------------------------------------------------


func test_curve_matches_the_documented_formula() -> void:
	assert_float(ProgressionScript.xp_to_level(1)).is_equal_approx(50.0, 0.001)
	assert_float(ProgressionScript.xp_to_level(2)).is_equal_approx(151.572, 0.001)
	assert_float(ProgressionScript.xp_to_level(3)).is_equal_approx(289.977, 0.001)


func test_starts_at_level_one_with_nothing_banked() -> void:
	assert_int(_progression.level).is_equal(1)
	assert_float(_progression.xp).is_equal(0.0)
	assert_int(_progression.upgrade_points).is_equal(0)

# --- Granting ------------------------------------------------------------------


func test_grant_below_the_threshold_banks_without_leveling() -> void:
	_progression.grant_xp("mining", 10.0)
	assert_float(_progression.xp).is_equal_approx(10.0, 0.001)
	assert_int(_progression.level).is_equal(1)
	assert_array(_level_events).is_empty()


func test_crossing_the_threshold_levels_and_carries_the_remainder() -> void:
	_progression.grant_xp("mining", 60.0)
	assert_int(_progression.level).is_equal(2)
	assert_float(_progression.xp).is_equal_approx(10.0, 0.001)
	assert_int(_progression.upgrade_points).is_equal(1)


## One grant may cross several levels — the debug XP button does exactly that.
func test_one_grant_can_cross_several_levels() -> void:
	_progression.grant_xp("kills", 250.0)
	var spent: float = ProgressionScript.xp_to_level(1) + ProgressionScript.xp_to_level(2)
	assert_int(_progression.level).is_equal(3)
	assert_float(_progression.xp).is_equal_approx(250.0 - spent, 0.001)
	assert_int(_progression.upgrade_points).is_equal(2)


## Every level announces, not just the last one reached.
func test_multi_level_grant_emits_once_per_level() -> void:
	_progression.grant_xp("kills", 250.0)
	assert_array(_level_events).contains_exactly([[2, 1], [3, 2]])


## One xp_changed per grant, however many levels it crossed — the HUD bar
## repaints from the settled values, not from every intermediate step.
func test_grant_emits_xp_changed_exactly_once() -> void:
	_progression.grant_xp("kills", 250.0)
	assert_array(_xp_events).has_size(1)
	var event: Array = _xp_events[0]
	assert_float(event[0]).is_equal_approx(_progression.xp, 0.001)
	assert_float(event[1]).is_equal_approx(ProgressionScript.xp_to_level(3), 0.001)
	assert_int(event[2]).is_equal(3)


func test_non_positive_grants_are_ignored() -> void:
	_progression.grant_xp("mining", 0.0)
	_progression.grant_xp("mining", -25.0)
	assert_float(_progression.xp).is_equal(0.0)
	assert_array(_xp_events).is_empty()


## The Day-4 balance pass asks "where is XP coming from" — unanswerable later
## if the sources aren't tallied as they land.
func test_grants_are_tallied_per_source() -> void:
	_progression.grant_xp("mining", 4.0)
	_progression.grant_xp("looting", 6.0)
	_progression.grant_xp("mining", 5.0)
	assert_float(_progression.xp_by_source["mining"]).is_equal_approx(9.0, 0.001)
	assert_float(_progression.xp_by_source["looting"]).is_equal_approx(6.0, 0.001)

# --- Stats ---------------------------------------------------------------------


func test_base_stats_apply_at_level_one() -> void:
	assert_float(_progression.get_stat("max_hp")).is_equal_approx(100.0, 0.001)
	assert_float(_progression.get_stat("max_mana")).is_equal_approx(50.0, 0.001)
	assert_float(_progression.get_stat("move_speed")).is_equal_approx(110.0, 0.001)


func test_levels_add_flat_stats() -> void:
	_progression.grant_xp("kills", 250.0) # -> level 3
	assert_int(_progression.level).is_equal(3)
	assert_float(_progression.get_stat("max_hp")).is_equal_approx(120.0, 0.001)
	assert_float(_progression.get_stat("max_mana")).is_equal_approx(60.0, 0.001)
	assert_float(_progression.get_stat("move_speed")).is_equal_approx(114.0, 0.001)


## Deliberately level-independent: buffing it is the skill tree's job, and
## `prospecting` is the node that does it — see the tree cases below.
func test_mining_speed_does_not_scale_with_level() -> void:
	_progression.grant_xp("kills", 250.0)
	assert_float(_progression.get_stat("mining_speed")).is_equal_approx(1.0, 0.001)


## What lets ItemStats.effective_* ask for buffs that don't exist yet.
func test_unknown_stats_read_as_neutral_at_every_level() -> void:
	assert_float(_progression.get_stat("melee_damage")).is_equal_approx(1.0, 0.001)
	_progression.grant_xp("kills", 250.0)
	assert_float(_progression.get_stat("swing_speed")).is_equal_approx(1.0, 0.001)

# --- The skill tree (3.7) ------------------------------------------------------
#
# The refusals matter more than the successes: every one of them is a way to spend
# a point on nothing, and none of them raises anything on its own.


func test_a_fresh_run_has_taken_nothing() -> void:
	assert_int(_progression.node_level("prospecting")).is_equal(0)
	assert_dict(_progression.taken).is_empty()


func test_a_node_that_does_not_exist_is_never_takeable() -> void:
	_grant_points(5)
	assert_bool(_progression.can_take("no_such_node")).is_false()
	assert_bool(_progression.take_node("no_such_node")).is_false()
	assert_int(_progression.upgrade_points).is_equal(5)


func test_a_root_is_refused_with_no_points_and_taken_with_one() -> void:
	assert_bool(_progression.can_take("prospecting")).is_false()
	_grant_points(1)
	assert_bool(_progression.can_take("prospecting")).is_true()
	assert_bool(_progression.take_node("prospecting")).is_true()
	assert_int(_progression.node_level("prospecting")).is_equal(1)
	assert_int(_progression.upgrade_points).is_equal(0)


## ❗️The whole point of the branch shape: a node whose parent is untaken cannot be
## bought at any price.
func test_a_child_is_refused_until_its_prerequisite_is_taken() -> void:
	_grant_points(5)
	assert_bool(_progression.can_take("power_grid")).is_false()
	_progression.take_node("logistics_i")
	assert_bool(_progression.can_take("power_grid")).is_true()


## A single-level node taken twice would spend a second point for nothing.
func test_max_level_is_respected() -> void:
	_grant_points(9)
	for _i in 3:
		assert_bool(_progression.take_node("prospecting")).is_true()
	assert_int(_progression.node_level("prospecting")).is_equal(3)
	assert_bool(_progression.can_take("prospecting")).is_false()
	assert_bool(_progression.take_node("prospecting")).is_false()
	assert_int(_progression.upgrade_points).is_equal(6)


func test_taking_a_node_announces_it_at_its_new_level() -> void:
	var events: Array = []
	_progression.node_unlocked.connect(
		func(id: String, level: int) -> void: events.append([id, level]),
	)
	_grant_points(3)
	_progression.take_node("prospecting")
	_progression.take_node("prospecting")
	assert_array(events).contains_exactly([["prospecting", 1], ["prospecting", 2]])


## The buff has to reach `get_stat` by exactly the authored rate, and a stat no
## taken node names must still read a neutral 1.0 — the property that lets
## `ItemStats.effective_*` ask for buffs nothing grants yet.
func test_a_taken_node_moves_exactly_its_own_stat() -> void:
	_grant_points(3)
	_progression.take_node("prospecting")
	assert_float(_progression.get_stat("mining_speed")).is_equal_approx(1.1, 0.001)
	assert_float(_progression.get_stat("turret_damage")).is_equal_approx(1.0, 0.001)
	_progression.take_node("prospecting")
	assert_float(_progression.get_stat("mining_speed")).is_equal_approx(1.2, 0.001)


## ⚠️ The one node that raises a MAXIMUM, and the reason the multiplier has to
## compose with the flat per-level table rather than replace it: at level 3 the
## ceiling is 120, and `conditioning` scales THAT.
func test_a_max_stat_node_multiplies_the_leveled_value() -> void:
	_progression.grant_xp("kills", 250.0) # -> level 3, 120 max HP
	_progression.take_node("conditioning")
	assert_float(_progression.get_stat("max_hp")).is_equal_approx(132.0, 0.001)

# --- Restart -------------------------------------------------------------------


func test_reset_run_clears_every_run_value() -> void:
	_progression.grant_xp("kills", 250.0)
	_progression.take_node("prospecting")
	_progression.reset_run()
	assert_int(_progression.level).is_equal(1)
	assert_float(_progression.xp).is_equal(0.0)
	assert_int(_progression.upgrade_points).is_equal(0)
	assert_dict(_progression.xp_by_source).is_empty()
	assert_dict(_progression.taken).is_empty()
	assert_float(_progression.get_stat("max_hp")).is_equal_approx(100.0, 0.001)
	assert_float(_progression.get_stat("mining_speed")).is_equal_approx(1.0, 0.001)

# --- Helpers -------------------------------------------------------------------


## Points without caring about the curve: the tree cases are about spending them.
func _grant_points(count: int) -> void:
	_progression.upgrade_points = count
