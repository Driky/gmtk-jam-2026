## Everything the player builds: one base, W×H, HP, a support rule and a single
## drop path. Miner, conveyor, inserter, furnace, generator, turret, chest,
## beacon and ladder are all meant to be `.tres` rows plus a small subclass on
## top of this — never another branch in the player.
##
## Owning doc: docs/systems/automation.md
class_name Deployable
extends Node2D

const TILE := TileLayout.TILE_SIZE

## Indexed by the bit order `@export_flags` assigns: 1 = Up, 2 = Right,
## 4 = Down, 8 = Left. ❗️Inverting Up/Down here produces a game that mostly
## works (torches mount on floors instead of ceilings) with no error anywhere,
## which is why there is a dedicated orientation test.
const SUPPORT_OFFSETS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const SUPPORT_ALL := 15
const SUPPORT_NONE := 0
## The Down bit on its own, named because the climbable-stacking clause below is
## gated on it: "a climbable under me holds me up" is a *downward* support
## direction, so a deployable that does not mount downward must not gain one.
const SUPPORT_DOWN := 4

## Nudge before the floor in `apply_yield`, and it is load-bearing rather than
## defensive. ❗️No authored rate is exact in binary: `+20%` accumulated five
## times lands on `1.9999999999999998`, which floors to **one** — so the bonus
## slips a tick, and ten extractions at ×1.2 return eleven items instead of
## twelve. Small enough that no reachable multiplier reaches it by accident, and
## it makes the accumulator answer the number a player can work out on paper.
const YIELD_EPSILON := 1e-6

## Backstop on the support drain, asserted in debug builds only. A cascade
## terminates because every step permanently removes one deployable; this
## catches a future predicate that breaks that argument.
const MAX_DRAIN_STEPS := 4096

## Footprint W×H. The origin cell is the TOP-LEFT one, so `footprint()` grows
## right and down from `cell()`.
@export var size := Vector2i.ONE
@export var max_hp := 20.0
## Which cardinal neighbours can hold this up. Torch = all four (wall, floor or
## ceiling); a ceiling lamp is `1` (Up); `0` never pops, which is how a
## free-floating machine opts out of the rule entirely.
@export_flags("Up", "Right", "Down", "Left") var support_dirs := SUPPORT_ALL
## Swings needed to take it back. Un-deploying is counted in HITS rather than
## accumulated damage: a swing is a discrete beat on the item's cooldown, and
## "three hits" is a thing a player can feel and count.
@export var removal_hits := 1
## What it pops out as — both when removed on purpose and when it is destroyed.
@export var item_id := ""
## Does this care which way it points? A torch does not; a conveyor and an
## inserter do. Authored per scene, and read by the ghost through
## `scene_directional` so the arrow appears for exactly the items that use one.
@export var directional := false
## Does this take ore out of the ground? Authored alongside `directional`, and
## read by placement through `scene_harvests` — a true here is what makes the
## ghost stay red until at least one HARVEST cell is a deposit. Only the Miner
## sets it, and the player never learns that: it asks the scene, not the class
## ([automation.md](../../docs/systems/automation.md) §Categories).
@export var harvests_deposits := false
## Power drawn per tick while running. **0 means it runs everywhere, for free**
## — and that is the authored answer for conveyors, inserters and torches, not a
## special case in the tick: neither of them ever asks `is_powered()`, so
## "machines only draw power" costs no code at all
## ([automation.md](../../docs/systems/automation.md) §Power).
@export var power_demand := 0.0
## Coverage radius in TILES; `> 0` is what makes something an emitter. Authored
## in tiles and multiplied by `TILE` at the one place the graph is built, so no
## reader has to remember which unit it is holding.
@export var power_radius := 0.0
## Can something go UP and DOWN through this cell? The ladder (3.5b) and 4.1's
## rope and pole are the only things that say true.
##
## ❗️**One export, four readers, and it also carries the stacking rule.** The
## player's climb, the flow field's cheap vertical edge, `EnemyLocomotion`'s CLIMB
## branch and `Enemy._attackable_entity`'s skip all ask this same question — a
## second copy of it (a `stack_group`, a `Ladder` type check) would be a second
## name for the same set. The stacking rule *is* "a climbable is held up by the
## climbable below it", so 4.1's rope and pole get it for free by authoring this
## one bool ([automation.md](../../docs/systems/automation.md) §Deployable base).
@export var is_climbable := false

## Which way it points. RIGHT by default, so a non-directional deployable still
## has a defined facing that nobody reads. Runtime rather than authored: the
## player stamps its pending rotation on the instance at placement, which is why
## it is a plain var and not an export ([save.md](../../docs/systems/save.md)
## already lists rotation as entity state).
var facing := Vector2i.RIGHT

## Seeded from the AUTHORED max_hp by _ensure_hp, not by this initializer: a
## member initializer runs before the scene loader applies the exports, so a
## scene saying 40 would silently ship a 20 HP machine.
var current_hp := max_hp
## Declared here so 3.5's turret has one place to read it; nothing reads it yet.
## A plain var rather than an @export — cross-class enum exports are finicky in
## 4.x and there is no authoring need until a turret picks a side.
var faction := Projectile.Faction.PLAYER

## Injected by tests; falls back to the autoload. ❗️**On the BASE, one seam for
## every machine that reads a buff** — the turret's `turret_damage`, the miner's
## `resource_yield`, the station's `crafting_speed` and `crafting_yield`. The
## turret declared its own until 3.7; three copies of one accessor is three things
## a suite has to remember to inject.
var progression: Node = null

## Fractional-yield carry, in items — see `apply_yield`. ⚠️ **Per instance by
## construction**, so two miners never share a counter, and deliberately NOT
## serialized at 4.3: at most one item per machine is lost across a reload, which
## is not worth a save field ([save.md](../../docs/systems/save.md)).
var _yield_credit := 0.0

## Stamped by `Automation` before every machine pass. ❗️Defaults to **1.0**, and
## that default is deliberate rather than optimistic: the only reader that ever
## sees it is a machine that was never ticked through `Automation` — i.e. a unit
## test driving `on_tick` by hand. Anything in a real world is re-stamped ten
## times a second, so a machine cannot silently run on this value.
var _power_ratio := 1.0
## Fractional tick budget — see `spend_power_tick`.
var _power_accum := 0.0

var _cell := Vector2i.ZERO
var _removal_hits := 0
## Stashed by a successful register(), so every later path (removal swing, mob
## kill, lost support) frees the same cells without being handed the terrain.
var _terrain: Node = null
## One-way: pop_to_pickup is reachable from three directions and re-enters
## itself through entity_changed, so it has to be idempotent.
var _popped := false
var _hp_synced := false


func _ready() -> void:
	_ensure_hp()


## Call before add_child, matching Core.setup — anchors the node at the
## footprint CENTRE, because the light grid (and every future overlay) floors a
## world position back to a cell.
func setup(origin: Vector2i) -> void:
	_cell = origin
	position = (Vector2(origin) + Vector2(size) * 0.5) * TILE
	_ensure_hp()


func cell() -> Vector2i:
	return _cell


func footprint() -> Array[Vector2i]:
	return footprint_at(_cell, size)


static func footprint_at(origin: Vector2i, area: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy in area.y:
		for dx in area.x:
			cells.append(origin + Vector2i(dx, dy))
	return cells

# --- Harvest block (3.3) -----------------------------------------------------


## The block of TILES a harvesting deployable reaches into: the SAME W×H as its
## footprint, flush against it, one full span along `facing`. **The arrow points
## at the ore.**
##
##     facing LEFT             facing DOWN
##       H H H M M M             M M M
##       H H H M M M             M M M
##            ← arrow            H H H
##                               H H H
##                                ↓ arrow
##
## ❗️It is a separate block rather than the footprint itself because it *has*
## to be. Every `*_deposit` material is `is_solid` and `Terrain.place_entity`
## rejects a solid cell — an invariant baked into three places in `terrain.gd`
## and depended on by name by `Enemy._attackable_entity`. "Placed on the deposit"
## is delivered by GATING placement on this block instead
## ([automation.md](../../docs/systems/automation.md) §Categories).
##
## Span is `area.x` for a horizontal facing and `area.y` for a vertical one —
## a 3×2 miner reaches 3 cells sideways but only 2 cells up or down, so the
## block always lands flush with no gap and no overlap.
static func harvest_cells_at(origin: Vector2i, area: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	var span: int = area.x if facing.y == 0 else area.y
	return footprint_at(origin + facing * span, area)


func harvest_cells() -> Array[Vector2i]:
	return harvest_cells_at(_cell, size, facing)


static func is_deposit_at(terrain: Node, cell: Vector2i) -> bool:
	var mat: Dictionary = Materials.MATERIALS.get(terrain.get_material_id(cell), { })
	return mat.get("is_deposit", false)


## The placement gate and the Miner's idle state are the same question asked of
## the same cells, so they ask it through one function.
static func has_deposit_in(terrain: Node, cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		if is_deposit_at(terrain, cell):
			return true
	return false

# --- Climbables (3.5b) --------------------------------------------------------


## Is this cell climbable? THE predicate, mirroring `is_deposit_at`: four systems
## ask it (the player's climb, the flow-field snapshot, `EnemyLocomotion.decide`
## and `Enemy._attackable_entity`) and none of them ever learns what a Ladder is.
##
## `as Deployable` rather than a group or a type check, for the same reason
## `_hit_deployable` uses one: the Core is a plain `Node2D`, so it answers false
## with no special case anywhere.
static func climbable_at(terrain: Node, cell: Vector2i) -> bool:
	var occupant := terrain.get_entity(cell) as Deployable
	return occupant != null and occupant.is_climbable

# --- Registration ------------------------------------------------------------


## Claim every footprint cell. All-or-nothing with rollback — a partial claim
## would leave dead cells nothing can ever occupy again. False means the caller
## must NOT have consumed the item yet (see Player._place_scene).
func register(terrain: Node) -> bool:
	var placed: Array[Vector2i] = []
	for cell_pos: Vector2i in footprint():
		if not terrain.place_entity(cell_pos, self):
			for done: Vector2i in placed:
				terrain.remove_entity(done)
			return false
		placed.append(cell_pos)
	_terrain = terrain
	return true


## Give the cells back without popping anything — the rollback for a claim that
## succeeded but whose item could not be consumed.
func unregister(terrain: Node) -> void:
	for cell_pos: Vector2i in footprint():
		terrain.remove_entity(cell_pos)
	_terrain = null

# --- Support -----------------------------------------------------------------


## THE support predicate. Static, with terrain injected, so placement validity
## and the post-mine re-check call the exact same function — the two can't drift.
##
## Support means a solid TILE neighbour: a deployable never holds up another
## deployable, so a chain is one deep and a cascade is a rare special case
## rather than the norm. `dirs == 0` opts out entirely.
##
## ❗️**One exception, and it is DIRECTIONAL: a climbable is held up by the
## climbable BELOW it** (3.5b). `climbable` is a defaulted fifth argument — "this
## deployable is itself climbable" — so every pre-3.5b call site keeps the 3.1
## behaviour by construction, the same bargain `facing`/`harvests` made at 3.3.
##
## ❗️The naive symmetric version ("a climbable neighbour holds me up") is a real
## bug: two ladders floating in mid-air each point at the other and both claim
## support forever, and `is_supported_at` is a **one-step predicate, not a
## reachability query**, so nothing can see the cycle. Reading only DOWNWARD makes
## the relation strictly increase in `y` toward a solid anchor, so a cycle is
## impossible by construction — and you build a column bottom-up from the floor,
## which is the direction you climb anyway. The cell below is skipped when it is
## part of this deployable's own footprint, so a future 1×2 climbable cannot stand
## on itself either.
##
## Gated on the Down bit so `support_dirs` keeps meaning exactly what it says
## ("which cardinal neighbours can hold this up"), and `dirs == SUPPORT_NONE`
## still opts out by construction.
static func is_supported_at(
		terrain: Node,
		origin: Vector2i,
		area: Vector2i,
		dirs: int,
		climbable := false,
) -> bool:
	if dirs == SUPPORT_NONE:
		return true
	var footprint := Rect2i(origin, area)
	for cell_pos: Vector2i in footprint_at(origin, area):
		for i in SUPPORT_OFFSETS.size():
			if dirs & (1 << i) == 0:
				continue
			if terrain.is_solid(cell_pos + SUPPORT_OFFSETS[i]):
				return true
		if not climbable or dirs & SUPPORT_DOWN == 0:
			continue
		var below := cell_pos + Vector2i.DOWN
		if not footprint.has_point(below) and climbable_at(terrain, below):
			return true
	return false


func is_supported(terrain: Node) -> bool:
	return is_supported_at(terrain, _cell, size, support_dirs, is_climbable)

# --- Coming off the wall -----------------------------------------------------


## One landed swing. True once it has taken enough to come off — the caller then
## calls pop_to_pickup().
func take_removal_hit(hits := 1) -> bool:
	_removal_hits += hits
	return _removal_hits >= removal_hits


## Progress toward removal, for the cursor highlight.
func removal_ratio() -> float:
	return clampf(float(_removal_hits) / float(maxi(removal_hits, 1)), 0.0, 1.0)


## Mobs chew what is in front of them; entity cells are air, so a deployable
## takes discrete melee hits instead of the tile pipeline ([enemies.md]).
## Reaching zero drops it rather than destroying it — see pop_to_pickup.
func take_damage(amount: float, _attacker: Node2D = null) -> void:
	if _popped:
		return
	current_hp = maxf(current_hp - amount, 0.0)
	if current_hp <= 0.0:
		pop_to_pickup()


## The ONE drop path: a removal swing, a mob killing it, and lost support all
## converge here. Nothing the player built is ever destroyed outright — it falls
## on the floor as a pickup, so a wave that eats your torch line costs you a walk
## rather than the torches.
##
## The pickup carries `grants_xp = false`: place → remove → place would otherwise
## be an infinite looting-XP loop ([progression.md](../../docs/systems/progression.md)).
##
## Cells are freed **eagerly** rather than on queue_free, which defers to the end
## of the frame — a removal followed by a re-place into the same cell on the same
## frame would otherwise hit a stale entity entry and be rejected for no visible
## reason.
func pop_to_pickup(spawner: Node = null) -> void:
	if _popped:
		return
	# Set first: remove_entity emits entity_changed, which re-enters the support
	# handler, which can reach straight back here.
	_popped = true
	if _terrain != null:
		for cell_pos: Vector2i in footprint():
			_terrain.remove_entity(cell_pos)
		_terrain = null
	on_removed()
	var sink := spawner if spawner != null else _find_spawner()
	if sink != null:
		if item_id != "":
			sink.spawn_at(global_position, item_id, 1, false)
		# Whatever it was CARRYING lands on the floor beside it, through the same
		# sink — one drop path, no second exit for cargo.
		for stack: Dictionary in take_cargo():
			sink.spawn_at(global_position, stack.id, stack.count, false)
	queue_free()

# --- Virtuals ----------------------------------------------------------------


## After the cells are claimed and the node is in the tree. Every registry joins
## here — the three tick phases and (3.4) the emitter list.
func on_placed() -> void:
	pass


## After the cells are already free, so an override reads a world without this
## deployable in it rather than one where it half-exists.
func on_removed() -> void:
	pass


## Everything this was HOLDING, handed over so `pop_to_pickup` can drop it beside
## the deployable itself. Empty for anything that holds nothing (a torch, a wall,
## an inserter — the inserter's transfer is atomic by design, so there is never a
## stack on the arm). A crafting station returns its input and output slots here.
##
## ❗️Named `take_cargo`, not `cargo`, because it is DESTRUCTIVE: an override hands
## the stacks over and is left empty. A pure read would dupe the cargo the moment
## anything called it twice, and this is a path that already re-enters itself
## through `entity_changed`.
##
## Dropped with `grants_xp = false` like the deployable itself: the ore on a belt
## already paid XP when it was mined, and belt → pop → re-place would otherwise be
## a fresh looting-XP loop ([progression.md](../../docs/systems/progression.md)).
func take_cargo() -> Array[Dictionary]:
	return []

# --- The item-transfer seam --------------------------------------------------
#
# The ENTIRE interface between deployables. An inserter, 3.3's miner and furnace,
# 3.5's ammo turret, 3.6's chest and the player's own hand all move items through
# exactly these two, so none of them ever asks WHAT it is talking to — the same
# "one base, no branches in the player" bargain `place_scene` already made.
#
# ❗️Both default to REFUSE, and that default is the load-bearing part: it is
# what lets an inserter point at a torch and simply do nothing, with no type
# check anywhere. Every deployable that exists and every one that ever will is a
# legal, safe neighbour that happens to take nothing — exactly as there is no
# "is this the Core" test in the removal path.
#
# Two virtuals rather than three: there is no `peek`. The inserter extracts
# before it knows the destination will take it and hands the remainder back
# through the source's own `accept_item`, which is safe *because* of the locked
# tick order (inserters run before conveyors, so the slot it just emptied is
# still free). See automation.md.


## How many of `id` this will take. 0 = none. A partial accept is legal and the
## caller keeps the remainder — the one place items go missing if this returns
## void instead of a count.
func accept_item(_id: String, _count: int) -> int:
	return 0


## Hand back at most `max_count`, as a DETACHED `{id, count}`; `{}` when there is
## nothing to give. What is returned is already gone from here — there is no
## confirm step to forget.
func extract_item(_max_count := 1) -> Dictionary:
	return { }


## One 10 Hz tick, for whichever registry this joined in `on_placed()`. Terrain
## is handed in rather than reached for, so the whole sim unit-tests against a
## fresh world (`Automation.step_tick`).
##
## The conveyor phase does NOT come through here: its mark-then-commit pass is
## global by nature. Machines (3.3's miner and furnace) and inserters do.
func on_tick(_terrain: Node) -> void:
	pass


## "This machine has nothing left to do and needs the player." False for
## everything that is not a machine, so the HUD's idle counter can walk the
## whole registry with no type check
## ([ui.md](../../docs/systems/ui.md) §HUD). A Miner over exhausted rock is the
## only thing that says true in 3.3.
##
## ❗️Deliberately ONE state for "ran dry" and "never had a deposit": from the
## player's side both mean the same thing — this machine is producing nothing,
## come and move it.
func is_idle() -> bool:
	return false

# --- Power (3.4) --------------------------------------------------------------
#
# Three reads and one stateful spend, all on the BASE, so every machine gets the
# whole brownout rule by calling one function and no machine ever implements it.


## Is this machine running at all? A `power_demand` of 0 is always true — that
## is what makes a torch, a belt and an inserter free — and anything drawing
## power needs a non-zero ratio, i.e. a fuelled grid covering it.
##
## ⚠️ **This is a state question, not a permission to act.** A machine's tick
## gate is `spend_power_tick()`; this one is for the overlays and the tests,
## which want "is it dead" rather than "may it run this tick".
func is_powered() -> bool:
	return power_demand <= 0.0 or _power_ratio > 0.0


## `min(1, supply/demand)` for the grid covering this machine, 0.0 when nothing
## covers it. Read by the power overlay (amber vs red) and the slot overlay.
func power_ratio() -> float:
	return _power_ratio


func set_power_ratio(ratio: float) -> void:
	_power_ratio = clampf(ratio, 0.0, 1.0)


## ❗️**STATEFUL — call exactly once per tick, from `on_tick` only.** A second
## call in the same tick spends a second tick's worth of budget and makes the
## machine run fast under a brownout.
##
## A fractional accumulator: each tick banks `ratio`, and the machine acts on the
## tick that carries the running total past 1.0. At ratio 1.0 that is *exactly*
## every tick with no float drift; at 0.5 it is every other tick, i.e. five
## actions in ten ticks.
##
## ❗️**Why this and not scaling each machine's own cooldown.** One gate on the
## base that every machine reuses unchanged, versus the brownout rule copied into
## N machines. Every machine's timing also stays in whole ticks, so 4.3
## serializes an int and 3.3's cooldown/progress tests keep their exact numbers.
func spend_power_tick() -> bool:
	if power_demand <= 0.0:
		return true
	if _power_ratio <= 0.0:
		return false
	_power_accum += _power_ratio
	if _power_accum < 1.0:
		return false
	_power_accum -= 1.0
	return true

# --- Yield buffs (3.7) --------------------------------------------------------


## Deterministic whole-item output for a fractional yield multiplier.
##
## ❗️**A ×1.1 on an output of 1 is 1 forever if it is floored, and a coin flip a
## deterministic tick has no business making if it is rolled** — and a random tick
## contradicts [automation.md](../../docs/systems/automation.md)'s determinism. So
## it accumulates: 20% over ten extractions is two bonus items, on the second and
## the seventh, every run. Exactly the `spend_power_tick` bargain one field up.
##
## Returns at most `cap` and banks **only what it hands out**, so a bonus a full
## slot cannot take is kept for the next call rather than destroyed — the same
## conservation that keeps a brownout's part-ticks.
##
## ⚠️ **Neutral by construction at ×1.0**: `base * 1.0` is exact for the small
## integers involved, so an unbuffed machine never moves the credit at all.
func apply_yield(base: int, stat_name: String, cap: int) -> int:
	# Annotated, not inferred: `_progression()` is a `Node`, so its `get_stat` has
	# no declared return type for `:=` to read.
	var total: float = base * _progression().get_stat(stat_name) + _yield_credit
	# `maxi(cap, 0)`: a caller with no room at all banks the whole thing rather
	# than handing back a negative count and going into credit debt.
	var whole := mini(floori(total + YIELD_EPSILON), maxi(cap, 0))
	_yield_credit = total - whole
	return whole


## The carry, for the tests and the debug overlay.
func yield_credit() -> float:
	return _yield_credit

# --- Internals ---------------------------------------------------------------


func _progression() -> Node:
	if progression == null:
		progression = Progression
	return progression


## Risk-1 guard: `var current_hp := max_hp` runs before the scene loader applies
## the authored export, so the value has to be re-taken once the exports are in.
## Called from both setup() and _ready() because either can come first depending
## on how the node was built.
func _ensure_hp() -> void:
	if _hp_synced:
		return
	_hp_synced = true
	current_hp = max_hp


## No spawner in the tree (unit tests, headless tools) simply means no pickup —
## the cells still have to be freed either way.
func _find_spawner() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"pickup_spawner")

# --- Reading a scene's authoring without instantiating it ---------------------

## Keyed by the PackedScene reference, which the `.tres` already `preload`s, so
## the key is stable for the life of the run and the cache can never grow past
## the number of placeable types. Untyped on purpose — a Dictionary typed by an
## object key refuses to erase a freed instance in 4.6, and there is no reason
## to court that here.
static var _scene_size_cache := { }
static var _scene_dirs_cache := { }
static var _scene_visual_cache := { }
static var _scene_directional_cache := { }
static var _scene_harvests_cache := { }
static var _scene_power_radius_cache := { }
static var _scene_power_demand_cache := { }
static var _scene_climbable_cache := { }


## A scene's authored footprint, for the placement ghost. The ghost redraws
## every frame and a per-frame `instantiate()` would be absurd, so this builds
## ONE instance, reads the exports off it and frees it. Reading the authored
## value rather than a second copy of the number is the point: the ghost cannot
## draw a shape different from the one that will actually be placed.
static func scene_size(scene: PackedScene) -> Vector2i:
	_cache_scene(scene)
	return _scene_size_cache[scene]


static func scene_support_dirs(scene: PackedScene) -> int:
	_cache_scene(scene)
	return _scene_dirs_cache[scene]


## Whether the ghost should draw a facing arrow for this scene. Same anti-drift
## contract as `scene_size`: read off the authored instance, never a second copy
## of the answer kept somewhere the ghost can disagree with.
static func scene_directional(scene: PackedScene) -> bool:
	_cache_scene(scene)
	return _scene_directional_cache[scene]


## Whether placing this scene requires a deposit under its harvest block. Same
## anti-drift contract as `scene_size`: read off an authored instance, so the
## ghost's red and the click's refusal are the same answer rather than two
## copies of it.
static func scene_harvests(scene: PackedScene) -> bool:
	_cache_scene(scene)
	return _scene_harvests_cache[scene]


## The coverage radius (in TILES) placing this scene would emit, `0.0` for
## anything that is not an emitter. Same anti-drift contract as `scene_size`:
## the ghost's prospective circle is the authored number, not a second copy of it.
static func scene_power_radius(scene: PackedScene) -> float:
	_cache_scene(scene)
	return _scene_power_radius_cache[scene]


## What placing this scene would draw off a grid, `0.0` for anything that runs
## free. Read by the ghost to decide whether existing coverage is worth showing:
## "will this land powered" is only a question for something that needs power.
static func scene_power_demand(scene: PackedScene) -> float:
	_cache_scene(scene)
	return _scene_power_demand_cache[scene]


## Whether placing this scene would put a climbable down — which is what lets the
## ghost stay green on a column built rung by rung. Same anti-drift contract as
## `scene_size`: the ghost's validity and the click's are one answer read off an
## authored instance, not two copies of it.
static func scene_is_climbable(scene: PackedScene) -> bool:
	_cache_scene(scene)
	return _scene_climbable_cache[scene]


## The authored look, so the ghost can show WHAT is being placed rather than
## only where and how big. `{}` when the scene has no coloured rect to preview.
##
## `rect` is relative to the node ORIGIN, which `setup()` puts at the footprint
## centre — a caller drawing in cell space has to offset by `size * 0.5 * TILE`.
static func scene_visual(scene: PackedScene) -> Dictionary:
	_cache_scene(scene)
	return _scene_visual_cache[scene]


static func _cache_scene(scene: PackedScene) -> void:
	if _scene_size_cache.has(scene):
		return
	var probe: Deployable = scene.instantiate()
	_scene_size_cache[scene] = probe.size
	_scene_dirs_cache[scene] = probe.support_dirs
	_scene_directional_cache[scene] = probe.directional
	_scene_harvests_cache[scene] = probe.harvests_deposits
	_scene_power_radius_cache[scene] = probe.power_radius
	_scene_power_demand_cache[scene] = probe.power_demand
	_scene_climbable_cache[scene] = probe.is_climbable
	_scene_visual_cache[scene] = _probe_visual(probe)
	probe.free()


## Placeholder art across this repo is one `ColorRect` child (player.tscn,
## enemy.tscn, pickup.tscn, torch.tscn), so the ghost reuses whatever the scene
## already draws instead of making every deployable author a second preview
## sprite that could drift from it.
##
## Read from the OFFSETS, not `size`/`position`: a Control that has never been
## in a tree has not laid itself out, so those are still zero.
static func _probe_visual(probe: Node) -> Dictionary:
	for child: Node in probe.get_children():
		var visual := child as ColorRect
		if visual == null:
			continue
		return {
			rect = Rect2(
				visual.offset_left,
				visual.offset_top,
				visual.offset_right - visual.offset_left,
				visual.offset_bottom - visual.offset_top,
			),
			color = visual.color,
		}
	return { }
