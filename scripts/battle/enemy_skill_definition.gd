class_name EnemySkillDefinition
extends Resource

## 一个敌人招式的参数，和玩家侧的 SkillDefinition 对称。
##
## 以前这些数字是 intent_planner.gd 顶部的 24 个常量，调一次平衡要改代码、
## 重跑全量、重新提交。挪到数据对象之后，规划器只负责「这一招现在合不合法」
## 和「几何形状长什么样」，数值本身集中在这里。
##
## 没有放进 .tres 是有意的：玩家侧的 SkillDefinition 也是代码里的目录
## （sakura_skill_catalog.gd），两边保持同一种形态，改起来才不用想两套规则。

## damage：造成伤害（走 DamageTypes）；shield：给友军护盾（damage 字段装盾值）；
## defence_cut：降防（damage 字段装点数）；mark：只为下一段铺垫，本次零伤害；
## none：纯移动或不结算数值。
const PAYLOAD_DAMAGE := "damage"
const PAYLOAD_SHIELD := "shield"
const PAYLOAD_DEFENCE_CUT := "defence_cut"
const PAYLOAD_MARK := "mark"
const PAYLOAD_NONE := "none"

@export var action_id: StringName = &""
@export var label_zh: String = ""
@export var payload: String = PAYLOAD_DAMAGE
## 0 表示「看档案」：有 skill_damage 就用它（§14 要求专属技与基础攻击解耦），
## 否则 attack × 这个倍率。
@export var damage_multiplier: float = 0.0
@export var damage_type: String = "physical"
## 0..0 表示触身（自身格）；min_range 用于近战与「不能贴脸」的远程。
@export var min_range: int = 0
@export var max_range: int = 1
## 远程风筝取位时想保持的距离，和「能不能打到」是两件事：狙击手能打到 2 格，
## 但退到 3 格外才开火。-1 表示沿用 min_range。
@export var reposition_min_range: int = -1
## 专属技靠充能条节流：没满就这一招不可用，满了才能预告。
@export var requires_full_charge: bool = false
## 执行顺序：0 最先，3 最后。同优先级按 y、x 排。
@export var execution_priority: int = 1
## 铺地格（§15）时的地格类型与每跳伤害比例；空串表示不留地格。
@export var hazard_kind: String = ""
@export var hazard_multiplier: float = 0.0
@export var hazard_duration_turns: int = 0
## 带路径的招式（逐影突袭）最多走几格；0 表示不位移。
@export var move_steps: int = 0


func is_valid() -> bool:
	if String(action_id).is_empty():
		return false
	if payload != PAYLOAD_DAMAGE and payload != PAYLOAD_SHIELD \
			and payload != PAYLOAD_DEFENCE_CUT and payload != PAYLOAD_MARK and payload != PAYLOAD_NONE:
		return false
	if damage_multiplier < 0.0 or hazard_multiplier < 0.0:
		return false
	if min_range < 0 or max_range < min_range:
		return false
	if hazard_duration_turns < 0 or move_steps < 0:
		return false
	if not DamageTypes.is_valid(damage_type):
		return false
	return true


## 一个招式的完整说明，给报错和文档用：倍率、射程、载荷一句话说清。
func describe() -> String:
	return "%s(%s, x%.2f, %d-%d, %s)" % [
		String(action_id), payload, damage_multiplier, min_range, max_range, damage_type
	]
