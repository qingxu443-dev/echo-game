extends RefCounted

const SpringRunScript = preload("res://scripts/spring/spring_run.gd")
const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")
const SETTLEMENT_SCENE_PATH := "res://scenes/spring/spring_battle_settlement.tscn"


## CONTRACT: _test_restored_battle_parent
## CONTRACT: _test_handoff_retries
## CONTRACT: _test_handoff_failures_preserve_state
static func open(view, result: Dictionary, save_path: String = SpringRunScript.SAVE_PATH, scene_change: Callable = Callable()) -> void:
	var run := SpringRunScript.from_dict(BridgeScript.suspended_map) if not BridgeScript.suspended_map.is_empty() else SpringRunScript.load_from_file(save_path)
	if run == null:
		view.status_message = "战斗结果无法读取原始出征存档；结果仍保留在当前战斗中。"
		view.queue_redraw()
		return
	if run.pending_battle_settlement.is_empty():
		var settlement_id := "%s-%d-%d" % [str(result.get("place", "battle")), int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		run.pending_battle_settlement = {"id": settlement_id, "phase": "pending", "result": result.duplicate(true)}
	if not run.save_to_file(save_path):
		view.status_message = "战斗结果暂未写入存档，请重试；不会提前发放奖励。"
		view.queue_redraw()
		return
	BridgeScript.suspended_map = run.to_dict()
	var error: Error = scene_change.call(view.get_tree(), SETTLEMENT_SCENE_PATH) if scene_change.is_valid() else SceneTravel.change(view.get_tree(), SETTLEMENT_SCENE_PATH)
	if error != OK:
		view.status_message = "结算界面载入失败，战果已保存，请重试。Error: %s" % error
		view.queue_redraw()
		return
	SessionSave.clear()
	BridgeScript.clear_pending()
	BridgeScript.restore_map = false
	BridgeScript.suspended_map = {}


static func run_lead(view):
	var party_ids: Array = BridgeScript.pending.get("character_ids", [SpringRunScript.HERO_CHARACTER_ID])
	if party_ids.is_empty():
		return view.controller.get_active_character()
	return view.controller.actors.get(str(party_ids[0]))
