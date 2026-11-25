class_name OathkeeperV2SkillCatalog
extends RefCounted

const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")
const CharacterScript = preload("res://scripts/battle/character_definition.gd")


static func create_prototype_skills() -> Array[SkillDefinition]:
	var skills: Array[SkillDefinition] = []
	skills.append(_make_skill(&"oathkeeper_judgment_mark", "裁决印记", "消耗 1 AP；对 1–4 格内单个敌人造成 DEF×0.8 物理伤害并施加印记。", 1, SkillDefinitionScript.TARGET_ACTOR, 1, 4, SkillDefinitionScript.DAMAGE_PHYSICAL, 0.8, &"oathkeeper_mark", 1))
	skills.append(_make_skill(&"oath_shield", "誓盾庇护", "消耗 1 AP；为瑟弗林与一名两格内友军施加 DEF 系护盾；可救起倒地友军，回复等同护盾强度的生命（每名每关一次）。", 1, SkillDefinitionScript.TARGET_SELF_AND_ALLY, 0, 2, SkillDefinitionScript.DAMAGE_NONE, 0.0, &"oath_shield", 2))
	# §15 gives every character a normal attack. Sevrin's was removed from the UI
	# when the V2 kit landed; this puts it back at its designated slot, adjacent
	# and 1.0x attack, resolved by the shared basic-attack executor.
	skills.append(_make_skill(&"oathblade", "誓刃", "消耗 1 AP；对相邻敌人造成 100% ATK 物理伤害。", 1, SkillDefinitionScript.TARGET_ACTOR, 1, 1, SkillDefinitionScript.DAMAGE_PHYSICAL, 1.0, &"oathblade", 0))
	skills.append(_make_skill(&"absolute_guard", "绝对守护", "消耗 2 AP 与 5 点终极能量；嘲讽并反击。", 2, SkillDefinitionScript.TARGET_SELF, 0, 2, SkillDefinitionScript.DAMAGE_NONE, 0.0, &"absolute_guard", 1))
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
