class_name SkillBarView
extends RefCounted

## The right column: the four skill buttons, the end-turn button and the control
## hints. Also owns skill_rect(), so hit testing and drawing share one geometry.

const P = preload("res://scripts/ui/theme_palette.gd")


static func skill_rect(index: int) -> Rect2:
	return Rect2(P.SKILL_PANEL_X, P.SKILL_FIRST_Y + float(index) * P.SKILL_BTN_STEP, P.SKILL_PANEL_W, P.SKILL_BTN_H)


static func draw(canvas: CanvasItem, controller, skill_bar: Array, selected_skill: int, summon_options: Array, selected_summon: int) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, 96), "技能", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT)

	for index in range(skill_bar.size()):
		_draw_skill(canvas, font, controller, skill_bar, index, selected_skill, summon_options, selected_summon)

	var end_color := P.BUTTON_BG if controller.phase == controller.BattlePhase.PLAYER else P.BUTTON_BG_DISABLED
	canvas.draw_rect(P.END_TURN_RECT, end_color, true)
	canvas.draw_rect(P.END_TURN_RECT, P.BUTTON_BORDER, false, 2.0)
	canvas.draw_string(font, P.END_TURN_RECT.position + Vector2(100.0, 38.0), "结束回合", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.BUTTON_TEXT)

	var hint_y := 496.0
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y), "操作", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.TEXT_DIM)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 22.0), "点格子移动，最多两格直线", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 40.0), "自身技能点一下即生效", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 58.0), "选中技能后，黄圈标出可打目标", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 76.0), "数字键 1–4 施放/选择技能", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 94.0), "Esc / 右键取消目标选择", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)


static func _draw_skill(canvas: CanvasItem, font: Font, controller, skill_bar: Array, index: int, selected_skill: int, summon_options: Array, selected_summon: int) -> void:
	var skill: Dictionary = skill_bar[index]
	var rect := skill_rect(index)
	var affordable: bool = controller.ap != null and controller.ap.can_spend(int(skill["cost"]))
	if skill["id"] == "absolute_guard":
		var sevrin = controller.get_actor("sevrin")
		affordable = affordable and sevrin != null and sevrin.ultimate_energy >= P.ULTIMATE_ENERGY_MAX

	var cost_label := "%d AP" % int(skill["cost"])
	var cost_offset: float = 52.0
	var cost_y: float = 30.0
	if skill["id"] == "hunter_summon":
		var summon_remaining: int = controller.summon_cooldown_remaining()
		affordable = controller.phase == controller.BattlePhase.PLAYER and summon_remaining <= 0
		cost_label = "就绪" if summon_remaining <= 0 else "冷却 %d" % summon_remaining
		cost_offset = 76.0
		# The icon pushes the text block 36 px to the right, so the status label
		# shares the name baseline instead of sitting between the two text rows.
		cost_y = 21.0

	var is_selected: bool = (index == selected_skill and skill["mode"] == "actor")
	var bg := P.PANEL_SELECTED if is_selected else P.PANEL
	var border := P.GOLD_LIGHT if is_selected else P.PANEL_BORDER
	if not affordable:
		bg = P.PANEL_DISABLED
		border = P.PANEL_BORDER_DISABLED
	canvas.draw_rect(rect, bg, true)
	canvas.draw_rect(rect, border, false, 2.0 if is_selected else 1.0)

	var text_color := P.BUTTON_TEXT if affordable else P.TEXT_DISABLED
	var skill_name: String = str(skill["name"])
	var text_x: float = 14.0
	if skill["id"] == "hunter_summon" and not summon_options.is_empty():
		var summon_option: Dictionary = summon_options[selected_summon]
		var icon_modulate: Color = Color(1.0, 1.0, 1.0) if affordable else Color(1.0, 1.0, 1.0, 0.45)
		canvas.draw_texture_rect(summon_option["icon"], Rect2(rect.position + Vector2(8.0, 8.0), Vector2(34.0, 34.0)), false, icon_modulate)
		skill_name += " · " + str(summon_option["name"])
		text_x = 50.0

	canvas.draw_string(font, rect.position + Vector2(text_x, 21.0), skill_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, text_color)
	canvas.draw_string(font, rect.position + Vector2(text_x, 39.0), str(skill["hint"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_color)
	canvas.draw_string(font, rect.position + Vector2(rect.size.x - cost_offset, cost_y), cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.GOLD_LIGHT if affordable else P.TEXT_DISABLED)
