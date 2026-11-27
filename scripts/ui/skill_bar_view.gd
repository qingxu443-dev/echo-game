class_name SkillBarView
extends RefCounted

## Into-the-Breach style horizontal bottom skill dock + End Turn button.
## Owns skill_rect(), so hit testing and drawing share one geometry.

const P = preload("res://scripts/ui/theme_palette.gd")
const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")

const SKILL_HINTS := {
	&"oathblade": "相邻 · 击退 1 格 / 撞击",
	&"oathkeeper_judgment_mark": "1–4 格 · 轻伤 + 易伤 30%",
	&"oath_shield": "瞬发 · 650 护盾",
	&"absolute_guard": "2 AP + 4 能 · 周围击退",
	&"sakura_pierce_blossom": "相邻 · 100% ATK · 施加残香",
	&"sakura_flowing_wind": "突进 2 格 · 80% ATK · 施加残香",
	&"sakura_falling_petals": "面前 3×2 · 三段 · 每段 30% ATK",
	&"sakura_endless_fragrance": "2 AP + 5 能量 · 十字四段",
}

const SKILL_FULL_DESC := {
	&"oathblade": "【誓刃 · 1 AP】对相邻 1 格敌人造成 100% 攻击伤害并击退 1 格；撞墙或撞怪额外造成 450 真实伤害。",
	&"oathkeeper_judgment_mark": "【裁决印记 · 1 AP】对 1–4 格直线/斜线敌人造成 55% 攻击轻伤，并施加易伤（目标下次受伤 +30%）。",
	&"oath_shield": "【誓盾庇护 · 1 AP】一键瞬发，获得 650 护盾（每层守誓额外 +100 盾），持续至下回合开始。",
	&"absolute_guard": "【绝对裁决 · 2 AP + 4 能量】对自身周围 1 格（八方向）所有敌人造成 130% 攻击重击并击退 1 格（可撞墙）。",
	&"sakura_pierce_blossom": "【穿花 · 1 AP】对相邻 1 格敌人造成 100% 攻击物理伤害，命中后施加残香。",
	&"sakura_flowing_wind": "【流风 · 1 AP】朝指定方向突进至多 2 格，对一名相邻敌人造成 80% 攻击伤害并施加残香。",
	&"sakura_falling_petals": "【落英 · 2 AP】对面前 3×2 区域内的敌人三段斩击，每段 30% 攻击，命中后施加残香。",
	&"sakura_endless_fragrance": "【无尽芳华 · 2 AP + 5 能量】以自身为中心的十字四段斩击（20/20/20/40% 攻击），每层剑意使终结斩 +5%。",
}


static func build_entries(controller) -> Array:
	var entries: Array = []
	var character_id := String(controller.active_character_id)
	for skill in SkillRegistryScript.skills_for_character(character_id):
		if skill.is_passive:
			continue
		entries.append(_entry(
			skill.skill_id,
			skill.display_name_zh,
			String(SKILL_HINTS.get(skill.skill_id, skill.description_zh)),
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
		var desc: String = String(SKILL_FULL_DESC.get(StringName(str(sk["id"])), str(sk["hint"])))
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
	var mode_tag: String = "点敌人施放" if str(skill["mode"]) == "actor" else ("点自身施放" if str(skill["mode"]) == "ally" else "点击即生效")
	canvas.draw_string(font, rect.position + Vector2(10.0, 72.0), mode_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.GOLD if is_selected else P.TEXT_DIM)
