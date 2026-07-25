# UI

Owner of: all screens, shortcuts, overlays, pause behavior.

## Character screen — one window, three tabs (locked)
Navigable via tab buttons and cycling keys; each tab ALSO has a direct shortcut (`I` inventory, `C` crafting, `K` skill tree) that opens the window on that tab, or switches tab if open:
- **Inventory tab:** grid inventory + hotbar assignment, **equipment panel** (tool, weapon slots, armor/accessory slots), **player stats readout** (HP, mana, move speed, active buff multipliers). Container view opens alongside when interacting with a chest.
- **Crafting tab:** recipes in **category tabs** (Tools & Weapons / Automation / Logistics / Power / Defense / Components…) for findability; filtered by unlocks, greyed when inputs missing (with missing-item highlight); search box if time allows.
- **Skill tree tab:** node graph ([progression.md](progression.md)).

## Other screens
HUD (countdown / wave banner, HP/mana bars, XP bar + level, hotbar, Core HP) · pause menu · placement mode overlay · **power overlay** on its own hotkey, togglable anytime ([automation.md](automation.md)) · debug overlay (slot occupancy, fortification score) · death & game-over screens · main menu with seed input (stretch: seedless "New Run" only). Keyboard + mouse only. Toasts for rejected placements (buffer zone, light cap — [terrain.md](terrain.md)).

## Pause (locked)
`SceneTree.paused` + `process_mode`: gameplay pauses; the pause menu stays **fully interactive** (resume, settings, save during build phase, quit). Forbidden while paused: *gameplay* actions — placing/removing deployables, inventory/crafting manipulation, skill-tree spending. Enforcement: opening pause closes gameplay screens; gameplay input handlers live under paused `process_mode`.
