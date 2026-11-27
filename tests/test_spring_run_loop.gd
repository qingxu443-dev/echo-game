extends "res://tests/framework/test_case.gd"

## 整局冒烟：从开局一路打到首领，中途存读档一次。
##
## Why this suite exists: the other thirty-odd suites each pin one cell of the
## loop. Nothing ran the loop itself - map → fight → settle → next place → boss →
## region closed - so a state machine that deadlocks after the second fight, a
## resource that goes negative only on the fifth, or a place that settles twice
## would pass every existing test. This one walks the whole thing.
##
## The fights are settled through the same handshake the scene uses
## (`prepare` → `last_result` → `settle`), not by poking run fields, so a change
## to the bridge is caught here rather than on a playtest.

const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")


func _run() -> void:
	_test_a_whole_run_reaches_the_boss()
	_test_save_in_the_middle_keeps_the_loop_going()
	_test_resources_never_go_negative()


## 走完一整局：每处战斗都用真实握手结算，最后首领必须关掉本区域。
func _test_a_whole_run_reaches_the_boss() -> void:
	var run := SpringRun.begin(7)
	var places: Array = run.template.places.duplicate()
	var fought := 0
	var boss_settled := false

	for place in places:
		if place.kind == SpringPlace.Kind.SHOP or place.kind == SpringPlace.Kind.EVENT \
				or place.kind == SpringPlace.Kind.HIDDEN:
			run.complete_place(place)
			continue

		fought += 1
		var kind := _kind_of(place)
		_check(BridgeScript.prepare(run, place.payload, place.id, kind),
			"准备战斗 %s（%s）" % [String(place.id), kind])
		BridgeScript.last_result = _victory(run, place, kind)
		var outcome: Dictionary = BridgeScript.settle(run)
		_check(not bool(outcome.get("needs_revive", false)), "%s 打赢后不需要续行" % String(place.id))
		_check(run.exploration.completed.has(place.id), "%s 结算后标记为已完成" % String(place.id))
		if place.kind == SpringPlace.Kind.BOSS:
			boss_settled = true
			_check(bool(outcome.get("finished_run", false)), "击败首领后本区域结束")
			_check(run.exploration.finished, "探索状态被标记为结束")

	_check(fought >= 3, "整局至少经过三场战斗（普通 + 精英 + 首领）")
	_check(boss_settled, "整局走完后首领确实被结算")
	_check(run.battles_won == fought, "每一场都计入战绩：期望 %d，实际 %d" % [fought, run.battles_won])
	_check(run.hero_health > 0 and run.hero_health <= run.effective_max_health(), "通关时血量仍在合法区间")


## 中途存档再接着打：位置、完成项、资源都不能丢，循环要能继续。
func _test_save_in_the_middle_keeps_the_loop_going() -> void:
	var run := SpringRun.begin(11)
	var first_two := 0
	for place in run.template.places:
		if place.kind != SpringPlace.Kind.BATTLE:
			continue
		if first_two >= 2:
			break
		BridgeScript.prepare(run, place.payload, place.id, BridgeScript.KIND_BATTLE)
		BridgeScript.last_result = _victory(run, place, BridgeScript.KIND_BATTLE)
		BridgeScript.settle(run)
		first_two += 1

	var coins_before: int = run.coins
	var won_before: int = run.battles_won
	var restored := SpringRun.from_dict(run.to_dict())
	_check(restored != null, "半途存档能读回来")
	if restored == null:
		return
	_check(restored.battles_won == won_before, "战绩随档保存")
	_check(restored.coins == coins_before, "花钿随档保存")
	_check(restored.exploration.completed.size() == run.exploration.completed.size(), "已完成地点随档保存")

	# 读档后继续打一场，确认循环没有卡在旧状态上。
	var next_place = null
	for place in restored.template.places:
		if place.kind == SpringPlace.Kind.BATTLE and not restored.exploration.completed.has(place.id):
			next_place = place
			break
	_check(next_place != null, "读档后仍有未完成的战斗地点")
	if next_place == null:
		return
	BridgeScript.prepare(restored, next_place.payload, next_place.id, BridgeScript.KIND_BATTLE)
	BridgeScript.last_result = _victory(restored, next_place, BridgeScript.KIND_BATTLE)
	BridgeScript.settle(restored)
	_check(restored.battles_won == won_before + 1, "读档后能继续累计战绩")


func _test_resources_never_go_negative() -> void:
	var run := SpringRun.begin(13)
	for place in run.template.places:
		if place.kind == SpringPlace.Kind.BATTLE or place.kind == SpringPlace.Kind.ELITE:
			BridgeScript.prepare(run, place.payload, place.id, _kind_of(place))
			BridgeScript.last_result = _victory(run, place, _kind_of(place))
			BridgeScript.settle(run)
	_check(run.coins >= 0, "花钿不会变负")
	_check(run.supplies >= 0, "补给不会变负")
	_check(run.memory_pages >= 0, "记忆页不会变负")


func _kind_of(place) -> String:
	match place.kind:
		SpringPlace.Kind.ELITE:
			return BridgeScript.KIND_ELITE
		SpringPlace.Kind.BOSS:
			return BridgeScript.KIND_BOSS
	return BridgeScript.KIND_BATTLE


## 一场典型的胜仗：掉一部分血、带两个宝箱、无战利品。数值不重要，重要的是
## 形状和真实结算一致，否则这个冒烟测的是我自己编的字典。
func _victory(run, place, kind: String) -> Dictionary:
	return {
		"result": "victory",
		"kind": kind,
		"place": String(place.id),
		"hero_health": maxi(1, run.hero_health - 120),
		"hero_max_health": run.effective_max_health(),
		"carry": {"mods": [], "equipped_weapon": {}, "equipped_armor": {}, "backpack": []},
		"chests_saved": 2,
		"loot": [],
		"seed": run.seed_value,
	}
