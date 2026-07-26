## Per-type enemy data: combat numbers plus locomotion capabilities. One base
## scene reads everything from this, so later mobs (leaper, digger — Day 4)
## are data-only. Owning doc: docs/systems/enemies.md
class_name EnemyStats
extends Resource

enum MoveClass { GROUND, FLY }

@export var display_name := "walker"
@export var max_hp := 30.0
@export var speed := 40.0 ## px/s (player move_speed is 110).
@export var damage := 8.0 ## Per melee hit on entities (Core, deployables).
@export var attack_cooldown := 0.8 ## Seconds between melee hits.
@export var xp := 5.0 ## Granted on death via Progression.grant_xp (2.6).
## Dropped as a world pickup on death, feeding the looting XP channel like any
## mined drop. "" = drops nothing. Real mob loot is content work (4.2); what's
## authored today is a placeholder to keep the path exercised.
@export var drop_id := ""
@export var drop_count := 1

@export_group("Locomotion")
@export var move_class := MoveClass.GROUND
@export var jump_height := 1 ## Tiles cleared by a hop; 0 = can't jump.
@export var climb_speed := 0.0 ## 0 = can't wall-climb.
@export var is_biped := true ## Gates climbable use (Day 3).
@export var dig_power := 1.0 ## Hardness/s chewed (player tool is 4.0).
@export var max_safe_fall := 3 ## Tiles fallen without taking damage.
@export var color := Color(0.75, 0.2, 0.2) ## Placeholder visual tint.
