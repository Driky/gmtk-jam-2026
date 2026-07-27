## Per-item combat and mining numbers. Everything the player does with the
## active hotbar item reads from here — there are no combat constants on the
## Player. That makes a tool a design space rather than a fixed upgrade curve:
## a fast, low-damage, high-knockback pickaxe is a "mine while shoving mobs off
## you" tool, and a slow heavy one is a weapon that also digs.
## Owning doc: docs/systems/player-combat.md
class_name ItemStats
extends Resource

## What one `use` (LMB) does. Every item is usable — bare hand and plain blocks
## resolve to swing defaults (data/item_defs.gd), so there is no "unusable item"
## branch anywhere in the player.
enum UseKind { SWING, PROJECTILE }

## Which equipment slot an item is worn in, `NONE` for everything that is not
## wearable ([ui.md](../../docs/systems/ui.md) §Character screen).
##
## ❗️**A SEPARATE enum from `Equipment.Slot`, and `RING` is ONE value here.** The
## panel has two ring slots; `Equipment.slot_accepts` answers true for both, so an
## item never learns there are two and a second ring is never a second `.tres`.
##
## ❗️**This is why the field lives on `ItemStats` at all.** `ItemDefs.stats_for`
## never returns null and both its fallbacks default to `NONE`, so every existing
## authored item and every `Materials.ORDER` id is non-equippable with zero data
## migration — and a `.tres` authored with a stray slot is caught by a test rather
## than by wearing a conveyor.
enum EquipSlot { NONE, HELMET, CHEST, LEGS, FEET, BACK, RING, NECKLACE }

@export var display_name := ""
## Hotbar swatch until real art lands (4.2). Blocks draw their tile instead —
## only authored items reach this ([ui.md](../../docs/systems/ui.md) icon rules).
@export var icon_color := Color(0.75, 0.75, 0.8)
@export var use_kind := UseKind.SWING
## Seconds between uses — swing rate and fire rate are the same knob.
@export var use_cooldown := 0.35

@export_group("Mining")
@export var mining_power := 2.0 ## Hardness per second of held mining.
@export var tool_tier := 1 ## Gates deeper blocks via Materials.min_tool_tier.

@export_group("Melee")
@export var melee_damage := 3.0
@export var knockback := 60.0 ## px/s imparted away from the swinger.
## null = the default arc scene. A custom scene may carry several shapes (one
## set per swing step) — see scripts/combat/swing_hitbox.gd.
@export var hitbox_scene: PackedScene = null
@export var arc_degrees := 90.0 ## Sweep the default arc travels through.
@export var active_window := 0.15 ## Seconds the hitbox stays enabled.

@export_group("Placement")
## Non-null makes `place` (RMB) put this SCENE in the target cell instead of
## writing a tile — the seam Day 3's deployables land on, so a miner or a turret
## is a .tres row rather than another branch in the player. It wins over the
## material-id block path, and the scene's root must be a `Deployable`
## ([automation.md](../../docs/systems/automation.md)) — the player reads its
## `size` and `support_dirs` to validate the placement before claiming a cell.
@export var place_scene: PackedScene = null

@export_group("Equipment")
@export var equip_slot := EquipSlot.NONE
## Damage reduction fed to `Player.mitigate` through `Equipment.armor_total()`
## ([player-combat.md](../../docs/systems/player-combat.md) §Taking damage). Flat
## points, not a fraction — the curve is the player's.
@export var armor := 0.0

@export_group("Ranged")
## What a PROJECTILE item fires. Ammo and mana costs are 4.2 — the placeholder
## caster is free so the pooled system has a live consumer before 3.5's
## turrets depend on it.
@export var projectile: ProjectileStats = null


## Buff seam: every gameplay read goes through one of these, so skill-tree
## buffs (3.7) and any later debuff land without touching an item or a call
## site. `Progression.get_stat` already returns a neutral 1.0 for unknown
## names. The provider is injectable so this unit-tests without the autoload.
func effective_mining_power(progression: Node = null) -> float:
	return mining_power * _stat(progression, "mining_speed")


func effective_melee_damage(progression: Node = null) -> float:
	return melee_damage * _stat(progression, "melee_damage")


func effective_knockback(progression: Node = null) -> float:
	return knockback * _stat(progression, "knockback")


## Faster swings are a HIGHER stat, so the multiplier divides the cooldown.
func effective_cooldown(progression: Node = null) -> float:
	return use_cooldown / maxf(_stat(progression, "swing_speed"), 0.01)


func _stat(progression: Node, stat_name: String) -> float:
	return (progression if progression != null else Progression).get_stat(stat_name)
