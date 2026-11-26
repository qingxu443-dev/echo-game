class_name OathkeeperV2SkillCatalog
extends RefCounted

const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")
const CharacterScript = preload("res://scripts/battle/character_definition.gd")


static func create_prototype_skills() -> Array[SkillDefinition]:
	var skills: Array[SkillDefinition] = []
	skills.append(_make_skill(&"oathkeeper_judgment_mark", "裁决印记", "消耗 1 AP；对 1–4 格直线/斜线敌人造成 55% 攻击伤害，并挂易伤印记（下次受伤 +30%）。", 1, SkillDefinitionScript.TARGET_ACTOR, 1, 4, SkillDefinitionScript.DAMAGE_PHYSICAL, 0.55))
	skills.append(_make_skill(&"oath_shield", "誓盾庇护", "消耗 1 AP；瞬发获得 650 护盾（每层守誓额外 +100），持续至下回合开始。", 1, SkillDefinitionScript.TARGET_SELF, 0, 0, SkillDefinitionScript.DAMAGE_NONE, 0.0))
	skills.append(_make_skill(&"oathblade", "誓刃", "消耗 1 AP；对相邻 1 格敌人造成 100% 攻击伤害并击退 1 格，撞墙或撞怪额外造成 450 真实伤害。", 1, SkillDefinitionScript.TARGET_ACTOR, 1, 1, SkillDefinitionScript.DAMAGE_PHYSICAL, 1.0))
	skills.append(_make_skill(&"absolute_guard", "绝对裁决", "消耗 2 AP 与 4 点能量；对自身周围 1 格（八方向）所有敌人造成 130% 攻击重击并击退 1 格。", 2, SkillDefinitionScript.TARGET_SELF, 0, 1, SkillDefinitionScript.DAMAGE_PHYSICAL, 1.3))
	# Assigned by id, not by list position: adding a skill to this catalog must not
	# silently move another skill into the wrong slot or onto the wrong executor.
	_assign(skills, &"oathblade", CharacterScript.SLOT_NORMAL, &"basic_attack")
	_assign(skills, &"oathkeeper_judgment_mark", CharacterScript.SLOT_ACTIVE_ONE, &"oathkeeper_judgment_mark")
	_assign(skills, &"oath_shield", CharacterScript.SLOT_ACTIVE_TWO, &"oath_shield")
	_assign(skills, &"absolute_guard", CharacterScript.SLOT_ULTIMATE, &"absolute_guard")
	return skills


static func _assign(skills: Array[SkillDefinition], skill_id: StringName, slot: StringName, executor_id: StringName) -> void:
	for skill in skills:
		if skill.skill_id == skill_id:
			skill.slot = slot
			skill.executor_id = executor_id
			return


static func create_passive_skill() -> SkillDefinition:
	var skill: SkillDefinition = SkillDefinitionScript.new()
	skill.skill_id = &"oath_vow"
	skill.display_name_zh = "不屈誓约"
	skill.description_zh = "敌方主动攻击命中瑟弗林时获得守誓，最多三层；誓盾庇护消耗全部层数。"
	skill.ap_cost = 0
	skill.target_mode = SkillDefinitionScript.TARGET_SELF
	skill.is_passive = true
	skill.slot = CharacterScript.SLOT_PASSIVE
	return skill


static func _make_skill(p_id: StringName, p_name: String, p_description: String, p_ap: int, p_target: StringName, p_min: int, p_max: int, p_damage_type: StringName, p_multiplier: float) -> SkillDefinition:
	var skill: SkillDefinition = SkillDefinitionScript.new()
	skill.skill_id = p_id
	skill.display_name_zh = p_name
	skill.description_zh = p_description
	skill.ap_cost = p_ap
	skill.target_mode = p_target
	skill.min_range = p_min
	skill.max_range = p_max
	skill.damage_type = p_damage_type
	skill.damage_multiplier = p_multiplier
	return skill
