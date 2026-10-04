#!/bin/bash
# Fast parse/compile check of all GDScript and shaders (updates the class cache first).
# Usage: bash frontier/tools/check.sh
cd "$(dirname "$0")/.."
godot --headless --import >/dev/null 2>&1
godot --headless res://scenes/check.tscn 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error|CHECK FAIL|checked|ERROR: .*\.gd|SHADER ERROR|shader" | grep -v "^$"
exit ${PIPESTATUS[0]}
