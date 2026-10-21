#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-}"
if [[ -z "$godot_bin" ]]; then
  if command -v godot >/dev/null 2>&1; then godot_bin="$(command -v godot)"
  elif command -v godot4 >/dev/null 2>&1; then godot_bin="$(command -v godot4)"
  elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then godot_bin=/Applications/Godot.app/Contents/MacOS/Godot
  elif [[ -x "$project_dir/../.tmp/godot-tools/Godot.app/Contents/MacOS/Godot" ]]; then godot_bin="$project_dir/../.tmp/godot-tools/Godot.app/Contents/MacOS/Godot"
  else
    echo 'Godot 4.6+ is required. Set GODOT_BIN to the executable path.' >&2
    exit 1
  fi
fi
if [[ ! -f "$project_dir/.godot/global_script_class_cache.cfg" && " $* " != *" --editor "* ]]; then
  "$godot_bin" --headless --path "$project_dir" --editor --import --quit
fi
exec "$godot_bin" --path "$project_dir" "$@"
