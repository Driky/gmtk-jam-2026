#!/usr/bin/env bash
# Regenerate placeholder tile sheets + terrain_tileset.tres from the template
# and data/materials.gd. Two godot passes with an --import between them: the
# .tres must reference *imported* textures. Owning doc: docs/systems/pipeline.md
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$GODOT" --headless --path "$PROJECT_DIR" --script res://tools/generate_tilesets.gd -- --pngs
"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null
"$GODOT" --headless --path "$PROJECT_DIR" --script res://tools/generate_tilesets.gd -- --tileset
