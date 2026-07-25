## XP, levels, stats, skill tree. Owning doc: docs/systems/progression.md
##
## Node-free by design: this never reaches for the Player. A level-up emits
## `leveled_up` and the Player decides what that means for its current HP —
## which keeps the autoload testable without a scene.
extends Node

## Current XP toward the next level, and what that level costs. Emitted once
## per grant, even when the grant crossed several levels.
signal xp_changed(current: float, needed: float, level: int)
## A level was gained. Fires once per level, so a grant big enough to cross
## three levels announces three times — the HUD banner and any future
## level-up feedback see every step, not just the final number.
signal leveled_up(level: int, upgrade_points: int)

## Flat base values. Skill-tree buffs (3.7) multiply these; levels add to them.
const _BASE_STATS := {
	max_hp = 100.0,
	max_mana = 50.0,
	move_speed = 110.0,
	mining_speed = 1.0,
}

## Added per level beyond the first. A stat absent here is level-independent —
## `mining_speed` is deliberately one of those: it's the skill tree's job.
const _PER_LEVEL := {
	max_hp = 10.0,
	max_mana = 5.0,
	move_speed = 2.0,
}

## Curve: xp_to_level(L) = XP_BASE * L^XP_EXP. Day-4 tuning knob (4.6) —
## expect it to be too generous on the first playtest.
const XP_BASE := 50.0
const XP_EXP := 1.6

## Mining pays a flat rate per block broken, NOT hardness — digging deeper is
## rewarded through what the block DROPS (Materials.loot_xp), not through how
## long it took to break. Otherwise a slow tool would out-earn a fast one.
const MINING_XP_PER_BLOCK := 1.0

var level := 1
## Progress toward the NEXT level; reset to the remainder on each level-up.
var xp := 0.0
## Spent in the skill tree (3.7). Until then they simply accumulate.
var upgrade_points := 0
## Lifetime XP per source id ("mining" / "looting" / "kills"). Exists for the
## Day-4 balance pass: "where is XP actually coming from" is the question the
## curve gets tuned against, and it's unanswerable after the fact otherwise.
var xp_by_source: Dictionary[String, float] = { }


## Every XP source routes through here (progression.md). `source` is recorded
## rather than branched on — the amount is decided by the caller, which is what
## keeps mining/looting/kill rates independently tunable.
func grant_xp(source: String, amount: float) -> void:
	if amount <= 0.0:
		return
	xp += amount
	xp_by_source[source] = xp_by_source.get(source, 0.0) + amount
	# while, not if: a single grant may cross several levels (the debug XP
	# button does exactly that, and so will a boss kill).
	while xp >= xp_to_level(level):
		xp -= xp_to_level(level)
		_level_up()
	xp_changed.emit(xp, xp_to_level(level), level)


## XP required to advance FROM level `l` to l+1. Static so tests and a tuning
## pass can plot the curve without the autoload.
static func xp_to_level(l: int) -> float:
	return XP_BASE * pow(l, XP_EXP)


## XP the current level still needs — what the HUD bar measures against.
func xp_needed() -> float:
	return xp_to_level(level)


## Single stat lookup for all gameplay code: flat base, plus a flat per-level
## grant, times the skill tree's multiplier. Unknown stats read as a neutral
## 1.0 (base 1.0, no per-level, no multiplier), which is what lets
## ItemStats.effective_* ask for buffs that don't exist yet.
func get_stat(stat_name: String) -> float:
	var base: float = _BASE_STATS.get(stat_name, 1.0)
	var per_level: float = _PER_LEVEL.get(stat_name, 0.0)
	return (base + per_level * (level - 1)) * _multiplier(stat_name)


## Wipe all run state ahead of a scene reload (restart flow, 2.1). Every
## autoload holding run state exposes reset_run() — tech-design.md. Direct
## assignment, no emit: the reload re-seeds every listener from _ready.
func reset_run() -> void:
	level = 1
	xp = 0.0
	upgrade_points = 0
	xp_by_source.clear()

# --- Internals ---------------------------------------------------------------


func _level_up() -> void:
	level += 1
	upgrade_points += 1
	leveled_up.emit(level, upgrade_points)


## Skill-tree buff product for a stat (3.7). Neutral until the tree exists —
## the seam is here so no call site changes when it lands.
func _multiplier(_stat_name: String) -> float:
	return 1.0
