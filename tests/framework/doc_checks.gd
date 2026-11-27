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

## 单个脚本的行数上限。ARCHITECTURE 的行数表只保证「文档没撒谎」——它会把
## 846 行如实记成 846，然后放行。battle_view.gd 曾长到 846 行，现已拆到 596 行并移出存量豁免。
const MAX_MODULE_LINES := 600

## 已经超标的存量文件：值 = 当前行数，只许减不许增。
## 加代码让它变红；拆到 600 行以内后请把条目删掉——留着会变成永久豁免，
## 而永久豁免和没有守卫是一回事。
const MODULE_LINE_DEBT := {
	"spring_map_view.gd": 759,
	"battle_controller.gd": 628,
}

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

## 套件数也需要单一来源。BASELINE.md 的「套件数」行是权威值；正文里凡声明
## 当前套件数的地方都要跟它一致。历史/归档行照旧由 SKIP_MARKERS 豁免。
static var _suite_total_re: RegEx = _compile("\\| 套件数 \\| (\\d+) \\|")
static var _suite_count_patterns: Array[RegEx] = [
	_compile("suites=(\\d+)"),
	_compile("(\\d+)\\s*个套件"),
	_compile("(\\d+)\\s*套件"),
	_compile("测试套件[：:]\\s*(\\d+)\\s*个"),
]


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


static func expected_suite_count() -> int:
	var match := _suite_total_re.search(read_text(BASELINE_PATH))
	if match == null:
		return 0
	return int(match.get_string(1))


## 与断言数同构：正文里每一处「当前套件数」都必须等于 BASELINE 的权威值。
## 复用同一套跳过规则，避免把历史快照和单套件引用误判为漂移。
static func check_suite_count_copies(expected: int) -> Array[String]:
	var problems: Array[String] = []
	for path in TOTAL_SCAN_FILES:
		var text := read_text(path)
		if text.is_empty():
			continue
		for line in text.split("\n"):
			if _is_skipped(line):
				continue
			var seen := {}
			for re in _suite_count_patterns:
				for match in re.search_all(line):
					seen[int(match.get_string(1))] = true
			for number in seen.keys():
				if number != expected:
					problems.append("%s says %d suites, baseline says %d" % [path, number, expected])
	return problems


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


## 行数预算。空数组表示每个脚本都在 600 行以内，或已在存量清单里且没有变长。
##
## 三种失败：新文件超过上限、存量文件又长了、存量文件已经达标但还挂在清单上。
## 最后一条是刻意的：清单必须持续收缩，否则它就是一张写着「允许腐烂」的纸条。
static func check_module_line_limits() -> Array[String]:
	var problems: Array[String] = []
	var index := _script_index()
	for file_name in index:
		var actual := count_lines(read_text(index[file_name]))
		var debt := int(MODULE_LINE_DEBT.get(file_name, 0))
		if debt > 0:
			if actual > debt:
				problems.append("%s grew to %d lines (ceiling %d) - split it before adding more" % [file_name, actual, debt])
			elif actual <= MAX_MODULE_LINES:
				problems.append("%s is down to %d lines; remove it from MODULE_LINE_DEBT" % [file_name, actual])
		elif actual > MAX_MODULE_LINES:
			problems.append("%s is %d lines, over the %d limit - split it" % [file_name, actual, MAX_MODULE_LINES])
	return problems


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
## 数据字段必须有人读。
##
## 第十轮手工扫出三个纯写入死字段（skill 的 effect_id / duration_player_phases、
## summon 的 icon），第十三轮数据化拆包又造出 label_zh 零读者——每次仓库自己
## 长回来的同一类腐烂。这条守卫把那两次手工扫描变成每次 CI 的机器检查。
##
## 规则（调过参，避免狼来了）：
##  - 只查 *_definition.gd（数据类）；
##  - 读者 = 其它文件里的 `.field`（非赋值）或 `.get("field")` 字典键；
##  - 自身文件里 is_valid() 之外的裸名出现也算读（to_dict/from_dict 这类序列化
##    正是裸名消费——loot_item_definition 整类就是这种形态）；
##  - is_valid() 里的自校验不算——只有校验认识它的字段，就是死字段。
##
## 例外只增不减没有意义：给字段接上读者后请把条目删掉。
const FIELD_READER_EXCEPTIONS := {
}

static func check_field_readers() -> Array[String]:
	var problems: Array[String] = []
	var index := _script_index()
	var all_text: Dictionary = {}
	for file_name in index:
		all_text[file_name] = read_text(index[file_name])
	for file_name in index:
		if not file_name.ends_with("_definition.gd"):
			continue
		var own: String = all_text[file_name]
		var body: String = _strip_is_valid(own)
		for match in _export_field_re.search_all(own):
			var field: String = match.get_string(1)
			var exceptions: Array = FIELD_READER_EXCEPTIONS.get(file_name, [])
			if exceptions.has(field):
				continue
			if _field_has_reader(field, file_name, body, all_text):
				continue
			problems.append("%s.%s has no reader - a field nothing obeys" % [file_name, field])
	return problems


static func _strip_is_valid(text: String) -> String:
	var start := text.find("func is_valid(")
	if start < 0:
		return text
	var rest := text.substr(start + 1)
	var next_func := rest.find("\nfunc ")
	var next_static := rest.find("\nstatic func ")
	var cut := rest.length()
	if next_func >= 0:
		cut = mini(cut, next_func)
	if next_static >= 0:
		cut = mini(cut, next_static)
	return text.substr(0, start) + rest.substr(cut)


static func _field_has_reader(field: String, own_file: String, own_body: String, all_text: Dictionary) -> bool:
	# Bare-name use in the declaring file outside is_valid (to_dict, from_dict,
	# describe, ...) - but an assignment is a write, not a read.
	var bare := _compile("\\b%s\\b(?!\\s*=(?!=))" % field)
	if bare.search(own_body) != null:
		return true
	var dotted := _compile("\\.%s\\b(?!\\s*=(?!=))" % field)
	var dict_key := _compile("\\.get\\(\"%s\"\\)" % field)
	for other in all_text:
		if other == own_file:
			continue
		var t: String = all_text[other]
		if dotted.search(t) != null or dict_key.search(t) != null:
			return true
	return false


## 注释里的承诺必须指向一个测试：`## CONTRACT: <测试函数名>`。
##
## 嘲讽两格拉扯（注释说两格合法、结算层悄悄取消）与续行重置（注释说进区域
## 重置、没有任何重置点）都是"注释承诺≠实现承诺"，且两次都是零测试覆盖。
## 这条守卫让谎话变成构建失败：立约可以，把测试名写上；没有测试的承诺不许进注释。
const CONTRACT_RE := "## CONTRACT: (\\S+)"

static func check_contract_tags() -> Array[String]:
	var problems: Array[String] = []
	var index := _script_index()
	var tests_text := _read_all_suite_text()
	var regex := _compile(CONTRACT_RE)
	for file_name in index:
		var text: String = read_text(index[file_name])
		for match in regex.search_all(text):
			var token: String = match.get_string(1)
			if not tests_text.contains(token):
				problems.append("%s promises '%s' but no test mentions it" % [file_name, token])
	return problems


static func _read_all_suite_text() -> String:
	var combined := ""
	var dir := DirAccess.open("res://tests")
	if dir == null:
		return combined
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			combined += read_text("res://tests/" + file_name)
	return combined


static var _export_field_re: RegEx = _compile("@export(?:_multiline)? var (\\w+)")


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

	var suite_count := expected_suite_count()
	if suite_count <= 0:
		print("doc-suites: could not read 套件数 from ", BASELINE_PATH)
		ok = false
	else:
		var stale_suites := check_suite_count_copies(suite_count)
		for problem in stale_suites:
			print("doc-suites: ", problem)
		if stale_suites.is_empty():
			print("doc-suites: ok (%d)" % suite_count)
		else:
			print("doc-suites: %d stale suite count(s); update them from %s" % [stale_suites.size(), BASELINE_PATH])
			ok = false

	var sizes := check_module_sizes()
	if sizes.is_empty():
		print("module-sizes: ok (%d rows)" % _count_module_rows())
	else:
		for problem in sizes:
			print("module-sizes: ", problem)
		print("module-sizes: %d row(s) disagree with the files; run tests/run_all.sh --fix" % sizes.size())
		ok = false

	# 真正的膨胀闸门。上面那条只保证文档没撒谎：文件长到 846 行它也会如实
	# 记录成 846，然后放行。这条才拦。
	var limits := check_module_line_limits()
	if limits.is_empty():
		print("module-lines: ok (limit %d)" % MAX_MODULE_LINES)
	else:
		for problem in limits:
			print("module-lines: ", problem)
		print("module-lines: %d file(s) over budget" % limits.size())
		ok = false

	var shape := check_table_shape()
	if shape.is_empty():
		print("table-shape: ok")
	else:
		for problem in shape:
			print("table-shape: ", problem)
		print("table-shape: %d row(s) would render shifted" % shape.size())
		ok = false
	var readers := check_field_readers()
	if readers.is_empty():
		print("field-readers: ok")
	else:
		for problem in readers:
			print("field-readers: ", problem)
		print("field-readers: %d dead field(s); wire it up or delete it" % readers.size())
		ok = false

	var promises := check_contract_tags()
	if promises.is_empty():
		print("contracts: ok")
	else:
		for problem in promises:
			print("contracts: ", problem)
		print("contracts: %d promise(s) without a test; name the test in the tag" % promises.size())
		ok = false

	return ok


static func _count_module_rows() -> int:
	var rows := 0
	for line in read_text(ARCHITECTURE_PATH).split("\n"):
		if _module_row_re.search(line) != null:
			rows += 1
	return rows
