extends RefCounted

## Cross-platform documentation guards.
##
## These checks used to live in tests/check_doc_numbers.sh, which only bash could
## run. A Windows run of the suites therefore skipped them entirely - the platform
## the project is actually verified on was the one without the guard. The checks
## now live here, the shell entry points only start the engine, and Linux, Windows
## and CI run the same code.
##
## Two separate drifts are caught:
##
##  1. A document repeats the *total* assertion count with a stale value. That
##     number has drifted three times; each time a separate pull request updated
##     its own copy, the last to merge won, and the rest described a state that no
##     longer applied. BASELINE.md is the single source and is not scanned.
##  2. ARCHITECTURE.md's per-module line counts stop matching the files. Five rows
##     had already drifted when the title menu merged, while that file's own
##     opening line claims it describes what currently exists.

const BASELINE_PATH := "docs/engineering/BASELINE.md"
const ARCHITECTURE_PATH := "docs/engineering/ARCHITECTURE.md"

const TOTAL_SCAN_FILES := [
	"README.md",
	"docs/engineering/ARCHITECTURE.md",
	"docs/engineering/PROJECT_STATUS.md",
	"docs/engineering/TESTER_WINDOWS_0.1.md",
	"docs/engineering/IMPLEMENTATION_DEBT_v1.0_zh-CN.md",
]

## Lines that talk about something other than the current total: earlier runs,
## archived records, and reverts. Their numbers are allowed to differ.
const SKIP_MARKERS := ["更早", "历史", "归档", "archive", "修复前", "回滚", "已废弃"]

## A single suite's own count is correct without matching the total.
static var _suite_reference: RegEx = _compile("`test_[a-z_]+\\.gd`|tests/[a-z_]+\\.gd")
static var _total_re: RegEx = _compile("\\| 断言总数 \\| \\*\\*(\\d+)\\*\\*")
static var _count_patterns: Array[RegEx] = [
	_compile("(\\d+)\\s*条断言"),
	_compile("(\\d+)\\s*断言"),
	_compile("assertions=(\\d+)"),
]
static var _module_row_re: RegEx = _compile("^\\| `([\\w./]+\\.gd)` \\| (\\d+) \\|")


static func _compile(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


static func read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## Number of lines a reader would count, with or without a trailing newline.
static func count_lines(text: String) -> int:
	if text.is_empty():
		return 0
	var rows := text.split("\n")
	return rows.size() - (1 if text.ends_with("\n") else 0)


static func expected_assertions() -> int:
	var match := _total_re.search(read_text(BASELINE_PATH))
	if match == null:
		return 0
	return int(match.get_string(1))


## Every stale copy of the total, one line per offending file and number.
static func check_assertion_copies(expected: int) -> Array[String]:
	var problems: Array[String] = []
	for path in TOTAL_SCAN_FILES:
		var text := read_text(path)
		if text.is_empty():
			continue
		for line in text.split("\n"):
			if _is_skipped(line):
				continue
			var seen := {}
			for re in _count_patterns:
				for match in re.search_all(line):
					seen[int(match.get_string(1))] = true
			for number in seen.keys():
				if number != expected:
					problems.append("%s says %d, baseline says %d" % [path, number, expected])
	return problems


static func _is_skipped(line: String) -> bool:
	for marker in SKIP_MARKERS:
		if line.contains(marker):
			return true
	return _suite_reference.search(line) != null


## basename -> res:// path, for every script in the project.
static func _script_index() -> Dictionary:
	var index := {}
	var pending: Array[String] = ["res://scripts"]
	while not pending.is_empty():
		var folder: String = pending.pop_back()
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if file_name.ends_with(".gd"):
				index[file_name] = folder.path_join(file_name)
		for child in dir.get_directories():
			pending.append(folder.path_join(child))
	return index


## Each row of ARCHITECTURE.md's module table against the file it names.
static func check_module_sizes() -> Array[String]:
	var problems: Array[String] = []
	var index := _script_index()
	for line in read_text(ARCHITECTURE_PATH).split("\n"):
		var match := _module_row_re.search(line)
		if match == null:
			continue
		var name := match.get_string(1)
		var declared := int(match.get_string(2))
		var path: String = index.get(name.get_file(), "")
		if path.is_empty():
			problems.append("no script found for %s" % name)
			continue
		var actual := count_lines(read_text(path))
		if actual != declared:
			problems.append("%s is declared as %d lines, file has %d" % [name, declared, actual])
	return problems


## A row with fewer columns than its header renders shifted: the 职责 text lands
## under 行数 and the constraint lands under 职责, so the reader sees a wrong
## number next to a wrong sentence. This happened twice - once when a row was
## added by hand, once inherited - and neither was caught by anything.
##
## Not auto-fixable: deciding whether a short row needs `—` in the count column or
## actually wants merging with another row is a judgement call.
static func check_table_shape() -> Array[String]:
	var problems: Array[String] = []
	var lines := read_text(ARCHITECTURE_PATH).split("\n")
	var header_columns := 0
	for index in range(lines.size()):
		var line: String = lines[index]
		if line.begins_with("| 模块 |"):
			header_columns = line.split("|").size()
			continue
		if header_columns == 0:
			continue
		if not line.begins_with("|"):
			# Blank or prose line ends the table.
			header_columns = 0
			continue
		if line.begins_with("|---") or line.begins_with("| ---"):
			continue
		var columns := line.split("|").size()
		if columns != header_columns:
			# split() keeps the empty first and last field, so subtract two.
			problems.append("line %d has %d cells, its header has %d" % [index + 1, columns - 2, header_columns - 2])
	return problems


## `--fix` is passed after `--`, so OS.get_cmdline_user_args() reports it as a
## bare token; accept both spellings rather than depending on the caller.
static func wants_fix() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.trim_prefix("--").begins_with("fix"):
			return true
	return false


## Rewrites the stale numbers in place. Returns how many rows changed.
static func fix_module_sizes() -> int:
	var text := read_text(ARCHITECTURE_PATH)
	var index := _script_index()
	var changed := 0
	var rows: Array[String] = []
	for line in text.split("\n"):
		var match := _module_row_re.search(line)
		if match != null:
			var path: String = index.get(match.get_string(1).get_file(), "")
			if not path.is_empty():
				var actual := count_lines(read_text(path))
				if actual != int(match.get_string(2)):
					line = line.substr(0, match.get_start(2)) + str(actual) + line.substr(match.get_end(2))
					changed += 1
		rows.append(line)
	var file := FileAccess.open(ARCHITECTURE_PATH, FileAccess.WRITE)
	if file == null:
		return -1
	file.store_string("\n".join(rows))
	file.close()
	return changed


## Prints every check and returns whether all of them passed.
static func report() -> bool:
	var ok := true
	var expected := expected_assertions()
	if expected <= 0:
		print("doc-numbers: could not read 断言总数 from ", BASELINE_PATH)
		ok = false
	else:
		var stale := check_assertion_copies(expected)
		for problem in stale:
			print("doc-numbers: ", problem)
		if stale.is_empty():
			print("doc-numbers: ok (%d)" % expected)
		else:
			print("doc-numbers: %d stale count(s); update them from %s" % [stale.size(), BASELINE_PATH])
			ok = false

	var sizes := check_module_sizes()
	if sizes.is_empty():
		print("module-sizes: ok (%d rows)" % _count_module_rows())
	else:
		for problem in sizes:
			print("module-sizes: ", problem)
		print("module-sizes: %d row(s) disagree with the files; run tests/run_all.sh --fix" % sizes.size())
		ok = false

	var shape := check_table_shape()
	if shape.is_empty():
		print("table-shape: ok")
	else:
		for problem in shape:
			print("table-shape: ", problem)
		print("table-shape: %d row(s) would render shifted" % shape.size())
		ok = false
	return ok


static func _count_module_rows() -> int:
	var rows := 0
	for line in read_text(ARCHITECTURE_PATH).split("\n"):
		if _module_row_re.search(line) != null:
			rows += 1
	return rows
