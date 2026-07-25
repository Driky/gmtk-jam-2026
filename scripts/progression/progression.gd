## XP, levels, stats, skill tree. Owning doc: docs/systems/progression.md
extends Node

## Flat base values until levels (2.6) and skill-tree buffs (3.7) multiply them.
const _BASE_STATS := {
	max_hp = 100.0,
	max_mana = 50.0,
	move_speed = 110.0,
	mining_speed = 1.0,
}


## Single stat lookup for all gameplay code; unknown stats read as neutral 1.0.
func get_stat(stat_name: String) -> float:
	return _BASE_STATS.get(stat_name, 1.0)
