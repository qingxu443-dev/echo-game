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
	p_damage_type: String = "physical"
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
