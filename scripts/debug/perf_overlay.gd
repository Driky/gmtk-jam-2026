## Debug perf readout (F4): frame pacing + flow-field solve cost, readable in
## the browser where the editor profiler isn't available.
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

## Injected by tests; falls back to the autoloads.
var waves: Node = null
var game: Node = null

var _label: Label
var _window_left := WINDOW
var _worst_window := 0.0
var _worst_shown := 0.0
var _peak := 0.0
var _refresh_left := 0.0
var _solves := 0
var _solve_last := 0.0
var _solve_peak := 0.0


func _ready() -> void:
	if waves == null:
		waves = Waves
	if game == null:
		game = Game
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
	_window_left -= delta
	if _window_left <= 0.0:
		_window_left = WINDOW
		_worst_shown = _worst_window
		_worst_window = 0.0
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
		)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_perf_overlay"):
		visible = not visible
		if visible:
			reset_stats() # Toggling on means "measure from here".


## Zero the accumulated peaks. Public so a measurement run can start clean.
func reset_stats() -> void:
	_worst_window = 0.0
	_worst_shown = 0.0
	_peak = 0.0
	_solves = 0
	_solve_last = 0.0
	_solve_peak = 0.0
	_window_left = WINDOW
	_refresh_left = 0.0


static func format_stats(
		fps: int,
		frame_ms: float,
		worst_ms: float,
		peak_ms: float,
		solve_last: float,
		solve_peak: float,
		solves: int,
		mobs: int,
) -> String:
	return (
		"fps %d | frame %.1f | worst %.0fs %.1f | peak %.1f ms\nfield last %.1f | peak %.1f ms | solves %d\nmobs %d"
		% [fps, frame_ms, WINDOW, worst_ms, peak_ms, solve_last, solve_peak, solves, mobs]
	)


func _on_field_updated() -> void:
	var field: FlowField = waves.flow_field
	if field == null:
		return
	_solve_last = field.last_solve_msec
	_solve_peak = maxf(_solve_peak, _solve_last)
	_solves += 1
