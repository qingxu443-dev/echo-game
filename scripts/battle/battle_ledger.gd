class_name BattleLedger
extends RefCounted

## 单场战斗的机制记账容器。
##
## 这些字段原本平铺在 BattleController 上（11 个字典 + 1 个整数），
## 由战斗流、伤害管线、技能效果、意图解析、召唤服务和棋盘视图共同读写。
## 收编为一个对象后，controller 只保留"战场状态"，机制账本归本类所有。
##
## 迁移约定：字段名、键语义、默认值与旧版逐字一致，调用方只把
## `battle.xxx` / `controller.xxx` 换成 `battle.ledger.xxx` / `controller.ledger.xxx`。

## actor_id -> 最近一次触发地格的玩家回合号（每回合至多一次）。
var hazard_trigger_turn: Dictionary = {}
## summon_id -> 最近一次召唤的玩家回合号。缺省表示从未使用。
var summon_last_used_turn: Dictionary = {}
## actor_id -> 誓约护盾到期后的玩家回合号。
var oath_shield_expiry_turn: Dictionary = {}
## 本场已被誓约护盾复活过的队员 actor_id。
var oath_shield_revived: Dictionary = {}
## 已被"誓约"计入过的敌方意图 id，防止多段攻击重复叠加。
var oath_vow_triggered_intents: Dictionary = {}
## 绝对防御期间成功命中瑟弗林的公开攻击意图 id。
var absolute_guard_hit_intents: Dictionary = {}
## 当前玩家回合内已被反击的敌方 actor_id。
var absolute_guard_countered_enemies: Dictionary = {}
## actor_id -> 职业资源上次结算的回合号。
var resource_gain_turn: Dictionary = {}
## actor_id -> 本回合已消耗的职业资源额度。
var resource_gain_count: Dictionary = {}
## actor_id -> 本回合首次回响返还是否已结算。
var echo_return_gain_turn: Dictionary = {}
## 本回合是否已用掉"回响疾行"的免费移动；-1 表示本回合未用。
var free_move_used_turn: int = -1
var rewards_settled: bool = false
## 同一施法内多段近战命中的去重序号，以及当前回合击杀返 AP 次数。
var pressure_sequence: int = 0
var pressure_refund_turn: int = -1
var pressure_refund_count: int = 0
## Synchronous, non-persistent settlement state for Dest Lee multi-hit chains.
var dest_lee_batch_depth: int = 0
var dest_lee_death_queue: Array[Dictionary] = []
var dest_lee_chain_active: bool = false
var dest_lee_chain_hit_targets: Dictionary = {}


## 每场遭遇开始时清空全部账本。旧版分散在 BattleFlow.start_encounter 的
## 十余处 .clear() 与一次 = -1 中，收口到这里避免漏清。
func reset_for_encounter() -> void:
	hazard_trigger_turn.clear()
	summon_last_used_turn.clear()
	oath_shield_expiry_turn.clear()
	oath_shield_revived.clear()
	oath_vow_triggered_intents.clear()
	absolute_guard_hit_intents.clear()
	absolute_guard_countered_enemies.clear()
	resource_gain_turn.clear()
	resource_gain_count.clear()
	echo_return_gain_turn.clear()
	free_move_used_turn = -1
	rewards_settled = false
	pressure_sequence = 0
	pressure_refund_turn = -1
	pressure_refund_count = 0
	dest_lee_batch_depth = 0
	dest_lee_death_queue.clear()
	dest_lee_chain_active = false
	dest_lee_chain_hit_targets.clear()


## 每个玩家回合开始时只清"每回合一次"的账本；跨回合账本保持不变。
func reset_for_player_turn() -> void:
	absolute_guard_countered_enemies.clear()


## 只读快照，供测试与未来的 UI 诊断使用；返回的是新字典，不共享内部引用。
func snapshot() -> Dictionary:
	return {
		"hazard_trigger_turn": hazard_trigger_turn.duplicate(),
		"summon_last_used_turn": summon_last_used_turn.duplicate(),
		"oath_shield_expiry_turn": oath_shield_expiry_turn.duplicate(),
		"oath_shield_revived": oath_shield_revived.duplicate(),
		"oath_vow_triggered_intents": oath_vow_triggered_intents.duplicate(),
		"absolute_guard_hit_intents": absolute_guard_hit_intents.duplicate(),
		"absolute_guard_countered_enemies": absolute_guard_countered_enemies.duplicate(),
		"resource_gain_turn": resource_gain_turn.duplicate(),
		"resource_gain_count": resource_gain_count.duplicate(),
		"echo_return_gain_turn": echo_return_gain_turn.duplicate(),
		"free_move_used_turn": free_move_used_turn,
		"rewards_settled": rewards_settled,
		"pressure_sequence": pressure_sequence,
		"pressure_refund_turn": pressure_refund_turn,
		"pressure_refund_count": pressure_refund_count,
	}
