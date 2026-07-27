#!/usr/bin/env bash
# Daily web build: headless export + push to itch.io (roadmap standing item).
# Usage: tools/export_and_push.sh [--no-push]
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
BUTLER="${BUTLER:-$HOME/workspace/tools/butler-darwin-arm64/butler}"
ITCH_TARGET="driky/jailos:html5"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/web"

mkdir -p "$BUILD_DIR"
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Web" "$BUILD_DIR/index.html"

test -s "$BUILD_DIR/index.html" -a -s "$BUILD_DIR/index.wasm" -a -s "$BUILD_DIR/index.pck"

if [[ "${1:-}" == "--no-push" ]]; then
    echo "Export OK (push skipped): $BUILD_DIR"
    exit 0
fi

"$BUTLER" push "$BUILD_DIR" "$ITCH_TARGET" --userversion "$(date +%Y-%m-%d-%H%M)"
echo "Pushed to https://driky.itch.io/jailos"
