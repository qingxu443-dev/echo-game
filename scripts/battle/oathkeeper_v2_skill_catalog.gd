class_name OathkeeperV2SkillCatalog
extends RefCounted

const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")
const CharacterScript = preload("res://scripts/battle/character_definition.gd")


static func create_prototype_skills() -> Array[SkillDefinition]:
	var skills: Array[SkillDefinition] = []
	skills.append(_make_skill(&"oathkeeper_judgment_mark", "裁决印记", "消耗 1 AP；对 1–4 格内单个敌人造成 DEF×0.8 物理伤害并施加印记。", 1, SkillDefinitionScript.TARGET_ACTOR, 1, 4, SkillDefinitionScript.DAMAGE_PHYSICAL, 0.8, &"oathkeeper_mark", 1))
	skills.append(_make_skill(&"oath_shield", "誓盾庇护", "消耗 1 AP；为瑟弗林与一名两格内友军施加 DEF 系护盾。", 1, SkillDefinitionScript.TARGET_SELF_AND_ALLY, 0, 2, SkillDefinitionScript.DAMAGE_NONE, 0.0, &"oath_shield", 2))
	skills.append(_make_skill(&"absolute_guard", "绝对守护", "消耗 2 AP 与 5 点终极能量；嘲讽并反击。", 2, SkillDefinitionScript.TARGET_SELF, 0, 2, SkillDefinitionScript.DAMAGE_NONE, 0.0, &"absolute_guard", 1))
	skills[0].executor_id = &"oathkeeper_judgment_mark"
	skills[1].executor_id = &"oath_shield"
	skills[2].executor_id = &"absolute_guard"
	skills[0].slot = CharacterScript.SLOT_ACTIVE_ONE
	skills[1].slot = CharacterScript.SLOT_ACTIVE_TWO
	skills[2].slot = CharacterScript.SLOT_ULTIMATE
	return skills


static func create_passive_skill() -> SkillDefinition:
	var skill: SkillDefinition = SkillDefinitionScript.new()
	skill.skill_id = &"oath_vow"
	skill.display_name_zh = "不屈誓约"
	skill.description_zh = "敌方主动攻击命中瑟弗林时获得守誓，最多三层；誓盾庇护消耗全部层数。"
	skill.ap_cost = 0
	skill.target_mode = SkillDefinitionScript.TARGET_SELF
	skill.effect_id = &"oath_vow"
	skill.is_passive = true
	skill.slot = CharacterScript.SLOT_PASSIVE
	return skill


static func _make_skill(p_id: StringName, p_name: String, p_description: String, p_ap: int, p_target: StringName, p_min: int, p_max: int, p_damage_type: StringName, p_multiplier: float, p_effect: StringName, p_duration: int) -> SkillDefinition:
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
	skill.effect_id = p_effect
	skill.duration_player_phases = p_duration
	return skill
