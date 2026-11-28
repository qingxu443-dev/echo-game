class_name FragmentCenterPanel
extends ScrollContainer

signal character_changed(character_id: String)

const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const FragmentCatalogScript = preload("res://scripts/fragments/fragment_catalog.gd")
const FragmentStoreScript = preload("res://scripts/fragments/fragment_store.gd")
const FragmentBuildAdvisorScript = preload("res://scripts/fragments/fragment_build_advisor.gd")

var selected_character_id := "sevrin"
var selected_module_id := ""
var selected_direction := FragmentBuildAdvisorScript.DIRECTION_ATTACK
var recommendation: Dictionary = {}
var notice := ""
var store: FragmentStore


func configure(character_id: String) -> void:
	if CharacterCatalogScript.has_definition(character_id):
		selected_character_id = character_id


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rebuild()


func _button(label: String, active: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_pressed = active
	button.custom_minimum_size = Vector2(130, 42)
	return button


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	store = FragmentStoreScript.load_store()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)
	if store == null:
		var invalid := Label.new()
		invalid.text = "残片存档无法读取。为保护现有数据，本界面不会覆盖损坏的存档。"
		content.add_child(invalid)
		return

	var character_row := HBoxContainer.new()
	content.add_child(character_row)
	var character_label := Label.new()
	character_label.text = "管理角色"
	character_row.add_child(character_label)
	var character_option := OptionButton.new()
	character_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var definitions := CharacterCatalogScript.all_definitions()
	var selected_index := 0
	for index in range(definitions.size()):
		var definition = definitions[index]
		character_option.add_item("%s · %s" % [definition.display_name_zh, definition.role_label_zh])
		character_option.set_item_metadata(index, String(definition.character_id))
		if String(definition.character_id) == selected_character_id:
			selected_index = index
	character_option.select(selected_index)
	character_option.item_selected.connect(_on_character_selected.bind(character_option))
	character_row.add_child(character_option)
	var capacity_label := Label.new()
	capacity_label.text = "容量 %d / 12" % store.equipped_capacity(selected_character_id)
	character_row.add_child(capacity_label)

	var instruction := Label.new()
	instruction.text = "每名角色拥有 6 个槽位和 12 点容量。选择库存模块后点击槽位安装；未选择模块时点击已装备槽位可卸下。"
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(instruction)

	var slots: Array = store.equipped_by_character.get(selected_character_id, [])
	var slot_grid := GridContainer.new()
	slot_grid.columns = 3
	slot_grid.add_theme_constant_override("h_separation", 8)
	slot_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(slot_grid)
	for index in range(FragmentCatalogScript.SLOT_COUNT):
		var id := str(slots[index]) if index < slots.size() else ""
		var module := store.module_by_id(id) if not id.is_empty() else {}
		var label := "槽位 %d · 空" % (index + 1) if module.is_empty() else "槽位 %d · %s\n%s" % [index + 1, FragmentCatalogScript.SIZE_NAMES.get(str(module.size), "模块"), FragmentCatalogScript.display_name(module)]
		var button := _button(label, not id.is_empty())
		button.custom_minimum_size = Vector2(240, 66)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_slot_pressed.bind(index))
		slot_grid.add_child(button)

	var inventory_title := Label.new()
	inventory_title.text = "可用模块库存（同类型的不同实例可以重复装备）"
	inventory_title.add_theme_color_override("font_color", Color("#cdb27d"))
	content.add_child(inventory_title)
	var inventory_grid := GridContainer.new()
	inventory_grid.columns = 3
	inventory_grid.add_theme_constant_override("h_separation", 8)
	inventory_grid.add_theme_constant_override("v_separation", 6)
	content.add_child(inventory_grid)
	var available := store.available_modules(selected_character_id)
	for module in available:
		var id := str(module.instance_id)
		var label := "%s\n容量 %d · 实例 %s" % [FragmentCatalogScript.display_name(module), int(module.capacity), id.right(10)]
		var button := _button(label, selected_module_id == id)
		button.custom_minimum_size = Vector2(240, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_module.bind(id))
		inventory_grid.add_child(button)
	if available.is_empty():
		var empty := Label.new()
		empty.text = "目前没有可用模块。可通过通讯终端的补给邮件获得测试模块。"
		content.add_child(empty)

	var direction_title := Label.new()
	direction_title.text = "智能构筑 · 先预览，再确认应用"
	direction_title.add_theme_color_override("font_color", Color("#cdb27d"))
	content.add_child(direction_title)
	var direction_row := HBoxContainer.new()
	direction_row.add_theme_constant_override("separation", 8)
	content.add_child(direction_row)
	var supported := FragmentBuildAdvisorScript.directions_for_character(selected_character_id)
	var direction_ids := [
		FragmentBuildAdvisorScript.DIRECTION_ATTACK,
		FragmentBuildAdvisorScript.DIRECTION_DEFENSE,
		FragmentBuildAdvisorScript.DIRECTION_SUPPORT,
		FragmentBuildAdvisorScript.DIRECTION_BALANCED,
	]
	var direction_names := ["攻击爆发", "坚韧防御", "治疗辅助", "均衡构筑"]
	for index in range(direction_ids.size()):
		var button := _button(direction_names[index], selected_direction == direction_ids[index])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not supported.has(direction_ids[index])
		button.pressed.connect(_request_recommendation.bind(direction_ids[index]))
		direction_row.add_child(button)

	var recommendation_label := Label.new()
	recommendation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if recommendation.is_empty():
		recommendation_label.text = "选择一个方向，系统只给出一套当前库存下的最佳可行配置；预览不会立即改变装备。"
	else:
		var names: Array[String] = []
		for id in recommendation.get("instance_ids", []):
			var recommended_module := store.module_by_id(str(id))
			if not recommended_module.is_empty():
				names.append(FragmentCatalogScript.display_name(recommended_module))
		recommendation_label.text = "%s\n%s\n容量 %d / 12 · 槽位 %d / 6" % [
			str(recommendation.get("message", "")),
			"\n".join(names) if not names.is_empty() else "无需安装模块",
			int(recommendation.get("capacity", 0)),
			names.size(),
		]
	content.add_child(recommendation_label)
	var apply_button := _button("确认应用推荐配置")
	apply_button.disabled = recommendation.is_empty() or not bool(recommendation.get("ok", false)) or bool(recommendation.get("already_optimal", false))
	apply_button.pressed.connect(_apply_recommendation)
	content.add_child(apply_button)
	var notice_label := Label.new()
	notice_label.text = notice
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.add_theme_color_override("font_color", Color("#8fc7dc"))
	content.add_child(notice_label)


func _on_character_selected(index: int, option: OptionButton) -> void:
	selected_character_id = str(option.get_item_metadata(index))
	character_changed.emit(selected_character_id)
	selected_module_id = ""
	recommendation = {}
	notice = ""
	_rebuild()


func _select_module(instance_id: String) -> void:
	selected_module_id = "" if selected_module_id == instance_id else instance_id
	recommendation = {}
	notice = "已选择模块，请点击目标槽位。" if not selected_module_id.is_empty() else ""
	_rebuild()


func _on_slot_pressed(slot_index: int) -> void:
	if store == null:
		return
	var result: Dictionary
	if not selected_module_id.is_empty():
		result = store.install(selected_character_id, slot_index, selected_module_id)
		if bool(result.get("ok", false)):
			selected_module_id = ""
	else:
		result = store.uninstall(selected_character_id, slot_index)
	notice = str(result.get("message", ""))
	if bool(result.get("ok", false)) and not store.save():
		notice = "残片存档写入失败；请检查存储空间后重试。"
	recommendation = {}
	_rebuild()


func _request_recommendation(direction: String) -> void:
	if store == null:
		return
	selected_direction = direction
	recommendation = FragmentBuildAdvisorScript.recommend(store, selected_character_id, direction)
	notice = str(recommendation.get("message", ""))
	_rebuild()


func _apply_recommendation() -> void:
	if store == null or recommendation.is_empty():
		return
	var ids: Array[String] = []
	for id in recommendation.get("instance_ids", []):
		ids.append(str(id))
	var result := store.apply_loadout(selected_character_id, ids)
	notice = str(result.get("message", ""))
	if bool(result.get("ok", false)) and not store.save():
		notice = "推荐配置已计算，但存档写入失败。"
	selected_module_id = ""
	recommendation = {}
	_rebuild()
