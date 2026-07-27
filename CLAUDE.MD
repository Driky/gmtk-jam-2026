Solo game jam. Godot 4.x, GDScript only, HTML5/web export (Compatibility renderer, single-threaded, no threads, no C#).

docs/tech-design.md is the design entry point: pitch, constraints, glossary, and a decision log linking each locked decision to its single owning doc under docs/systems/ (+ docs/plan.md). Before modifying a system, read its owning doc. Every decision lives in exactly ONE doc — when it changes, update that owning doc in the SAME commit; never restate a decision in another doc (one-line mention + link only).

## Freed instances vs. type annotations

**A type annotation is executable code.** It type-checks — and therefore dereferences — the value as it lands in the typed slot, *before* the next line runs. A freed object is not `null`; it is a dangling reference. So an `is_instance_valid` guard written one line below an annotation protects nothing: the annotation already raised. Two shapes, both of which have shipped here:

- `for x: SomeNode in stored_array:` — raises `Trying to assign invalid previously freed instance`. Shipped in `Turret.pick_target` (3.5a).
- `Dictionary[SomeNode, X]` — `erase()` on a freed key is rejected, returns `false`, and the entry **survives and leaks** while lookups still look correct. Shipped in `ThreatTable`.

**The discriminator is whether the collection was built this frame.** A call (`get_nodes_in_group(…)`, `machines()`, `get_children()`) is safe: Godot drops a node from its groups when it actually deletes it, and a `queue_free()`d node stays valid until then — so a fresh scan can never hold a corpse. A **stored** collection — a member array, or an `Array` parameter a public/static function was handed — can outlive that boundary and must be iterated **untyped** with an explicit `is_instance_valid` filter.

`tools/check_freed_safety.sh` enforces both (run by the `pre-commit` hook; ~10 known-safe sites carry a `# freed-safe: <reason>` marker, honoured anywhere in the comment block above the line). ⚠️ Git hooks are not version-controlled — after a fresh clone, re-add `.git/hooks/pre-commit`.