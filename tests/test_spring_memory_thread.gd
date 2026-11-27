extends "res://tests/framework/test_case.gd"

## 归乡记忆线（设计汇总 2026-11-26 §10.4「三级剧情延续，关键选择影响整局剧情
## 但不阻断主线」，§6.3「记忆残页用于记忆拼合」）。
##
## 断言钉的是行为而不是文案措辞：选择正确才拼到碎片、碎片只读 event_log 且不改它、
## 回响只在「拼上第二片及以后」出现、结局回顾随拼合度分档、任何文案都不倒向
## 三个候选结局方向、不解锁后续区域——最后一条把「不锁结局」变成可测约束。

const CatalogScript = preload("res://scripts/spring/spring_event_catalog.gd")
const MemoryScript = preload("res://scripts/spring/spring_memory_thread.gd")
const EndingScript = preload("res://scripts/spring/spring_ending.gd")


func _run() -> void:
	_test_thread_events_are_reachable()
	_test_only_memory_choices_contribute()
	_test_collected_is_read_only_and_stable()
	_test_echo_needs_an_earlier_fragment()
	_test_reflection_scales_with_fragments()
	_test_reflection_never_locks_an_ending()
	_test_no_effect_on_rules_or_progression()
	_test_cleared_ending_appends_reflection()


## 每套地图至少有一个记忆事件——否则「弱主线」对某些局根本不存在。
func _test_thread_events_are_reachable() -> void:
	for event_id in MemoryScript.THREAD:
		_check(CatalogScript.has_event(StringName(event_id)), "%s is a real event" % event_id)
		var count: int = CatalogScript.option_count(StringName(event_id))
		var memory_option: int = int(MemoryScript.THREAD[event_id]["option"])
		_check(memory_option >= 0 and memory_option < count, "%s memory option is in range" % event_id)


func _log(event_id: String, option: int) -> Dictionary:
	return {event_id: {"option": option, "log": []}}


func _test_only_memory_choices_contribute() -> void:
	for event_id in MemoryScript.THREAD:
		var right: int = int(MemoryScript.THREAD[event_id]["option"])
		_check(MemoryScript.is_memory_choice(StringName(event_id), right), "%s designated option counts" % event_id)
		_check(not MemoryScript.is_memory_choice(StringName(event_id), right + 1), "%s other option does not" % event_id)
	_check(MemoryScript.count(_log("lost_traveler", 2)) == 0, "a non-memory choice yields no fragment")
	_check(MemoryScript.count({}) == 0, "empty log yields no fragment")


func _test_collected_is_read_only_and_stable() -> void:
	var log := _log("unsent_letter", 0)
	log.merge(_log("lost_traveler", 0), true)
	log.merge(_log("unworshipped_shrine", 0), true)
	var before: String = str(log)
	var fragments := MemoryScript.collected(log)
	_check(fragments.size() == 3, "three memory choices yield three fragments")
	_check(str(log) == before, "collected() does not mutate event_log")
	# 顺序按 THREAD 固定键序，与 event_log 的插入顺序无关。
	var reordered := _log("unworshipped_shrine", 0)
	reordered.merge(_log("unsent_letter", 0), true)
	reordered.merge(_log("lost_traveler", 0), true)
	_check(MemoryScript.collected(log) == MemoryScript.collected(reordered), "collected() is insertion-order independent")
	# 重复写同一个事件不会把碎片翻倍（event_log 本来就是每事件一条）。
	var dup := _log("lost_traveler", 0)
	dup["lost_traveler"]["option"] = 0
	_check(MemoryScript.count(dup) == 1, "one event contributes at most one fragment")
	_check(MemoryScript.thread_complete(log), "three fragments complete the thread")


func _test_echo_needs_an_earlier_fragment() -> void:
	# 第一片记忆：此前没有别的可呼应，不出回响（§10.4 没遇到后续事件不受惩罚）。
	_check(MemoryScript.echo_for(&"lost_traveler", 0, {}) == "", "first fragment has no echo")
	var prior := _log("unsent_letter", 0)
	_check(MemoryScript.echo_for(&"lost_traveler", 0, prior) != "", "second fragment echoes the first")
	_check(MemoryScript.echo_for(&"lost_traveler", 2, prior) == "", "non-memory choice never echoes")
	# 回响只读，不往 event_log 里写。
	var snapshot: String = str(prior)
	MemoryScript.echo_for(&"lost_traveler", 0, prior)
	_check(str(prior) == snapshot, "echo_for() leaves event_log untouched")


func _test_reflection_scales_with_fragments() -> void:
	_check(MemoryScript.reflection_for({}) == "", "no fragments -> no reflection")
	_check(MemoryScript.reflection_for(_log("unsent_letter", 0)) != "", "one fragment -> a reflection")
	var two := _log("unsent_letter", 0)
	two.merge(_log("lost_traveler", 0), true)
	var r1: String = MemoryScript.reflection_for(_log("unsent_letter", 0))
	var r2: String = MemoryScript.reflection_for(two)
	_check(r1 != r2, "reflection differs by fragment count")
	_check(not MemoryScript.reflection_for(two).contains("解锁"), "reflection never mentions unlocking")


## 关键：任何记忆文案都不得倒向三个候选结局方向（让时间重新流动 / 留下守护 /
## 迎来新春天），也不得出现职业、区域解锁或结局定论词。
func _test_reflection_never_locks_an_ending() -> void:
	var log := _log("unsent_letter", 0)
	log.merge(_log("lost_traveler", 0), true)
	log.merge(_log("unworshipped_shrine", 0), true)
	var texts: Array[String] = []
	for event_id in MemoryScript.THREAD:
		texts.append(str(MemoryScript.THREAD[event_id]["echo"]))
		texts.append(str(MemoryScript.THREAD[event_id]["fragment"]))
	texts.append(MemoryScript.reflection_for(log))
	var joined: String = " ".join(PackedStringArray(texts))
	for banned in ["让时间重新流动", "留下守护", "迎来新的春天", "结局", "成为守护者", "夏之境已解锁"]:
		_check(not joined.contains(banned), "memory text stays open: no '%s'" % banned)


func _test_no_effect_on_rules_or_progression() -> void:
	var run := SpringRun.begin(7)
	run.add_memory_pages(3)
	var coins_before: int = run.coins
	var pages_before: int = run.memory_pages
	var log := _log("unsent_letter", 0)
	MemoryScript.collected(log)
	MemoryScript.reflection_for(log)
	MemoryScript.echo_for(&"lost_traveler", 0, log)
	_check(run.coins == coins_before, "memory thread does not touch coins")
	_check(run.memory_pages == pages_before, "memory thread does not touch memory pages")


func _test_cleared_ending_appends_reflection() -> void:
	var log := _log("unsent_letter", 0)
	log.merge(_log("lost_traveler", 0), true)
	var plain: Dictionary = EndingScript.ending_for("cleared")
	var enriched: Dictionary = EndingScript.ending_for("cleared", log)
	_check((enriched["lines"] as Array).size() > (plain["lines"] as Array).size(), "cleared ending gains a reflection line")
	_check(EndingScript.leaves_choice_open("cleared"), "ending still leaves the choice open")
	# 没有碎片时不追加——不遇到后续事件不受惩罚。
	var empty: Dictionary = EndingScript.ending_for("cleared", {})
	_check((empty["lines"] as Array).size() == (plain["lines"] as Array).size(), "no fragments -> no extra line")
	# 非 cleared 结局不追加记忆回顾。
	var defeat: Dictionary = EndingScript.ending_for("defeat", log)
	_check((defeat["lines"] as Array).size() == (EndingScript.ending_for("defeat")["lines"] as Array).size(), "defeat ending unchanged")
