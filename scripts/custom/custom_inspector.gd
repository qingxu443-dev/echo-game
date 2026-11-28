class_name CustomInspector
extends VBoxContainer

signal stat_changed(key: String, value: int)
signal delete_requested
var design: CustomLevelData
var cell := Vector2i(-1, -1)
const LABELS := {"health": "生命上限", "attack": "攻击", "defense": "物理防御", "magic_resistance": "魔法抗性", "shield": "初始护盾", "ultimate_energy": "初始终极能量", "resource_current": "初始职业资源", "move_steps": "敌人移动格数", "skill_charge": "初始技能充能", "skill_charge_max": "技能充能上限", "skill_damage": "招牌技固定伤害", "armor_layers": "初始重甲层数"}


func refresh(level: CustomLevelData, selected: Vector2i) -> void:
	design = level
	cell = selected
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 10)
	add_child(CustomEditorTheme.label("单位与地形属性", 20, UiPalette.GOLD_PALE))
	if not design.inside(cell):
		_hint("在棋盘上选择一个单位。\n\n拖动可移动角色或怪物；选中单位后点击空地，也可直接移动。\n\n数值即时应用于编辑方案，试玩会使用修改后的属性。")
		return
	add_child(CustomEditorTheme.label("格子  %d / %d" % [cell.x + 1, cell.y + 1], 13, UiPalette.TEXT_DIM))
	var unit := design.unit_at(cell)
	if unit.is_empty():
		var terrain := "障碍石墙" if design.data.walls.has([cell.x, cell.y]) else "遗迹宝箱" if design.data.chests.has([cell.x, cell.y]) else "可通行地面"
		add_child(CustomEditorTheme.label(terrain, 18))
		_hint("左侧选择工具，点击或拖动棋盘编辑。宝箱使用原有两次受击耐久和随机掉落规则。")
		_add_delete()
		return
	var hero: bool = unit.kind == "hero"
	var sheet = CharacterCatalog.get_definition(unit.id) if hero else EnemyCatalog.get_definition(unit.id)
	var title: String = sheet.display_name_zh
	add_child(CustomEditorTheme.label(title, 19, UiPalette.CYAN if hero else UiPalette.GOLD_LIGHT))
	_hint("己方角色 · 保留原有技能" if hero else "敌方单位 · 保留原有 AI 与招式")
	for key in LABELS:
		if not unit.has(key): continue
		var row := HBoxContainer.new()
		var label := CustomEditorTheme.label(LABELS[key], 13)
		label.custom_minimum_size.x = 126
		row.add_child(label)
		var maximum: int = CustomLevelData.LIMITS[key][1]
		if key == "ultimate_energy": maximum = sheet.ultimate_energy_max
		elif key == "resource_current": maximum = sheet.resource_max
		elif key == "skill_charge": maximum = int(unit.get("skill_charge_max", 3))
		var spin := CustomEditorTheme.number(int(unit[key]), CustomLevelData.LIMITS[key][0], maximum)
		spin.name = "Stat_" + key
		spin.custom_minimum_size.x = 100
		spin.editable = maximum > 0
		spin.value_changed.connect(func(value: float): stat_changed.emit(key, int(value)))
		row.add_child(spin)
		add_child(row)
	if not hero: _hint("固定伤害为 0 时，招牌技沿用攻击倍率计算。更改同名怪物的属性不会影响其他个体。")
	_add_delete()


func _hint(text: String) -> void:
	var label := CustomEditorTheme.label(text, 13, UiPalette.TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 240
	add_child(label)


func _add_delete() -> void:
	var button := Button.new()
	button.text = "擦除所选格  [Delete]"
	CustomEditorTheme.button(button)
	button.pressed.connect(func(): delete_requested.emit())
	add_child(button)
