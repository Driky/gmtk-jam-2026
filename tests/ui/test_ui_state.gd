## Unit tests for the shared open-screen predicate (roadmap 3.6a). Drives the two
## statics directly — that is the whole point of them being statics with no
## autoload slot.
extends GdUnitTestSuite

## Never leave either flag set for the next suite: the player reads them, so a
## leaked `true` would silently freeze an unrelated movement test.
func after_test() -> void:
	DebugMenu.is_open = false
	CharacterScreen.is_open = false


func test_nothing_open_blocks_nothing() -> void:
	assert_bool(UiState.blocks_gameplay_actions()).is_false()
	assert_bool(UiState.blocks_movement()).is_false()


## ❗️**Two predicates, not one.** The debug menu keeps its existing freedom to walk
## around while its panel is up, so the current feel and every existing movement
## test survive by construction — this is the regression pin on that split.
func test_the_debug_menu_blocks_actions_but_still_allows_movement() -> void:
	DebugMenu.is_open = true
	assert_bool(UiState.blocks_gameplay_actions()).is_true()
	assert_bool(UiState.blocks_movement()).is_false()


func test_the_character_screen_blocks_both() -> void:
	CharacterScreen.is_open = true
	assert_bool(UiState.blocks_gameplay_actions()).is_true()
	assert_bool(UiState.blocks_movement()).is_true()


## Closing one while the other is up must not un-block anything.
func test_either_screen_alone_is_enough_to_block_actions() -> void:
	DebugMenu.is_open = true
	CharacterScreen.is_open = true
	DebugMenu.is_open = false
	assert_bool(UiState.blocks_gameplay_actions()).is_true()
	CharacterScreen.is_open = false
	DebugMenu.is_open = true
	assert_bool(UiState.blocks_gameplay_actions()).is_true()
