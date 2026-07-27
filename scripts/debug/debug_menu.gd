## One debug panel behind F3, replacing the scatter of F-keys that each owned
## one trick. Adding a debug affordance is now a row here, not another global
## keybinding to remember and collide with.
##
## Only mob spawning keeps a key (F4): it needs the cursor to say *where*, and
## no button can express that.
##
## `is_open` is static and read by the Player, mirroring how `Perf` avoids an
## autoload slot. Gameplay input is polled from `Input` directly rather than
## routed through the UI, so without that flag every click on a button would
## also swing at the world behind it.
## Owning doc: docs/systems/ui.md
class_name DebugMenu
extends CanvasLayer

## True while the panel is showing. Gameplay reads this to ignore clicks that
## are meant for the panel.
static var is_open := false

## Above the HUD (0) and the game-over screen (10); below the perf readout
## (100), which must stay legible on top of everything.
const LAYER := 50
const PANEL_SIZE := Vector2(232.0, 0.0)
const MARGIN := Vector2(12.0, 96.0) ## Clears the HUD bars on the left.

## Test loot: one stack of every ordinary material. Deliberately more stacks
## than the 10-slot hotbar, so the overflow lands past it and a death actually
## has something to put in a loot bag ([player-combat.md](../../docs/systems/player-combat.md)).
const LOOT_STACK := 50

## One press of the XP button. Sized past the first level's cost so a single
## click always visibly does something — levelling is otherwise a long grind
## to reach by hand ([progression.md](../../docs/systems/progression.md)).
const XP_GRANT := 100.0

## Enough of whatever you picked to actually try something with it.
const GIVE_DEFAULT_COUNT := 20

## The factory test rig (3.3). A production chain needs a deposit, and deposits
## only generate underground — so checking one by hand means digging twenty rows
## and hoping. This carves a flat pocket beside the player, lays a short
## `copper_deposit` seam at one end and stocks the hotbar, which is the whole
## setup for `miner → inserter → belt → inserter → furnace` in one press.
##
## ❗️It exists because the WEB build has no other way in: there is no console in
## an exported build, so the browser check of the tick — the one place
## `MAX_CATCH_UP` and the deposit-exhaustion path are real — was otherwise a
## twenty-minute dig every time ([automation.md](../../docs/systems/automation.md)).
const RIG_ORE_MATERIAL := "copper_deposit"
const RIG_ORE_WIDTH := 3
const RIG_HEIGHT := 4
## Wide enough for the FOUR-machine chain 3.5a made possible, laid right to left
## from the seam along the pocket's bottom row:
##
##     turret ins belt ins [press 2] ins belt ins [furnace 2] ins belt ins [miner 3] [ore 3]
##
## which is 20 cells with a single belt tile per link. At the old 22 that left
## two spare and no room to make a mistake; this is that layout with three belt
## tiles per link plus slack, measured off the footprints rather than guessed.
const RIG_WIDTH := 30
## Clear of the player's own body, so the pocket does not carve him out of the
## floor he is standing on.
const RIG_OFFSET := Vector2i(3, 1)
## Everything the chain is built from, at a count that leaves room to make
## mistakes.
##
## ❗️**The generator and the relay are not optional here as of 3.4.** The moment
## `is_powered()` stopped being a stub, a kit of miner/inserter/belt/furnace
## became a chain that can never run: `STARTING_KIT` hands out no machines at
## all, and 3.6's crafting does not exist yet — so an exported build had no way
## to make a single bar ([automation.md](../../docs/systems/automation.md) §Power).
##
## ❗️**Bounded by the HOTBAR, not by the inventory.** 3.5a briefly added
## `ammo_press` and `turret` here, which pushed the kit past
## `Inventory.HOTBAR_SIZE` — the last two stacks (relay and the coal below) landed
## in slots 11-12, which have no UI until 3.6. The generator could not be
## fuelled, so the rig handed over a chain that could never run: exactly the
## failure 3.4 added the generator here to prevent. Caught only in a browser.
##
## Both went back out when "Build defense chain" landed — that row assembles a
## turret line directly, so this one is once again only "hand me the parts to
## place by hand". Either item is still reachable through the give-item dropdown,
## which is already how the spike trap is reached.
##
## ⚠️ `test_debug_menu.gd` asserts the whole kit fits the hotbar. Adding a row
## here without removing one fails that test.
const RIG_KIT: Array[String] = [
	"miner",
	"inserter",
	"conveyor_t1",
	"furnace",
	"generator",
	"relay",
]
const RIG_KIT_COUNT := 10
## ❗️Handed over outright rather than mined. Coal is the bootstrap — a miner
## needs power, a generator needs coal, and coal comes from mining — but the
## seam this rig lays is COPPER (the chain has to smelt something), so without
## this the very first thing a browser check would have to do is go and dig for
## fuel somewhere else.
const RIG_FUEL := "coal"
const RIG_FUEL_COUNT := 50

# --- The assembled defense chain (3.5a browser load test) ---------------------

const MINER_SCENE := preload("res://scenes/automation/miner.tscn")
const INSERTER_SCENE := preload("res://scenes/automation/inserter.tscn")
const CONVEYOR_SCENE := preload("res://scenes/automation/conveyor.tscn")
const FURNACE_SCENE := preload("res://scenes/automation/furnace.tscn")
const PRESS_SCENE := preload("res://scenes/automation/ammo_press.tscn")
const TURRET_SCENE := preload("res://scenes/automation/turret.tscn")
const GENERATOR_SCENE := preload("res://scenes/automation/generator.tscn")

## The figure the 3.5a browser check calls for: enough turrets that the OLD fixed
## 32-slot pool would have been saturated and started stealing shots in flight.
const CHAIN_TURRETS := 6
## One generator runs ~2 machines at full rate, and the chain plus six turrets
## draws well past that. Spread along the pocket so their radii overlap into one
## grid — a brownout here would be measuring the wrong thing.
const CHAIN_GENERATORS := 3
const CHAIN_AMMO := "copper_ammo"

## Injected by tests; fall back to the autoloads.
var game: Node = null
var waves: Node = null
var items: Node = null
var progression: Node = null
var terrain: Node = null
## Set by main.gd before add_child — the overlays this panel drives.
var flow_overlay: Node2D = null
var slot_overlay: Node2D = null
var perf_overlay: CanvasLayer = null
## The light grid's render pass. Hiding it IS full bright (terrain.md §Lighting).
var light_map: Node2D = null
## Where `build_defense_chain` parents what it builds. Injected by tests, which
## have no `current_scene` — the same seam `Waves.spawn_parent` is.
var spawn_parent: Node = null
## Which tick registry the built chain joins. Injected by tests so the fixture is
## assertable against their own Automation rather than the live autoload.
var automation: Node = null

var _rows: VBoxContainer = null
var _give_id: OptionButton = null
var _give_count: SpinBox = null


func _ready() -> void:
	if game == null:
		game = Game
	if waves == null:
		waves = Waves
	if items == null:
		items = Items
	if progression == null:
		progression = Progression
	if terrain == null:
		terrain = Terrain
	layer = LAYER
	# Usable while the tree is paused (the game-over screen pauses it).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_set_open(false)


func _exit_tree() -> void:
	is_open = false # Never leave the flag set for the next scene.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug_menu"):
		_set_open(not visible)


## Public so tests can drive it without synthesising input.
func toggle() -> void:
	_set_open(not visible)


func _set_open(open: bool) -> void:
	visible = open
	is_open = open

# --- Actions -----------------------------------------------------------------


## Enough stacks to overflow the hotbar, so the surplus sits in slots 10+ and
## dying leaves a bag worth walking back to.
func give_test_loot() -> void:
	for id in Materials.ORDER:
		var mat: Dictionary = Materials.MATERIALS[id]
		if mat.is_deposit or mat.min_tool_tier >= 99:
			continue # Deposits aren't items; bedrock never drops.
		items.player_inventory.add_item(id, LOOT_STACK)


## Carve the factory pocket beside the player and hand over the kit. Returns the
## pocket's top-left cell so a test can assert against it without re-deriving the
## geometry.
##
## The seam sits at the pocket's RIGHT end and is two rows tall, so a miner
## placed against it faces RIGHT and its harvest block lands on the ore — the
## placement the ghost is trying to teach. The floor under the pocket is stone,
## because a `support_dirs = 15` machine standing in a carved hole needs
## something solid to hold it up.
##
## Since 3.4 it also hands over a generator, a relay and a stack of coal: the
## chain draws power now, and the rig's whole job is "one press, then build".
func build_factory_rig() -> Vector2i:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return Vector2i.ZERO
	var at := Vector2i((player.global_position / TileLayout.TILE_SIZE).floor()) + RIG_OFFSET
	for dx in RIG_WIDTH:
		for dy in RIG_HEIGHT:
			terrain.set_tile(at + Vector2i(dx, dy), "")
		terrain.set_tile(at + Vector2i(dx, RIG_HEIGHT), "stone")
	for dx in RIG_ORE_WIDTH:
		for dy in 2:
			var ore := at + Vector2i(RIG_WIDTH - 1 - dx, RIG_HEIGHT - 2 + dy)
			terrain.set_tile(ore, RIG_ORE_MATERIAL)
	for id: String in RIG_KIT:
		items.player_inventory.add_item(id, RIG_KIT_COUNT)
	items.player_inventory.add_item(RIG_FUEL, RIG_FUEL_COUNT)
	return at


## The whole `miner → belt → furnace → belt → ammo press → belt → turret` chain,
## ASSEMBLED, plus a line of fuelled turrets — the browser load test in one press.
##
## ❗️**Why this exists beside `build_factory_rig`.** That row hands over parts so
## the placement path can be exercised by hand. This one skips placement on
## purpose: what only a browser can tell us is how the 10 Hz tick and the
## projectile pool behave under concurrent load
## ([automation.md](../../docs/systems/automation.md) §The 10 Hz tick), and
## building a four-machine chain plus six turrets by hand is ~40 precise clicks
## that land somewhere slightly different every run. A measurement you cannot
## reproduce is not a measurement. Placement, support, mining and the transfer
## seam are already covered headless and in the editor.
##
## ❗️Everything is built in the REAL placement order — instantiate → inject →
## `facing` → `setup` → `add_child` → `register` → `on_placed()` — so this is a
## world assembled the way the player would assemble it, not a special case the
## tick might treat differently. Layout is lifted from
## `tests/automation/test_production_chain.gd`, which asserts this exact geometry
## produces loaded ammo; duplicating it into a second shape would let the two
## drift.
##
## Returns the pocket's top-left cell, and the turrets, so a test can assert
## against them without re-deriving the geometry.
func build_defense_chain() -> Dictionary:
	var at := build_factory_rig()
	if at == Vector2i.ZERO:
		return { }
	var row := at + Vector2i(0, RIG_HEIGHT - 1) # The pocket's floor row.
	# Right to left from the seam, mirroring the test's layout.
	var miner_x := RIG_WIDTH - RIG_ORE_WIDTH - 3
	var chain: Array[Deployable] = []
	chain.append(_spawn(MINER_SCENE, row + Vector2i(miner_x, -1), Vector2i.RIGHT))
	chain.append(_spawn(INSERTER_SCENE, row + Vector2i(miner_x - 1, 0), Vector2i.LEFT))
	chain.append(_spawn(CONVEYOR_SCENE, row + Vector2i(miner_x - 2, 0), Vector2i.LEFT))
	chain.append(_spawn(INSERTER_SCENE, row + Vector2i(miner_x - 3, 0), Vector2i.LEFT))
	chain.append(_spawn(FURNACE_SCENE, row + Vector2i(miner_x - 5, -1), Vector2i.LEFT))
	chain.append(_spawn(INSERTER_SCENE, row + Vector2i(miner_x - 6, 0), Vector2i.LEFT))
	chain.append(_spawn(CONVEYOR_SCENE, row + Vector2i(miner_x - 7, 0), Vector2i.LEFT))
	chain.append(_spawn(INSERTER_SCENE, row + Vector2i(miner_x - 8, 0), Vector2i.LEFT))
	chain.append(_spawn(PRESS_SCENE, row + Vector2i(miner_x - 10, -1), Vector2i.LEFT))

	# ❗️Generators are handed their coal directly. The bootstrap (mine coal, feed
	# the generator) is a thing to play, not a thing to re-prove on every perf run,
	# and a rig that needs feeding mid-measurement measures the feeding.
	var gens: Array[Deployable] = []
	for i in CHAIN_GENERATORS:
		var gen := _spawn(GENERATOR_SCENE, row + Vector2i(2 + i * 5, -3))
		gen.accept_item(RIG_FUEL, Inventory.STACK_SIZE)
		gens.append(gen)

	# The turret line, along the pocket's open left end — spread one clear cell
	# apart so each has its own footprint and its own reservation.
	var turrets: Array[Deployable] = []
	for i in CHAIN_TURRETS:
		var turret := _spawn(TURRET_SCENE, row + Vector2i(1 + i * 2, 0))
		turret.accept_item(CHAIN_AMMO, Inventory.STACK_SIZE)
		turrets.append(turret)

	return { pocket = at, chain = chain, generators = gens, turrets = turrets }


## One deployable, built exactly the way `Player._place_scene` builds one. Returns
## it un-registered rather than crashing if the cells are taken, so a rig dropped
## on top of an old one degrades instead of dying mid-build.
func _spawn(scene: PackedScene, cell: Vector2i, facing := Vector2i.RIGHT) -> Deployable:
	var node: Deployable = scene.instantiate()
	# Before on_placed, which is what reads it to pick a registry.
	if &"automation" in node:
		node.automation = automation if automation != null else Automation
	node.facing = facing
	node.setup(cell)
	var parent: Node = spawn_parent if spawn_parent != null else get_tree().current_scene
	parent.add_child(node)
	if not node.register(terrain):
		node.queue_free()
		return null
	node.on_placed()
	return node


## Levelling by hand means mining hundreds of blocks; this is how the level-up
## path (stat grant, banner, bar rebase) gets exercised on demand.
func grant_xp() -> void:
	progression.grant_xp("debug", XP_GRANT)


func kill_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	# Clear the grace window first, or a recent hit silently eats this.
	player._invuln_left = 0.0
	player.take_damage(INF)


## Every item worth handing out by name: authored items first, then ordinary
## materials. Deposits are terrain features rather than items and bedrock never
## drops, so neither can end up in the inventory as an unplaceable id — the same
## rule give_test_loot uses.
static func giveable_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id: String in ItemDefs.STATS:
		ids.append(id)
	for id: String in Materials.ORDER:
		var mat: Dictionary = Materials.MATERIALS[id]
		if mat.is_deposit or mat.min_tool_tier >= 99:
			continue
		if not ids.has(id):
			ids.append(id)
	return ids


## Hand over an arbitrary stack. Kept ALONGSIDE give_test_loot rather than
## replacing it: that row is a one-click fixture that deliberately overflows the
## hotbar for the loot-bag flow, and reproducing it through this dropdown is 16
## interactions. Two rows, two purposes (ui.md).
func give_item(id: String, count: int) -> void:
	if id == "" or count <= 0:
		return
	items.player_inventory.add_item(id, count)


## Answers "is this dark because of the depth, or because my light is broken",
## and is how the itch screenshots get taken. Tolerates a missing light map so
## every row stays clickable in a stripped build or a test harness.
func _toggle_full_bright(pressed: bool) -> void:
	if light_map != null:
		light_map.visible = not pressed


func _give_pressed() -> void:
	if _give_id == null or _give_id.selected < 0:
		return
	give_item(_give_id.get_item_text(_give_id.selected), int(_give_count.value))


func _toggle_flow_overlay(pressed: bool) -> void:
	if flow_overlay != null:
		flow_overlay.visible = pressed


## Automation slot occupancy, counts, facings and cooldowns — the visible half of
## the tick-bug mitigation ([plan.md](../../docs/plan.md) names tick bugs the
## top-listed risk). A row rather than a hotkey, per this doc's own rule that
## debug overlays own no keybindings.
func _toggle_slot_overlay(pressed: bool) -> void:
	if slot_overlay != null:
		slot_overlay.visible = pressed


## Routed through the static seam rather than a node reference: this panel is
## handed its overlays by main.gd, but the HUD is not one of them and should not
## become one for a checkbox ([ui.md](../../docs/systems/ui.md)).
func _toggle_inspector(pressed: bool) -> void:
	Hud.set_inspector_enabled(pressed)


func _toggle_perf_overlay(pressed: bool) -> void:
	if perf_overlay == null:
		return
	perf_overlay.visible = pressed
	if pressed:
		perf_overlay.reset_stats() # Turning it on means "measure from here".

# --- Layout ------------------------------------------------------------------


func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = MARGIN
	panel.custom_minimum_size = PANEL_SIZE
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	_rows = VBoxContainer.new()
	margin.add_child(_rows)

	_title("Debug — F3")
	_check("Flow field overlay", _toggle_flow_overlay)
	_check("Automation slots", _toggle_slot_overlay)
	_check("Perf readout", _toggle_perf_overlay)
	_check("Full bright", _toggle_full_bright)
	# ❗️The one row that starts ON: the cursor inspector is a player-facing
	# readout ([ui.md](../../docs/systems/ui.md)), not a debug overlay, and it
	# only lives here because this panel is where a toggle belongs.
	_check("Cursor inspector", _toggle_inspector, Hud.inspector_enabled)
	_button("Skip countdown", func() -> void: game.skip_countdown())
	_button("Clear wave", func() -> void: waves.debug_clear_wave())
	_button("Poke nearest mob", func() -> void: waves.debug_poke_nearest())
	_button("Give test loot", give_test_loot)
	_button("Build factory rig", build_factory_rig)
	_button("Build defense chain", func() -> void: build_defense_chain())
	_give_row()
	_button("Grant %d XP" % roundi(XP_GRANT), grant_xp)
	_button("Kill player", kill_player)
	_title("F4 — spawn mob at cursor")


## Item dropdown + quantity + Give, on one line.
func _give_row() -> void:
	var row := HBoxContainer.new()
	_rows.add_child(row)

	_give_id = OptionButton.new()
	_give_id.fit_to_longest_item = false
	_give_id.custom_minimum_size = Vector2(96.0, 0.0)
	for id in giveable_ids():
		_give_id.add_item(id)
	row.add_child(_give_id)

	_give_count = SpinBox.new()
	_give_count.min_value = 1
	_give_count.max_value = 999
	_give_count.value = GIVE_DEFAULT_COUNT
	_give_count.custom_minimum_size = Vector2(56.0, 0.0)
	row.add_child(_give_count)

	var button := Button.new()
	button.text = "Give"
	button.pressed.connect(_give_pressed)
	row.add_child(button)


func _title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	_rows.add_child(label)


func _check(text: String, on_toggled: Callable, starts_on := false) -> void:
	var check := CheckButton.new()
	check.text = text
	# Set BEFORE connecting, so seeding the box does not fire the handler and
	# re-assert a state that is already true.
	check.button_pressed = starts_on
	check.toggled.connect(on_toggled)
	_rows.add_child(check)


func _button(text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	_rows.add_child(button)
