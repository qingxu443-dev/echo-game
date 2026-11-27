extends SceneTree

## Runs every headless suite and prints one summary line.
##
## This is the single implementation. tests/run_all.sh and tests/run_all.ps1 only
## locate the engine and start this file, so the two platforms cannot drift the
## way they had: the PowerShell entry point was missing the SCRIPT ERROR guard and
## the documentation check that the bash one had, which meant a Windows run could
## report all-green while a suite had aborted half way through.
##
##   godot --headless --path . --script res://tests/run_suites.gd
##   EXPECTED_ASSERTIONS=805 godot ...            # override the declared minimum
##   ... run_suites.gd -- --fix                   # rewrite stale line counts
##
## Exit code is 0 only when every suite reported failures=0, none aborted with a
## script error, the assertion total did not drop below the declaration, and the
## documentation agrees with both.

const DocChecks = preload("res://tests/framework/doc_checks.gd")

const SUITE_DIR := "res://tests"
const NAME_WIDTH := 38


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DocChecks.wants_fix():
		_fix_and_exit()
		return

	var suites := _suite_files()
	if suites.is_empty():
		print("no test suites found under ", SUITE_DIR)
		quit(2)
		return

	var engine := OS.get_executable_path()
	var total := 0
	var failures := 0
	var broken := 0

	for name in suites:
		var output: Array = []
		var exit_code := OS.execute(engine, ["--headless", "--path", ".", "--script", "res://tests/%s.gd" % name], output, true)
		var text := "".join(PackedStringArray(output))
		var result := _parse_result(text)

		if result.is_empty():
			print(_row(name, "NO RESULT (crashed or failed to parse)"))
			broken += 1
			continue

		# A GDScript runtime error aborts the function that raised it, and the
		# suite still prints a RESULT line with failures=0. Any script error means
		# the run stopped testing what it claims to, so treat it as broken rather
		# than green.
		var script_error := _first_script_error(text)
		if not script_error.is_empty():
			print(_row(name, "SCRIPT ERROR: " + script_error))
			broken += 1
			continue

		if exit_code != 0 and result.failures == 0:
			print(_row(name, "EXIT %d after a successful RESULT" % exit_code))
			broken += 1
			continue

		total += result.assertions
		failures += result.failures
		if result.failures == 0:
			print(_row(name, "%3d ok" % result.assertions))
		else:
			print(_row(name, "%3d FAIL(%d)" % [result.assertions, result.failures]))

	print("-----")
	print("suites=%d assertions=%d failures=%d broken=%d" % [suites.size(), total, failures, broken])

	if failures != 0 or broken != 0:
		quit(1)
		return

	# 基线是下限而不是精确快照：低于下限说明覆盖被删掉，必须拦；高于下限只是
	# 有人加了测试，不需要任何分支去改共享文档——这正是四个文档反复冲突的根因。
	var expected := _expected_assertions()
	if expected > 0 and total < expected:
		print("coverage dropped: %d assertions ran, baseline floor is %d" % [total, expected])
		print("If the drop is intended, lower the floor in ", DocChecks.BASELINE_JSON_PATH, " and record why in ", DocChecks.BASELINE_PATH, ".")
		quit(1)
		return
	if expected > 0 and total > expected:
		print("baseline floor: %d; %d assertions ran (coverage grew, no doc change needed)" % [expected, total])

	var expected_suites := DocChecks.expected_suite_count()
	if expected_suites > 0 and suites.size() < expected_suites:
		print("coverage dropped: %d suites ran, baseline floor is %d" % [suites.size(), expected_suites])
		quit(1)
		return

	if not DocChecks.report():
		print("documentation disagrees with the baseline above")
		quit(1)
		return

	quit(0)


func _fix_and_exit() -> void:
	var changed := DocChecks.fix_module_sizes()
	if changed < 0:
		print("could not open ", DocChecks.ARCHITECTURE_PATH, " for writing")
		quit(1)
		return
	print("module-sizes: rewrote %d row(s) to match the files" % changed)
	quit(0)


func _suite_files() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(SUITE_DIR)
	if dir == null:
		return names
	for file_name in dir.get_files():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			names.append(file_name.get_basename())
	names.sort()
	return names


func _row(name: String, tail: String) -> String:
	return name.rpad(NAME_WIDTH) + " " + tail


func _expected_assertions() -> int:
	var from_env := OS.get_environment("EXPECTED_ASSERTIONS")
	if from_env.is_valid_int():
		return int(from_env)
	return DocChecks.expected_assertions()


## The last RESULT line, so a suite that prints more than one still counts once.
func _parse_result(text: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("RESULT \\S+ assertions=(\\d+) failures=(\\d+)")
	var matches := re.search_all(text)
	if matches.is_empty():
		return {}
	var last := matches[matches.size() - 1]
	return {"assertions": int(last.get_string(1)), "failures": int(last.get_string(2))}


## The detail after the marker, so the row does not read "SCRIPT ERROR: SCRIPT
## ERROR: ..." the way the shell version did.
func _first_script_error(text: String) -> String:
	const MARKER := "SCRIPT ERROR"
	for line in text.split("\n"):
		var at := line.find(MARKER)
		if at >= 0:
			var detail := line.substr(at + MARKER.length()).trim_prefix(":").strip_edges()
			return detail.substr(0, 90)
	return ""
