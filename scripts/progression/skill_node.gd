## One node of the skill tree: what it costs, what it needs first, and what it
## does. Authored as `.tres` under `data/skills/` and registered in
## `data/skill_defs.gd`, exactly as `ItemStats` is by `data/item_defs.gd`.
##
## ❗️**There is no `unlock_recipes[]`, and that is a resolution rather than an
## omission.** A node unlocking a recipe and a recipe naming its gate are the same
## edge; storing it on both sides is one fact with two writable copies, free to
## drift the first time a recipe moves branch. The recipe row's `unlocked_by`
## wins — it shipped at 3.6b and the crafting tab already filters on it — so a
## node's unlocks are a QUERY over `RecipeDefs`, never a second list here.
##
## Owning doc: docs/systems/progression.md
class_name SkillNode
extends Resource

## Stable key. ⚠️ Stored here **and** used as the `SkillDefs.NODES` key: a `.tres`
## whose `id` disagrees with its key resolves through one path and not the other,
## which is why a test pins the two together.
@export var id := ""
@export var display_name := ""
## One line, shown in the node's tooltip. What the buff or unlock is FOR, not a
## restatement of the numbers — the tooltip prints those from the fields below.
@export var description := ""
## Node ids that must be at level ≥ 1 before this can be taken. A root has none.
##
## `PackedStringArray` rather than `Array[String]`: it is a small authored list of
## ids read by value, and the packed type is what a `.tres` round-trips cleanly.
@export var prerequisites := PackedStringArray()
## Upgrade points **per level**, so a ×3 node costs three points to max out.
@export var point_cost := 1
## `{item_id: count}`, the same shape as a recipe's `inputs`, paid through
## `Items.consume_available` ([progression.md](../../docs/systems/progression.md)
## §Crafting range) — so a chest in range pays for a node exactly as it pays for
## a craft.
##
## ❗️**Empty on every ROOT**, and that is not a balance number: a level-2 player
## has exactly one point and whatever ore they dug by hand, so a root priced in
## bars is the same deadlock the bootstrap-recipe rule forbids one layer down.
## Pinned by a test.
##
## ⚠️ An empty cost is *refused* by `consume_available` rather than trivially
## granted, so the caller must only call it when this is non-empty — otherwise
## every point-only node is unbuyable.
@export var resource_cost: Dictionary = { }
## How many times it can be taken. 1 for an unlock, 2–3 for a leveled buff.
@export var max_level := 1

## The `Progression.get_stat` name this multiplies, `""` for a node that only
## unlocks recipes. Unknown stats read a neutral 1.0, which is what lets a buff
## be authored before its consumer exists.
@export var stat_name := ""
## Added to the multiplier per level taken: 0.1 is "+10% per level", and two
## nodes naming one stat add rather than compound.
@export var stat_per_level := 0.0

## Hand-placed position inside the tree canvas, in canvas pixels
## ([progression.md](../../docs/systems/progression.md) §Skill tree locks that the
## layout is authored rather than computed).
##
## ⚠️ The canvas is a plain `Control` for exactly this reason: any container
## re-lays-out its children and would overwrite this the frame it is set.
@export var position := Vector2.ZERO
