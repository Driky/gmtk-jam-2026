# Item Authoring Tools — intent, decisions, rejected avenues

> ⚠️ **Nothing here is locked, and nothing here is scheduled.** This is the record of a design
> conversation held while 3.5c landed (2026-07-27), written down so the eventual step doc argues
> from it rather than re-deriving it. It is deliberately **not** in [tech-design.md](tech-design.md)'s
> decision log: that log is for decisions the shipping code obeys, and no code obeys any of this yet.
>
> **Sequencing: after the jam-planned scope is finished.** The jam deadline has passed; the project
> continues, and the remaining roadmap is being completed first so it is not left unfinished.

## The goal

A developer or game designer should be able to create and edit items and their stats through a
**datatable-style GUI inside the Godot editor** — not by hand-editing resource files one at a time.

- Simple fields (name, damage, cooldown, colours, counts) are edited in the table directly.
- Compound values that are authored elsewhere — a melee `hitbox_scene`, a `ProjectileStats` — are
  **created first as their own assets**, and the tool offers them in a picker.
- A **preview** shows the item as it actually behaves: deployed in the world if it is a deployable,
  held in the character's hand, static, and mid-swing — with the animation, FX and sound that go
  with each action.

## ❗️The blocker: authoring is split across two surfaces

Today an item's identity lives in **two places with different shapes**:

| | Authored in | Table-shaped? |
|---|---|---|
| Item stats — `display_name`, `mining_power`, `melee_damage`, `place_scene`, … | `data/items/*.tres` (a `Resource`) | Yes — plain-text `key = value` |
| Deployable structure — `size`, `max_hp`, `support_dirs`, `removal_hits`, `power_demand`, … | `scenes/automation/*.tscn` | **No** — a scene is not a row |

So a chest is `chest.tres` **and** `chest.tscn`, and a GUI over only the first half is a GUI a
designer cannot finish a chest in. `scripts/automation/deployable.gd`'s own header already claims
these are "`.tres` rows plus a small subclass" — the code and that sentence disagree, and have since
3.1.

**This is the real prerequisite.** The consolidation is not a nice-to-have before the tool; it *is*
the tool's data model. It also pays for itself independently — [save.md](systems/save.md)'s diff and
any balance pass both get easier when a deployable's numbers are one row.

## Decisions taken (in this conversation, not yet in code)

1. **The GUI is a main-screen tab**, beside 2D / 3D / Script / Game — not a bottom panel. A table
   plus a per-item form plus a preview pane wants full-screen real estate; the bottom panel is a
   horizontal strip. Mechanism: `EditorPlugin._has_main_screen()` → `true`, plus
   `_get_plugin_name()` / `_get_plugin_icon()` / `_make_visible()`, with the root control parented
   under `EditorInterface.get_editor_main_screen()`.
2. **The preview runs the real game, not the editor.** A Preview button calls
   `EditorInterface.play_custom_scene(...)` on a preview harness. It is a real game process, so it
   gets every autoload, the real renderer, real audio and real physics — and needs **no `@tool`
   annotation anywhere**. See §Rejected for why that matters more than it sounds.
3. **One static harness scene, built at runtime** — not a `.tscn` generated per preview. Generating
   scene files into the project is a known footgun here: a headless editor pass resurrects deleted
   dev scenes at their old paths.
4. **The item to preview is handed over through a request file**, not an object: the game is a
   separate OS process. Writing e.g. `preview_request.json` before launching also makes the harness
   runnable by hand with a checked-in request, which is what makes it debuggable on its own.
5. **A single text DB is the source of truth**, written by the tool and read directly by the game —
   no generated `.tres` mirror to drift. **JSON leads** (typed enough for a `Color` or a `Vector2i`,
   trivially parsed, diffs line-per-item under a stable key order).
6. **Resources stay resources.** The DB stores `res://` **paths** for `hitbox_scene` / `projectile`;
   it never inlines them. The picker for those fields is Godot's own `EditorResourcePicker` with
   `base_type` set — typed, drag-drop, quick-load, and nothing to build.

## Avenues considered and rejected

- **Bottom panel for the GUI** — proposed first, then dropped: wrong aspect ratio for a table plus a
  form plus a preview.
- **`@tool` on the gameplay scripts, so an editor dock can animate the preview.** Rejected, and this
  is the decision that saves the most work. A swing, its hitbox, its FX and its timing *are* gameplay
  code; running them in the editor means `@tool` on the player, the hitbox, the tween paths and the
  pooled projectiles, each then needing guards for "no autoloads, no `Game.state`, no physics". That
  is a permanent tax on every future edit to those scripts, and `@tool` mistakes can hang the editor,
  which makes them miserable to debug. Decision 2 removes the entire category.
- **A folder of hand-edited `.tres` as the DB.** Rejected on **serializer churn**, not on conflict
  volume: Godot rewrites a resource on save with reordered properties and uid annotations, so a
  one-field edit produces a diff nobody can review. (One big file does not reduce conflicts — everyone
  touches it — but it makes them *readable*, line-per-item, instead of engine noise.)
- **CSV instead of JSON.** Not rejected outright — kept as the option if spreadsheet-first authoring
  turns out to matter more than nesting. It diffs beautifully and is worse at everything else
  (a `Color`, a `Vector2i`, a resource path).
- **Generating `.tres` from the DB.** Rejected: an extra step and a second copy that can drift, for
  no benefit once the tool exists.
- **Putting the chest's slot count on `chest.tscn` as an `@export`.** The worked example that started
  this. Smallest change and consistent with every other deployable number today — and exactly the
  wrong side of the migration above. Left as a script `const` (`Chest.CHEST_SLOTS`) rather than
  moving it somewhere it would move again.
- **Putting deployable stats on `ItemStats` (`data/items/*.tres`).** A reasonable interim — it is
  already a `Resource` and already couples to deployables through `place_scene` — but superseded by
  decision 5, which does not want a `.tres` layer at all.
- **A new `data/deployable_defs.gd` static dict**, mirroring `item_defs.gd` / `recipe_defs.gd`. Good
  shape, and the closest thing the repo has to a table today; superseded by the same decision, since
  a GUI writing GDScript source is awkward.

## Open questions

- CSV vs JSON, finally — decided by whether authoring is genuinely spreadsheet-first.
- Whether item stats and deployable structure become **one row** per thing or two linked tables.
- Whether the DB is one file or split by category (conflict surface vs. lookup simplicity).
- **What happens to `ItemDefs.stats_for`'s resolution chain** (authored → block default → bare hand).
  It is why nothing in the player has a "no item" branch — see
  [systems/player-combat.md](systems/player-combat.md) — and it is the kind of thing that dies quietly
  in a data migration.
- Migration mechanics for the existing `.tres` and `.tscn` content, and whether it is one pass or
  incremental per category.

## Adjacent, and not this doc's subject

Dropping the jam's web constraints (single-threaded, Compatibility renderer, HTML5 export — see
[tech-design.md](tech-design.md) §Hard Constraints) lands in the same post-jam window. Several
shipped decisions are justified *by* those constraints and would become stale rather than
wrong-looking; they need their own pass over the decision log, not a mention here.
