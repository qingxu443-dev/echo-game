extends RefCounted

const SpringRunScript = preload("res://scripts/spring/spring_run.gd")
const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")
const SETTLEMENT_SCENE_PATH := "res://scenes/spring/spring_battle_settlement.tscn"


static func open(view, result: Dictionary) -> void:
	var run := SpringRunScript.load_from_file(SpringRunScript.SAVE_PATH)
	if run == null and not BridgeScript.suspended_map.is_empty():
		run = SpringRunScript.from_dict(BridgeScript.suspended_map)
	if run == null:
		view.status_message = "战斗结果无法读取原始出征存档；结果仍保留在当前战斗中。"
		view.queue_redraw()
		return
	var settlement_id := "%s-%d-%d" % [str(result.get("place", "battle")), int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	run.pending_battle_settlement = {
		"id": settlement_id,
		"phase": "pending",
		"result": result.duplicate(true),
	}
	if not run.save_to_file(SpringRunScript.SAVE_PATH):
		view.status_message = "战斗结果暂未写入存档，请重试；不会提前发放奖励。"
		view.queue_redraw()
		return
	SessionSave.clear()
	BridgeScript.clear_pending()
	BridgeScript.restore_map = false
	BridgeScript.suspended_map = {}
	var error := SceneTravel.change(view.get_tree(), SETTLEMENT_SCENE_PATH)
	if error != OK:
		push_error("独立战斗结算界面载入失败，待结算记录已保留。Error: %s" % error)
