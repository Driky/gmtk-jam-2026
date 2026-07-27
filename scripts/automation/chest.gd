## A placed chest: 20 slots that anything can put items into and take items out
## of. The first Utility deployable ([automation.md](../../docs/systems/automation.md)
## §Categories) and the first N-slot container in the game.
##
## ❗️**It owns an `Inventory`, it does not re-implement one.** Every machine so
## far hand-rolls one or two bare `{id, count}` dicts because one or two is all it
## needs; twenty would be a third shape with its own stacking bugs. `Inventory` is
## already a player-agnostic `RefCounted` with per-slot change signals, so the
## chest just constructs one at its own size — that is what 3.5c made `_init`
## take a size for.
##
## **No tick and no registry**, the `Torch` shape: an inserter reaches a chest
## through `Terrain.get_entity` and the transfer seam, so there is nothing for
## `Automation` to call every 100 ms. Registering it anyway — for the F3 slot
## overlay, say — would put a node that does nothing in the tick loop.
##
## ✅ **The container UI landed at 3.6a**: `E` over a chest in reach opens the
## character screen's container panel against the `storage()` seam below. The one
## thing that added here is `on_removed` — everything else stays true, and a chest
## is still fully usable without the panel (inserters both ways, RMB hand-feeds one
## item per click, and swinging it down pops every stack).
##
## Owning doc: docs/systems/automation.md
class_name Chest
extends Deployable

## Half the player's 40. Big enough that one chest is a real buffer, small enough
## that the 3.6 container view is one screenful beside the player's own grid.
const CHEST_SLOTS := 20

var _storage := Inventory.new(CHEST_SLOTS)


## ❗️The 3.6 seam, and the reason this step shipped before the character screen:
## the container view binds `slot_changed` on this exactly as the HUD hotbar binds
## the player's, and 3.6b's `Items.gather_available(player_pos)` will read it too.
##
## Handed out live rather than copied — a snapshot could not emit, and a UI that
## has to poll a chest is a UI that shows stale counts while an inserter fills it.
##
## ⚠️ It is also what `Player.interact` duck-types on: **having this method is what
## makes something a container**, so 4.x's next one needs no edit anywhere else.
func storage() -> Inventory:
	return _storage


## ❗️Close the panel before this chest stops being a chest.
##
## `pop_to_pickup`'s order is: free the cells → **`on_removed()`** → `take_cargo()`
## → `queue_free()`. That puts this hook before the chest empties and before it is
## freed, so the panel closes while everything is still valid and a stack held on
## the cursor goes back to the PLAYER's inventory rather than into a dying
## container. `deployable.gd` needs no change for it.
##
## ❗️**Reached by GROUP, and naming `CharacterScreen` here is not an option.** It
## closes a real dependency cycle, through a RESOURCE rather than through code:
##
##     chest.gd → CharacterScreen → ItemSlot → Hud → ItemDefs
##              → chest.tres (`place_scene`) → chest.tscn → chest.gd
##
## Godot cannot resolve `ItemDefs.STATS` inside it, so the HUD fails to compile and
## takes the give-item row and every slot icon down with it. Every deployable that
## an `ItemDefs` row can place is inside that loop, which is why none of them
## reference the UI by class name. The group is the same escape `pickup_spawner`
## and `respawn_beacon` already use, and it dies with the scene for free.
##
## No-op with no screen in the tree, so headless tests are unaffected.
func on_removed() -> void:
	for screen in get_tree().get_nodes_in_group(&"character_screen"):
		screen.hide_container(self)


## Takes what fits and reports it. A partial accept is legal by the seam's
## contract, and `add_item` already returns the leftover — so "how many it took"
## is the count minus that, with no second pass over the slots.
func accept_item(id: String, count: int) -> int:
	if count <= 0:
		return 0
	return count - _storage.add_item(id, count)


## The first non-empty slot, in slot order. Detached because `remove_from_slot`
## hands back a fresh `{id, count}` of what it actually removed, never the slot.
##
## First-slot rather than a filter: the seam has no id argument, so an inserter
## pointed at a chest empties it in slot order. Sorting or filtering is a 3.6
## concern the UI owns, not something the transfer path should guess at.
func extract_item(max_count := 1) -> Dictionary:
	if max_count <= 0:
		return { }
	for i in _storage.slot_count():
		var slot := _storage.get_slot(i)
		if slot.is_empty():
			continue
		var moved: int = mini(max_count, slot.count)
		var id: String = slot.id
		_storage.remove_from_slot(i, moved)
		return { id = id, count = moved }
	return { }


## Everything, so swinging a chest down drops its contents beside it rather than
## deleting them. `take_range` is destructive and already returns detached copies,
## which is exactly this contract.
func take_cargo() -> Array[Dictionary]:
	return _storage.take_range(0, _storage.slot_count())
