extends SceneTree

## Standalone entry point for the documentation guards.
##
## tests/run_suites.gd calls the same static functions at the end of every full
## run, so this file exists for checking the documents without running 18 suites:
##
##   godot --headless --path . --script res://tests/check_docs.gd
##   godot --headless --path . --script res://tests/check_docs.gd -- --fix

const DocChecks = preload("res://tests/framework/doc_checks.gd")


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	if DocChecks.wants_fix():
		var changed := DocChecks.fix_module_sizes()
		if changed < 0:
			print("could not open ", DocChecks.ARCHITECTURE_PATH, " for writing")
			quit(1)
			return
		print("module-sizes: rewrote %d row(s) to match the files" % changed)
	quit(0 if DocChecks.report() else 1)
