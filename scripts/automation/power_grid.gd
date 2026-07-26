## The power solver: emitter discs in, connected components ("grids") out, plus
## one supply/demand/ratio triple per component.
##
## ❗️**Pure and scene-free on purpose.** It takes two parallel arrays of world-
## space centres and radii and knows nothing about `Deployable`, `Terrain` or the
## tree, so the whole graph question — which is the part with a wrong answer that
## looks right — unit-tests with no world at all.
##
## ❗️**World units, no cell stamping.** Coverage is "is this point inside a disc",
## answered against the discs themselves rather than against a rasterised set of
## powered cells. Nothing has to be invalidated when a machine moves, a 3×2 that
## half-overlaps a circle has an unambiguous answer, and the overlay draws the
## same circles the solver reasons about.
##
## Owning doc: docs/systems/automation.md §Power
class_name PowerGrid
extends RefCounted

## No emitter covers this point.
const NO_GRID := -1

var _centres: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat32Array = PackedFloat32Array()
## Component index per emitter, parallel to the two above.
var _component: PackedInt32Array = PackedInt32Array()
var _component_count := 0

## Per component, refilled every tick by the caller.
var _supply: PackedFloat32Array = PackedFloat32Array()
var _demand: PackedFloat32Array = PackedFloat32Array()
var _ratio: PackedFloat32Array = PackedFloat32Array()


## Take a new emitter set and re-label the components. Called on place/remove
## only — never per tick ([automation.md](../../docs/systems/automation.md)).
##
## Radii are already in WORLD units: the export is authored in tiles and
## multiplied once by the caller, so nothing downstream has to remember which
## unit it is holding.
func build(centres: PackedVector2Array, radii: PackedFloat32Array) -> void:
	assert(centres.size() == radii.size())
	_centres = centres
	_radii = radii
	_label_components()
	_supply.resize(_component_count)
	_demand.resize(_component_count)
	_ratio.resize(_component_count)
	begin_tick()


func emitter_count() -> int:
	return _centres.size()


func component_count() -> int:
	return _component_count


## Which grid an EMITTER belongs to, by its index in the arrays handed to build.
func component_of(emitter: int) -> int:
	if emitter < 0 or emitter >= _component.size():
		return NO_GRID
	return _component[emitter]


## Which grid covers a world point, or `NO_GRID`. The FIRST disc containing it
## wins — overlapping discs are by definition the same component, so "first"
## and "any" are the same answer.
func grid_of_point(point: Vector2) -> int:
	for i in _centres.size():
		if _centres[i].distance_to(point) <= _radii[i]:
			return _component[i]
	return NO_GRID


func centre_of(emitter: int) -> Vector2:
	return _centres[emitter]


func radius_of(emitter: int) -> float:
	return _radii[emitter]

# --- The per-tick pass --------------------------------------------------------


## Zero every accumulator. Supply and demand are rebuilt from scratch each tick
## rather than maintained incrementally — a machine that stops drawing has no
## event to fire, and a stale demand is a brownout nobody can explain.
func begin_tick() -> void:
	_supply.fill(0.0)
	_demand.fill(0.0)
	_ratio.fill(1.0)


func add_supply(component: int, amount: float) -> void:
	if component < 0 or component >= _component_count:
		return
	_supply[component] += amount


func add_demand(component: int, amount: float) -> void:
	if component < 0 or component >= _component_count:
		return
	_demand[component] += amount


## ❗️Runs between the two machine passes, and that is what forces there to BE
## two: a ratio does not exist until every machine on the grid has declared its
## demand.
##
## No demand means ratio 1.0, not a division by zero — an empty grid is fully
## powered in the only sense that matters (the next machine placed in it runs).
func resolve() -> void:
	for c in _component_count:
		_ratio[c] = 1.0 if _demand[c] <= 0.0 else minf(1.0, _supply[c] / _demand[c])


## `min(1, supply/demand)` — **brownouts slow, they never hard-stop**
## ([automation.md](../../docs/systems/automation.md) §Power). An uncovered point
## is not a grid at all and gets 0.0, which is the one case that does stop.
func ratio_of(component: int) -> float:
	if component < 0 or component >= _component_count:
		return 0.0
	return _ratio[component]


func supply_of(component: int) -> float:
	if component < 0 or component >= _component_count:
		return 0.0
	return _supply[component]


func demand_of(component: int) -> float:
	if component < 0 or component >= _component_count:
		return 0.0
	return _demand[component]

# --- Internals ----------------------------------------------------------------


## ❗️**Two emitters share a grid when their discs touch or overlap** —
## `distance <= rA + rB`, inclusive, so exact tangency connects. Relays exist to
## be placed at exactly that reach, and a strict `<` would make the intended
## placement a coin flip on float rounding.
##
## Plain BFS over an O(N²) adjacency test rather than union-find: N is dozens of
## emitters on a 200-column world, this runs on place/remove only, and the
## reachability argument is one anyone can check by reading it.
func _label_components() -> void:
	var n := _centres.size()
	_component.resize(n)
	_component.fill(NO_GRID)
	_component_count = 0
	for seed in n:
		if _component[seed] != NO_GRID:
			continue
		var component := _component_count
		_component_count += 1
		_component[seed] = component
		# Iterative, like the support drain: a long relay chain must not depend
		# on stack depth.
		var frontier: Array[int] = [seed]
		while not frontier.is_empty():
			var a: int = frontier.pop_back()
			for b in n:
				if _component[b] != NO_GRID:
					continue
				if _centres[a].distance_to(_centres[b]) <= _radii[a] + _radii[b]:
					_component[b] = component
					frontier.append(b)
