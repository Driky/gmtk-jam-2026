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

@export var display_name := ""
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
