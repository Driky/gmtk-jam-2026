## Anything that radiates a coverage disc: the relay uses this script directly,
## the generator subclasses it to burn fuel and supply the grid.
##
## ❗️**The relay ships as this class with no supply at all** (✂️5 not fired). It
## costs exactly one class split, and the graph code is identical either way —
## `PowerGrid` sees a disc, and whether that disc also feeds the grid is one
## `power_supply()` return value. What it buys is the reason to build outward:
## a generator has a small radius and a relay chain reaches the mine.
##
## Owning doc: docs/systems/automation.md §Power
class_name PowerEmitter
extends Deployable

## Injected by tests; falls back to the autoload, so a test registers against its
## own Automation instance rather than the live one.
var automation: Node = null


func on_placed() -> void:
	_automation().register_emitter(self)


func on_removed() -> void:
	_automation().unregister_emitter(self)


## One tick of whatever keeps this thing supplying — a no-op for a relay, one
## step of the fuel burn for a generator. Called by `Automation` at the top of
## the tick, BEFORE supply is read, so a generator that runs dry this tick stops
## powering on this tick rather than one late.
func burn_tick() -> void:
	pass


## What this adds to its grid's supply, right now. ❗️Zero for a relay, and that
## is the whole of "a relay extends coverage but generates nothing" — no flag,
## no type check in the solver.
func power_supply() -> float:
	return 0.0


func _automation() -> Node:
	if automation == null:
		automation = Automation
	return automation
