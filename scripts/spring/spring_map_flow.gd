class_name SpringMapFlow
extends RefCounted

const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")
const RegionProgressionScript = preload("res://scripts/spring/spring_region_progression.gd")
const EventCatalogScript = preload("res://scripts/spring/spring_event_catalog.gd")
const EncounterCatalogScript = preload("res://scripts/spring/spring_encounter_catalog.gd")

## Scene travel can be replaced by the owning scene or a failure-path fixture.
var scene_change: Callable = Callable()

func change_scene(view, path: String, label: String = "") -> Error:
	if scene_change.is_valid():
		return scene_change.call(view.get_tree(), path, label)
	return SceneTravel.change(view.get_tree(), path, label)

func initialize(view) -> void:
	var suspended := SessionSave.consume("map")
	if not suspended.is_empty() and PlaySession.restore_map(view, suspended): SessionSave.clear()
	if BridgeScript.restore_map:
		view.run = SpringRun.from_dict(BridgeScript.suspended_map)
		BridgeScript.restore_map = false
	var req_mode: String = BridgeScript.consume_requested_mode()
	if SpringSaveTransaction.is_pending(view.atelier_save_path):
		if not SpringSaveTransaction.recover(view.save_path, view.atelier_save_path):
			view.status_message = "未能恢复出征存档，请返回大厅后重试。"
			return
		req_mode = ""
	if view.run == null:
		if not BridgeScript.has_result() and req_mode in ["hard", "normal"]:
			var pending_run := SpringRun.load_from_file(view.save_path)
			if pending_run != null and not pending_run.pending_battle_settlement.is_empty():
				view.run = pending_run
			else:
				view.start_new_run(int(Time.get_unix_time_from_system()) % 100000, req_mode == "hard")
		else:
			var restored := SpringRun.load_from_file(view.save_path)
			if restored != null and (BridgeScript.has_result() or not restored.pending_battle_settlement.is_empty() or not restored.exploration.finished):
				view.run = restored
				view.status_message = "已恢复本局：模板 %d · 剩余体力 %d。" % [view.run.template_id, view.run.exploration.stamina]
			elif not BridgeScript.has_result():
				view.start_new_run(int(Time.get_unix_time_from_system()) % 100000, false)
			else:
				view.status_message = "战前存档无法读取，保留待结算结果。"
	if view.run != null and not view.run.pending_battle_settlement.is_empty():
		var settlement_error := change_scene(view, "res://scenes/spring/spring_battle_settlement.tscn", "战斗结算")
		if settlement_error != OK:
			view.status_message = "待结算战果已保留，但结算界面载入失败。Error: %s" % settlement_error
		return
	view._apply_returned_battle()
	if view.run == null:
		return
	if not view.run.pending_event.is_empty():
		view.event_place = view.run.template.place_by_id(StringName(view.run.pending_event["place"]))
		view.event_result = view.run.pending_event["result"]
		view.event_open = view.event_place != null

func start_new_run(view, seed_value: int, hard_mode: bool = false) -> void:
	view.run = SpringRunStorage.start(seed_value, hard_mode, view.save_path, view.atelier_save_path)
	if view.run == null:
		view.status_message = "无法读取或写入出征存档，原存档已保留。"
		return
	view.selected_cell = Vector2i(-1, -1)
	if hard_mode:
		view.status_message = "【困难·一笔画】长按棋盘拖动连接任意数量节点，结尾必须落于「王」！"
	else:
		view.status_message = "抵达 %s。点击地点查看路程与体力消耗。" % view._place_label(view.run.template.start_cell)
	view.confirm_end = false

func save(view) -> bool:
	if view.run.save_to_file(view.save_path):
		return true
	view.status_message = "春之境存档写入失败。"
	return false

func launch(view, battle_id: StringName, place_id: StringName, kind: String) -> bool:
	if not BridgeScript.prepare(view.run, battle_id, place_id, kind):
		view.status_message = "遭遇编成缺失，当前地点与事件已保留。"
		return false
	if not view._save():
		BridgeScript.clear_pending()
		return false
	var error := change_scene(view, BridgeScript.BATTLE_SCENE_PATH, "踏入春之境战场")
	if error != OK:
		BridgeScript.clear_pending()
		view.status_message = "无法进入战斗场景。Error: %s" % error
		return false
	return true

func start_battle(view, place: SpringPlace, kind: String) -> void:
	launch(view, place.payload, place.id, kind)

func apply_returned_battle(view) -> void:
	if view.run == null or not BridgeScript.has_result():
		return
	var result: Dictionary = BridgeScript.last_result
	if view.run.exploration.completed.has(StringName(result.get("place", ""))):
		BridgeScript.consume_result()
		return
	var next_scene_path := RegionProgressionScript.scene_path_for(RegionProgressionScript.REGION_SUMMER)
	var scene_available: bool = not next_scene_path.is_empty() and ResourceLoader.exists(next_scene_path)
	var outcome: Dictionary = BridgeScript.settle_result(
		view.run, result, RegionProgressionScript.get_unlocked_region_ids(), scene_available
	)
	view.status_message = str(outcome.get("message", view.status_message))
	if not view.run.pending_event.is_empty() and view.run.exploration.completed.has(StringName(view.run.pending_event["place"])):
		view.run.pending_event.clear()
	var transition: Dictionary = outcome.get("region_transition", {})
	if view.run.pending_hidden_reveal:
		view.run.pending_hidden_reveal = false
		if not bool(transition.get("can_enter", false)):
			view._reveal_hidden_place()
	var saved := SpringRunStorage.settle(view.run, view.save_path, view.atelier_save_path, int(outcome.get("atelier_shards", 0)))
	if saved or SpringSaveTransaction.is_pending(view.atelier_save_path):
		BridgeScript.consume_result()
	if not saved:
		view.status_message = "战后结算存档未完成，请返回大厅后重试。"
		view.run = null
		return
	if bool(transition.get("can_enter", false)):
		RegionProgressionScript.set_pending_transition(view.run, transition)
		var error := change_scene(view, next_scene_path)
		if error == OK:
			return
		RegionProgressionScript.clear_pending_transition()
		transition["status"] = "load_failed"
		transition["can_enter"] = false
		outcome["region_transition"] = transition
		outcome["finished_run"] = true
		outcome["message"] = "下一层已解锁，但区域场景载入失败；本次探索已结束。"
		BridgeScript.last_transition_message = str(outcome["message"])
		view.status_message = str(outcome["message"])

func choose_event_option(view, event_id: StringName, index: int) -> void:
	var result: Dictionary = EventCatalogScript.resolve(view.run, event_id, index)
	if not bool(result.get("ok", false)):
		view.status_message = "；".join(result.get("log", []))
		return
	view.event_result = result
	view.run.pending_event = {"place": String(view.event_place.id), "result": result}
	view.run.event_log[String(event_id)] = {"option": index, "log": result.get("log", [])}
	if bool(result.get("reveal_hidden", false)) or view.run.pending_hidden_reveal:
		view.run.pending_hidden_reveal = false
		view._reveal_hidden_place()
	view._save()

func close_event(view) -> void:
	var battle_id := StringName(str(view.event_result.get("battle", "")))
	if battle_id != &"" and view.event_place != null:
		var kind: String = BridgeScript.KIND_BATTLE
		if EncounterCatalogScript.is_elite_or_boss(battle_id):
			kind = BridgeScript.KIND_ELITE
		launch(view, battle_id, view.event_place.id, kind)
		return
	if view.event_place != null:
		view.run.complete_place(view.event_place)
	view.event_open = false
	view.event_result = {}
	view.run.pending_event.clear()
	view.status_message = "「%s」已了结。" % (view.run.title_of(view.event_place) if view.event_place != null else "事件")
	view._save()

func handle_reward_tap(view, point: Vector2) -> void:
	for index in range(view.run.reward_choices.size()):
		if not view.reward_card_rect(index).has_point(point):
			continue
		var collectible_id: StringName = view.run.reward_choices[index]
		if not view.run.grant_collectible(collectible_id):
			view.status_message = "这件藏品已不再可领取。"
			view.run.reward_choices.clear()
			view._save()
			return
		var effect_note: String = "已收纳，可在藏品栏中选择使用。"
		if not SpringCollectibleCatalog.is_consumable(collectible_id):
			var applied: Dictionary = view.run.apply_collectible_effect(collectible_id)
			effect_note = str(applied.get("message", "效果已结算。"))
		view.status_message = "获得藏品「%s」：%s" % [view.run.collectible_name(collectible_id), effect_note]
		view.run.reward_choices.clear()
		if view.run.pending_hidden_reveal:
			view.run.pending_hidden_reveal = false
			view._reveal_hidden_place()
		view._save()
		return

func handle_revive_tap(view, point: Vector2) -> void:
	if view.REVIVE_YES.has_point(point):
		if not view.run.revive_prompt or not BridgeScript.can_continue(view.run):
			return
		var outcome: Dictionary = BridgeScript.continue_run(view.run)
		view.status_message = str(outcome.get("message", ""))
		if bool(outcome.get("ok", false)):
			view.run.revive_prompt = false
			view._save()
		return
	if view.REVIVE_NO.has_point(point):
		view.run.revive_prompt = false
		view.run.exploration.finish("defeat")
		view._save()


func open_shop(view) -> void:
	view.run.enter_shop()
	view.shop_open = true
	view.shop_tab = 0
	view.shop_sell_page = 0
	view.shop_message = ""
