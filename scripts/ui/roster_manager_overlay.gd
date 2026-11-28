class_name RosterManagerOverlay
extends Control

signal close_requested

const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const SquadStoreScript = preload("res://scripts/meta/squad_loadout_store.gd")

const BG := Color("#11151a")
const PANEL := Color("#1b2027")
const GOLD := Color("#d4b77b")
const BLUE := Color("#72b9ed")
const TEXT := Color("#f0e7d8")
const MUTED := Color("#a9a39a")

var current_mode: String = "characters"
var selected_character_id: String = ""
var selected_team_index: int = 0
var status_label: Label
var team_name_edit: LineEdit
var glossary_popup: PopupPanel
var glossary_label: RichTextLabel
var member_options: Array[OptionButton] = []

const GLOSSARY := {
	"blade_intent": {"title": "剑意", "body": "樱的专属战斗资源，上限为 4 点。攻击与移动可积累剑意；达到 4 层进入极意状态。无尽芳华的终结斩每层剑意提高 5%，满层时另有 20% 加成。"},
	"extreme": {"title": "极意", "body": "樱达到 4 点剑意后进入的强化状态。强化流风与落英的后续效果；具体消耗与强化范围以对应技能说明和当前战斗规则为准。"},
	"petal_mark": {"title": "残香", "body": "樱施加在敌人身上的标记，持续 3 个敌方阶段。再次攻击带有残香的相邻敌人时，可触发一次回锋追击，基础倍率为 50% ATK；特定强化可提高倍率。"},
	"echo_return": {"title": "回锋", "body": "樱对带有残香且仍与自己相邻的敌人触发的自动追加攻击。基础伤害为 50% ATK；每回合首次回锋还会额外积累剑意。"},
	"oath": {"title": "守誓", "body": "瑟弗林的专属被动层数。敌方主动攻击命中瑟弗林时获得守誓，最多 3 层；誓盾庇护会消耗当前全部层数强化护盾。"},
	"judgment": {"title": "易伤印记", "body": "裁决印记施加的负面标记：目标下一次受到伤害时额外承受 30% 伤害，触发后消耗。"},
	"ignite": {"title": "引燃", "body": "德斯特·李的专属负面状态，最多 2 层。1 层在敌方阶段结束造成 25% ATK 法术伤害；2 层造成 40% ATK。持续时间与刷新规则按技能说明执行。"},
	"death_embers": {"title": "死亡余烬", "body": "带有引燃的敌人死亡时触发的连锁爆炸机制。以死亡格为中心影响 3×3 区域，伤害与引燃层数、方向有关；同一连锁内目标不会重复承受爆炸伤害。"},
}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	glossary_popup = PopupPanel.new()
	glossary_popup.name = "GlossaryPopup"
	var popup_panel := PanelContainer.new()
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color("#202a34")
	popup_style.border_color = BLUE
	popup_style.set_border_width_all(1)
	popup_style.set_corner_radius_all(8)
	popup_style.content_margin_left = 14
	popup_style.content_margin_right = 14
	popup_style.content_margin_top = 12
	popup_style.content_margin_bottom = 12
	popup_panel.add_theme_stylebox_override("panel", popup_style)
	glossary_label = RichTextLabel.new()
	glossary_label.bbcode_enabled = true
	glossary_label.fit_content = true
	glossary_label.custom_minimum_size = Vector2(250, 90)
	glossary_label.scroll_active = false
	popup_panel.add_child(glossary_label)
	glossary_popup.add_child(popup_panel)
	add_child(glossary_popup)

func open_characters() -> void:
	current_mode = "characters"
	selected_character_id = ""
	_rebuild()
	show()

func open_squads() -> void:
	current_mode = "squads"
	selected_team_index = SquadStoreScript.active_team_index()
	_rebuild()
	show()

func _clear_screen() -> void:
	for child in get_children():
		if child != glossary_popup:
			remove_child(child)
			child.queue_free()

func _rebuild() -> void:
	_clear_screen()
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.03, 0.04, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.035
	panel.anchor_top = 0.045
	panel.anchor_right = 0.965
	panel.anchor_bottom = 0.955
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL
	panel_style.border_color = Color("#8e7955")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	_build_header(root)
	if current_mode == "characters":
		_build_characters(root)
	else:
		_build_squads(root)

func _build_header(root: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	root.add_child(header)
	var heading := Label.new()
	heading.text = "角色总览" if current_mode == "characters" else "队伍编成"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", GOLD)
	header.add_child(heading)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var roster_button := _make_button("角色总览", current_mode == "characters")
	roster_button.pressed.connect(open_characters)
	header.add_child(roster_button)
	var squad_button := _make_button("队伍编成", current_mode == "squads")
	squad_button.pressed.connect(open_squads)
	header.add_child(squad_button)
	var close_button := _make_button("关闭", false)
	close_button.pressed.connect(_close)
	header.add_child(close_button)
	var rule := HSeparator.new()
	root.add_child(rule)

func _build_characters(root: VBoxContainer) -> void:
	var definitions := CharacterCatalogScript.all_definitions()
	if definitions.is_empty():
		var empty := Label.new()
		empty.text = "当前没有可查看的角色。"
		root.add_child(empty)
		return
	if selected_character_id.is_empty() or not CharacterCatalogScript.has_definition(selected_character_id):
		selected_character_id = String(definitions[0].character_id)

	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 10)
	root.add_child(card_row)
	for definition in definitions:
		var character_id := String(definition.character_id)
		var card := _make_button("%s\n%s" % [definition.display_name_zh, definition.role_label_zh], character_id == selected_character_id)
		card.custom_minimum_size = Vector2(150, 64)
		card.pressed.connect(_select_character.bind(character_id))
		card_row.add_child(card)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(detail_scroll)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 10)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail)
	var definition = CharacterCatalogScript.get_definition(selected_character_id)
	if definition == null:
		return
	var intro := PanelContainer.new()
	intro.add_theme_stylebox_override("panel", _subpanel_style())
	detail.add_child(intro)
	var intro_box := VBoxContainer.new()
	intro_box.add_theme_constant_override("separation", 5)
	intro.add_child(intro_box)
	var name := Label.new()
	name.text = "%s  ·  %s" % [definition.display_name_zh, definition.role_label_zh]
	name.add_theme_font_size_override("font_size", 21)
	name.add_theme_color_override("font_color", TEXT)
	intro_box.add_child(name)
	var stats := Label.new()
	stats.text = "生命 %d    攻击 %d    防御 %d    法术抗性 %d    终极能量上限 %d" % [definition.max_health, definition.attack, definition.defense, definition.magic_resistance, definition.ultimate_energy_max]
	stats.add_theme_color_override("font_color", MUTED)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_box.add_child(stats)
	if definition.has_resource():
		var resource := Label.new()
		resource.text = "专属资源：%s（上限 %d）" % [definition.resource_name_zh, definition.resource_max]
		resource.add_theme_color_override("font_color", BLUE)
		intro_box.add_child(resource)

	var section := Label.new()
	section.text = "技能详情"
	section.add_theme_font_size_override("font_size", 18)
	section.add_theme_color_override("font_color", GOLD)
	detail.add_child(section)
	var skills := SkillRegistryScript.skills_for_character(selected_character_id)
	for skill in skills:
		detail.add_child(_skill_panel(skill, selected_character_id))
	if skills.is_empty():
		var missing := Label.new()
		missing.text = "该角色的技能资料尚未登记。"
		detail.add_child(missing)

func _skill_panel(skill: SkillDefinition, character_id: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _subpanel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)
	var title := Label.new()
	var slot_name := _slot_label(String(skill.slot))
	title.text = "%s  ·  %s" % [slot_name, skill.display_name_zh]
	title.add_theme_color_override("font_color", TEXT)
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	var meta := Label.new()
	var cost := "被动" if skill.is_passive else "%d AP" % skill.ap_cost
	var target := _target_label(String(skill.target_mode))
	var range_text := "自身" if skill.max_range == 0 else ("%d 格" % skill.max_range if skill.min_range == skill.max_range else "%d–%d 格" % [skill.min_range, skill.max_range])
	var damage := "无直接伤害"
	if skill.damage_multiplier > 0.0:
		damage = "%s · %.0f%% ATK" % ["物理伤害" if skill.damage_type == SkillDefinition.DAMAGE_PHYSICAL else "法术伤害", skill.damage_multiplier * 100.0]
		if skill.hits > 1:
			damage += " · %d 段" % skill.hits
	meta.text = "%s    目标：%s    范围：%s    %s" % [cost, target, range_text, damage]
	meta.add_theme_color_override("font_color", BLUE)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(meta)
	var description := RichTextLabel.new()
	description.bbcode_enabled = true
	description.fit_content = true
	description.scroll_active = false
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_color_override("default_color", MUTED)
	description.text = _link_special_terms(skill.description_zh, character_id)
	description.meta_clicked.connect(_on_meta_clicked)
	box.add_child(description)
	return card

func _link_special_terms(source: String, character_id: String) -> String:
	var result := source
	var terms: Dictionary = {}
	match character_id:
		"sakura":
			terms = {"剑意": "blade_intent", "极意": "extreme", "残香": "petal_mark", "回锋": "echo_return"}
		"sevrin":
			terms = {"守誓": "oath", "易伤印记": "judgment"}
		"dest_lee":
			terms = {"引燃": "ignite", "死亡余烬": "death_embers"}
	for term in terms:
		result = result.replace(term, "[url=glossary:%s][color=#72b9ed][u]%s[/u][/color][/url]" % [terms[term], term])
	return result

func _on_meta_clicked(meta: Variant) -> void:
	var key := str(meta)
	if not key.begins_with("glossary:"):
		return
	key = key.trim_prefix("glossary:")
	var entry: Dictionary = GLOSSARY.get(key, {})
	if entry.is_empty():
		return
	glossary_label.text = "[color=#d4b77b][b]%s[/b][/color]\n%s" % [str(entry.title), str(entry.body)]
	var origin := get_global_mouse_position() + Vector2(12, 12)
	glossary_popup.popup(Rect2i(Vector2i(origin), Vector2i(310, 170)))

func _build_squads(root: VBoxContainer) -> void:
	var state := SquadStoreScript.load_state()
	var team_tabs := HBoxContainer.new()
	root.add_child(team_tabs)
	for index in range(SquadStoreScript.TEAM_COUNT):
		var team: Dictionary = state.teams[index]
		var button := _make_button(str(team.get("name", "编队%d" % (index + 1))), index == selected_team_index)
		button.pressed.connect(_select_team.bind(index))
		team_tabs.add_child(button)

	var team: Dictionary = state.teams[selected_team_index]
	var name_row := HBoxContainer.new()
	root.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "编队名称"
	name_label.add_theme_color_override("font_color", MUTED)
	name_row.add_child(name_label)
	team_name_edit = LineEdit.new()
	team_name_edit.text = str(team.get("name", "编队%d" % (selected_team_index + 1)))
	team_name_edit.max_length = 12
	team_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(team_name_edit)
	var rename := _make_button("保存名称", false)
	rename.pressed.connect(_save_team_name)
	name_row.add_child(rename)

	var note := Label.new()
	note.text = "最多 3 名角色；同一编队不可重复上阵。此编队用于未尽之春及未来主题，不改变教程关卡。"
	note.add_theme_color_override("font_color", MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)

	member_options.clear()
	var members: Array = team.get("members", [])
	for slot in range(SquadStoreScript.PARTY_LIMIT):
		var row := HBoxContainer.new()
		root.add_child(row)
		var label := Label.new()
		label.text = "出战位 %d" % (slot + 1)
		label.custom_minimum_size = Vector2(90, 0)
		label.add_theme_color_override("font_color", TEXT)
		row.add_child(label)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_item("空位")
		option.set_item_metadata(0, "")
		for character in CharacterCatalogScript.all_definitions():
			option.add_item("%s · %s" % [character.display_name_zh, character.role_label_zh])
			option.set_item_metadata(option.item_count - 1, String(character.character_id))
		var current_id := str(members[slot]) if slot < members.size() else ""
		var selected := 0
		for item_index in range(option.item_count):
			if str(option.get_item_metadata(item_index)) == current_id:
				selected = item_index
				break
		option.select(selected)
		option.item_selected.connect(_on_member_selected.bind(slot))
		row.add_child(option)
		member_options.append(option)

	var footer := HBoxContainer.new()
	root.add_child(footer)
	var active_text := Label.new()
	active_text.text = "当前出战编队" if int(state.active_team) == selected_team_index else "尚未设为当前出战"
	active_text.add_theme_color_override("font_color", BLUE if int(state.active_team) == selected_team_index else MUTED)
	footer.add_child(active_text)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var activate := _make_button("设为当前出战", int(state.active_team) == selected_team_index)
	activate.pressed.connect(_activate_team)
	footer.add_child(activate)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

func _select_character(character_id: String) -> void:
	selected_character_id = character_id
	_rebuild()

func _select_team(index: int) -> void:
	selected_team_index = index
	_rebuild()

func _on_member_selected(option_index: int, slot: int) -> void:
	var members: Array[String] = []
	var option: OptionButton = member_options[slot]
	var chosen_id := str(option.get_item_metadata(option_index))
	var state := SquadStoreScript.load_state()
	var team: Dictionary = state.teams[selected_team_index]
	for value in team.get("members", []):
		members.append(str(value))
	while members.size() <= slot:
		members.append("")
	members[slot] = chosen_id
	var compact: Array[String] = []
	for value in members:
		if not value.is_empty():
			compact.append(value)
	if not SquadStoreScript.set_team_members(selected_team_index, compact):
		if status_label != null:
			status_label.text = "保存失败：角色不能重复，且每队最多 3 人。"
		return
	_rebuild()

func _save_team_name() -> void:
	if not SquadStoreScript.set_team_name(selected_team_index, team_name_edit.text):
		status_label.text = "名称不能为空。"
		return
	_rebuild()

func _activate_team() -> void:
	if not SquadStoreScript.set_active_team(selected_team_index):
		status_label.text = "编队保存失败，请重试。"
		return
	_rebuild()

func _slot_label(slot: String) -> String:
	match slot:
		"normal": return "普通攻击"
		"passive": return "被动技能"
		"active_one": return "主动技能 I"
		"active_two": return "主动技能 II"
		"ultimate": return "终极技能"
	return "技能"

func _target_label(mode: String) -> String:
	match mode:
		"self": return "自身/周围"
		"self_and_ally": return "自身或友方"
		"actor": return "角色目标"
		"cell": return "指定地格"
		"area": return "范围"
	return "未注明"

func _make_button(caption: String, selected: bool) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(92, 38)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#34302a") if selected else Color("#222831")
	normal.border_color = GOLD if selected else Color("#59616a")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	return button

func _subpanel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#252b33")
	style.border_color = Color("#48515c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

func _close() -> void:
	glossary_popup.hide()
	hide()
	close_requested.emit()
