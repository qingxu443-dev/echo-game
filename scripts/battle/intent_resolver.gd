class_name IntentResolver
extends RefCounted

## Executes the intents that IntentPlanner produced, in the order it produced
## them. This is the only place where an enemy action mutates the battlefield.
##
## The telegraph and the execution read the same snapshot: every branch below
## re-checks the world (target still alive, cell still occupied, line still
## clear) and cancels with a reason rather than silently skipping, so a
## cancelled intent is visible in the event log.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")

const ABSOLUTE_GUARD_MARKED_MULTIPLIER: float = 0.7
const ABSOLUTE_GUARD_PLAIN_MULTIPLIER: float = 0.5


static func resolve_phase(battle) -> void:
	var actors = battle.actors
	var statuses = battle.statuses
	for intent in battle.intents:
		if battle.phase == battle.BattlePhase.FINISHED:
			break
		if intent.state != BattleIntentScript.IntentState.ACTIVE:
			continue
		if not actors.has(intent.source_actor_id) or not actors[intent.source_actor_id].is_alive():
			intent.cancel("source_defeated")
			continue
		if statuses.has_status("sevrin", &"absolute_guard"):
			redirect_to_sevrin(battle, intent)
		match intent.action_id:
			"basic_melee":
				_actor_locked_attack(battle, intent)
			"charged_strike", "aimed_shot":
				_tile_locked_attack(battle, intent)
			"ground_pulse":
				_area_attack(battle, intent)
			"pursuit":
				_pursuit(battle, intent)
			"wait":
				intent.mark_resolved()
				battle._emit_event("enemy_action_resolved", intent.source_actor_id, "", "wait")
			_:
				intent.cancel("unknown_action")
		if battle.absolute_guard_hit_intents.has(intent.intent_id):
			absolute_guard_counter(battle, intent)
			battle.absolute_guard_hit_intents.erase(intent.intent_id)
		battle._check_battle_end()
		if battle.phase == battle.BattlePhase.FINISHED:
			break

	if battle.phase != battle.BattlePhase.FINISHED:
		var expired_statuses: int = statuses.expire_all_boundary(&"enemy_phase_end")
		if expired_statuses > 0:
			battle._emit_event("statuses_expired", "", "", "boundary=enemy_phase_end count=%d" % expired_statuses)
		battle._begin_player_turn()


## Absolute Guard pulls eligible single-target attacks onto Sevrin. This runs
## before the action branch so the redirected intent resolves against him.
static func redirect_to_sevrin(battle, intent) -> void:
	var actors = battle.actors
	if not actors.has("sevrin") or not actors["sevrin"].is_alive() or not actors.has(intent.source_actor_id):
		return
	if intent.target_mode != BattleIntentScript.TargetMode.ACTOR_LOCKED and intent.target_mode != BattleIntentScript.TargetMode.TILE_LOCKED:
		return
	var source = actors[intent.source_actor_id]
	var target = actors["sevrin"]
	var distance: int = GridRulesScript.manhattan_distance(source.cell, target.cell)
	if distance > 2:
		return
	var legal := false
	match intent.action_id:
		"basic_melee":
			# Actor-locked attacks are dodge-proof by design: they track their
			# target without re-checking distance at resolve time. A melee is
			# therefore legally redirected to Sevrin anywhere inside the
			# two-cell taunt radius, not only when adjacent.
			legal = distance <= 2
		"charged_strike":
			legal = distance == 2 and GridRulesScript.has_clear_orthogonal_line(source.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells(intent.source_actor_id))
		_:
			return
	if not legal:
		return
	if intent.target_mode == BattleIntentScript.TargetMode.ACTOR_LOCKED:
		intent.target_actor_id = "sevrin"
	intent.target_cell = target.cell
	var redirected_cells: Array[Vector2i] = [target.cell]
	intent.affected_cells = redirected_cells
	battle._emit_event("absolute_guard_taunt", intent.source_actor_id, "sevrin", "intent=%s action=%s" % [intent.intent_id, intent.action_id])


static func absolute_guard_counter(battle, intent) -> void:
	var actors = battle.actors
	var statuses = battle.statuses
	if not statuses.has_status("sevrin", &"absolute_guard") or not actors.has("sevrin") or not actors["sevrin"].is_alive():
		return
	if not actors.has(intent.source_actor_id) or not actors[intent.source_actor_id].is_alive():
		return
	if battle.absolute_guard_countered_enemies.has(intent.source_actor_id):
		return
	battle.absolute_guard_countered_enemies[intent.source_actor_id] = true
	var marked: bool = statuses.has_status(intent.source_actor_id, &"oathkeeper_mark")
	var multiplier: float = ABSOLUTE_GUARD_MARKED_MULTIPLIER if marked else ABSOLUTE_GUARD_PLAIN_MULTIPLIER
	var raw_damage: int = CombatMathScript.calculate_raw_damage(actors["sevrin"].defense, multiplier)
	battle._apply_damage(intent.source_actor_id, raw_damage, "sevrin", "absolute_guard_counter", "physical", false, intent.intent_id)
	battle._emit_event("counter_resolved", "sevrin", intent.source_actor_id, "skill=absolute_guard multiplier=%.2f raw=%d" % [multiplier, raw_damage])


static func _actor_locked_attack(battle, intent) -> void:
	var actors = battle.actors
	if not actors.has(intent.target_actor_id) or not actors[intent.target_actor_id].is_alive():
		intent.cancel("actor_target_defeated")
		return
	battle._apply_damage(intent.target_actor_id, intent.damage, intent.source_actor_id, intent.action_id, intent.damage_type, true, intent.intent_id)
	intent.mark_resolved()
	battle._emit_event("enemy_action_resolved", intent.source_actor_id, intent.target_actor_id, intent.action_id)


static func _tile_locked_attack(battle, intent) -> void:
	var actors = battle.actors
	var target_id := ""
	for actor_id in actors:
		var candidate = actors[actor_id]
		if candidate.is_alive() and candidate.team == "player" and candidate.cell == intent.target_cell:
			target_id = actor_id
			break
	if target_id == "":
		intent.cancel("marked_cell_empty")
		return
	var source = actors[intent.source_actor_id]
	var current_distance: int = GridRulesScript.manhattan_distance(source.cell, intent.target_cell)
	if intent.action_id == "aimed_shot" and (current_distance < 3 or current_distance > 6):
		intent.cancel("shot_out_of_range")
		return
	if not GridRulesScript.has_clear_orthogonal_line(source.cell, intent.target_cell, battle.blocked_cells, battle.get_occupied_cells(intent.source_actor_id)):
		intent.cancel("marked_cell_line_blocked")
		return
	battle._apply_damage(target_id, intent.damage, intent.source_actor_id, intent.action_id, intent.damage_type, true, intent.intent_id)
	intent.mark_resolved()
	battle._emit_event("enemy_action_resolved", intent.source_actor_id, target_id, intent.action_id)


static func _area_attack(battle, intent) -> void:
	var actors = battle.actors
	var hit_any := false
	for actor_id in actors:
		var target = actors[actor_id]
		if target.team != "player" or not target.is_alive() or not intent.affected_cells.has(target.cell):
			continue
		battle._apply_damage(actor_id, intent.damage, intent.source_actor_id, intent.action_id, intent.damage_type, true, intent.intent_id)
		hit_any = true
	if not hit_any:
		intent.cancel("marked_area_empty")
		return
	intent.mark_resolved()
	battle._emit_event("enemy_action_resolved", intent.source_actor_id, "", intent.action_id)


static func _pursuit(battle, intent) -> void:
	var actors = battle.actors
	var source = actors[intent.source_actor_id]
	var path: Array = intent.affected_cells
	if path.is_empty() or path.size() > 2:
		intent.cancel("invalid_pursuit_path")
		return
	var cursor: Vector2i = source.cell
	for destination in path:
		if not GridRulesScript.is_inside_bounds(destination, battle.grid_size):
			intent.cancel("destination_out_of_bounds")
			return
		if battle.blocked_cells.has(destination) or battle.get_occupied_cells(intent.source_actor_id).has(destination):
			intent.cancel("destination_blocked")
			return
		if GridRulesScript.manhattan_distance(cursor, destination) != 1:
			intent.cancel("destination_not_adjacent")
			return
		cursor = destination
	source.cell = cursor
	intent.mark_resolved()
	battle._emit_event("enemy_action_resolved", intent.source_actor_id, "", "pursuit")
