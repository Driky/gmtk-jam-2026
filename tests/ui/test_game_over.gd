## Unit tests for the game-over stats screen (roadmap 2.1). Pure view —
## no autoload reads, so no injection needed.
extends GdUnitTestSuite

const GameOverScene := preload("res://scenes/ui/game_over.tscn")

var _screen: CanvasLayer
var _restarts := 0


func before_test() -> void:
	_screen = auto_free(GameOverScene.instantiate())
	add_child(_screen)
	_restarts = 0
	_screen.restart_requested.connect(func() -> void: _restarts += 1)


func test_hidden_until_opened() -> void:
	assert_bool(_screen.visible).is_false()


func test_open_fills_stats_and_shows() -> void:
	_screen.open({ waves_survived = 4, max_depth_row = 87, blocks_mined = 152 })
	assert_bool(_screen.visible).is_true()
	assert_str(_screen._waves_label.text).is_equal("Waves survived: 4")
	assert_str(_screen._depth_label.text).contains("row 87")
	assert_str(_screen._blocks_label.text).is_equal("Blocks mined: 152")


func test_restart_button_emits_request() -> void:
	_screen._restart_button.pressed.emit()
	assert_int(_restarts).is_equal(1)
