class_name HudView
extends RefCounted

## The left column: title block, turn and resource readouts, the tactical hint,
## and the enemy action order.
##
## Also owns the CJK line wrapping, since it is the only thing that needs it.

const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const P = preload("res://scripts/ui/theme_palette.gd")


## Title block. Drawn before the board so the battlefield never covers it.
static func draw_header(canvas: CanvasItem, level, level_index: int, level_count: int) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 52), "回声计划  /  原型 0.1", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.TEXT)
	canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 82), "初次守望", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.TEXT_DIM)
	if level != null:
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 112), "%s　（%d / %d）" % [level.display_name_zh, level_index + 1, level_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.GOLD)


## Turn, resources, tactical hint and the enemy action order.
static func draw_status(canvas: CanvasItem, controller, status_message: String) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 145), "回合  %02d" % controller.turn_number, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.TEXT_STRONG)
	canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 180), "行动点  %d / %d" % [controller.ap.current, controller.ap.maximum], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.GOLD_LIGHT)
	canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 235), "瑟弗林", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT)

	var sevrin = controller.get_actor("sevrin")
	if sevrin != null:
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 263), "生命  %d / %d" % [sevrin.health, sevrin.max_health], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT_BODY)
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 290), "攻击 %d  防御 %d" % [sevrin.attack, sevrin.defense], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.TEXT_BODY)
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 313), "魔抗 %d" % sevrin.magic_resistance, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.TEXT_BODY)
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 336), "护盾 %d  终极能量 %d / %d" % [sevrin.shield, sevrin.ultimate_energy, P.ULTIMATE_ENERGY_MAX], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.CYAN)
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 359), "被动：不屈誓约 · 守誓 %d / %d" % [controller.get_oath_vow_stacks(), P.OATH_VOW_MAX], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.GOLD_LIGHT)

	_draw_wrapped(canvas, font, status_message, Vector2(P.LEFT_COLUMN_X, 382), 320.0, 15, P.TEXT_MUTED, 2)

	canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 425), "敌方行动顺序", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.GOLD)
	var order_y := 455.0
	for index in range(controller.intents.size()):
		var intent = controller.intents[index]
		var action_label: String = action_name(intent.action_id)
		var state_label: String = "  [待执行]" if intent.state == IntentScript.IntentState.ACTIVE else ("  [已执行]" if intent.state == IntentScript.IntentState.RESOLVED else "  [已取消]")
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, order_y), "%d. %s — %s%s" % [index + 1, actor_name(intent.source_actor_id), action_label, state_label], HORIZONTAL_ALIGNMENT_LEFT, 315, 13, P.TEXT_FAINT)
		order_y += 24.0


## Character-level wrapping so CJK status text breaks cleanly instead of clipping.
static func _draw_wrapped(canvas: CanvasItem, font: Font, text: String, pos: Vector2, max_width: float, size: int, color: Color, max_lines: int) -> void:
	var lines: Array[String] = []
	var current := ""
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		var trial := current + ch
		if current != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
			lines.append(current)
			current = ch
		else:
			current = trial
	if current != "":
		lines.append(current)
	var y := pos.y
	for i in range(mini(lines.size(), max_lines)):
		var line_text: String = lines[i]
		if i == max_lines - 1 and lines.size() > max_lines:
			line_text += "…"
		canvas.draw_string(font, Vector2(pos.x, y), line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		y += float(size) + 6.0


static func actor_name(actor_id: String) -> String:
	if actor_id == "sevrin":
		return "瑟弗林"
	if actor_id.begins_with("vanguard"):
		return "先锋"
	if actor_id.begins_with("marksman"):
		return "神射手"
	if actor_id.begins_with("area_controller"):
		return "区域术士"
	return "未知单位"


static func action_name(action_id: String) -> String:
	var names := {
		"charged_strike": "蓄力重击",
		"basic_melee": "近战攻击",
		"pursuit": "追击",
		"aimed_shot": "瞄准射击",
		"ground_pulse": "地脉脉冲",
		"wait": "待机"
	}
	return names.get(action_id, "未知行动")
