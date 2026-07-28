## Item/recipe DB, crafting-range queries. Owning doc: docs/systems/progression.md
extends Node

## Lives here (not on the player node) so crafting-range queries (3.6) and
## save serialization (4.3) never need a player reference.
var player_inventory := Inventory.new()

## What the player is wearing (3.6a). Beside the inventory rather than inside it
## for the reason `equipment.gd` gives: `add_item` would put a helmet in the feet
## slot from any auto-fill path. `Player.take_damage` reads `armor_total()`.
var equipment := Equipment.new()


## Per-item combat/mining numbers for an item id ("" = bare hand). The one
## lookup every gameplay read goes through; the table and the resolution chain
## live in data/item_defs.gd ([player-combat.md](../../docs/systems/player-combat.md)).
func stats_for(id: String) -> ItemStats:
	return ItemDefs.stats_for(id)


## Stats of whatever the player currently has selected — the hot path for the
## use verb (2.5). An empty slot resolves to bare hands.
func selected_stats() -> ItemStats:
	var slot := player_inventory.selected_item()
	return stats_for(slot.get("id", ""))


## Fresh inventory ahead of a scene reload (restart flow, 2.1); connectees
## are scene nodes that die in the reload, so dropping them is safe.
##
## ❗️The equipment line is not optional and the omission is invisible until run
## two: forget it and you keep last run's armor, silently, forever.
func reset_run() -> void:
	player_inventory = Inventory.new()
	equipment = Equipment.new()

# --- Crafting range (3.6b) ----------------------------------------------------
#
# Every crafting-cost check in the game draws from these three: the hand crafting
# tab, player-initiated station crafting, and 3.7's tree `resource_cost` unlocks
# ([progression.md](../../docs/systems/progression.md) §Crafting range).
#
# ❗️**Equipment is excluded, by construction**: `equipment` is a separate object
# and nothing below reads it. Crafting out of your worn helmet means the consume
# step can silently un-equip you, and "why did my armor vanish" is a bug report
# rather than a feature.
#
# ❗️**`Items` is an autoload `Node`, so `get_tree()` resolves** — but with no tree
# and with no container in the group these answer from the player inventory alone,
# so headless tests are unaffected.

## Containers this far from the player count toward a cost.
##
## ⚠️ Not `Player.REACH_RADIUS_PX` (4.5 tiles) — the only precedent, and far too
## small: you would have to stand on the chest.
const CRAFTING_RANGE_PX := 12.0 * TileLayout.TILE_SIZE

## How a container is FOUND — a group declared on the scene root, the
## `respawn_beacon.tscn` convention ([automation.md](../../docs/systems/automation.md)
## §Categories → Utility owns the decision and why the two alternatives lost).
const CONTAINER_GROUP := &"container"


## Every container within `CRAFTING_RANGE_PX`, **row-major by `global_position`**
## (y, then x).
##
## ❗️**The order is STATED, not inherited.** `get_nodes_in_group` hands back
## scene-tree order, which drifts across [save.md](../../docs/systems/save.md)'s
## restore-in-file-order — so which chest a craft drains would change across a save
## round-trip. Sorted here rather than in each caller so the tally and the consume
## share one discovery *and* one order. Same argument that made the tick row-major.
##
## ⚠️ **The group loop is untyped.** A typed loop variable fails on the *assignment*
## of a freed instance, before any `is_instance_valid` guard in the body can run —
## what `tools/check_freed_safety.sh` blocks and what `Turret.pick_target` paid for.
## Duck-typed on `Node2D` + `storage()` rather than on `Deployable`: the radius
## filter already needs the position, and `storage()` is what makes something a
## container everywhere else (`Player.interact`, the container panel).
func containers_near(player_pos: Vector2) -> Array:
	var found: Array = []
	var tree := get_tree()
	if tree == null:
		return found
	for node in tree.get_nodes_in_group(CONTAINER_GROUP):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if not node.has_method(&"storage"):
			continue
		if (node as Node2D).global_position.distance_to(player_pos) > CRAFTING_RANGE_PX:
			continue
		found.append(node)
	found.sort_custom(_row_major)
	return found


## Flat `{item_id: total_count}` over the player inventory plus every container in
## range. Flat counts rather than a list of `Inventory`s because every consumer
## asks the same question: "do I have ≥ N of `id`".
func gather_available(player_pos: Vector2) -> Dictionary:
	var totals: Dictionary = { }
	_tally_into(player_inventory, totals)
	for node in containers_near(player_pos):
		_tally_into(node.storage(), totals)
	return totals


## Pay `inputs` (`{item_id: count}`) out of the same pool. True when the whole cost
## was taken, false when nothing was.
##
## ❗️**Two-phase, and this is the half most likely to ship broken.** `gather_available`
## is a flattened copy — it can *report* but not *remove*. A naive per-id loop that
## runs short on the last input has already eaten the first ones and produces
## nothing, which is an item sink with no error message. So: verify the **whole**
## cost first, and only then drain — player inventory first, then containers in
## `containers_near`'s stated order.
##
## ⚠️ An empty cost is refused rather than trivially granted: no recipe in the table
## has one, and treating it as payable would make a malformed row an infinite tap.
func consume_available(player_pos: Vector2, inputs: Dictionary) -> bool:
	if inputs.is_empty():
		return false
	# Discovered ONCE. Re-scanning between the phases would let the verified pool
	# and the drained pool be different sets.
	var containers := containers_near(player_pos)
	var available: Dictionary = { }
	_tally_into(player_inventory, available)
	for node in containers:
		_tally_into(node.storage(), available)
	for id: String in inputs:
		if available.get(id, 0) < inputs[id]:
			return false
	for id: String in inputs:
		var owed: int = inputs[id]
		owed -= player_inventory.remove_item(id, owed)
		for node in containers:
			if owed <= 0:
				break
			owed -= (node.storage() as Inventory).remove_item(id, owed)
	return true


## Row-major: y, then x. Compared exactly rather than approximately — containers
## are cell-aligned deployables, so this is a total order over any real set.
static func _row_major(a, b) -> bool:
	var pa: Vector2 = a.global_position
	var pb: Vector2 = b.global_position
	if pa.y != pb.y:
		return pa.y < pb.y
	return pa.x < pb.x


static func _tally_into(inv: Inventory, totals: Dictionary) -> void:
	for i in inv.slot_count():
		var slot := inv.get_slot(i)
		if slot.is_empty():
			continue
		totals[slot.id] = totals.get(slot.id, 0) + slot.count
