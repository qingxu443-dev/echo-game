extends "res://scripts/ui/battle_view.gd"


func _ready() -> void:
	if SessionSave.pending.get("custom_level") is Dictionary:
		CustomLevelBridge.design = CustomLevelData.from_dict(SessionSave.pending.custom_level)
	if CustomLevelBridge.design == null: CustomLevelBridge.design = CustomLevelData.demo()
	SpringBattleBridge.clear_pending()
	SpringBattleBridge.tutorial_loadout_requested = false
	encounter_override = CustomLevelBridge.design.encounter()
	super._ready()
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	for index in range(2):
		var button := Button.new()
		button.text = "返回编辑  [F2]" if index == 0 else "重新试玩"
		button.position = Vector2(336 + index * 154, 84)
		button.size = Vector2(144, 34)
		CustomEditorTheme.button(button)
		button.pressed.connect(_edit if index == 0 else _begin_fresh_run)
		layer.add_child(button)


func custom_definition() -> Dictionary:
	return CustomLevelBridge.design.to_dict()


func _start_level(_index: int) -> void:
	selected_skill = -1
	pending_rewards.clear()
	if not CustomLevelRuntime.start(self, CustomLevelBridge.design):
		status_message = "关卡配置无法开始，请返回编辑检查。"
		return
	current_level = 0
	skill_bar = SkillBarViewScript.build_entries(controller)
	status_message = "自定义试玩 · F2 返回编辑 · 本模式不消耗补给、不结算残晶"
	_reset_fx_for_encounter()
	SceneTravel.reveal(self, str(CustomLevelBridge.design.data.name))
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		get_viewport().set_input_as_handled()
		_edit()
		return
	super._input(event)


func _edit() -> void:
	var error := SceneTravel.change(get_tree(), CustomLevelBridge.EDITOR_PATH, "返回关卡编辑")
	if error != OK: status_message = "无法返回编辑器，请重试。"


func _on_battle_finished(result: String) -> void:
	inventory_open = false
	controller.ledger.rewards_settled = true
	if result == "victory": pending_rewards = controller.collect_remaining_chests()
	else: pending_rewards.clear()
	status_message = "试玩%s · 不计入正式奖励。点击上方「返回编辑」继续调整。" % ("胜利" if result == "victory" else "结束")
	queue_redraw()


func _handle_settlement_tap(position: Vector2) -> void:
	var action := SettlementViewScript.hit(position, controller.battle_result == "victory", false, false)
	if action == SettlementViewScript.ACTION_OPEN_BAG:
		inventory_open = true
	elif action in [SettlementViewScript.ACTION_RESTART, SettlementViewScript.ACTION_NEXT]:
		_begin_fresh_run()
	queue_redraw()
