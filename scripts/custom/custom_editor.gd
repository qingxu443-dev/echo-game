extends Control

var design: CustomLevelData
var grid: CustomGrid
var inspector: CustomInspector
var status: Label
var summary: Label
var name_input: LineEdit
var width_input: SpinBox
var height_input: SpinBox
var ap_input: SpinBox
var hero_choice: OptionButton
var enemy_choice: OptionButton
var file_dialog: FileDialog
var save_dialog: bool = false
var tool: String = "select"
var selected := Vector2i(-1, -1)
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var tool_buttons: Dictionary = {}
var stroke: Dictionary = {}
var drag_origin := Vector2i(-1, -1)
var left_panel: PanelContainer
var center_panel: PanelContainer
var right_panel: PanelContainer


func _ready() -> void:
	design = CustomLevelBridge.design
	if design == null: design = CustomLevelBridge.load_file(CustomLevelBridge.draft_path())
	if design == null: design = CustomLevelData.demo()
	CustomLevelBridge.design = design
	selected = CustomLevelBridge.selected
	_build()
	_layout()
	resized.connect(_layout)
	_sync_settings()
	_sync(true)
	_message("左侧选工具 → 点击/拖动棋盘 → 右侧改属性 → 开始试玩。F2 可从试玩返回。")


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("#101923")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var title := CustomEditorTheme.label("自定义关卡", 30, UiPalette.GOLD_PALE)
	title.position = Vector2(26, 22)
	add_child(title)
	var subtitle := CustomEditorTheme.label("ECHO / LOCAL SANDBOX  ·  编辑 · 验证 · 再试一次", 12, UiPalette.TEXT_DIM)
	subtitle.position = Vector2(28, 65)
	add_child(subtitle)
	var toolbar := HBoxContainer.new()
	toolbar.position = Vector2(482, 26)
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)
	for entry in [["返回标题", _back, 106], ["载入", _open_load, 84], ["保存", _open_save, 84], ["撤销", _undo, 72], ["重做", _redo, 72], ["▶  开始试玩", _play, 166]]:
		var button := _button(str(entry[0]), entry[1], entry[0] == "▶  开始试玩")
		button.custom_minimum_size = Vector2(entry[2], 46)
		toolbar.add_child(button)
	left_panel = _panel()
	center_panel = _panel()
	right_panel = _panel()
	var left := _scroll(left_panel)
	_build_palette(left)
	grid = CustomGrid.new()
	center_panel.add_child(grid)
	grid.pressed.connect(_grid_pressed)
	grid.dragged.connect(_grid_dragged)
	grid.released.connect(_grid_released)
	var right := _scroll(right_panel)
	inspector = CustomInspector.new()
	right.add_child(inspector)
	inspector.stat_changed.connect(_stat_changed)
	inspector.delete_requested.connect(_delete_selected)
	summary = CustomEditorTheme.label("", 13, UiPalette.CYAN)
	add_child(summary)
	status = CustomEditorTheme.label("", 14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_USERDATA
	file_dialog.filters = PackedStringArray(["*.json ; ECHO 自定义关卡"])
	file_dialog.size = Vector2i(820, 520)
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CustomEditorTheme.panel())
	add_child(panel)
	return panel


func _scroll(panel: PanelContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	return box


func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	CustomEditorTheme.button(button, primary)
	button.pressed.connect(callback)
	return button


func _build_palette(box: VBoxContainer) -> void:
	box.add_child(CustomEditorTheme.label("关卡设置", 19, UiPalette.GOLD_PALE))
	name_input = LineEdit.new()
	name_input.max_length = 40
	name_input.placeholder_text = "关卡名称"
	name_input.custom_minimum_size.y = 34
	name_input.text_changed.connect(func(value: String):
		var before := design.to_dict()
		design.data.name = value
		_changed(before, false))
	box.add_child(name_input)
	var dimensions := HBoxContainer.new()
	box.add_child(dimensions)
	for key in ["width", "height"]:
		dimensions.add_child(CustomEditorTheme.label("宽" if key == "width" else "高", 13))
		var spin := CustomEditorTheme.number(8, 4, 8)
		spin.custom_minimum_size.x = 76
		spin.get_line_edit().add_theme_constant_override("minimum_character_width", 1)
		spin.value_changed.connect(_setting_changed.bind(key))
		dimensions.add_child(spin)
		if key == "width": width_input = spin
		else: height_input = spin
	var ap_row := HBoxContainer.new()
	ap_row.add_child(CustomEditorTheme.label("每回合 AP", 14))
	ap_input = CustomEditorTheme.number(3, 1, 15)
	ap_input.value_changed.connect(_setting_changed.bind("ap"))
	ap_row.add_child(ap_input)
	box.add_child(ap_row)
	box.add_child(CustomEditorTheme.label("放置工具", 17, UiPalette.GOLD_PALE))
	var tools := GridContainer.new()
	tools.columns = 2
	tools.add_theme_constant_override("h_separation", 8)
	tools.add_theme_constant_override("v_separation", 6)
	box.add_child(tools)
	var group := ButtonGroup.new()
	for entry in [["select", "选择 / 移动"], ["hero", "放置角色"], ["enemy", "放置怪物"], ["wall", "障碍石墙"], ["chest", "遗迹宝箱"], ["erase", "橡皮擦"]]:
		var button := _button(entry[1], _choose_tool.bind(entry[0]))
		button.add_theme_font_size_override("font_size", 14)
		for state in ["normal", "hover", "pressed", "focus"]:
			var style: StyleBoxFlat = button.get_theme_stylebox(state).duplicate()
			style.set_content_margin_all(6)
			button.add_theme_stylebox_override(state, style)
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tools.add_child(button)
		tool_buttons[entry[0]] = button
	tool_buttons.select.button_pressed = true
	box.add_child(CustomEditorTheme.label("出战角色", 13, UiPalette.TEXT_DIM))
	hero_choice = OptionButton.new()
	hero_choice.fit_to_longest_item = false
	hero_choice.clip_text = true
	for sheet in CharacterCatalog.all_definitions():
		hero_choice.add_item(sheet.display_name_zh)
		hero_choice.set_item_metadata(hero_choice.item_count - 1, str(sheet.character_id))
	hero_choice.item_selected.connect(func(_index: int): _choose_tool("hero"))
	box.add_child(hero_choice)
	box.add_child(CustomEditorTheme.label("敌人档案 · 普通 / 精英 / Boss", 13, UiPalette.TEXT_DIM))
	enemy_choice = OptionButton.new()
	enemy_choice.fit_to_longest_item = false
	enemy_choice.clip_text = true
	for sheet in EnemyCatalog.definitions():
		var tier: String = ["普通", "精英", "Boss"][sheet.tier]
		enemy_choice.add_item("[%s] %s" % [tier, sheet.display_name_zh])
		enemy_choice.set_item_metadata(enemy_choice.item_count - 1, str(sheet.archetype_id))
	enemy_choice.item_selected.connect(func(_index: int): _choose_tool("enemy"))
	box.add_child(enemy_choice)
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("载入示例", _demo))
	buttons.add_child(_button("清空地图", _clear))
	box.add_child(buttons)
	var help := CustomEditorTheme.label("右键擦除 · 拖动刷墙\nCtrl+Z 撤销 · Ctrl+Y 重做\n数值仅影响本关，不改正式角色。", 12, UiPalette.TEXT_DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)


func _layout() -> void:
	if left_panel == null: return
	var height := maxf(390, size.y - 170)
	left_panel.position = Vector2(24, 108)
	left_panel.size = Vector2(240, height)
	right_panel.position = Vector2(size.x - 308, 108)
	right_panel.size = Vector2(284, height)
	center_panel.position = Vector2(280, 108)
	center_panel.size = Vector2(maxf(400, size.x - 604), height)
	summary.position = Vector2(288, 82)
	status.position = Vector2(26, size.y - 50)
	status.size = Vector2(size.x - 52, 46)


func _choose_tool(value: String) -> void:
	tool = value
	tool_buttons[value].set_pressed_no_signal(true)
	_message("工具：%s。点击棋盘放置，拖动可连续编辑。" % tool_buttons[value].text)


func _grid_pressed(cell: Vector2i, button: int) -> void:
	stroke = design.to_dict()
	drag_origin = Vector2i(-1, -1)
	if button == MOUSE_BUTTON_RIGHT:
		_message(design.paint(cell, "erase"))
		_changed(stroke)
		stroke = {}
		return
	if button != MOUSE_BUTTON_LEFT: return
	if tool == "select":
		if not design.unit_at(cell).is_empty(): drag_origin = cell
		elif not design.unit_at(selected).is_empty() and not design.occupied(cell):
			_message(design.move_unit(selected, cell))
		selected = cell
	else:
		_apply_tool(cell)
		selected = cell
	_sync(true)


func _apply_tool(cell: Vector2i) -> void:
	var error := ""
	if tool in ["hero", "enemy"]:
		var choice := hero_choice if tool == "hero" else enemy_choice
		error = design.place_unit(tool, str(choice.get_selected_metadata()), cell)
	else: error = design.paint(cell, tool)
	if not error.is_empty(): _message(error)


func _grid_dragged(cell: Vector2i) -> void:
	if stroke.is_empty() or tool not in ["wall", "erase"]: return
	_apply_tool(cell)
	grid.queue_redraw()


func _grid_released(cell: Vector2i) -> void:
	if stroke.is_empty(): return
	if tool == "select" and drag_origin.x >= 0 and design.inside(cell):
		var error := design.move_unit(drag_origin, cell)
		if error.is_empty(): selected = cell
		else: _message(error)
	_changed(stroke)
	stroke = {}
	drag_origin = Vector2i(-1, -1)


func _changed(before: Dictionary, refresh_inspector: bool = true) -> void:
	if before != design.data:
		undo_stack.append(before.duplicate(true))
		if undo_stack.size() > 60: undo_stack.pop_front()
		redo_stack.clear()
	_sync(refresh_inspector)


func _sync(refresh_inspector: bool) -> void:
	CustomLevelBridge.design = design
	CustomLevelBridge.selected = selected
	grid.design = design
	grid.selected = selected
	grid.queue_redraw()
	summary.text = "%d × %d  ·  角色 %d  ·  敌人 %d  ·  障碍 %d  ·  宝箱 %d" % [design.data.width, design.data.height, design.data.heroes.size(), design.data.enemies.size(), design.data.walls.size(), design.data.chests.size()]
	if refresh_inspector: inspector.refresh(design, selected)


func _sync_settings() -> void:
	for entry in [[name_input, design.data.name], [width_input, design.data.width], [height_input, design.data.height], [ap_input, design.data.ap]]:
		entry[0].set_block_signals(true)
		if entry[0] is LineEdit: entry[0].text = entry[1]
		else: entry[0].value = entry[1]
		entry[0].set_block_signals(false)


func _setting_changed(value: float, key: String) -> void:
	var before := design.to_dict()
	if key == "ap": design.data.ap = int(value)
	elif not design.resize_board(int(value) if key == "width" else int(design.data.width), int(value) if key == "height" else int(design.data.height)):
		_message("缩小地图前，请先移走边界外的单位和地形。")
		_sync_settings()
		return
	_changed(before, false)


func _stat_changed(key: String, value: int) -> void:
	var before := design.to_dict()
	var unit := design.unit_at(selected)
	if unit.is_empty(): return
	unit[key] = value
	if key == "skill_charge_max": unit.skill_charge = mini(int(unit.skill_charge), value)
	_changed(before, false)
	if key == "skill_charge_max": inspector.refresh.call_deferred(design, selected)


func _delete_selected() -> void:
	var before := design.to_dict()
	design.paint(selected, "erase")
	_changed(before)


func _undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(design.to_dict())
	design = CustomLevelData.new()
	design.data = undo_stack.pop_back()
	_sync_settings()
	_sync(true)
	_message("已撤销。")


func _redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(design.to_dict())
	design = CustomLevelData.new()
	design.data = redo_stack.pop_back()
	_sync_settings()
	_sync(true)
	_message("已重做。")


func _demo() -> void:
	var before := design.to_dict()
	design = CustomLevelData.demo()
	_changed(before)
	_sync_settings()
	_message("已载入示例，可自由修改。")


func _clear() -> void:
	var before := design.to_dict()
	for key in ["heroes", "enemies", "walls", "chests"]: design.data[key].clear()
	selected = Vector2i(-1, -1)
	_changed(before)
	_message("已清空地图，Ctrl+Z 可撤销。")


func _play() -> void:
	var error := design.error(true)
	if not error.is_empty():
		_message(error)
		return
	if not CustomLevelBridge.save_file(design, CustomLevelBridge.draft_path()):
		_message("草稿保存失败，请检查存档目录后重试。")
		return
	if SceneTravel.change(get_tree(), CustomLevelBridge.BATTLE_PATH, "踏入自定义试炼") != OK: _message("无法进入试玩，请重试。")


func _back() -> void:
	if not CustomLevelBridge.save_file(design, CustomLevelBridge.draft_path()):
		_message("草稿保存失败，当前编辑内容仍然保留。")
		return
	if SceneTravel.change(get_tree(), "res://scenes/menu/main_menu.tscn", "返回标题") != OK: _message("无法返回标题。")


func _open_save() -> void:
	save_dialog = true
	_open_file(FileDialog.FILE_MODE_SAVE_FILE)
	file_dialog.current_file = design.data.name.validate_filename() + ".json"


func _open_load() -> void:
	save_dialog = false
	_open_file(FileDialog.FILE_MODE_OPEN_FILE)


func _open_file(mode: int) -> void:
	DirAccess.make_dir_recursive_absolute("user://custom_levels")
	file_dialog.file_mode = mode
	file_dialog.current_dir = "user://custom_levels"
	file_dialog.title = "保存自定义关卡" if save_dialog else "载入自定义关卡"
	file_dialog.get_ok_button().text = "保存" if save_dialog else "载入"
	file_dialog.get_cancel_button().text = "取消"
	file_dialog.popup_centered(Vector2i(820, 520))


func _file_selected(path: String) -> void:
	if save_dialog:
		_message("已保存：" + path if CustomLevelBridge.save_file(design, path) else "保存失败，原方案已保留。")
	else:
		var loaded := CustomLevelBridge.load_file(path)
		if loaded == null:
			_message("关卡文件格式无效，当前方案未改变。")
			return
		var before := design.to_dict()
		design = loaded
		_changed(before)
		_sync_settings()
		_message("已载入：" + path)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed and event.keycode == KEY_Z: _undo()
	elif event.ctrl_pressed and event.keycode == KEY_Y: _redo()
	elif event.keycode == KEY_DELETE: _delete_selected()
	else: return
	get_viewport().set_input_as_handled()


func _message(text: String) -> void:
	if not text.is_empty(): status.text = text
