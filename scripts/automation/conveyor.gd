## One cell of scaffold tube: non-blocking, directional, items levitate through.
## Everything structural is `Deployable`'s — this owns one slot, one cooldown,
## one facing, and the two-phase advance pass for the whole group.
##
## Owning doc: docs/systems/automation.md
class_name Conveyor
extends Deployable

## Mark-phase memo states. RESOLVING is a conveyor we are currently inside, which
## can only happen on a genuine cycle — see `_can_move`.
const UNVISITED := 0
const RESOLVING := 1
const NO := 2
const YES := 3

## Ticks a stack waits here before it may move on: the tier lever, all data.
## 1 = one cell per tick (10 cells/s), 2 = every other tick. Set on RECEIPT, so
## a saturated line moves in lockstep.
@export var ticks_per_move := 1

## Injected by tests; falls back to the autoload, so a test registers against its
## own Automation instance rather than the live one.
var automation: Node = null

## THE slot: `{}` or `{ id: String, count: int }` — byte-identical to an
## `Inventory` slot, so a stack moves belt → inserter → chest with no conversion
## anywhere and `Inventory.STACK_SIZE` is the one cap.
var _slot: Dictionary = { }
var _cooldown := 0
## Where this belt's stack came from, for render interpolation. Reset to this
## belt's OWN cell at the top of every tick and overwritten by the commit only
## for a belt that actually received — which is what makes the interpolation
## self-correcting: a blocked item's lerp is a no-op and an arriving item's lerp
## runs for exactly one tick.
var _prev_cell := Vector2i.ZERO


## Overridden only to seed `_prev_cell`. Without it a hand-fed item would render
## flying in from cell (0, 0) on the frame before the first tick.
func setup(origin: Vector2i) -> void:
	super(origin)
	_prev_cell = origin


func on_placed() -> void:
	_automation().register_conveyor(self)


func on_removed() -> void:
	_automation().unregister_conveyor(self)


## Drained through `extract_item`, so the slot is genuinely empty afterwards and
## the stack cannot be dropped twice — the belt itself pops as one `conveyor_t1`,
## and the ore it was carrying lands beside it instead of evaporating.
func take_cargo() -> Array[Dictionary]:
	# Built up rather than returned as a ternary: an `[] if … else [stack]` is an
	# UNTYPED Array literal and 4.x rejects it against Array[Dictionary] at runtime,
	# not at parse time.
	var cargo: Array[Dictionary] = []
	var stack := extract_item(Inventory.STACK_SIZE)
	if not stack.is_empty():
		cargo.append(stack)
	return cargo

# --- Slot state --------------------------------------------------------------


func slot_empty() -> bool:
	return _slot.is_empty()


## Read-only view; `{}` when empty. Callers must not mutate the result — same
## contract as `Inventory.get_slot`.
func slot() -> Dictionary:
	return _slot


func cooldown() -> int:
	return _cooldown


## The cell the item is interpolating FROM this tick. Equal to `cell()` unless it
## arrived on the last tick.
func prev_cell() -> Vector2i:
	return _prev_cell


func target_cell() -> Vector2i:
	return _cell + facing

# --- The transfer seam -------------------------------------------------------


## Takes into an empty slot, or onto a matching id below the stack cap. A
## mismatched id is refused outright: merging two different stacks has nowhere to
## go with one slot, and merging identical ones under saturation is the
## **Stacker**'s job ([automation.md](../../docs/systems/automation.md)), so a
## belt deliberately does not densify by itself.
func accept_item(id: String, count: int) -> int:
	if count <= 0:
		return 0
	if _slot.is_empty():
		var taken: int = mini(count, Inventory.STACK_SIZE)
		_slot = { id = id, count = taken }
		# An item appearing in place must render parked rather than sliding in
		# from wherever this belt last received from.
		_prev_cell = _cell
		return taken
	if _slot.id != id:
		return 0
	var moved: int = mini(count, Inventory.STACK_SIZE - _slot.count)
	if moved <= 0:
		return 0
	_slot.count += moved
	return moved


func extract_item(max_count := 1) -> Dictionary:
	if _slot.is_empty() or max_count <= 0:
		return { }
	var moved: int = mini(max_count, _slot.count)
	var out := { id = _slot.id, count = moved }
	_slot.count -= moved
	if _slot.count <= 0:
		_slot = { }
	return out

# --- The advance pass --------------------------------------------------------

## Per-pass scratch. One instance per tick, so nothing leaks into the next one
## and there is no static state to reset. Untyped dictionaries on purpose: a
## Dictionary typed by an object key refuses to erase a freed instance in 4.x.


class Walk:
	extends RefCounted

	var resolve := { }
	var claims := { }
	var moves: Array[Dictionary] = []


## Advance every conveyor by one tick. Called from `Automation.step_tick()` with
## the registry in row-major order; static because the pass is a property of the
## group rather than of any one belt, and `terrain` is handed in so the whole
## thing runs against a fresh world in tests.
##
## Three passes, and all three are load-bearing:
##  0. **settle** — tick down cooldowns and reset every `_prev_cell` to self.
##  1. **mark** — walk the list and memoize who may move (`_can_move`).
##  2. **commit** — capture, clear, then write, in three separate sweeps.
static func advance_all(terrain: Node, conveyors: Array[Deployable]) -> void:
	# freed-safe: `conveyors` is `Automation._conveyors`, pruned eagerly on removal.
	for node: Deployable in conveyors:
		var c := node as Conveyor
		c._cooldown = maxi(c._cooldown - 1, 0)
		c._prev_cell = c._cell
	var walk := Walk.new()
	# freed-safe: same registry, same eager prune.
	for node: Deployable in conveyors:
		_can_move(terrain, node as Conveyor, walk)
	_commit(walk.moves)


## Memoized "does this belt vacate this tick?".
##
## ❗️Re-entering a belt that is already RESOLVING answers **true**, and that is
## CORRECT rather than a shortcut. A re-entry can only happen on a genuine cycle,
## because `_evaluate` never recurses into a belt that is empty and checks the
## target's cooldown *before* recursing — so every member of the cycle is full,
## ready, and pointing at the next one. The commit is simultaneous, so "the cell
## will be free" is exactly true, not a guess: a closed loop of full belts
## rotates one cell per tick instead of deadlocking, and every frame in the cycle
## unwinds `true`, producing one move and one claim per member.
##
## Starting the walk at any member of a cycle produces the same move SET in a
## different order, and the commit is order-independent — so the memo carries no
## hidden dependence on where iteration began.
static func _can_move(terrain: Node, c: Conveyor, walk: Walk) -> bool:
	var state: int = walk.resolve.get(c, UNVISITED)
	if state == RESOLVING:
		return true
	if state != UNVISITED:
		return state == YES
	walk.resolve[c] = RESOLVING
	var ok := _evaluate(terrain, c, walk)
	walk.resolve[c] = YES if ok else NO
	return ok


static func _evaluate(terrain: Node, c: Conveyor, walk: Walk) -> bool:
	if c._slot.is_empty():
		return false
	# ❗️Checked BEFORE recursing, which is what makes a cooled-down member of a
	# cycle block the whole loop properly rather than being waved through by the
	# RESOLVING answer above.
	if c._cooldown > 0:
		return false
	var target := terrain.get_entity(c.target_cell()) as Conveyor
	if target == null:
		# Off the end of the line, or facing a machine/inserter/wall: a JAM, never
		# a spill. Items on a belt never fall on the floor. (3.3 routes a machine
		# input through `accept_item` here.)
		return false
	if walk.claims.has(target):
		return false # An upstream belt already claimed it; early-out.
	if not target._slot.is_empty():
		if not _can_move(terrain, target, walk):
			return false
	# ❗️The claim is taken HERE, after the recursion has returned, and the
	# `has(target)` test above is repeated because that recursion can itself have
	# claimed this cell — a cycle two cells long claims the very cell its feeder
	# was about to. Claiming before the recursion instead would let the feeder and
	# the cycle both write the same slot, destroying one of the two stacks.
	if walk.claims.has(target):
		return false
	walk.claims[target] = c
	walk.moves.append({ source = c, target = target })
	return true


## Three sweeps, and they cannot be folded into one. A belt is routinely both a
## source and a target in the same tick, so writing one move at a time overwrites
## a stack that has not vacated yet — the dupe-and-loss bug this shape exists to
## make impossible, and one that is invisible until a full line quietly eats an
## item.
static func _commit(moves: Array[Dictionary]) -> void:
	var carried: Array[Dictionary] = []
	for move: Dictionary in moves:
		carried.append((move.source as Conveyor)._slot)
	for move: Dictionary in moves:
		# Assignment, not clear() — `carried` holds the same Dictionary reference.
		(move.source as Conveyor)._slot = { }
	for i in moves.size():
		var source := moves[i].source as Conveyor
		var target := moves[i].target as Conveyor
		target._slot = carried[i]
		# The ONLY place _prev_cell becomes something other than the belt's own
		# cell. It is what makes the item slide rather than teleport.
		target._prev_cell = source._cell
		target._cooldown = target.ticks_per_move

# --- Internals ---------------------------------------------------------------


func _automation() -> Node:
	if automation == null:
		automation = Automation
	return automation
