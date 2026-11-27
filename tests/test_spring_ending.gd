extends "res://tests/framework/test_case.gd"

## 留白式结局文案（设计汇总 §2：暂不锁定结局，玩家陪伴樱而非替她决定）。
##
## 这些断言钉住三件事：四种结束原因都有文案、每条文案非空、平定结局明确保留
## 选择而不倒向三个候选方向中的任何一个。UI 只绘制这些数据，不持有副本。

const EndingScript = preload("res://scripts/spring/spring_ending.gd")


func _run() -> void:
	_test_all_reasons_have_an_ending()
	_test_ending_text_is_complete()
	_test_cleared_leaves_the_choice_open()
	_test_unknown_reason_falls_back()
	_test_no_ending_unlocks_next_region()
	_report()


func _test_all_reasons_have_an_ending() -> void:
	for reason in ["cleared", "defeat", "exhausted", "abandoned"]:
		_check(EndingScript.has_ending(reason), "%s has a dedicated ending" % reason)


func _test_ending_text_is_complete() -> void:
	for reason in ["cleared", "defeat", "exhausted", "abandoned"]:
		var ending: Dictionary = EndingScript.ending_for(reason)
		_check(not str(ending.get("title", "")).is_empty(), "%s has a title" % reason)
		var lines: Array = ending.get("lines", [])
		_check(lines.size() > 0, "%s has at least one line" % reason)
		for line in lines:
			_check(not str(line).is_empty(), "%s has no blank line" % reason)
		_check(not str(ending.get("footer", "")).is_empty(), "%s has a footer" % reason)


func _test_cleared_leaves_the_choice_open() -> void:
	# 设计明确反对替樱选边：文案必须表达「还没决定 / 留给她自己」。
	_check(EndingScript.leaves_choice_open("cleared"), "cleared ending leaves the decision to Sakura")
	# 三个候选方向都可以作为氛围被提及，但不得被写成「已选择」。
	var ending: Dictionary = EndingScript.ending_for("cleared")
	var joined: String = " ".join(PackedStringArray(ending.get("lines", [])))
	_check(not joined.contains("决定让时间"), "does not commit to letting time flow")
	_check(not joined.contains("选择留下"), "does not commit to staying as guardian")


func _test_unknown_reason_falls_back() -> void:
	var fallback: Dictionary = EndingScript.ending_for("not_a_real_reason")
	_check(not str(fallback.get("title", "")).is_empty(), "unknown reason still yields a title")
	_check(str(fallback.get("title")) == str(EndingScript.ending_for("abandoned").get("title")), "unknown reason uses the generic ending")


func _test_no_ending_unlocks_next_region() -> void:
	# 结局文案只描述收束，不得声称进入了夏之境。
	for reason in ["cleared", "defeat", "exhausted", "abandoned"]:
		var ending: Dictionary = EndingScript.ending_for(reason)
		var joined: String = str(ending.get("title", "")) + " " + str(ending.get("footer", "")) + " " + " ".join(PackedStringArray(ending.get("lines", [])))
		_check(joined.contains("尚未解锁"), "%s footer still marks later regions locked" % reason)
