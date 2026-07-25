## Unit tests for the named-section frame profiler. Static state, so every
## test resets first.
extends GdUnitTestSuite

const PerfScript := preload("res://scripts/debug/perf.gd")


func before_test() -> void:
	Perf.reset()
	Perf.enabled = true


func after_test() -> void:
	Perf.reset()


## Burn wall-clock so a section registers a non-zero cost.
func _spin(usec: int) -> void:
	var until := Time.get_ticks_usec() + usec
	while Time.get_ticks_usec() < until:
		pass


func test_no_sections_reports_none() -> void:
	assert_str(Perf.format_top(3)).is_equal("sections: none")


func test_section_records_time_and_calls() -> void:
	Perf.begin(&"a")
	_spin(2000)
	Perf.end()
	var rows := Perf.top_sections(3)
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0].name).is_equal("a")
	assert_float(rows[0].worst_ms).is_greater(1.0)
	assert_int(rows[0].calls).is_equal(1)


## The headline is the worst SINGLE frame, so repeated cheap calls in later
## frames must not dilute an earlier spike.
func test_worst_is_a_max_not_an_average() -> void:
	Perf.begin(&"a")
	_spin(3000)
	Perf.end()
	var spike: float = Perf.top_sections(1)[0].worst_ms
	for i in 20:
		Perf._frame = -1 # Force a frame boundary without rendering.
		Perf.begin(&"a")
		Perf.end()
	var rows := Perf.top_sections(1)
	assert_float(rows[0].worst_ms).is_equal_approx(spike, 0.5)
	assert_int(rows[0].calls).is_equal(21)


## Two calls inside one frame are one frame's cost for that section.
func test_calls_within_a_frame_accumulate() -> void:
	Perf.begin(&"a")
	_spin(1500)
	Perf.end()
	Perf.begin(&"a")
	_spin(1500)
	Perf.end()
	var rows := Perf.top_sections(1)
	assert_float(rows[0].worst_ms).is_greater(2.5) # Both halves, not one.
	assert_int(rows[0].calls).is_equal(2)


func test_sections_rank_by_worst_frame() -> void:
	Perf.begin(&"cheap")
	Perf.end()
	Perf.begin(&"expensive")
	_spin(3000)
	Perf.end()
	var rows := Perf.top_sections(2)
	assert_str(rows[0].name).is_equal("expensive")
	assert_str(rows[1].name).is_equal("cheap")


func test_top_sections_respects_the_limit() -> void:
	for name in ["a", "b", "c", "d"]:
		Perf.begin(StringName(name))
		Perf.end()
	assert_int(Perf.top_sections(2).size()).is_equal(2)


func test_nesting_pops_in_order() -> void:
	Perf.begin(&"outer")
	Perf.begin(&"inner")
	_spin(1500)
	Perf.end()
	Perf.end()
	var rows := Perf.top_sections(5)
	var names: Array[String] = []
	for row in rows:
		names.append(row.name)
	assert_array(names).contains(["outer", "inner"])
	# Parent includes child by design.
	for row in rows:
		if row.name == "outer":
			assert_float(row.worst_ms).is_greater_equal(1.0)


func test_disabled_records_nothing() -> void:
	Perf.enabled = false
	Perf.begin(&"a")
	_spin(1500)
	Perf.end()
	assert_array(Perf.top_sections(3)).is_empty()


## A stray end() (mismatched instrumentation) must not corrupt later readings.
func test_unbalanced_end_is_ignored() -> void:
	Perf.end()
	Perf.begin(&"a")
	Perf.end()
	assert_int(Perf.top_sections(1)[0].calls).is_equal(1)


func test_reset_clears_everything() -> void:
	Perf.begin(&"a")
	_spin(1500)
	Perf.end()
	Perf.reset()
	assert_array(Perf.top_sections(3)).is_empty()
	assert_str(Perf.format_top(3)).is_equal("sections: none")


func test_format_top_names_the_worst_first() -> void:
	Perf.begin(&"cheap")
	Perf.end()
	Perf.begin(&"expensive")
	_spin(3000)
	Perf.end()
	var text := Perf.format_top(2)
	assert_str(text).starts_with("worst frame by section: expensive")
	assert_str(text).contains("cheap")
