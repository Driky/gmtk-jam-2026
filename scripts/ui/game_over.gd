## Game-over stats screen (waves survived, depth reached, blocks mined —
## plan.md). Pure view: open(stats) fills the labels; the restart button
## only emits restart_requested — main.gd owns the actual restart. Runs
## with PROCESS_MODE_ALWAYS so the button works while the tree is paused.
## Owning doc: docs/systems/ui.md
extends CanvasLayer

signal restart_requested

const HudScript := preload("res://scripts/ui/hud.gd")

@onready var _waves_label: Label = %WavesLabel
@onready var _depth_label: Label = %DepthLabel
@onready var _blocks_label: Label = %BlocksLabel
@onready var _restart_button: Button = %RestartButton


func _ready() -> void:
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())


func open(stats: Dictionary) -> void:
	_waves_label.text = "Waves survived: %d" % stats.waves_survived
	_depth_label.text = (
		"Depth reached: row %d — %s"
		% [stats.max_depth_row, HudScript.biome_name(stats.max_depth_row)]
	)
	_blocks_label.text = "Blocks mined: %d" % stats.blocks_mined
	visible = true
