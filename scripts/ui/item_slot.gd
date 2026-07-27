## One inventory slot as a widget: a background, the item icon, an optional key
## label and a count. Extracted from the HUD's `_make_slot` at 3.6a because the
## character screen needs **68 more of them** — 40 inventory + 20 container + 8
## equipment — and copy-pasting it would be three more sets of parallel arrays
## plus a second home for the icon and count rules to drift from.
##
## ❗️It resolves nothing itself. The texture comes from `Hud.icon_for` and the
## tooltip from `Hud.item_name`, which are static, cached, and inert without a HUD
## in the tree — so this widget unit-tests headless and there is still exactly one
## answer to "what is this item called" ([ui.md](../../docs/systems/ui.md)).
##
## Owning doc: docs/systems/ui.md
class_name ItemSlot
extends ColorRect

## A click landed on this slot. `button_index` is a `MOUSE_BUTTON_*` and `shift`
## is what separates quick-move from pick-up — the screen owns what those *mean*
## ([ui.md](../../docs/systems/ui.md) §Character screen); this only reports them.
signal slot_pressed(index: int, button_index: int, shift: bool)

const SLOT_SIZE := Vector2(44, 44)
const SLOT_MARGIN := 6.0
const NORMAL_BG := Color(0, 0, 0, 0.45)
const SELECTED_BG := Color(0.95, 0.85, 0.3, 0.55)

const KEY_FONT_SIZE := 10
const COUNT_FONT_SIZE := 12

## Which slot this widget stands for, echoed back in `slot_pressed`. In the
## equipment panel it is an `Equipment.Slot` rather than an inventory index, which
## is why nothing in here ever indexes an `Inventory` with it.
var index := 0

var _icon: TextureRect = null
var _key: Label = null
var _count: Label = null


## `key_label` is opt-in and empty by default, so a grid slot and a hotbar slot
## are one widget rather than two.
##
## ⚠️ Child order is **icon → key → count**, and `tests/ui/test_hud.gd` pins it:
## the key label is asserted at child index 1.
func _init(slot_index := 0, key_label := "") -> void:
	index = slot_index
	custom_minimum_size = SLOT_SIZE
	color = NORMAL_BG

	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = SLOT_MARGIN
	_icon.offset_top = SLOT_MARGIN
	_icon.offset_right = -SLOT_MARGIN
	_icon.offset_bottom = -SLOT_MARGIN
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Or the icon eats the click that was meant for the slot under it.
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	if key_label != "":
		_key = Label.new()
		_key.text = key_label
		_key.add_theme_font_size_override("font_size", KEY_FONT_SIZE)
		_key.set_anchors_and_offsets_preset(
			Control.PRESET_TOP_LEFT,
			Control.PRESET_MODE_MINSIZE,
			3,
		)
		_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_key)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", COUNT_FONT_SIZE)
	_count.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT,
		Control.PRESET_MODE_MINSIZE,
		3,
	)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)


## Paint whatever `{id, count}` (or `{}`) this slot now holds. The one place a
## stack becomes pixels, so an empty slot can never keep a stale icon.
func set_stack(stack: Dictionary) -> void:
	if stack.is_empty():
		_icon.texture = null
		_count.text = ""
		tooltip_text = ""
		return
	_icon.texture = Hud.icon_for(stack.id)
	_count.text = str(stack.count)
	# Same wording as the cursor inspector's hotbar case, because it is the same
	# question — and while the screen is open the inspector is gated off, so this
	# is the readout that answers it over the grid.
	tooltip_text = "%s ×%d" % [Hud.item_name(stack.id), stack.count]


func set_selected(selected: bool) -> void:
	color = SELECTED_BG if selected else NORMAL_BG


## Read-only accessors for the tests, which would otherwise reach across the
## class boundary into the children this widget owns.
func count_text() -> String:
	return _count.text


func icon_texture() -> Texture2D:
	return _icon.texture


## LMB and RMB only, on press. The screen decides what each means; a slot that
## interpreted them would be a second copy of the interaction model.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	slot_pressed.emit(index, button.button_index, button.shift_pressed)
	accept_event()
