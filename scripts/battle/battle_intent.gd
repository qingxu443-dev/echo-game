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
## Cells the source must step through BEFORE this action resolves (Into-the-Breach
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
