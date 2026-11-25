#!/usr/bin/env bash
# Run every headless suite and print one summary line.
#
#   ./tests/run_all.sh
#   GODOT=/path/to/godot ./tests/run_all.sh
#   EXPECTED_ASSERTIONS=483 ./tests/run_all.sh   # fail if fewer assertions ran
#
# Exit code is 0 only when every suite reported failures=0 and none crashed.

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

total=0
failures=0
broken=0
suites=0

for f in tests/test_*.gd; do
	name="$(basename "$f" .gd)"
	out="$("$GODOT" --headless --path . --script "res://tests/$name.gd" 2>&1)"
	line="$(printf '%s\n' "$out" | grep -o 'RESULT .*' | tail -1)"

	if [ -z "$line" ]; then
		printf '%-38s NO RESULT (crashed or failed to parse)\n' "$name"
		broken=$((broken + 1))
		suites=$((suites + 1))
		continue
	fi

	# A GDScript runtime error aborts the function that raised it, and the suite
	# still prints a RESULT line with failures=0. Any script error means the run
	# stopped testing what it claims to, so treat it as broken rather than green.
	if printf '%s\n' "$out" | grep -q 'SCRIPT ERROR'; then
		first="$(printf '%s\n' "$out" | grep -m1 'SCRIPT ERROR' | cut -c1-90)"
		printf '%-38s SCRIPT ERROR: %s\n' "$name" "$first"
		broken=$((broken + 1))
		suites=$((suites + 1))
		continue
	fi

	a="$(printf '%s' "$line" | sed -n 's/.*assertions=\([0-9]*\).*/\1/p')"
	x="$(printf '%s' "$line" | sed -n 's/.*failures=\([0-9]*\).*/\1/p')"
	total=$((total + a))
	failures=$((failures + x))
	suites=$((suites + 1))

	if [ "$x" -eq 0 ]; then
		printf '%-38s %3s ok\n' "$name" "$a"
	else
		printf '%-38s %3s FAIL(%s)\n' "$name" "$a" "$x"
	fi
done

echo "-----"
echo "suites=$suites assertions=$total failures=$failures broken=$broken"

if [ "$failures" -ne 0 ] || [ "$broken" -ne 0 ]; then
	exit 1
fi

# Guard against silent coverage loss. A suite that aborts part-way (a call to a
# removed method, for instance) still exits 0 and still reports failures=0 - the
# only evidence is that fewer assertions ran. Compare against the declared
# baseline with EXPECTED_ASSERTIONS to catch that.
if [ -n "${EXPECTED_ASSERTIONS:-}" ] && [ "$total" -lt "$EXPECTED_ASSERTIONS" ]; then
	echo "coverage dropped: $total assertions ran, baseline declares at least $EXPECTED_ASSERTIONS"
	echo "If the drop is intended, update docs/engineering/BASELINE.md and record why."
	exit 1
fi
exit 0
