class_name EnemySkillCatalog
extends RefCounted

## 敌人全部招式的参数表。intent_planner 只读这里，不再自带数字。
##
## 为什么要有这张表：规划器原本在文件顶部摆了 24 个 const，倍率、射程、
## 地格比例混在一起，和「决策逻辑」和「几何形状」缠在同一个文件里。调一次
## 平衡要改代码 + 重跑全量 + 重新提交；现在改这里一行，行为和测试都跟着走。
##
## 表里没有的 action_id 会被 get() 拒绝并报错，而不是悄悄退化成默认近战——
## 一份 .tres 写了 `actions = ["sakura_shok"]` 这种错字，应该在第一次规划时
## 就炸，而不是让敌人站着不动。

const DefinitionScript = preload("res://scripts/battle/enemy_skill_definition.gd")

static var _skills: Dictionary = {}


static func get_skill(action_id: StringName):
	_ensure_loaded()
	var found = _skills.get(String(action_id))
	if found == null:
		push_error("EnemySkillCatalog: unknown action '%s' (known: %s)" % [String(action_id), ", ".join(_skills.keys())])
	return found


static func has(action_id: StringName) -> bool:
	_ensure_loaded()
	return _skills.has(String(action_id))


static func all_ids() -> Array:
	_ensure_loaded()
	return _skills.keys()


static func is_move(action_id: StringName) -> bool:
	var spec = get_skill(action_id)
	return spec != null and spec.payload == DefinitionScript.PAYLOAD_NONE and spec.move_steps > 0


static func _ensure_loaded() -> void:
	if not _skills.is_empty():
		return
	# 通用招式：任何会用这些 action 的档案共享同一套参数。
	_register(&"charged_strike", "蓄力横扫", DefinitionScript.PAYLOAD_DAMAGE, 1.5, "physical", 1, 2, true, 0)
	_register(&"basic_melee", "近战斩击", DefinitionScript.PAYLOAD_DAMAGE, 0.8, "physical", 1, 1, false, 1)
	_register(&"pursuit", "追击", DefinitionScript.PAYLOAD_NONE, 0.0, "physical", 0, 1, false, 2)
	_register(&"aimed_shot", "贯通狙击", DefinitionScript.PAYLOAD_DAMAGE, 1.35, "physical", 2, 6, true, 2).reposition_min_range = 3
	_register(&"light_shot", "点射", DefinitionScript.PAYLOAD_DAMAGE, 0.75, "physical", 2, 6, false, 2)
	_register(&"ground_pulse", "裂地脉冲", DefinitionScript.PAYLOAD_DAMAGE, 1.15, "magical", 2, 4, false, 1)
	_register(&"echo_bolt", "回声弹", DefinitionScript.PAYLOAD_DAMAGE, 0.7, "magical", 2, 4, false, 1)

	# 精英专属（§14）。
	_register(&"ward_ally", "古木壁垒", DefinitionScript.PAYLOAD_SHIELD, 0.0, "physical", 0, 2, true, 0)
	_register(&"ward_stance", "结界守护", DefinitionScript.PAYLOAD_SHIELD, 0.0, "physical", 0, 0, true, 0)
	_register(&"lock_on", "锁命", DefinitionScript.PAYLOAD_MARK, 0.0, "physical", 2, 6, true, 0)
	_register(&"locked_shot", "锁命箭", DefinitionScript.PAYLOAD_DAMAGE, 1.15, "physical", 1, 6, false, 0)
	_register(&"shadow_raid", "逐影突袭", DefinitionScript.PAYLOAD_DAMAGE, 1.05, "physical", 2, 4, true, 0).move_steps = 3
	_register(&"rot_curse", "腐樱诅咒", DefinitionScript.PAYLOAD_DEFENCE_CUT, 0.0, "magical", 1, 4, true, 0)

	# Boss 招牌（§15）。三条都是「范围 3 个相邻地格」，差别只在站位与地格。
	var blight = _register(&"blight_field", "樱落领域", DefinitionScript.PAYLOAD_DAMAGE, 1.0, "physical", 1, 2, true, 0)
	blight.hazard_kind = "blight"
	blight.hazard_multiplier = 0.25
	blight.hazard_duration_turns = 2
	var bloom = _register(&"spring_bloom", "春痕绽放", DefinitionScript.PAYLOAD_DAMAGE, 0.75, "magical", 2, 5, true, 1)
	bloom.hazard_kind = "lingering_spring"
	bloom.hazard_multiplier = 0.2
	bloom.hazard_duration_turns = 2
	_register(&"sakura_shock", "樱庭震荡", DefinitionScript.PAYLOAD_DAMAGE, 0.75, "physical", 1, 2, true, 0)

	for action_id in _skills:
		var spec = _skills[action_id]
		if not spec.is_valid():
			push_error("EnemySkillCatalog: invalid definition for '%s'" % action_id)


static func _register(
	action_id: StringName,
	label_zh: String,
	payload: String,
	multiplier: float,
	damage_type: String,
	min_range: int,
	max_range: int,
	requires_charge: bool,
	priority: int
):
	var spec = DefinitionScript.new()
	spec.action_id = action_id
	spec.label_zh = label_zh
	spec.payload = payload
	spec.damage_multiplier = multiplier
	spec.damage_type = damage_type
	spec.min_range = min_range
	spec.max_range = max_range
	spec.requires_full_charge = requires_charge
	spec.execution_priority = priority
	_skills[String(action_id)] = spec
	return spec
