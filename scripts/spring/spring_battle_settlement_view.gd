extends Control

const SpringRunScript = preload("res://scripts/spring/spring_run.gd")
const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")
const StorageScript = preload("res://scripts/spring/spring_run_storage.gd")
const RegionProgressionScript = preload("res://scripts/spring/spring_region_progression.gd")

const VIEW := Vector2(1280.0, 720.0)
const RETURN_BUTTON := Rect2(1000.0, 632.0, 232.0, 54.0)
const MAP_SCENE_PATH := "res://scenes/spring/spring_map.tscn"

var run: SpringRun
var record: Dictionary = {}
var outcome: Dictionary = {}
var status_message := ""
var prepared := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_or_prepare()


func _load_or_prepare() -> void:
	run = SpringRunScript.load_from_file(SpringRunScript.SAVE_PATH)
	if run == null:
		status_message = "无法读取春之境存档。原始战果未被覆盖，请返回后重试。"
		queue_redraw()
		return
	record = run.pending_battle_settlement.duplicate(true)
	if record.is_empty():
		status_message = "没有待确认的战斗结算记录。"
		queue_redraw()
		return
	if str(record.get("phase", "pending")) == "prepared":
		outcome = record.get("outcome", {}).duplicate(true)
		prepared = true
		queue_redraw()
		return
	_prepare_once()


func _prepare_once() -> void:
	var result: Dictionary = record.get("result", {})
	if result.is_empty():
		status_message = "战斗结果记录不完整，奖励尚未入账。"
		queue_redraw()
		return
	var next_scene_path := RegionProgressionScript.scene_path_for(RegionProgressionScript.REGION_SUMMER)
	var scene_available := not next_scene_path.is_empty() and ResourceLoader.exists(next_scene_path)
	outcome = BridgeScript.settle_result(
		run,
		result,
		RegionProgressionScript.get_unlocked_region_ids(),
		scene_available
	)
	if not run.pending_event.is_empty() and run.exploration.completed.has(StringName(run.pending_event.get("place", ""))):
		run.pending_event.clear()
	var transition: Dictionary = outcome.get("region_transition", {})
	if run.pending_hidden_reveal:
		run.pending_hidden_reveal = false
		if not bool(transition.get("can_enter", false)):
			var hidden := run.template.place_by_id(&"hidden")
			if hidden == null:
				run.reveal_hidden(run.hidden_cell)
	record["phase"] = "prepared"
	record["outcome"] = {
		"message": str(outcome.get("message", "")),
		"atelier_shards": int(outcome.get("atelier_shards", 0)),
		"finished_run": bool(outcome.get("finished_run", false)),
		"needs_revive": bool(outcome.get("needs_revive", false)),
		"region_transition": transition.duplicate(true),
	}
	run.pending_battle_settlement = record
	prepared = true
	if not run.save_to_file(SpringRunScript.SAVE_PATH):
		status_message = "结算内容已生成，但存档写入失败。请点击下方按钮重试保存；奖励不会重复抽取。"
	queue_redraw()


func _confirm_and_return() -> void:
	if run == null or record.is_empty():
		get_tree().change_scene_to_file(MAP_SCENE_PATH)
		return
	if not prepared:
		_prepare_once()
		if not prepared:
			return
	var settlement_id := str(record.get("id", ""))
	if settlement_id.is_empty():
		status_message = "结算记录缺少唯一编号，暂不发放奖励。"
		queue_redraw()
		return
	var shards := int(outcome.get("atelier_shards", 0))
	if not StorageScript.settle(run, SpringRunScript.SAVE_PATH, AtelierStash.SAVE_PATH, shards, settlement_id):
		status_message = "战后奖励存档未完成。当前结算记录仍被保留，请重试。"
		queue_redraw()
		return
	var previous_record := run.pending_battle_settlement.duplicate(true)
	run.pending_battle_settlement = {}
	if not run.save_to_file(SpringRunScript.SAVE_PATH):
		run.pending_battle_settlement = previous_record
		status_message = "奖励已安全入账，但结算标记清理失败。再次点击不会重复领取。"
		queue_redraw()
		return
	var transition: Dictionary = outcome.get("region_transition", {})
	if bool(transition.get("can_enter", false)):
		RegionProgressionScript.set_pending_transition(run, transition)
		var next_path := RegionProgressionScript.scene_path_for(RegionProgressionScript.REGION_SUMMER)
		if not next_path.is_empty() and ResourceLoader.exists(next_path):
			var next_error := get_tree().change_scene_to_file(next_path)
			if next_error == OK:
				return
			RegionProgressionScript.clear_pending_transition()
	get_tree().change_scene_to_file(MAP_SCENE_PATH)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_handle_confirm(mouse.position)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_handle_confirm(touch.position)


func _handle_confirm(point: Vector2) -> void:
	if RETURN_BUTTON.has_point(point):
		_confirm_and_return()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("#101923"), true)
	draw_rect(Rect2(72.0, 54.0, 1136.0, 600.0), Color("#192733"), true)
	draw_rect(Rect2(72.0, 54.0, 1136.0, 600.0), Color("#425968"), false, 2.0)
	draw_line(Vector2(112.0, 160.0), Vector2(1168.0, 160.0), Color("#526a73"), 1.0)
	var font := ThemeDB.fallback_font
	var battle_result: Dictionary = record.get("result", {})
	var won := str(battle_result.get("result", "")) == "victory"
	var title := "战斗胜利" if won else "战斗结束"
	draw_string(font, Vector2(120.0, 122.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("#f0dfb8"))
	draw_string(font, Vector2(120.0, 148.0), "春之境 · 战后结算", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#a9c1c7"))
	if prepared:
		draw_multiline_string(font, Vector2(124.0, 220.0), str(outcome.get("message", "")), HORIZONTAL_ALIGNMENT_LEFT, 980.0, 21, 4, Color("#e5e9e4"))
		var shards := int(outcome.get("atelier_shards", 0))
		draw_string(font, Vector2(124.0, 340.0), "工坊残晶  +%d" % shards, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#d9bd82"))
		var result: Dictionary = record.get("result", {})
		var loot: Array = result.get("loot", [])
		var loot_names: Array[String] = []
		for item in loot:
			if item is Dictionary and not str(item.get("name", "")).is_empty():
				loot_names.append(str(item.get("name", "")))
		if not loot_names.is_empty():
			draw_multiline_string(font, Vector2(124.0, 392.0), "战利品：" + "、".join(loot_names), HORIZONTAL_ALIGNMENT_LEFT, 980.0, 18, 3, Color("#bdcfd0"))
		if not run.reward_choices.is_empty():
			draw_string(font, Vector2(124.0, 490.0), "精英奖励已保留：返回地图后选择一件藏品。", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#d8c59b"))
	else:
		draw_multiline_string(font, Vector2(124.0, 230.0), status_message, HORIZONTAL_ALIGNMENT_LEFT, 980.0, 20, 5, Color("#e5e9e4"))
	if not status_message.is_empty() and prepared:
		draw_multiline_string(font, Vector2(124.0, 555.0), status_message, HORIZONTAL_ALIGNMENT_LEFT, 820.0, 15, 2, Color("#d99a86"))
	draw_rect(RETURN_BUTTON, Color("#8c7150"), true)
	draw_rect(RETURN_BUTTON, Color("#d9bd82"), false, 2.0)
	var button_label := "返回春之境" if prepared and status_message.is_empty() else ("重试保存并返回" if prepared else "返回")
	draw_string(font, Vector2(RETURN_BUTTON.position.x + 32.0, RETURN_BUTTON.position.y + 34.0), button_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#fff7e7"))
