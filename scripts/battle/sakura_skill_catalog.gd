class_name SakuraSkillCatalog
extends RefCounted

## Sakura's kit, from design plan §15 and §18-24.
##
## Values are the approved test baselines. The plan marks Sakura's multipliers as
## a testing baseline rather than a final lock, so they live here rather than
## being spread through the executor.

const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")
const CharacterScript = preload("res://scripts/battle/character_definition.gd")


static func create_skills() -> Array[SkillDefinition]:
	var skills: Array[SkillDefinition] = []

	# 穿花 - normal attack. The plan does not fix its multiplier, so it uses the
	# 1.0 attack baseline that §8's three-to-five-hit pacing assumes.
	skills.append(_make(
		&"sakura_pierce_blossom", "穿花",
		"消耗 1 AP；对相邻敌人造成 100% ATK 物理伤害，命中后施加残香。",
		1, SkillDefinitionScript.TARGET_ACTOR, 1, 1,
		SkillDefinitionScript.DAMAGE_PHYSICAL, 1.0, &"sakura_pierce_blossom",
		CharacterScript.SLOT_NORMAL))

	# 花信 - passive resource track.
	var passive := SkillDefinitionScript.new()
	passive.skill_id = &"sakura_flower_message"
	passive.display_name_zh = "花信"
	passive.description_zh = "被动：攻击与移动积累剑意，满 4 层进入极意。"
	passive.ap_cost = 0
	passive.target_mode = SkillDefinitionScript.TARGET_SELF
	passive.effect_id = &"blade_intent"
	passive.is_passive = true
	passive.slot = CharacterScript.SLOT_PASSIVE
	skills.append(passive)

	# 流风 - 2-cell dash, then a strike on one adjacent enemy.
	skills.append(_make(
		&"sakura_flowing_wind", "流风",
		"消耗 1 AP；朝指定方向突进至多 2 格，对一名邻敌造成 80% ATK 伤害并施加残香。",
		1, SkillDefinitionScript.TARGET_ACTOR, 1, 3,
		SkillDefinitionScript.DAMAGE_PHYSICAL, 0.8, &"sakura_flowing_wind",
		CharacterScript.SLOT_ACTIVE_ONE))

	# 落英 - three segments of 30% each.
	var falling := _make(
		&"sakura_falling_petals", "落英",
		"消耗 2 AP；对面前横 3 格、纵 2 格区域内敌人三段攻击，每段 30% ATK，命中后施加残香。",
		2, SkillDefinitionScript.TARGET_ACTOR, 1, 3,
		SkillDefinitionScript.DAMAGE_PHYSICAL, 0.9, &"sakura_falling_petals",
		CharacterScript.SLOT_ACTIVE_TWO)
	falling.hits = 3
	falling.hit_multipliers = [0.3, 0.3, 0.3]
	falling.shape = SkillDefinitionScript.SHAPE_FAN
	# Owner decision 2026-11-25: the fan became a rectangle in front of Sakura -
	# three cells across and two cells deep. Kept as data so flipping the footprint
	# is an edit rather than a code change.
	falling.shape_width = 3
	falling.shape_depth = 2
	skills.append(falling)

	# 无尽芳华 - cross around Sakura, three 20% cuts and a 40% finisher. Each
	# stack of blade intent lifts the finisher by 5%, and full stacks add 20%.
	var ultimate := _make(
		&"sakura_endless_fragrance", "无尽芳华",
		"消耗 2 AP 与 5 点终极能量；以自身为中心十字范围四段斩击（20/20/20/40% ATK），每层剑意使终结斩 +5%，满层额外 +20%。",
		2, SkillDefinitionScript.TARGET_SELF, 0, 2,
		SkillDefinitionScript.DAMAGE_PHYSICAL, 1.0, &"sakura_endless_fragrance",
		CharacterScript.SLOT_ULTIMATE)
	ultimate.hits = 4
	ultimate.hit_multipliers = [0.2, 0.2, 0.2, 0.4]
	ultimate.shape = SkillDefinitionScript.SHAPE_CROSS
	skills.append(ultimate)

	return skills


static func _make(
	skill_id: StringName,
	display_name: String,
	description: String,
	ap_cost: int,
	target_mode: StringName,
	min_range: int,
	max_range: int,
	damage_type: StringName,
	multiplier: float,
	effect_id: StringName,
	slot: StringName
) -> SkillDefinition:
	var skill: SkillDefinition = SkillDefinitionScript.new()
	skill.skill_id = skill_id
	skill.display_name_zh = display_name
	skill.description_zh = description
	skill.ap_cost = ap_cost
	skill.target_mode = target_mode
	skill.min_range = min_range
	skill.max_range = max_range
	skill.damage_type = damage_type
	skill.damage_multiplier = multiplier
	skill.effect_id = effect_id
	skill.executor_id = effect_id
	skill.slot = slot
	return skill
