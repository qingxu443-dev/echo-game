class_name HudView
extends RefCounted

## The left column: title block, turn and resource readouts, the tactical hint,
## and the enemy action order.
##
## Also owns the CJK line wrapping, since it is the only thing that needs it.

const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const P = preload("res://scripts/ui/theme_palette.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")


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
	var active = controller.get_active_character()
	var active_name: String = "—"
	if active != null:
		active_name = String(active.display_name_zh)
		if active_name.is_empty():
			active_name = String(active.actor_id)
		active_name = _name_with_glyph(String(active.glyph), active_name)
	canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 235), active_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT)

	var sevrin = active
	if sevrin != null:
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 263), "生命  %d / %d" % [sevrin.health, sevrin.max_health], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT_BODY)
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 290), "攻击 %d  防御 %d" % [sevrin.attack, sevrin.defense], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.TEXT_BODY)
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 313), "魔抗 %d" % sevrin.magic_resistance, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.TEXT_BODY)
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 336), "护盾 %d  终极能量 %d / %d" % [sevrin.shield, sevrin.ultimate_energy, P.ULTIMATE_ENERGY_MAX], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.CYAN)
		if sevrin.has_resource():
			canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 359), "%s %d / %d%s" % [String(sevrin.resource_name_zh), sevrin.resource_current, sevrin.resource_max, "　极意" if sevrin.is_resource_full() else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.GOLD_LIGHT)
		else:
			canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 359), "被动：不屈誓约 · 守誓 %d / %d" % [controller.get_oath_vow_stacks(), P.OATH_VOW_MAX], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.GOLD_LIGHT)

	_draw_wrapped(canvas, font, status_message, Vector2(P.LEFT_COLUMN_X, 382), 320.0, 15, P.TEXT_MUTED, 2)

	canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 425), "敌方行动顺序", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.GOLD)
	var order_y := 455.0
	for index in range(controller.intents.size()):
		var intent = controller.intents[index]
		var action_label: String = action_name(intent.action_id)
		var state_label: String = "  [待执行]" if intent.state == IntentScript.IntentState.ACTIVE else ("  [已执行]" if intent.state == IntentScript.IntentState.RESOLVED else "  [已取消]")
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, order_y), "%d. %s — %s%s" % [index + 1, actor_name(controller, intent.source_actor_id), action_label, state_label], HORIZONTAL_ALIGNMENT_LEFT, 315, 13, P.TEXT_FAINT)
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


## Board glyph in front of a name. Sakura's glyph is her own name, so prefixing
## unconditionally printed "樱　樱"; the glyph is a board marker, not part of the
## name, and only earns its place when it says something the name does not.
static func _name_with_glyph(glyph: String, display_name: String) -> String:
	if glyph.is_empty() or glyph == display_name:
		return display_name
	return "%s　%s" % [glyph, display_name]


## Display name from data: a character sheet for the party, an enemy definition
## for anything else. Both tables already carry the name, so the HUD owns no id
## branches - a new character or a new enemy archetype needs no edit here.
static func actor_name(controller, actor_id: String) -> String:
	var definition = CharacterCatalogScript.get_definition(actor_id)
	if definition != null:
		return definition.display_name_zh
	var unit = null if controller == null else controller.get_actor(actor_id)
	if unit != null:
		# Enemies are keyed by archetype ("vanguard"), not by instance id
		# ("vanguard_00"), which is exactly why prefix matching was fragile.
		var enemy = EnemyCatalogScript.get_definition(String(unit.archetype))
		if enemy != null and not enemy.display_name_zh.is_empty():
			return enemy.display_name_zh
		if not String(unit.display_name_zh).is_empty():
			return String(unit.display_name_zh)
	return "未知单位"


## The whole party at a glance, one row per member: with revival in play, the
## inactive member's health is tactical information - whether Sakura can take
## one more hit decides whether to shield her, reposition her or spend the
## revival now. The stats panel above still shows the commanded member only.
static func draw_party(canvas: CanvasItem, controller) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, 604.0), "队伍", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.GOLD)
	var y := 628.0
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		if actor.team != "player":
			continue
		var marker: String = "▸" if String(actor_id) == String(controller.active_character_id) else "　"
		var name: String = String(actor.display_name_zh)
		if name.is_empty():
			name = String(actor.actor_id)
		var row: String = "%s%s  %d/%d" % [marker, _name_with_glyph(String(actor.glyph), name), actor.health, actor.max_health]
		if actor.is_downed():
			row += "  [倒地]"
		elif actor.shield > 0:
			row += "  盾%d" % actor.shield
		if not actor.is_downed():
			row += "  能%d/%d" % [actor.ultimate_energy, P.ULTIMATE_ENERGY_MAX]
		var color := P.TEXT_DISABLED if actor.is_downed() else (P.GOLD_LIGHT if String(actor_id) == String(controller.active_character_id) else P.TEXT_BODY)
		canvas.draw_string(font, Vector2(P.LEFT_COLUMN_X, y), row, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		y += 22.0


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
