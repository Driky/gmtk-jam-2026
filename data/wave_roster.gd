## Wave composition table: the budget curve and which mob types a wave may
## spend it on. All numbers are Day-2 stubs, balanced Day 4 (roadmap 4.6).
## Owning doc: docs/systems/enemies.md
##
## Day-4 mobs (leaper, digger, crawler, flyer) land here as extra ENTRIES rows
## and nothing else changes; the reachability-adaptive skew (Day 4, cut line 9)
## biases `weight` at build_queue time.
class_name WaveRoster

const WALKER: EnemyStats = preload("res://data/enemies/walker.tres")

## B(n) = BASE_BUDGET * BUDGET_GROWTH^(n-1), floored, never below one mob.
## Wave 1 = 3, wave 10 ~ 22, wave 15 ~ 68.
const BASE_BUDGET := 3.0
const BUDGET_GROWTH := 1.25

## cost = budget spent per spawn · unlock = first wave the type may appear ·
## weight = relative pick chance among the unlocked, affordable types.
const ENTRIES: Array[Dictionary] = [
	{ stats = WALKER, cost = 1, unlock = 1, weight = 1.0 },
]


static func budget_for(wave: int) -> int:
	return maxi(1, floori(BASE_BUDGET * pow(BUDGET_GROWTH, wave - 1)))


## Pre-roll a whole wave into a spawn list. Rolling up front (rather than
## picking per spawn tick) makes the HUD's "X remaining" an exact head count
## instead of a cost-weighted number, and gives the Day-4 skew one hook.
static func build_queue(rng: RandomNumberGenerator, wave: int) -> Array[EnemyStats]:
	var queue: Array[EnemyStats] = []
	var budget := budget_for(wave)
	while true:
		var entry := pick(rng, wave, budget)
		if entry.is_empty(): # Nothing unlocked is affordable — budget stranded.
			break
		queue.append(entry.stats)
		budget -= int(entry.cost)
	return queue


## Weighted pick among types unlocked at `wave` and costing <= `budget_left`
## {} when none qualify.
static func pick(rng: RandomNumberGenerator, wave: int, budget_left: int) -> Dictionary:
	var total := 0.0
	for entry in ENTRIES:
		if entry.unlock <= wave and entry.cost <= budget_left:
			total += entry.weight
	if total <= 0.0:
		return { }
	var roll := rng.randf() * total
	var last: Dictionary = { }
	for entry in ENTRIES:
		if entry.unlock > wave or entry.cost > budget_left:
			continue
		last = entry # Float slop can undershoot the last slice — fall back to it.
		roll -= entry.weight
		if roll <= 0.0:
			return entry
	return last
