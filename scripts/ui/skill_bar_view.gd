class_name SkillBarView
extends RefCounted

## The right column: the four skill buttons, the end-turn button and the control
## hints. Also owns skill_rect(), so hit testing and drawing share one geometry.

const P = preload("res://scripts/ui/theme_palette.gd")
const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const SummonCatalogScript = preload("res://scripts/battle/summon_catalog.gd")

## Short HUD hint lines. Rule-relevant numbers (AP cost, target ranges) are
## intentionally NOT written here: the entries are built from the V2 skill
## catalog, the single source of truth, so a catalog change can never desync
## the skill bar display.
const SKILL_HINTS := {
	&"oathkeeper_judgment_mark": "1–4 格 · DEF×0.8 · 施加标记",
	&"oath_shield": "自身 + 两格内友军 · 护盾",
	&"absolute_guard": "2 AP + 5 能量 · 嘲讽反击",
	&"summon:yu_bubble": "任意敌人 · 现身一击",
	&"oathblade": "相邻 · 100% ATK",
	&"sakura_pierce_blossom": "相邻 · 100% ATK · 施加残香",
	&"sakura_flowing_wind": "突进 2 格 · 80% ATK · 施加残香",
	&"sakura_falling_petals": "面前 3×2 · 三段 · 每段 30% ATK",
	&"sakura_endless_fragrance": "2 AP + 5 能量 · 十字四段",
}

## Three targeting modes, straight from the skill data:
##  - "actor": pick an enemy, then tap it
##  - "ally":  pick a party member (self included), then tap it
##  - "self":  press once, no target
## SELF_AND_ALLY exists in the data and was being flattened into "self", which is
## why Oath Shield could only ever shield Sevrin while its description promised a
## second party member.
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

	# Summons belong to the player, not to a character sheet, so every character
	# offers them. The list comes from data/summons/, and the id is prefixed so the
	# runtime needs one branch for all summons rather than one per summon.
	for summon in SummonCatalogScript.all_definitions():
		var summon_key := StringName("summon:" + String(summon.summon_id))
		var reach: int = controller.grid_size.x + controller.grid_size.y
		var entry: Dictionary = _entry(
			summon_key,
			summon.display_name_zh,
			String(SKILL_HINTS.get(summon_key, summon.description_zh)),
			summon.ap_cost,
			"actor",
			1,
			reach
		)
		entry["summon_id"] = String(summon.summon_id)
		entry["icon"] = summon.icon
		entries.append(entry)
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


## Whether the button may look ready right now: the AP cost, the summon
## cooldown, and - for an ultimate - a full energy bar. Extracted from draw() so
## a suite can assert the rule instead of the pixels, and driven by the slot
## rather than by a skill id, so a second character's ultimate is covered too.
static func is_affordable(controller, skill: Dictionary) -> bool:
	if controller.ap == null:
		return false
	if skill.has("summon_id"):
		if controller.phase != controller.BattlePhase.PLAYER:
			return false
		var summon_remaining: int = controller.summon_cooldown_remaining(StringName(str(skill["summon_id"])))
		# A summon still has to be paid for, even though its data says 0 AP today.
		return summon_remaining <= 0 and controller.ap.can_spend(int(skill["cost"]))
	if not controller.ap.can_spend(int(skill["cost"])):
		return false
	if str(skill.get("slot", "")) == "ultimate":
		var caster = controller.get_active_character()
		return caster != null and caster.ultimate_energy >= P.ULTIMATE_ENERGY_MAX
	return true


static func skill_rect(index: int) -> Rect2:
	return Rect2(P.SKILL_PANEL_X, P.SKILL_FIRST_Y + float(index) * P.SKILL_BTN_STEP, P.SKILL_PANEL_W, P.SKILL_BTN_H)


static func draw(canvas: CanvasItem, controller, skill_bar: Array, selected_skill: int) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, 96), "技能", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT)

	for index in range(skill_bar.size()):
		_draw_skill(canvas, font, controller, skill_bar, index, selected_skill)

	var end_color := P.BUTTON_BG if controller.phase == controller.BattlePhase.PLAYER else P.BUTTON_BG_DISABLED
	canvas.draw_rect(P.END_TURN_RECT, end_color, true)
	canvas.draw_rect(P.END_TURN_RECT, P.BUTTON_BORDER, false, 2.0)
	canvas.draw_string(font, P.END_TURN_RECT.position + Vector2(100.0, 38.0), "结束回合", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.BUTTON_TEXT)

	var hint_y := 496.0
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y), "操作", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.TEXT_DIM)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 22.0), "点格子移动，最多两格直线", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 40.0), "自身技能点一下即生效", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 58.0), "选中技能后，黄圈标出可打目标", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 76.0), "数字键 1–5 施放/选择技能", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 94.0), "Esc / 右键取消目标选择", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)
	canvas.draw_string(font, Vector2(P.SKILL_PANEL_X, hint_y + 112.0), "Tab 切换角色", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_HINT)


static func _draw_skill(canvas: CanvasItem, font: Font, controller, skill_bar: Array, index: int, selected_skill: int) -> void:
	var skill: Dictionary = skill_bar[index]
	var rect := skill_rect(index)
	var affordable: bool = is_affordable(controller, skill)

	var cost_label := "%d AP" % int(skill["cost"])
	var cost_offset: float = 52.0
	var cost_y: float = 30.0
	if skill.has("summon_id"):
		var summon_remaining: int = controller.summon_cooldown_remaining(StringName(str(skill["summon_id"])))
		cost_label = "就绪" if summon_remaining <= 0 else "冷却 %d" % summon_remaining
		cost_offset = 76.0
		# The icon pushes the text block 36 px to the right, so the status label
		# shares the name baseline instead of sitting between the two text rows.
		cost_y = 21.0

	var is_selected: bool = index == selected_skill and str(skill["mode"]) != "self"
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
	if skill.has("icon") and skill["icon"] != null:
		var icon_modulate: Color = Color(1.0, 1.0, 1.0) if affordable else Color(1.0, 1.0, 1.0, 0.45)
		canvas.draw_texture_rect(skill["icon"], Rect2(rect.position + Vector2(8.0, 8.0), Vector2(34.0, 34.0)), false, icon_modulate)
		text_x = 50.0

	canvas.draw_string(font, rect.position + Vector2(text_x, 21.0), skill_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, text_color)
	canvas.draw_string(font, rect.position + Vector2(text_x, 39.0), str(skill["hint"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_color)
	canvas.draw_string(font, rect.position + Vector2(rect.size.x - cost_offset, cost_y), cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.GOLD_LIGHT if affordable else P.TEXT_DISABLED)
