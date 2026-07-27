## Guards what a run opens with (roadmap 1.6 tool, 2.7 torches). The list is
## data on main.gd precisely so this can assert it: the torches were silently
## dropped from it once by a stray `git checkout` during a screenshot run, and
## nothing caught it until an empty hotbar showed up in a browser build.
extends GdUnitTestSuite

const MainScript := preload("res://scripts/game/main.gd")


func _kit_count(id: String) -> int:
	var total := 0
	for entry: Array in MainScript.STARTING_KIT:
		if entry[0] == id:
			total += entry[1] as int
	return total


## Bare hands mine at 2.0 hardness/s — a run without a tool is a slog.
func test_a_run_opens_with_a_pickaxe() -> void:
	assert_int(_kit_count("pickaxe_t1")).is_greater(0)


## Depth is the progression axis and depth is dark: a run with no light cannot
## descend at all, so the torches are not a nicety.
func test_a_run_opens_with_enough_torches_to_descend() -> void:
	assert_int(_kit_count("torch")).is_greater_equal(10)


## ❗️**The kit is added FIRST, so every entry pushes everything handed over later
## one slot closer to falling off the hotbar** — and past slot ten it cannot be
## selected at all until 3.6. That is not hypothetical: 3.5a overflowed it and the
## rig's coal fell off the end, leaving a chain that could never be fuelled. This
## caps the kit well inside the hotbar so the rig and a wave's loot still fit.
func test_the_kit_leaves_most_of_the_hotbar_free() -> void:
	assert_int(MainScript.STARTING_KIT.size()).override_failure_message(
		"The starting kit is crowding the hotbar — see debug_menu.gd's RIG_KIT",
	).is_less_equal(3)


## ⚠️ Dropped at 3.5a: the turret is the pooled projectile system's live consumer
## now, so the placeholder caster no longer earns a permanent slot. It stays an
## authored item, so the ranged path is still one give-item click away.
func test_the_placeholder_caster_no_longer_takes_a_slot() -> void:
	assert_int(_kit_count("bolt_caster")).is_equal(0)
	assert_bool(ItemDefs.STATS.has("bolt_caster")).override_failure_message(
		"The caster must remain giveable — it is the only hand-driven ranged test",
	).is_true()


## Every id has to be something the inventory and the hotbar can actually
## render and use — a typo here is a dead slot with no error anywhere.
func test_every_kit_id_resolves_to_real_item_stats() -> void:
	for entry: Array in MainScript.STARTING_KIT:
		var id: String = entry[0]
		var is_known: bool = ItemDefs.STATS.has(id) or Materials.MATERIALS.has(id)
		assert_bool(is_known).override_failure_message(
			"Starting-kit id '%s' resolves to nothing" % id,
		).is_true()
		assert_int(entry[1] as int).is_greater(0)
