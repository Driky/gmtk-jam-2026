## Unit tests for the wave composition table (roadmap 2.4): budget curve and
## the pre-rolled spawn queue. Pure statics — no tree, no autoloads.
extends GdUnitTestSuite

const Roster := preload("res://data/wave_roster.gd")


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_budget_at_wave_one_is_the_base() -> void:
	assert_int(Roster.budget_for(1)).is_equal(3)


func test_budget_grows_and_never_shrinks() -> void:
	var previous := 0
	for wave in range(1, 30):
		var budget := Roster.budget_for(wave)
		assert_int(budget).is_greater_equal(previous)
		previous = budget
	assert_int(Roster.budget_for(29)).is_greater(Roster.budget_for(1))


func test_budget_floors_to_at_least_one_mob() -> void:
	# Waves are 1-based; a defensive 0/negative must still yield a spawnable wave.
	assert_int(Roster.budget_for(0)).is_greater_equal(1)
	assert_int(Roster.budget_for(-5)).is_greater_equal(1)


func test_queue_spends_the_whole_budget() -> void:
	# Every current entry costs 1, so the head count equals the budget exactly.
	for wave in [1, 5, 12]:
		var queue := Roster.build_queue(_rng(wave), wave)
		var spent := 0
		for stats in queue:
			spent += int(_entry_for(stats).cost)
		assert_int(spent).is_equal(Roster.budget_for(wave))


func test_queue_never_exceeds_the_budget() -> void:
	for wave in range(1, 20):
		var queue := Roster.build_queue(_rng(wave), wave)
		var spent := 0
		for stats in queue:
			spent += int(_entry_for(stats).cost)
		assert_int(spent).is_less_equal(Roster.budget_for(wave))


func test_queue_only_holds_unlocked_types() -> void:
	var queue := Roster.build_queue(_rng(7), 1)
	assert_array(queue).is_not_empty()
	for stats in queue:
		assert_int(_entry_for(stats).unlock).is_less_equal(1)


func test_same_seed_same_queue() -> void:
	# Save-replay determinism: (world_seed, wave) must reproduce the wave.
	var a := Roster.build_queue(_rng(42), 6)
	var b := Roster.build_queue(_rng(42), 6)
	assert_array(a).is_equal(b)


func test_pick_returns_empty_when_nothing_is_affordable() -> void:
	assert_dict(Roster.pick(_rng(1), 1, 0)).is_empty()


func test_pick_returns_empty_before_unlock() -> void:
	assert_dict(Roster.pick(_rng(1), 0, 99)).is_empty()


func _entry_for(stats: EnemyStats) -> Dictionary:
	for entry in Roster.ENTRIES:
		if entry.stats == stats:
			return entry
	return { }
