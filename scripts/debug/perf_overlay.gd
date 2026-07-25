## Debug perf readout: frame pacing + flow-field solve cost, readable in the
## browser where the editor profiler isn't available. Visibility is driven by
## the F3 debug menu — this node owns no keybinding.
## Owning doc: docs/systems/ui.md
##
## Headline number is the WORST frame in the last few seconds, not the mean:
## a 200 ms hitch every half second barely moves an FPS average but is exactly
## the micro-freeze we're chasing. Text only, repainted 4x/s — an overlay that
## costs frame time can't measure frame time.
extends CanvasLayer

const WINDOW := 3.0
const REFRESH := 0.25
const MARGIN := Vector2(8.0, 60.0) ## Clears the HUD's HP/mana bars.

## Frames after a cell write that still count as "dirty". The engine defers
## its TileMapLayer quadrant rebuild (physics bodies, occluders) past the
## frame that called set_cell, so the cost lands a frame or two later.
const DIRTY_FRAMES := 2
## Sections shown in the breakdown line. Three is enough to name a culprit
## without the label covering the game.
const SECTION_ROWS := 3

## Injected by tests; falls back to the autoloads.
var waves: Node = null
var game: Node = null
var terrain: Node = null

var _label: Label
var _window_left := WINDOW
var _worst_window := 0.0
var _worst_shown := 0.0
var _peak := 0.0
var _refresh_left := 0.0
var _solves := 0
var _solve_last := 0.0
var _solve_peak := 0.0
## Split the worst frame by whether a cell write happened near it. If dirty is
## slow and clean is smooth, the cost is in the tile-change path — and if
## _write_usec stays tiny while dirty is slow, it's the engine's deferred
## rebuild rather than anything we call.
var _worst_dirty := 0.0
var _worst_clean := 0.0
var _writes := 0
var _write_usec := 0
var _write_usec_base := 0
var _write_peak_usec := 0
## Godot's own accounting: time inside _process / _physics_process across the
## whole tree. If a frame is 83 ms while these read ~2 ms, the cost is not in
## our script at all — it's the renderer, the physics server, or the browser.
## Rolling-window, NOT all-time: creating 240k tile bodies at world-gen end
## spikes physics once, and an all-time max would report that startup cost
## forever while a recurring hitch hid behind it.
var _engine_process_peak := 0.0
var _engine_physics_peak := 0.0
var _engine_process_shown := 0.0
var _engine_physics_shown := 0.0
var _last_writes := 0
var _dirty_left := 0


func _ready() -> void:
	if waves == null:
		waves = Waves
	if game == null:
		game = Game
	if terrain == null:
		terrain = Terrain
	layer = 100
	visible = false
	_label = Label.new()
	_label.position = MARGIN
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	waves.flow_field_updated.connect(_on_field_updated)


func _process(delta: float) -> void:
	# Only sample once the run is live: GENERATING's amortized row sweep has
	# legitimately huge frames that would poison the peak forever.
	if game.state != game.State.BUILD_PHASE and game.state != game.State.WAVE_PHASE:
		return
	var frame_ms := delta * 1000.0
	_worst_window = maxf(_worst_window, frame_ms)
	_peak = maxf(_peak, frame_ms)
	_sample_writes(frame_ms)
	_engine_process_peak = maxf(
		_engine_process_peak,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	)
	_engine_physics_peak = maxf(
		_engine_physics_peak,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	)
	_window_left -= delta
	if _window_left <= 0.0:
		_window_left = WINDOW
		_worst_shown = _worst_window
		_worst_window = 0.0
		_engine_process_shown = _engine_process_peak
		_engine_physics_shown = _engine_physics_peak
		_engine_process_peak = 0.0
		_engine_physics_peak = 0.0
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH
		_label.text = format_stats(
			Engine.get_frames_per_second(),
			frame_ms,
			maxf(_worst_shown, _worst_window),
			_peak,
			_solve_last,
			_solve_peak,
			_solves,
			get_tree().get_nodes_in_group(&"enemies").size(),
			_writes,
			_write_usec / 1000.0,
			_write_peak_usec / 1000.0,
			_worst_dirty,
			_worst_clean,
		)
		_label.text += "\n" + Perf.format_top(SECTION_ROWS)
		_label.text += (
			"\ngodot %.0fs: process %.1f | physics %.1f ms"
			% [
				WINDOW,
				maxf(_engine_process_shown, _engine_process_peak),
				maxf(_engine_physics_shown, _engine_physics_peak),
			]
		)


## Attribute this frame to the dirty or clean bucket. `delta` describes the
## frame that just ENDED, and the writes counted since the last sample happened
## during it, so a write seen now keeps the next DIRTY_FRAMES dirty too.
func _sample_writes(frame_ms: float) -> void:
	var total: int = terrain.cell_writes
	var wrote := total != _last_writes
	if wrote:
		_writes += total - _last_writes
		_last_writes = total
		_write_usec = terrain.cell_write_usec - _write_usec_base
		_write_peak_usec = terrain.cell_write_peak_usec
	if wrote or _dirty_left > 0:
		_worst_dirty = maxf(_worst_dirty, frame_ms)
	else:
		_worst_clean = maxf(_worst_clean, frame_ms)
	_dirty_left = DIRTY_FRAMES if wrote else maxi(_dirty_left - 1, 0)


## Zero the accumulated peaks. Called by the debug menu when the readout is
## switched on, so toggling it means "measure from here".
func reset_stats() -> void:
	_worst_window = 0.0
	_worst_shown = 0.0
	_peak = 0.0
	_solves = 0
	_solve_last = 0.0
	_solve_peak = 0.0
	_worst_dirty = 0.0
	_worst_clean = 0.0
	_writes = 0
	_write_usec = 0
	# Baseline BOTH counters: world gen writes ~240k cells before the run
	# starts, and folding those in made the in-call total read ~10x high.
	_write_usec_base = terrain.cell_write_usec
	_write_peak_usec = 0
	_engine_process_peak = 0.0
	_engine_physics_peak = 0.0
	terrain.cell_write_peak_usec = 0 # Drop world gen's peak.
	_last_writes = terrain.cell_writes # Baseline: don't count world gen's writes.
	_dirty_left = 0
	_window_left = WINDOW
	_refresh_left = 0.0
	Perf.reset()


static func format_stats(
		fps: int,
		frame_ms: float,
		worst_ms: float,
		peak_ms: float,
		solve_last: float,
		solve_peak: float,
		solves: int,
		mobs: int,
		writes: int,
		write_ms: float,
		write_peak_ms: float,
		worst_dirty: float,
		worst_clean: float,
) -> String:
	return (
		(
			"fps %d | frame %.1f | worst %.0fs %.1f | peak %.1f ms\n"
			+ "field last %.1f | peak %.1f ms | solves %d | mobs %d\n"
			+ "cells %d in %.1f ms in-call | worst one %.1f ms\n"
			+ "worst frame  dirty %.1f | clean %.1f ms"
		)
		% [
			fps,
			frame_ms,
			WINDOW,
			worst_ms,
			peak_ms,
			solve_last,
			solve_peak,
			solves,
			mobs,
			writes,
			write_ms,
			write_peak_ms,
			worst_dirty,
			worst_clean,
		]
	)


func _on_field_updated() -> void:
	var field: FlowField = waves.flow_field
	if field == null:
		return
	_solve_last = field.last_solve_msec
	_solve_peak = maxf(_solve_peak, _solve_last)
	_solves += 1
