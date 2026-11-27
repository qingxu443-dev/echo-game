class_name HudView
extends RefCounted

## Into-the-Breach inspired clean battle HUD:
## - Top-left: compact stage title, turn counter, and visual AP pips.
## - Top-center: single-line interactive tutorial / status banner.
## - Bottom-left: hero portrait with HP & shield bar directly underneath.
## - Top-right: enemy turn order + hovered enemy skill & threat inspector.

const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const P = preload("res://scripts/ui/theme_palette.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")
const BoardObjectsViewScript = preload("res://scripts/ui/board_objects_view.gd")

const PORTRAIT_DIR: String = "res://assets/actors/portraits/"


static func draw_header(canvas: CanvasItem, level, level_index: int, level_count: int) -> void:
	var font := ThemeDB.fallback_font
	var rect := P.TOP_LEFT_RECT
	_draw_card(canvas, rect, P.PANEL, P.PANEL_BORDER)

	var title: String = "ECHO · 遗迹守望"
	if level != null:
		title = "%s  (%d/%d)" % [level.display_name_zh, level_index + 1, level_count]
	canvas.draw_string(font, rect.position + Vector2(14.0, 26.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 15, P.GOLD_PALE)


static func draw_status(canvas: CanvasItem, controller, status_message: String, fx_state: Dictionary = {}) -> void:
	var font := ThemeDB.fallback_font
	_draw_turn_and_ap(canvas, font, controller)
	_draw_camera_controls(canvas, font)
	_draw_active_mods(canvas, font, controller)
	_draw_guide_banner(canvas, font, status_message)
	_draw_portrait_card(canvas, font, controller)
	_draw_enemy_order_card(canvas, font, controller)
	_draw_enemy_inspector_card(canvas, font, controller, fx_state)


## Kept as a no-op stub so existing callers (battle_view.gd) stay compatible;
## solo Sevrin's info now lives cleanly inside the bottom-left portrait card.
static func draw_party(_canvas: CanvasItem, _controller) -> void:
	pass


# --- top-left: turn + visual AP pips ----------------------------------------

static func _draw_turn_and_ap(canvas: CanvasItem, font: Font, controller) -> void:
	var rect := P.TOP_LEFT_RECT
	canvas.draw_string(font, rect.position + Vector2(14.0, 56.0), "回合 %02d" % controller.turn_number, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT_STRONG)

	var ap_label_pos := rect.position + Vector2(106.0, 55.0)
	# 春之结界 nodes live in the same table as the relic chests (that is how the
	# battle layer holds a cell), but they are not loot and must not be counted as
	# chests the player can still save.
	var b_alive: int = 0
	var b_total: int = 0
	for cell in controller.beacons:
		var beacon: Dictionary = controller.beacons[cell]
		if str(beacon.get("kind", "")) == "ward_node":
			continue
		b_total += 1
		if int(beacon.get("health", 0)) > 0:
			b_alive += 1
	canvas.draw_string(font, ap_label_pos, "遗迹宝箱 %d/%d" % [b_alive, b_total], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.GOLD_PALE if b_alive > 1 else P.WARN)

	var pip_start := rect.position + Vector2(14.0, 74.0)
	var total_ap: int = maxi(1, controller.ap.maximum)
	var cur_ap: int = controller.ap.current
	var pip_w: float = minf(38.0, (rect.size.x - 28.0 - float(total_ap - 1) * 6.0) / float(total_ap))
	for i in range(total_ap):
		var pr := Rect2(pip_start.x + float(i) * (pip_w + 6.0), pip_start.y, pip_w, 12.0)
		var filled: bool = i < cur_ap
		canvas.draw_rect(pr, P.GOLD_LIGHT if filled else Color(0.14, 0.16, 0.19, 1.0), true)
		canvas.draw_rect(pr, P.GOLD_PALE if filled else P.PANEL_BORDER, false, 1.2)


static func _draw_camera_controls(canvas: CanvasItem, font: Font) -> void:
	_draw_card(canvas, P.CAM_LEFT_BTN, P.PANEL, P.PANEL_BORDER)
	_draw_card(canvas, P.CAM_RIGHT_BTN, P.PANEL, P.PANEL_BORDER)
	canvas.draw_string(font, P.CAM_LEFT_BTN.position + Vector2(18.0, 21.0), "[Q] 逆时针视角", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_FAINT)
	canvas.draw_string(font, P.CAM_RIGHT_BTN.position + Vector2(18.0, 21.0), "[E] 顺时针视角", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_FAINT)
	canvas.draw_string(font, Vector2(P.CAM_LEFT_BTN.position.x + 2.0, P.CAM_LEFT_BTN.end.y + 18.0), "当前镜头：" + P.camera_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.GOLD)


static func _draw_active_mods(canvas: CanvasItem, font: Font, controller) -> void:
	if controller.run_state == null:
		return
	# Backpack / Equipment toggle button
	var bag_n: int = controller.run_state.backpack.size()
	var w_tag: String = "有武" if not controller.run_state.equipped_weapon.is_empty() else "无武"
	var a_tag: String = "有甲" if not controller.run_state.equipped_armor.is_empty() else "无甲"
	_draw_card(canvas, P.BAG_BTN, P.BUTTON_BG if bag_n > 0 else P.PANEL, P.GOLD_LIGHT if bag_n > 0 else P.PANEL_BORDER)
	canvas.draw_string(font, P.BAG_BTN.position + Vector2(14.0, 22.0), "[B] 装备/背包 (%d) · %s/%s" % [bag_n, w_tag, a_tag], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.BUTTON_TEXT if bag_n > 0 else P.TEXT_FAINT)

	var names: Array[String] = controller.run_state.active_mod_names()
	if names.is_empty():
		return
	var y: float = P.BAG_BTN.end.y + 12.0
	var rect := Rect2(P.LEFT_COLUMN_X, y, 284.0, 26.0 + float(names.size()) * 20.0)
	_draw_card(canvas, rect, Color(0.12, 0.14, 0.17, 0.90), P.CYAN)
	canvas.draw_string(font, rect.position + Vector2(12.0, 19.0), "已获回声铭文 / 遗物", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.CYAN)
	for i in range(names.size()):
		canvas.draw_string(font, rect.position + Vector2(14.0, 39.0 + float(i) * 20.0), "◆ " + names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.GOLD_PALE)


# --- top-center: interactive guide / status banner --------------------------

static func _draw_guide_banner(canvas: CanvasItem, font: Font, message: String) -> void:
	var rect := P.GUIDE_BANNER_RECT
	_draw_card(canvas, rect, Color(0.13, 0.15, 0.18, 0.94), P.GOLD)
	canvas.draw_rect(Rect2(rect.position, Vector2(5.0, rect.size.y)), P.GOLD_LIGHT, true)
	_draw_wrapped(canvas, font, message, rect.position + Vector2(16.0, 22.0), rect.size.x - 28.0, 14, P.TEXT, 2)


# --- bottom-left: hero portrait + bottom HP bar (Into the Breach style) -----

static func _draw_portrait_card(canvas: CanvasItem, font: Font, controller) -> void:
	var rect := P.PORTRAIT_CARD_RECT
	_draw_card(canvas, rect, Color(0.13, 0.15, 0.18, 0.96), P.GOLD)

	var hero = controller.get_active_character()
	if hero == null:
		return

	# Portrait frame on the left
	var p_size: float = 96.0
	var p_rect := Rect2(rect.position + Vector2(12.0, 12.0), Vector2(p_size, p_size))
	canvas.draw_rect(p_rect, Color(0.09, 0.11, 0.14, 1.0), true)
	var p_key: String = String(hero.character_id) if hero.character_id != &"" else String(hero.actor_id)
	var tex: Texture2D = BoardObjectsViewScript._load_cached_texture(PORTRAIT_DIR + p_key + ".png")
	if tex != null:
		canvas.draw_texture_rect(tex, p_rect, false)
	canvas.draw_rect(p_rect, P.GOLD_LIGHT, false, 2.0)

	# HP bar & shield bar directly underneath the portrait (full card width)
	var hp_y: float = p_rect.end.y + 10.0
	var bar_rect := Rect2(rect.position.x + 12.0, hp_y, rect.size.x - 24.0, 18.0)
	canvas.draw_rect(bar_rect, P.HP_BG, true)
	var hp_ratio: float = clampf(float(hero.health) / float(maxi(1, hero.max_health)), 0.0, 1.0)
	if hp_ratio > 0.0:
		canvas.draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * hp_ratio, bar_rect.size.y)), P.HP_PLAYER, true)
	if hero.shield > 0:
		var sh_ratio: float = clampf(float(hero.shield) / float(maxi(1, hero.max_health)), 0.0, 1.0)
		canvas.draw_rect(Rect2(bar_rect.position.x, bar_rect.position.y - 4.0, bar_rect.size.x * minf(1.0, sh_ratio * 2.5), 3.0), P.HP_SHIELD, true)
	canvas.draw_rect(bar_rect, Color(0.45, 0.50, 0.56, 0.9), false, 1.2)

	var hp_text: String = "HP %d / %d" % [hero.health, hero.max_health]
	if hero.shield > 0:
		hp_text += "  (+%d 盾)" % hero.shield
	canvas.draw_string(font, bar_rect.position + Vector2(8.0, 14.0), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.96, 0.97, 0.98))

	# Compact stats to the right of the portrait
	var info_x: float = p_rect.end.x + 14.0
	var name_str: String = String(hero.display_name_zh) if not String(hero.display_name_zh).is_empty() else String(hero.actor_id)
	canvas.draw_string(font, Vector2(info_x, rect.position.y + 28.0), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT)
	if not String(hero.role_label_zh).is_empty():
		canvas.draw_string(font, Vector2(info_x, rect.position.y + 46.0), String(hero.role_label_zh), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.GOLD)
	canvas.draw_string(font, Vector2(info_x, rect.position.y + 68.0), "攻 %d   防 %d" % [hero.attack, hero.defense], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_BODY)

	# Ultimate energy pips
	canvas.draw_string(font, Vector2(info_x, rect.position.y + 88.0), "能量", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.CYAN)
	for i in range(hero.ultimate_energy_max):
		var c := Vector2(info_x + 38.0 + float(i) * 16.0, rect.position.y + 83.0)
		var lit: bool = i < hero.ultimate_energy
		canvas.draw_circle(c, 5.0, P.CYAN if lit else Color(0.18, 0.21, 0.25))
		canvas.draw_arc(c, 5.0, 0.0, TAU, 16, P.TEXT_DIM, 1.0)

	# Oath Vow passive stacks
	var vow: int = controller.get_oath_vow_stacks()
	canvas.draw_string(font, Vector2(info_x, rect.position.y + 106.0), "守誓 %d / %d" % [vow, P.OATH_VOW_MAX], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.GOLD_LIGHT)


# --- top-right: enemy turn order + hovered enemy skill inspector ------------

static func _draw_enemy_order_card(canvas: CanvasItem, font: Font, controller) -> void:
	var rect := P.ORDER_CARD_RECT
	_draw_card(canvas, rect, P.PANEL, P.PANEL_BORDER)
	canvas.draw_string(font, rect.position + Vector2(14.0, 24.0), "敌方行动顺序", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.GOLD)

	var y: float = rect.position.y + 48.0
	for index in range(mini(controller.intents.size(), 4)):
		var intent = controller.intents[index]
		var dot_color: Color = _intent_color(intent.action_id)
		canvas.draw_circle(Vector2(rect.position.x + 18.0, y - 4.0), 4.5, dot_color)
		var dmg_str: String = ""
		if intent.damage > 0:
			# 结界/壁垒 payload is a shield, and 腐樱诅咒 is a defence cut - both
			# would read as damage if printed as a bare number.
			if _is_shield_action(intent.action_id):
				dmg_str = " (盾 %d)" % intent.damage
			elif intent.action_id == "rot_curse":
				dmg_str = " (降防 %d)" % intent.damage
			else:
				dmg_str = " (%d)" % intent.damage
		var line: String = "%d. %s · %s%s" % [index + 1, actor_name(controller, intent.source_actor_id), action_name(intent.action_id), dmg_str]
		var text_col: Color = P.TEXT_FAINT if intent.state == IntentScript.IntentState.ACTIVE else P.TEXT_DISABLED
		canvas.draw_string(font, Vector2(rect.position.x + 28.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 38.0, 13, text_col)
		y += 23.0


static func _draw_enemy_inspector_card(canvas: CanvasItem, font: Font, controller, fx_state: Dictionary) -> void:
	var target_enemy = _pick_inspected_enemy(controller, fx_state)
	if target_enemy == null:
		return

	var rect := P.ENEMY_INFO_RECT
	_draw_card(canvas, rect, Color(0.13, 0.14, 0.17, 0.95), P.ENEMY_OUTLINE)

	# Enemy portrait + name + HP
	var p_rect := Rect2(rect.position + Vector2(12.0, 12.0), Vector2(62.0, 62.0))
	canvas.draw_rect(p_rect, Color(0.09, 0.10, 0.12), true)
	var tex: Texture2D = BoardObjectsViewScript._load_cached_texture(PORTRAIT_DIR + String(target_enemy.archetype) + ".png")
	if tex != null:
		canvas.draw_texture_rect(tex, p_rect, false)
	canvas.draw_rect(p_rect, P.ENEMY_OUTLINE, false, 1.5)

	var ix: float = p_rect.end.x + 10.0
	canvas.draw_string(font, Vector2(ix, rect.position.y + 26.0), actor_name(controller, target_enemy.actor_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.TEXT)
	canvas.draw_string(font, Vector2(ix, rect.position.y + 46.0), "生命 %d/%d" % [target_enemy.health, target_enemy.max_health], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.WARN)
	canvas.draw_string(font, Vector2(ix, rect.position.y + 64.0), "攻%d 防%d 抗%d" % [target_enemy.attack, target_enemy.defense, target_enemy.magic_resistance], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TEXT_MUTED)
	if target_enemy.skill_charge_max > 0:
		var full_c: bool = target_enemy.skill_charge >= target_enemy.skill_charge_max
		var c_str: String = "技能充能 %d / %d%s" % [target_enemy.skill_charge, target_enemy.skill_charge_max, " (已满!)" if full_c else " (随你耗AP充能)"]
		canvas.draw_string(font, rect.position + Vector2(14.0, 84.0), c_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TELEGRAPH_CHARGE_LINE if full_c else P.GOLD_LIGHT)
	if not target_enemy.stolen_equipment.is_empty():
		var eq_names: Array[String] = []
		for eq in target_enemy.stolen_equipment:
			eq_names.append(str(eq.get("name", "")))
		canvas.draw_string(font, rect.position + Vector2(14.0, 212.0), "已夺装备：" + "、".join(eq_names), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 11, P.GOLD_PALE)

	# Divider
	canvas.draw_line(rect.position + Vector2(12.0, 92.0), rect.position + Vector2(rect.size.x - 12.0, 92.0), P.PANEL_BORDER, 1.0)

	# Enemy active skill intent & tactical counterplay hint
	var active_intent = null
	for intent in controller.intents:
		if intent.source_actor_id == target_enemy.actor_id and intent.state == IntentScript.IntentState.ACTIVE:
			active_intent = intent
			break

	canvas.draw_string(font, rect.position + Vector2(14.0, 108.0), "本回合技能预告", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TEXT_DIM)
	if active_intent != null:
		var a_col: Color = _intent_color(active_intent.action_id)
		var skill_title: String = action_name(active_intent.action_id)
		if active_intent.damage > 0:
			if _is_shield_action(active_intent.action_id):
				skill_title += "  ·  %d 护盾" % active_intent.damage
			elif active_intent.action_id == "rot_curse":
				# The payload is a defence cut, not damage; calling it 伤害
				# would tell the player to expect health loss that never comes.
				skill_title += "  ·  降防 %d" % active_intent.damage
			else:
				skill_title += "  ·  %d 伤害" % active_intent.damage
		canvas.draw_string(font, rect.position + Vector2(14.0, 132.0), skill_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, a_col)
		_draw_wrapped(canvas, font, action_description(active_intent.action_id), rect.position + Vector2(14.0, 156.0), rect.size.x - 28.0, 13, P.TEXT_BODY, 3)
	else:
		canvas.draw_string(font, rect.position + Vector2(14.0, 132.0), "本回合暂无攻击意图", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_DIM)


static func _pick_inspected_enemy(controller, fx_state: Dictionary):
	if fx_state.has("hover_cell"):
		var hcell: Vector2i = fx_state["hover_cell"]
		for actor_id in controller.actors:
			var a = controller.actors[actor_id]
			if a.team == "enemy" and a.is_alive() and a.cell == hcell:
				return a
	for intent in controller.intents:
		if intent.state == IntentScript.IntentState.ACTIVE:
			var src = controller.get_actor(intent.source_actor_id)
			if src != null and src.team == "enemy" and src.is_alive():
				return src
	for actor_id in controller.actors:
		var a = controller.actors[actor_id]
		if a.team == "enemy" and a.is_alive():
			return a
	return null


static func _draw_card(canvas: CanvasItem, rect: Rect2, bg: Color, border: Color) -> void:
	canvas.draw_rect(rect, bg, true)
	canvas.draw_rect(rect, border, false, 1.5)


static func _intent_color(action_id: String) -> Color:
	match action_id:
		"charged_strike":
			return P.TELEGRAPH_CHARGE_LINE
		"aimed_shot", "light_shot":
			return P.TELEGRAPH_SHOT_LINE
		"ground_pulse", "echo_bolt":
			return P.TELEGRAPH_PULSE_LINE
		"blight_field":
			return P.HAZARD_BLIGHT_LINE
		"spring_bloom":
			return P.HAZARD_SPRING_LINE
		"sakura_shock":
			return P.TELEGRAPH_CHARGE_LINE
		"lock_on", "locked_shot":
			return P.TELEGRAPH_SHOT_LINE
		"shadow_raid":
			return P.TELEGRAPH_CHARGE_LINE
		"rot_curse":
			return P.TELEGRAPH_PULSE_LINE
		"basic_melee":
			return P.RING_MELEE
		"pursuit":
			return P.GOLD
		_:
			return P.TEXT_DIM


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


static func actor_name(controller, actor_id: String) -> String:
	var definition = CharacterCatalogScript.get_definition(actor_id)
	if definition != null:
		return definition.display_name_zh
	var unit = null if controller == null else controller.get_actor(actor_id)
	if unit != null:
		var enemy = EnemyCatalogScript.get_definition(String(unit.archetype))
		if enemy != null and not enemy.display_name_zh.is_empty():
			return enemy.display_name_zh
		if not String(unit.display_name_zh).is_empty():
			return String(unit.display_name_zh)
	return "未知单位"


## Actions whose integer payload is a shield amount rather than damage.
static func _is_shield_action(action_id: String) -> bool:
	return action_id in ["ward_ally", "ward_stance"]


static func action_name(action_id: String) -> String:
	match action_id:
		"charged_strike":
			return "重戟横扫"
		"basic_melee":
			return "近战挥击"
		"pursuit":
			return "逼近追击"
		"aimed_shot":
			return "贯通狙击"
		"light_shot":
			return "轻矢点射"
		"ground_pulse":
			return "地脉脉冲"
		"echo_bolt":
			return "回声弹"
		"ward_ally":
			return "古木壁垒"
		"ward_stance":
			return "结界守护"
		"blight_field":
			return "樱落领域"
		"spring_bloom":
			return "春痕绽放"
		"sakura_shock":
			return "樱庭震荡"
		"lock_on":
			return "百花锁命"
		"locked_shot":
			return "锁命箭"
		"shadow_raid":
			return "逐影突袭"
		"rot_curse":
			return "腐樱诅咒"
		"wait":
			return "待机观察"
		_:
			return action_id


static func action_description(action_id: String) -> String:
	match action_id:
		"charged_strike":
			return "锁定面前 3×2（6 格）大范围横扫重击！必须撤出红区，或举起「誓盾庇护」硬扛。"
		"basic_melee":
			return "锁定相邻 1 格重斩！走离该格，或用「誓刃」击退先锋即可让其挥空。"
		"pursuit":
			return "本回合向你逼近占位，下一回合将展开攻击。趁机抢占先手或保持距离。"
		"aimed_shot":
			return "【满充能技】沿正交或对角直线穿透 3 格重狙！走出射界，或击退偏移其瞄准线。"
		"light_shot":
			return "沿正交或对角直线单格点射，走离青框即可躲避。"
		"ground_pulse":
			return "【满充能技】锁定十字 5 格紫框爆破！撤出全部紫格即可躲避。"
		"echo_bolt":
			return "锁定单格释放回声弹，走离紫框即可躲避。"
		"ward_ally":
			return "为 2 格内一名普通同伴套上 500 护盾。先拆掉被保护的对象，或让它与守卫拉开距离。"
		"ward_stance":
			return "【满充能技】为自己升起护盾，每个存活结界节点都会让它更厚。先拆节点，再决战。"
		"blight_field":
			return "【满充能技】三格樱落斩；被斩过的地格化为凋零，站上去或走进去都会持续受伤两回合。"
		"spring_bloom":
			return "【满充能技】三格春痕爆发，并在原地留下残春；残春不挡路，但每一回合都会咬人。"
		"sakura_shock":
			return "【满充能技】预告相邻三格震荡；离开这三格就不会被震到。"
		"lock_on":
			return "【满充能技】在目标身上留下锁命印记；下一敌方阶段才射出强化箭。跑出 6 格或断开视线即可取消。"
		"locked_shot":
			return "锁命箭已上弦：追踪被标记的目标，走出射程或借障碍断线才会落空。"
		"shadow_raid":
			return "【满充能技】沿青色路径突进最多 3 格，落点相邻后斩击；离开红色落点即可让它挥空。"
		"rot_curse":
			return "【满充能技】剥离目标 100 防御，持续到下一敌方阶段结束；不叠加，只会刷新时长。"
		"wait":
			return "当前无合法目标，原地待机。"
		_:
			return "敌方正在准备行动。"
