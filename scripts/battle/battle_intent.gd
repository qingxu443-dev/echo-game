class_name BattleIntent
extends RefCounted

## Immutable-by-convention snapshot used by both telegraph UI and enemy resolution.

enum TargetMode { NONE, ACTOR_LOCKED, TILE_LOCKED, AREA_LOCKED }
enum IntentState { ACTIVE, RESOLVED, CANCELED }

var intent_id: String
var source_actor_id: String
var action_id: String
var target_mode: TargetMode
var target_actor_id: String
var target_cell: Vector2i
var affected_cells: Array[Vector2i]
var damage: int
var damage_type: String = "physical"
var execution_priority: int
var state: IntentState = IntentState.ACTIVE
var cancel_reason: String = ""
## Cells the source must step through BEFORE this action resolves (pre-attack
## reposition). The planner fills it instead of moving the enemy itself, so
## planning stays free of side effects; IntentResolver walks it during the enemy
## phase. Empty for intents that act from where the enemy already stands.
var move_path: Array[Vector2i] = []
## Ground hazard this action leaves behind (凋零 / 残春). Empty `hazard_cells`
## means the action leaves no ground effect, which is every action but the three
## signature ones. The planner pins the damage here so the telegraph can promise
## the same number the resolver applies.
var hazard_cells: Array[Vector2i] = []
var hazard_kind: String = ""
var hazard_damage: int = 0
var hazard_duration_turns: int = 0
## 樱华蓄斩 alone: the telegraph can be broken by control before it resolves.
## A cancelled intent keeps this flag so the log explains why it fizzled.
var interruptible: bool = false


func _init(
	p_intent_id: String,
	p_source_actor_id: String,
	p_action_id: String,
	p_target_mode: TargetMode,
	p_target_actor_id: String = "",
	p_target_cell: Vector2i = Vector2i.ZERO,
	p_affected_cells: Array[Vector2i] = [],
	p_damage: int = 0,
	p_execution_priority: int = 0,
	p_damage_type: String = "physical",
	p_hazard_cells: Array[Vector2i] = [],
	p_hazard_kind: String = "",
	p_hazard_damage: int = 0,
	p_hazard_duration_turns: int = 0
) -> void:
	intent_id = p_intent_id
	source_actor_id = p_source_actor_id
	action_id = p_action_id
	target_mode = p_target_mode
	target_actor_id = p_target_actor_id
	target_cell = p_target_cell
	affected_cells = p_affected_cells.duplicate()
	damage = maxi(0, p_damage)
	execution_priority = p_execution_priority
	damage_type = p_damage_type
	hazard_cells = p_hazard_cells.duplicate()
	hazard_kind = p_hazard_kind
	hazard_damage = maxi(0, p_hazard_damage)
	hazard_duration_turns = maxi(0, p_hazard_duration_turns)


func cancel(reason: String) -> bool:
	if state != IntentState.ACTIVE:
		return false
	state = IntentState.CANCELED
	cancel_reason = reason
	return true


func mark_resolved() -> bool:
	if state != IntentState.ACTIVE:
		return false
	state = IntentState.RESOLVED
	return true


## What this intent would actually cost the actor standing where it lands,
## mitigation and current shield included. Goes through
## BattleActor.preview_damage, which is the same expression the resolver bills
## with, so a telegraph can no longer quote 1688 for a hit that removes 1508.
##
## Shield and debuff payloads (古木壁垒 / 结界守护 / 腐樱诅咒) are not health
## damage - their `damage` field carries a shield or a defence number - so they
## keep the raw value and callers are expected not to ask this for them.
func preview_health_damage(battle) -> int:
	if damage <= 0:
		return 0
	var victim = null
	if not target_actor_id.is_empty() and battle.actors.has(target_actor_id):
		victim = battle.actors[target_actor_id]
	elif not affected_cells.is_empty():
		for actor_id in battle.actors:
			var unit = battle.actors[actor_id]
			if unit.is_alive() and affected_cells.has(unit.cell):
				victim = unit
				break
	if victim == null or not victim.has_method("preview_damage"):
		return damage
	return victim.preview_damage(damage, damage_type)
