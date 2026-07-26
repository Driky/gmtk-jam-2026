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

## Seeded from the AUTHORED max_hp by _ensure_hp, not by this initializer: a
## member initializer runs before the scene loader applies the exports, so a
## scene saying 40 would silently ship a 20 HP machine.
var current_hp := max_hp
## Declared here so 3.5's turret has one place to read it; nothing reads it yet.
## A plain var rather than an @export — cross-class enum exports are finicky in
## 4.x and there is no authoring need until a turret picks a side.
var faction := Projectile.Faction.PLAYER

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
static func is_supported_at(terrain: Node, origin: Vector2i, area: Vector2i, dirs: int) -> bool:
	if dirs == SUPPORT_NONE:
		return true
	for cell_pos: Vector2i in footprint_at(origin, area):
		for i in SUPPORT_OFFSETS.size():
			if dirs & (1 << i) == 0:
				continue
			if terrain.is_solid(cell_pos + SUPPORT_OFFSETS[i]):
				return true
	return false


func is_supported(terrain: Node) -> bool:
	return is_supported_at(terrain, _cell, size, support_dirs)

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
	if sink != null and item_id != "":
		sink.spawn_at(global_position, item_id, 1, false)
	queue_free()

# --- Virtuals ----------------------------------------------------------------


## After the cells are claimed and the node is in the tree. 3.4's power graph
## hooks here; empty in 3.1 on purpose.
func on_placed() -> void:
	pass


## After the cells are already free, so an override reads a world without this
## deployable in it rather than one where it half-exists.
func on_removed() -> void:
	pass

# --- Internals ---------------------------------------------------------------


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


static func _cache_scene(scene: PackedScene) -> void:
	if _scene_size_cache.has(scene):
		return
	var probe: Deployable = scene.instantiate()
	_scene_size_cache[scene] = probe.size
	_scene_dirs_cache[scene] = probe.support_dirs
	probe.free()
