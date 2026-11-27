class_name SkillBarView
extends RefCounted

## Horizontal bottom skill dock + End Turn button.
## Owns skill_rect(), so hit testing and drawing share one geometry.

const P = preload("res://scripts/ui/theme_palette.gd")
const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")

static func full_description(skill_id: StringName) -> String:
	var skill = SkillRegistryScript.get_skill(skill_id)
	if skill == null:
		return ""
	return "【%s · %d AP】%s" % [skill.display_name_zh, skill.ap_cost, skill.description_zh]


static func hint_for(skill) -> String:
	if skill.shape == SkillDefinitionScript.SHAPE_FAN:
		return "点地格定向 · 面前 %d×%d · %d 段" % [skill.shape_width, skill.shape_depth, skill.hits]
	if skill.shape == SkillDefinitionScript.SHAPE_CROSS:
		return "十字 %d 格 · %d 段" % [skill.max_range, skill.hits]
	if skill.target_mode == SkillDefinitionScript.TARGET_SELF:
		return "自身周围 %d 格" % skill.max_range if skill.max_range > 0 else "自身施放"
	if skill.target_mode == SkillDefinitionScript.TARGET_SELF_AND_ALLY:
		return "自己/友军 · %d 格" % skill.max_range
	return "%d–%d 格 · %d%% ATK" % [skill.min_range, skill.max_range, roundi(skill.damage_multiplier * 100.0)]


static func build_entries(controller) -> Array:
	var entries: Array = []
	var character_id := String(controller.active_character_id)
	for skill in SkillRegistryScript.skills_for_character(character_id):
		if skill.is_passive:
			continue
		entries.append(_entry(
			skill.skill_id,
			skill.display_name_zh,
			hint_for(skill),
			skill.ap_cost,
			_mode_for(skill.target_mode),
			skill.min_range,
			skill.max_range,
			skill.slot
		))
	return entries


static func _mode_for(target_mode: StringName) -> String:
	if target_mode == SkillDefinitionScript.TARGET_ACTOR:
		return "actor"
	if target_mode == SkillDefinitionScript.TARGET_SELF_AND_ALLY:
		return "ally"
	if target_mode == SkillDefinitionScript.TARGET_CELL:
		return "cell"
	return "self"


static func _entry(
	skill_id: StringName,
	display_name: String,
	hint: String,
	ap_cost: int,
	mode: String,
	min_range: int,
	max_range: int,
	slot: StringName = &""
) -> Dictionary:
	return {
		"id": String(skill_id),
		"name": display_name,
		"hint": hint,
		"cost": ap_cost,
		"mode": mode,
		"min_range": min_range,
		"max_range": max_range,
		"slot": String(slot),
	}


static func is_affordable(controller, skill: Dictionary) -> bool:
	if controller.ap == null:
		return false
	# Nothing is castable before the battle starts: showing a lit skill bar during
	# deployment invites a click that can only be refused.
	if controller.phase == controller.BattlePhase.DEPLOY:
		return false
	if not controller.ap.can_spend(int(skill["cost"])):
		return false
	if str(skill.get("slot", "")) == "ultimate":
		var caster = controller.get_active_character()
		return caster != null and caster.ultimate_energy >= caster.ultimate_energy_max
	return true


static func skill_rect(index: int) -> Rect2:
	return Rect2(
		P.SKILL_FIRST_X + float(index) * (P.SKILL_BTN_W + P.SKILL_BTN_GAP),
		P.SKILL_BAR_Y,
		P.SKILL_BTN_W,
		P.SKILL_BTN_H
	)


static func draw(canvas: CanvasItem, controller, skill_bar: Array, selected_skill: int, hovered_skill: int = -1) -> void:
	var font := ThemeDB.fallback_font

	for index in range(skill_bar.size()):
		_draw_skill(canvas, font, controller, skill_bar, index, selected_skill)

	# Full detail tooltip bar cleanly above the skill dock when hovering or selecting a skill
	var inspect_idx: int = hovered_skill if hovered_skill >= 0 else selected_skill
	if inspect_idx >= 0 and inspect_idx < skill_bar.size():
		var sk: Dictionary = skill_bar[inspect_idx]
		var desc: String = full_description(StringName(str(sk["id"])))
		var tip_rect := Rect2(P.SKILL_FIRST_X, P.SKILL_BAR_Y - 36.0, P.END_TURN_RECT.end.x - P.SKILL_FIRST_X, 28.0)
		canvas.draw_rect(tip_rect, Color(0.10, 0.12, 0.15, 0.94), true)
		canvas.draw_rect(tip_rect, P.GOLD, false, 1.2)
		canvas.draw_string(font, tip_rect.position + Vector2(12.0, 19.0), desc, HORIZONTAL_ALIGNMENT_LEFT, tip_rect.size.x - 24.0, 13, P.TEXT)

	# §11.1: the same button carries the deployment confirmation, because it is
	# the same verb at that moment - "I am done with this phase".
	var deploying: bool = controller.phase == controller.BattlePhase.DEPLOY
	var can_end: bool = controller.phase == controller.BattlePhase.PLAYER or (deploying and controller.all_deployed())
	var end_color := P.BUTTON_BG if can_end else P.BUTTON_BG_DISABLED
	var end_label := "确认部署" if deploying else "结束回合"
	var end_hint := "[确认后开战]" if deploying else "[空格 / Enter]"
	canvas.draw_rect(P.END_TURN_RECT, end_color, true)
	canvas.draw_rect(P.END_TURN_RECT, P.BUTTON_BORDER if can_end else P.PANEL_BORDER_DISABLED, false, 2.0)
	canvas.draw_string(font, P.END_TURN_RECT.position + Vector2(46.0, 44.0), end_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.BUTTON_TEXT if can_end else P.TEXT_DISABLED)
	canvas.draw_string(font, P.END_TURN_RECT.position + Vector2(48.0, 68.0), end_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.GOLD_PALE if can_end else P.TEXT_DISABLED)


static func _draw_skill(canvas: CanvasItem, font: Font, controller, skill_bar: Array, index: int, selected_skill: int) -> void:
	var skill: Dictionary = skill_bar[index]
	var base_rect := skill_rect(index)
	var affordable: bool = is_affordable(controller, skill)
	var is_selected: bool = index == selected_skill and str(skill["mode"]) != "self"

	# Slight upward lift when selected (tactile card feel)
	var rect := Rect2(base_rect.position + Vector2(0.0, -5.0 if is_selected else 0.0), base_rect.size)

	var bg := P.PANEL_SELECTED if is_selected else P.PANEL
	var border := P.GOLD_LIGHT if is_selected else P.PANEL_BORDER
	if not affordable:
		bg = P.PANEL_DISABLED
		border = P.PANEL_BORDER_DISABLED
	canvas.draw_rect(rect, bg, true)
	canvas.draw_rect(rect, border, false, 2.2 if is_selected else 1.2)

	# Hotkey badge [1]..[4] at top-left
	var key_rect := Rect2(rect.position + Vector2(8.0, 8.0), Vector2(20.0, 20.0))
	canvas.draw_rect(key_rect, P.GOLD if is_selected else Color(0.11, 0.13, 0.16), true)
	canvas.draw_rect(key_rect, border, false, 1.0)
	canvas.draw_string(font, key_rect.position + Vector2(6.0, 15.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TEXT_ON_DARK if is_selected else P.TEXT_MUTED)

	# AP cost badge at top-right
	var cost_label := "%d AP" % int(skill["cost"])
	canvas.draw_string(font, rect.position + Vector2(rect.size.x - 42.0, 23.0), cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.GOLD_LIGHT if affordable else P.TEXT_DISABLED)

	var text_color := P.BUTTON_TEXT if affordable else P.TEXT_DISABLED
	canvas.draw_string(font, rect.position + Vector2(36.0, 24.0), str(skill["name"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 80.0, 16, text_color)
	canvas.draw_string(font, rect.position + Vector2(10.0, 52.0), str(skill["hint"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 12, P.TEXT_MUTED if affordable else P.TEXT_DISABLED)
	var mode_tag: String = {"actor": "点敌人施放", "ally": "点自己/友军施放", "cell": "点地格施放（可空地）"}.get(str(skill["mode"]), "点击即生效")
	canvas.draw_string(font, rect.position + Vector2(10.0, 72.0), mode_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.GOLD if is_selected else P.TEXT_DIM)
