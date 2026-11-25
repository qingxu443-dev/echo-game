class_name BattleStatusCollection
extends RefCounted

const BattleStatusScript = preload("res://scripts/battle/battle_status.gd")

## actor_id -> Dictionary(status_id -> BattleStatus)
var _statuses_by_actor: Dictionary = {}


func apply_status(
	status_id: StringName,
	source_actor_id: String,
	target_actor_id: String,
	stacks: int = 1,
	max_stacks: int = 1,
	remaining_triggers: int = -1,
	expiry_boundary: StringName = &"",
	stack_policy: StringName = BattleStatusScript.STACK_REFRESH
) -> bool:
	if status_id == &"" or target_actor_id.is_empty():
		return false
	if stacks <= 0 or max_stacks <= 0 or remaining_triggers < -1:
		return false
	if stack_policy != BattleStatusScript.STACK_REPLACE and stack_policy != BattleStatusScript.STACK_REFRESH and stack_policy != BattleStatusScript.STACK_ADD:
		return false

	var actor_statuses: Dictionary = _get_actor_statuses(target_actor_id)
	var existing = actor_statuses.get(status_id)
	if existing == null:
		var created: BattleStatus = BattleStatusScript.new(
			status_id,
			source_actor_id,
			target_actor_id,
			stacks,
			max_stacks,
			remaining_triggers,
			expiry_boundary
		)
		if not created.is_valid():
			return false
		actor_statuses[status_id] = created
		_statuses_by_actor[target_actor_id] = actor_statuses
		return true

	var current: BattleStatus = existing as BattleStatus
	match stack_policy:
		BattleStatusScript.STACK_REPLACE:
			current.stacks = mini(stacks, max_stacks)
			current.max_stacks = max_stacks
			current.remaining_triggers = remaining_triggers
			current.source_actor_id = source_actor_id
			current.expiry_boundary = expiry_boundary
		BattleStatusScript.STACK_REFRESH:
			current.stacks = mini(current.stacks, max_stacks)
			current.max_stacks = max_stacks
			current.remaining_triggers = remaining_triggers
			current.source_actor_id = source_actor_id
			current.expiry_boundary = expiry_boundary
		BattleStatusScript.STACK_ADD:
			current.max_stacks = max_stacks
			current.stacks = mini(current.stacks + stacks, max_stacks)
			current.remaining_triggers = _refresh_trigger_count(current.remaining_triggers, remaining_triggers)
			current.source_actor_id = source_actor_id
			current.expiry_boundary = expiry_boundary
	_statuses_by_actor[target_actor_id] = actor_statuses
	return true


func has_status(target_actor_id: String, status_id: StringName) -> bool:
	var actor_statuses: Dictionary = _get_actor_statuses(target_actor_id)
	return actor_statuses.has(status_id)


func get_status(target_actor_id: String, status_id: StringName) -> BattleStatus:
	var actor_statuses: Dictionary = _get_actor_statuses(target_actor_id)
	var value = actor_statuses.get(status_id)
	if value == null:
		return null
	return value as BattleStatus


func consume_trigger(target_actor_id: String, status_id: StringName) -> bool:
	var actor_statuses: Dictionary = _get_actor_statuses(target_actor_id)
	var value = actor_statuses.get(status_id)
	if value == null:
		return false
	var status: BattleStatus = value as BattleStatus
	if status.remaining_triggers == 0:
		return false
	if status.remaining_triggers > 0:
		status.remaining_triggers -= 1
		if status.remaining_triggers == 0:
			actor_statuses.erase(status_id)
	_statuses_by_actor[target_actor_id] = actor_statuses
	return true


## Count down every status that uses the enemy-turn clock and drop the ones that
## reach zero. Returns how many were removed.
func tick_enemy_phase() -> int:
	var removed_count: int = 0
	var target_ids: Array[String] = []
	for target_id in _statuses_by_actor.keys():
		target_ids.append(String(target_id))
	for target_id in target_ids:
		var actor_statuses: Dictionary = _get_actor_statuses(target_id)
		var expired: Array[StringName] = []
		for key in actor_statuses.keys():
			var status: BattleStatus = actor_statuses[key] as BattleStatus
			if status.enemy_turns_remaining <= 0:
				continue
			status.enemy_turns_remaining -= 1
			if status.enemy_turns_remaining == 0:
				expired.append(status.status_id)
		for status_id in expired:
			actor_statuses.erase(status_id)
			removed_count += 1
		if actor_statuses.is_empty():
			_statuses_by_actor.erase(target_id)
		else:
			_statuses_by_actor[target_id] = actor_statuses
	return removed_count


func expire_boundary(target_actor_id: String, boundary: StringName) -> int:
	if boundary == &"":
		return 0
	var actor_statuses: Dictionary = _get_actor_statuses(target_actor_id)
	var expired_ids: Array[StringName] = []
	for key in actor_statuses.keys():
		var status: BattleStatus = actor_statuses[key] as BattleStatus
		if status.expiry_boundary == boundary:
			expired_ids.append(status.status_id)
	for status_id in expired_ids:
		actor_statuses.erase(status_id)
	if actor_statuses.is_empty():
		_statuses_by_actor.erase(target_actor_id)
	else:
		_statuses_by_actor[target_actor_id] = actor_statuses
	return expired_ids.size()


func expire_all_boundary(boundary: StringName) -> int:
	if boundary == &"":
		return 0
	var target_ids: Array[String] = []
	for target_id in _statuses_by_actor.keys():
		target_ids.append(String(target_id))
	var removed_count: int = 0
	for target_id in target_ids:
		removed_count += expire_boundary(target_id, boundary)
	return removed_count


func defer_status_boundary(status_id: StringName, from_boundary: StringName, to_boundary: StringName) -> int:
	if status_id == &"" or from_boundary == &"" or to_boundary == &"" or from_boundary == to_boundary:
		return 0
	var deferred_count: int = 0
	for actor_statuses in _statuses_by_actor.values():
		if not actor_statuses is Dictionary:
			continue
		var value = actor_statuses.get(status_id)
		if value == null:
			continue
		var status: BattleStatus = value as BattleStatus
		if status.expiry_boundary == from_boundary:
			status.expiry_boundary = to_boundary
			deferred_count += 1
	return deferred_count


func clear_all() -> int:
	var removed_count: int = 0
	for actor_statuses in _statuses_by_actor.values():
		if actor_statuses is Dictionary:
			removed_count += actor_statuses.size()
	_statuses_by_actor.clear()
	return removed_count


func remove_status(target_actor_id: String, status_id: StringName) -> bool:
	var actor_statuses: Dictionary = _get_actor_statuses(target_actor_id)
	if not actor_statuses.has(status_id):
		return false
	actor_statuses.erase(status_id)
	if actor_statuses.is_empty():
		_statuses_by_actor.erase(target_actor_id)
	else:
		_statuses_by_actor[target_actor_id] = actor_statuses
	return true


func clear_actor(target_actor_id: String) -> int:
	var actor_statuses: Dictionary = _get_actor_statuses(target_actor_id)
	var removed_count: int = actor_statuses.size()
	_statuses_by_actor.erase(target_actor_id)
	return removed_count


func _get_actor_statuses(actor_id: String) -> Dictionary:
	var value: Variant = _statuses_by_actor.get(actor_id, {})
	if value is Dictionary:
		return value
	return {}


## Combining trigger budgets when stacks are added. -1 means unlimited on either
## side, so the merged budget stays unlimited; otherwise the larger remaining
## count wins so adding a stack never shortens an existing status.
func _refresh_trigger_count(current: int, incoming: int) -> int:
	if current < 0 or incoming < 0:
		return -1
	return maxi(current, incoming)
