## Unit tests for the skill-tree table (roadmap 3.7). `SkillDefs` is static and
## pure, mirroring `ItemDefs` and `RecipeDefs`, so none of this needs an autoload.
##
## The cases here are the ones a plausible roster gets wrong SILENTLY:
## - a `.tres` whose `id` disagrees with its `NODES` key resolves through one path
##   and not the other, and the tab looks fine until something asks by id
## - a prerequisite naming a node that does not exist locks its subtree forever
##   with no error anywhere
## - a root priced in bars is a deadlock at level 2, which is exactly the failure
##   the bootstrap-recipe rule already forbids one layer down
## - a node placed outside the canvas rect renders INVISIBLE rather than broken.
extends GdUnitTestSuite

# --- Integrity ----------------------------------------------------------------

func test_every_node_id_matches_its_key() -> void:
	for key: String in SkillDefs.NODES:
		var node: SkillNode = SkillDefs.NODES[key]
		assert_str(node.id).override_failure_message(
			"Node under key '%s' carries id '%s'" % [key, node.id],
		).is_equal(key)


func test_all_returns_every_node_in_authored_order() -> void:
	var nodes := SkillDefs.all()
	assert_int(nodes.size()).is_equal(SkillDefs.NODES.size())
	assert_str(nodes[0].id).is_equal("storage")
	assert_str(nodes[nodes.size() - 1].id).is_equal("conditioning")


## ⚠️ No fallback, deliberately: a mistyped node id is a bug in this table or in a
## recipe's `unlocked_by`, not something a neutral node should paper over.
func test_node_for_answers_null_for_an_unknown_id() -> void:
	assert_object(SkillDefs.node_for("no_such_node")).is_null()
	assert_object(SkillDefs.node_for("storage")).is_not_null()


func test_every_node_is_named_and_described() -> void:
	for node: SkillNode in SkillDefs.all():
		assert_str(node.display_name).override_failure_message(
			"Node '%s' has no display_name" % node.id,
		).is_not_empty()
		assert_str(node.description).override_failure_message(
			"Node '%s' has no description" % node.id,
		).is_not_empty()
		assert_int(node.point_cost).is_greater(0)
		assert_int(node.max_level).is_greater(0)


## A node naming a stat must move it, and one that names none must not carry a
## number nothing reads — either half is a button that silently does nothing.
func test_a_stat_node_carries_a_rate_and_a_plain_node_carries_none() -> void:
	for node: SkillNode in SkillDefs.all():
		if node.stat_name == "":
			assert_float(node.stat_per_level).override_failure_message(
				"Node '%s' names no stat but carries a rate" % node.id,
			).is_equal(0.0)
		else:
			assert_float(node.stat_per_level).override_failure_message(
				"Node '%s' names '%s' but moves it by 0" % [node.id, node.stat_name],
			).is_greater(0.0)


## An unlock-only node taken twice would spend a second point for nothing.
func test_only_a_buff_node_is_multi_level() -> void:
	for node: SkillNode in SkillDefs.all():
		if node.max_level > 1:
			assert_str(node.stat_name).override_failure_message(
				"Node '%s' is multi-level but unlocks the same recipes twice" % node.id,
			).is_not_empty()

# --- Prerequisites -------------------------------------------------------------


func test_every_prerequisite_names_a_real_node() -> void:
	for node: SkillNode in SkillDefs.all():
		for prereq: String in node.prerequisites:
			assert_object(SkillDefs.node_for(prereq)).override_failure_message(
				"Node '%s' requires '%s', which does not exist" % [node.id, prereq],
			).is_not_null()


## ❗️A cycle is unreachable rather than infinite: nothing in `can_take` loops
## forever, the whole subtree simply can never be bought, and no error is raised.
func test_no_node_depends_on_itself_directly_or_transitively() -> void:
	for node: SkillNode in SkillDefs.all():
		assert_bool(_reaches(node.id, node.id)).override_failure_message(
			"Node '%s' is its own (transitive) prerequisite" % node.id,
		).is_false()


## ❗️**The roots are what a level-2 player can actually buy.** One point, and
## whatever ore was dug by hand — so a root priced in `copper_bar` is the same
## deadlock the bootstrap-recipe rule forbids for the generator
## ([progression.md](../../docs/systems/progression.md) §Recipe tiers).
func test_every_root_costs_points_only() -> void:
	var roots := 0
	for node: SkillNode in SkillDefs.all():
		if not node.prerequisites.is_empty():
			continue
		roots += 1
		assert_bool(node.resource_cost.is_empty()).override_failure_message(
			"Root node '%s' costs resources a fresh run may not have" % node.id,
		).is_true()
		assert_int(node.point_cost).is_equal(1)
	assert_int(roots).is_greater(0)


## Every `resource_cost` id must be something the rest of the game can resolve —
## an authored item or an ordinary material that drops as itself, the same set
## `test_recipe_defs` holds a recipe's inputs to. A dangling id is a node that is
## unbuyable with no error anywhere: `gather_available` simply never reports it.
func test_every_resource_cost_resolves_to_a_real_item() -> void:
	var known := DebugMenu.giveable_ids()
	for node: SkillNode in SkillDefs.all():
		for id: String in node.resource_cost:
			assert_bool(known.has(id)).override_failure_message(
				"Node '%s' costs '%s', which is not a real item id" % [node.id, id],
			).is_true()
			assert_int(node.resource_cost[id]).is_greater(0)

# --- Shape rules the roster exists to keep -------------------------------------


## ❗️**Both yields are MACHINE buffs** (automation.md §Deployable base), so a node
## granting one before `mechanization` unlocks the miner and the furnace is a point
## spent on nothing — a trap purchase the tree's shape has to make impossible.
func test_every_yield_node_sits_behind_mechanization() -> void:
	for node: SkillNode in SkillDefs.all():
		if not node.stat_name.ends_with("_yield"):
			continue
		assert_bool(_reaches(node.id, "mechanization")).override_failure_message(
			"Yield node '%s' can be bought before a machine exists to carry it" % node.id,
		).is_true()


## ❗️The miner and the furnace both carry `power_demand = 1.0`. Unlocking them
## before the grid hands the player two machines that cannot run and no way to
## power them — the tree restating what prices the generator in mined materials.
func test_mechanization_sits_behind_the_power_grid() -> void:
	assert_bool(_reaches("mechanization", "power_grid")).is_true()


## ⚠️ Off-screen UI renders INVISIBLE with `visible` still true — a bug that reads
## as a missing feature. The canvas rect the tab scrolls and the rect checked here
## are one number, which is why `CANVAS_SIZE` lives on the table.
func test_every_position_is_inside_the_canvas() -> void:
	var canvas := Rect2(Vector2.ZERO, SkillDefs.CANVAS_SIZE)
	for node: SkillNode in SkillDefs.all():
		var rect := Rect2(node.position, SkillDefs.NODE_SIZE)
		assert_bool(canvas.encloses(rect)).override_failure_message(
			"Node '%s' at %s falls outside the %s canvas" % [
				node.id,
				node.position,
				SkillDefs.CANVAS_SIZE,
			],
		).is_true()


## Two nodes on the same spot is one node you can never press.
func test_no_two_nodes_overlap() -> void:
	var nodes := SkillDefs.all()
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var a := Rect2(nodes[i].position, SkillDefs.NODE_SIZE)
			var b := Rect2(nodes[j].position, SkillDefs.NODE_SIZE)
			assert_bool(a.intersects(b)).override_failure_message(
				"Nodes '%s' and '%s' overlap on the canvas" % [nodes[i].id, nodes[j].id],
			).is_false()

# --- Helpers -------------------------------------------------------------------


## Is `target` a (transitive) prerequisite of `id`? Depth-first with a visited set,
## so a cycle in the data terminates the search rather than this suite.
func _reaches(id: String, target: String) -> bool:
	var seen: Dictionary = { }
	var stack := PackedStringArray()
	var start := SkillDefs.node_for(id)
	if start != null:
		stack.append_array(start.prerequisites)
	while not stack.is_empty():
		var next := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if next == target:
			return true
		if seen.has(next):
			continue
		seen[next] = true
		var node := SkillDefs.node_for(next)
		if node != null:
			stack.append_array(node.prerequisites)
	return false
