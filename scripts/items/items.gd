## Item/recipe DB, crafting-range queries. Owning doc: docs/systems/progression.md
extends Node

## Lives here (not on the player node) so crafting-range queries (3.6) and
## save serialization (4.3) never need a player reference.
var player_inventory := Inventory.new()


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
func reset_run() -> void:
	player_inventory = Inventory.new()
