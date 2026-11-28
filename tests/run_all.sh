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

# Keep suites off the developer's real user:// data. Godot reads XDG_DATA_HOME
# on Linux and %APPDATA% on Windows (including Git Bash); both point at a
# throwaway directory so assertion numbers match a clean CI profile.
TEST_DATA_ROOT="${TMPDIR:-/tmp}/echo-test-user-data"
export XDG_DATA_HOME="$TEST_DATA_ROOT/xdg-data"
export APPDATA="$TEST_DATA_ROOT/appdata"
mkdir -p "$XDG_DATA_HOME" "$APPDATA"

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

# Every suite runs against the engine's own user:// directory, which on a
# developer's machine holds a real save: equipped fragments, squad loadouts, a
# suspended journey. Those are not fixtures. A save with 5-6 fragments equipped
# per character shifted 49 damage and health assertions here while CI stayed
# green, because CI starts from an empty container and never sees them. Point
# user:// at a scratch directory so the numbers under test are the ones in the
# repository, and so a run never writes into someone's playthrough.
#
# The scratch directory lives under .godot/ (already ignored) rather than in the
# system temp dir: Windows keeps the engine's log handles open for a moment after
# it exits, so deleting the profile right away silently fails and leaves debris
# behind. A fixed path is cleared before each run instead, and only falls back to
# a unique name when the previous one is still locked.
USER_ROOT="$ROOT/.godot/test-userdata"
rm -rf "$USER_ROOT" 2>/dev/null
if [ -e "$USER_ROOT" ]; then
	USER_ROOT="$ROOT/.godot/test-userdata-$$"
	rm -rf "$USER_ROOT" 2>/dev/null
fi
mkdir -p "$USER_ROOT/share" "$USER_ROOT/home"
if command -v cygpath >/dev/null 2>&1; then
	# Windows resolves user:// from %APPDATA%; the engine wants a native path.
	export APPDATA="$(cygpath -w "$USER_ROOT")"
else
	# Linux resolves it from $XDG_DATA_HOME, macOS falls back to $HOME.
	export XDG_DATA_HOME="$USER_ROOT/share"
	export HOME="$USER_ROOT/home"
fi

"$GODOT" --headless --path . --script res://tests/run_suites.gd -- "$@"
status=$?
# Best effort: a locked profile is harmless because the next run clears it.
rm -rf "$USER_ROOT" 2>/dev/null
exit $status
