## Depth darkness: one CanvasModulate over the whole world canvas, lerped from
## daylight at the surface to a dim floor underground. Depth is the progression
## axis (better ores deeper), so this is what makes descending a decision —
## you have to bring light — rather than a walk.
## Owning doc: docs/systems/terrain.md
extends CanvasModulate

## Full brightness at or above this row. Derived, not taste:
## WorldGen.SURFACE_MEAN(24) + SURFACE_AMPLITUDE(8) + 2 — the deepest surface
## valley is row 32, so every surface column stays at daylight.
const SURFACE_ROW := 34.0
## Fully dark by here. 18 rows below the bright end — about half a screen of
## descent, so night falls while the surface is still visible above you. A
## longer ramp reads as "slightly overcast" for the whole first screen, which
## is not the Terraria feel: there, you dig down a little and it is DARK.
const DARK_ROW := 52.0
## Near-black, with a blue cast rather than a flat grey — the tint multiplies,
## so brown dirt lands at ~(0.025, 0.016, 0.015). Not literally zero: pickups,
## loot bags and mobs are unlit ColorRects, and a hard black loses your own
## death bag entirely. You still find it by walking there with your own light.
const FLOOR_COLOR := Color(0.045, 0.045, 0.075)
## Exponential chase rate. Exists for respawn: row 400 → the Core would
## otherwise snap the screen from black to white in a single frame.
const TINT_LERP_SPEED := 6.0


func _ready() -> void:
	color = Color.WHITE


## Driven by the CURRENT CAMERA, not the player: position_smoothing_speed 8
## lags the camera ~5 rows behind a fall, and the tint is a property of what is
## on screen. That also means this node needs no bind_* — during GENERATING the
## current camera is Main's static one at row 0 (white), and LoadingUI covers it.
func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var target := depth_color(camera.get_screen_center_position().y / TileLayout.TILE_SIZE)
	# 1 - exp(-k*delta), not a raw lerp weight: frame-rate independent.
	color = color.lerp(target, 1.0 - exp(-TINT_LERP_SPEED * delta))


static func depth_color(row: float) -> Color:
	return Color.WHITE.lerp(FLOOR_COLOR, smoothstep(SURFACE_ROW, DARK_ROW, row))
