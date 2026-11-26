#!/usr/bin/env bash
# Run every headless suite and print one summary line.
#
#   ./tests/run_all.sh
#   GODOT=/path/to/godot ./tests/run_all.sh
#   ./tests/run_all.sh --fix                 # rewrite stale line counts in the docs
#   EXPECTED_ASSERTIONS=805 ./tests/run_all.sh
#
# The checks themselves live in tests/run_suites.gd, so this file only locates
# the engine. Windows does the same through run_all.ps1; before that move the two
# entry points had drifted, and the PowerShell one was missing the SCRIPT ERROR
# and documentation guards entirely.
#
# Exit code is 0 only when every suite reported failures=0, none aborted, the
# assertion total did not drop below the baseline, and the documents agree.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
cd "$ROOT" || exit 2

# Fail fast: without a working binary every suite would look like a crash.
if ! command -v "$GODOT" >/dev/null 2>&1; then
	if [ -x "$GODOT" ]; then
		:
	else
		echo "Godot not found: '$GODOT'"
		echo "Set it explicitly, for example:"
		echo "  GODOT=/path/to/Godot_v4.7.2-stable_win64_console.exe ./tests/run_all.sh"
		exit 2
	fi
fi

exec "$GODOT" --headless --path . --script res://tests/run_suites.gd -- "$@"
