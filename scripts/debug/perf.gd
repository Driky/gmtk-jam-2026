## Named-section frame profiler for the F4 overlay. Owning doc: docs/systems/ui.md
##
## Exists because the browser has no editor profiler, and three rounds of
## hypothesis-then-fix on the wave-phase hitch each landed on the wrong
## subsystem. This names the cost instead of guessing at it.
##
## The headline per section is its **worst single frame**, not its average: a
## subsystem that costs 90 ms once a second and nothing otherwise is exactly
## the shape we're hunting, and an average buries it.
##
## Frame boundaries come from Engine.get_process_frames(), so this needs no
## autoload slot and no _process of its own — it can't be mis-ordered against
## the code it measures. Static state, so a scene reload keeps accumulating
## reset() is wired to the overlay's toggle-on.
##
## Nested sections double-count by design (a parent's total includes its
## children) — read the tree, not the sum.
class_name Perf

## Cheap but not free (two ticks_usec + dict ops per section). Keep sections
## coarse — per-frame subsystems, never per-cell or per-item loops.
static var enabled := true

static var _accum: Dictionary[StringName, int] = { }
static var _worst: Dictionary[StringName, int] = { }
static var _total: Dictionary[StringName, int] = { }
static var _calls: Dictionary[StringName, int] = { }
static var _stack: Array = []
static var _frame := -1


static func begin(section: StringName) -> void:
	if not enabled:
		return
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_roll()
		_frame = frame
	_stack.append(section)
	_stack.append(Time.get_ticks_usec())


static func end() -> void:
	if not enabled or _stack.is_empty():
		return
	var t0: int = _stack.pop_back()
	var section: StringName = _stack.pop_back()
	var usec := Time.get_ticks_usec() - t0
	_accum[section] = _accum.get(section, 0) + usec
	_total[section] = _total.get(section, 0) + usec
	_calls[section] = _calls.get(section, 0) + 1


## Sections sorted by worst single frame, worst first.
## Each entry: {name, worst_ms, total_ms, calls}.
static func top_sections(limit: int) -> Array[Dictionary]:
	_roll() # Fold the in-flight frame so the newest spike is visible.
	var rows: Array[Dictionary] = []
	for section: StringName in _worst:
		rows.append(
			{
				name = section,
				worst_ms = _worst[section] / 1000.0,
				total_ms = _total.get(section, 0) / 1000.0,
				calls = _calls.get(section, 0),
			},
		)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.worst_ms > b.worst_ms)
	return rows.slice(0, limit)


static func format_top(limit: int) -> String:
	var rows := top_sections(limit)
	if rows.is_empty():
		return "sections: none"
	var parts: Array[String] = []
	for row in rows:
		parts.append("%s %.1f" % [row.name, row.worst_ms])
	return "worst frame by section: " + " | ".join(parts)


static func reset() -> void:
	_accum.clear()
	_worst.clear()
	_total.clear()
	_calls.clear()
	_stack.clear()
	_frame = -1


## Fold the finished frame's per-section totals into the running maxima.
static func _roll() -> void:
	for section: StringName in _accum:
		_worst[section] = maxi(_worst.get(section, 0), _accum[section])
	_accum.clear()
