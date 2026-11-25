#!/usr/bin/env bash
# Checks that no document repeats the *total* assertion count with a stale value.
#
# Why this exists: the total has drifted three times. Each time a separate pull
# request updated the same number in several files, the last to merge won, and the
# others silently described a state that no longer applied. BASELINE.md already
# says the number is maintained in one place; this holds the rest of the tree to
# that instead of trusting everyone to remember.
#
# Three kinds of number are deliberately ignored, because they are correct while
# disagreeing with the baseline:
#   - a single suite's count ("`test_hunter_summon.gd`，39 条断言")
#   - historical runs ("修复前 ... 300 条断言", archived records)
#   - the change log's before/after pairs, which live in BASELINE itself
#
# The baseline is the source and is not checked.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

baseline="docs/engineering/BASELINE.md"
expected=$(grep -oP '\| 断言总数 \| \*\*\K[0-9]+' "$baseline" || true)
if [ -z "$expected" ]; then
	echo "doc-numbers: could not read 断言总数 from $baseline"
	exit 1
fi

files=(
	"README.md"
	"docs/engineering/ARCHITECTURE.md"
	"docs/engineering/PROJECT_STATUS.md"
	"docs/engineering/TESTER_WINDOWS_0.1.md"
	"docs/engineering/IMPLEMENTATION_DEBT_v1.0_zh-CN.md"
)

# Lines that talk about something other than the current total.
skip='更早|历史|归档|archive|修复前|回滚|已废弃'

mismatches=0
for f in "${files[@]}"; do
	[ -f "$f" ] || continue
	# Drop ignored lines and single-suite references before reading numbers.
	current=$(grep -vE "$skip" "$f" | grep -vE '`test_[a-z_]+\.gd`|tests/[a-z_]+\.gd' || true)
	numbers=$(
		{
			printf '%s\n' "$current" | grep -oE '[0-9]+ 条断言' | grep -oE '[0-9]+'
			printf '%s\n' "$current" | grep -oE '[0-9]+ 断言' | grep -oE '[0-9]+'
			printf '%s\n' "$current" | grep -oE 'assertions=[0-9]+' | cut -d= -f2
		} 2>/dev/null | sort -u
	)
	for n in $numbers; do
		if [ "$n" != "$expected" ]; then
			echo "doc-numbers: $f says $n, baseline says $expected"
			mismatches=$((mismatches + 1))
		fi
	done
done

if [ "$mismatches" -ne 0 ]; then
	echo "doc-numbers: $mismatches stale count(s); update them from $baseline"
	exit 1
fi

echo "doc-numbers: ok ($expected)"
