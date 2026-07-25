## Item/recipe DB, crafting-range queries. Owning doc: docs/systems/progression.md
extends Node

## Lives here (not on the player node) so crafting-range queries (3.6) and
## save serialization (4.3) never need a player reference.
var player_inventory := Inventory.new()
