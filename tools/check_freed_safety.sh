#!/usr/bin/env bash
#
# Catches the two ways a TYPE ANNOTATION dereferences a freed instance before
# your own guard can run. Both have shipped in this repo already.
#
# The root cause both patterns share: an annotation is executable code. GDScript
# type-checks the value as it lands in the typed slot, and type-checking an
# object means dereferencing it. A freed object is not `null` — it is a dangling
# reference — so the check itself raises, and the `is_instance_valid` guard on
# the next line never runs.
#
# [1] A typed LOOP VARIABLE over a stored collection.
#
#         for candidate: Node in candidates:      # <- raises here
#             if not is_instance_valid(candidate): # <- never reached
#
#     Shipped in Turret.pick_target (3.5a).
#
#     ❗️The discriminator is whether the collection was built THIS FRAME:
#     a call — get_nodes_in_group(...), machines(), get_children() — cannot
#     contain a freed instance, because Godot drops a node from its groups when
#     it actually deletes it, and a queue_free()d node is still valid until then.
#     A BARE IDENTIFIER (a member array, or an Array parameter someone handed
#     you) can outlive that boundary and hold a corpse. Only bare identifiers
#     are flagged, which is what keeps this check quiet enough to leave on.
#
# [2] A DICTIONARY TYPED BY AN OBJECT KEY.
#
#         var _threat: Dictionary[Node, float]
#
#     erase() on a freed key is REJECTED by the same validation, returns false,
#     and the entry survives — leaking silently while lookups appear to work.
#     Shipped in ThreatTable.
#
# Fix either by dropping the annotation and filtering explicitly, or — when the
# collection provably cannot hold a corpse — by justifying it in place:
#
#     # freed-safe: <why this collection cannot hold a freed instance>
#
# on the line before, or trailing the line itself.
#
# Usage: tools/check_freed_safety.sh [paths...]   (default: scripts/ tests/)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

TARGETS=("$@")
[[ ${#TARGETS[@]} -eq 0 ]] && TARGETS=(scripts tests)

# Value types can never be a dangling object reference, so a typed loop over
# them is always safe. Everything else is treated as an object type.
VALUE_TYPES='String|StringName|int|float|bool|Variant|Vector2|Vector2i|Vector3|Vector3i|Rect2|Rect2i|Color|Transform2D|Basis|Quaternion|Plane|AABB|Dictionary|Array|Packed[A-Za-z]+Array|NodePath|RID|Callable|Signal'

fail=0

# Is this hit exempt? Either it is a COMMENT — the doc comments warning against
# these very patterns must not trip the check that enforces them — or it carries
# a `# freed-safe:` marker, trailing the line or anywhere in the contiguous
# comment block directly above it. The block scan is deliberate: a reason worth
# writing is usually longer than one line, and forcing it onto the last line
# would push authors toward a marker with no reason attached.
is_exempt() {
	local file="$1" line="$2" text probe
	text="$(sed -n "${line}p" "$file")"
	[[ "$text" =~ ^[[:space:]]*# ]] && return 0
	grep -q '# *freed-safe:' <<<"$text" && return 0
	probe=$((line - 1))
	while [[ $probe -ge 1 ]]; do
		text="$(sed -n "${probe}p" "$file")"
		[[ "$text" =~ ^[[:space:]]*# ]] || break
		grep -q '# *freed-safe:' <<<"$text" && return 0
		probe=$((probe - 1))
	done
	return 1
}

report() {
	local file="$1" line="$2" why="$3"
	printf '%s:%s: %s\n' "$file" "$line" "$why"
	sed -n "${line}p" "$file" | sed 's/^/    /'
	fail=1
}

while IFS=: read -r file line _; do
	[[ -z "${file:-}" ]] && continue
	is_exempt "$file" "$line" || report "$file" "$line" \
		"typed loop variable over a stored collection — may hold a freed instance"
done < <(
	grep -rnE "for [a-z_][a-zA-Z0-9_]*: [A-Z][A-Za-z0-9_]* in [a-z_][a-zA-Z0-9_]*:" \
		--include='*.gd' "${TARGETS[@]}" 2>/dev/null \
		| grep -vE "for [a-z_][a-zA-Z0-9_]*: ($VALUE_TYPES) in "
)

while IFS=: read -r file line _; do
	[[ -z "${file:-}" ]] && continue
	is_exempt "$file" "$line" || report "$file" "$line" \
		"Dictionary typed by an object key — erase() silently fails on a freed key"
done < <(
	grep -rnE "Dictionary\[[A-Z][A-Za-z0-9_]*," --include='*.gd' "${TARGETS[@]}" 2>/dev/null \
		| grep -vE "Dictionary\[($VALUE_TYPES),"
)

if [[ $fail -ne 0 ]]; then
	cat <<'EOF'

A type annotation is executable code: it dereferences the value BEFORE the next
line's is_instance_valid guard can run, so the guard protects nothing.

Fix by dropping the annotation and filtering explicitly:

    for candidate in candidates:
        if not is_instance_valid(candidate):
            continue

or, if the collection provably cannot hold a freed instance, say why in place:

    # freed-safe: <reason>

See tools/check_freed_safety.sh for the full rationale.
EOF
	exit 1
fi

echo "freed-safety: clean"
