## "Is a screen open?", asked once. Gameplay polls `Input` directly rather than
## routing through the UI — that is why `DebugMenu.is_open` exists at all — so
## every screen that blocks anything has to be readable from the player. One screen
## was one line; three would be three ORs repeated at every polling site.
##
## A `class_name`-only statics script with no `extends`, the `Perf` / `RecipeDefs`
## precedent: no autoload slot, so [tech-design.md](../../docs/tech-design.md)'s
## fixed autoload map is untouched.
##
## Owning doc: docs/systems/ui.md
class_name UiState

## Placing, removing, mining, hand-feeding, interacting — everything that reaches
## into the world. ❗️The debug menu is in here so a click on one of its buttons
## does not also swing at the world behind the panel.
static func blocks_gameplay_actions() -> bool:
	return DebugMenu.is_open or CharacterScreen.is_open


## Walking, jumping and climbing.
##
## ❗️**Two predicates, not one, and deliberately.** The debug menu keeps its
## existing freedom to walk around while its panel is up, so the current feel and
## every existing test survive by construction. Only the character screen blocks
## movement ([ui.md](../../docs/systems/ui.md) §An open gameplay screen).
static func blocks_movement() -> bool:
	return CharacterScreen.is_open
