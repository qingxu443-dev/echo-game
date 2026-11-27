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
	while resolve_one_active(battle):
		if battle.phase == battle.BattlePhase.FINISHED:
			break
	finish_phase(battle)


## Resolves exactly ONE active enemy intent so the UI can animate each enemy's
## attack step-by-step during the enemy turn. Returns true if an intent ran.
static func resolve_one_active(battle) -> bool:
	var actors = battle.actors
	for intent in battle.intents:
		if battle.phase == battle.BattlePhase.FINISHED:
			return false
		if intent.state != BattleIntentScript.IntentState.ACTIVE:
			continue
		if not actors.has(intent.source_actor_id) or not actors[intent.source_actor_id].is_alive():
			intent.cancel("source_defeated")
			continue
		# Into-the-Breach reposition: the planner recorded the steps instead of
		# moving the enemy itself, so apply them here before anything reads the
		# source cell (taunt redirect measures distance from it).
		if not intent.move_path.is_empty():
			if not _apply_reposition(battle, intent):
				battle._check_battle_end()
				return true
		var guardian_id: String = battle.get_absolute_guardian()
		if not guardian_id.is_empty():
			redirect_to_guardian(battle, intent, guardian_id)
		match intent.action_id:
			"basic_melee", "light_shot", "echo_bolt":
				_tile_locked_attack(battle, intent)
			"ground_pulse", "charged_strike", "aimed_shot":
				_area_attack(battle, intent)
			"pursuit":
				_pursuit(battle, intent)
			"ward_ally":
				_ward_ally(battle, intent)
			"wait":
				intent.mark_resolved()
				battle._emit_event("enemy_action_resolved", intent.source_actor_id, "", "wait")
			_:
				intent.cancel("unknown_action")
		if battle.absolute_guard_hit_intents.has(intent.intent_id):
			absolute_guard_counter(battle, intent)
			battle.absolute_guard_hit_intents.erase(intent.intent_id)
		battle._check_battle_end()
		return true
	return false


static func finish_phase(battle) -> void:
	var statuses = battle.statuses
	if battle.phase != battle.BattlePhase.FINISHED:
		var timed_out: int = statuses.tick_enemy_phase()
		if timed_out > 0:
			battle._emit_event("statuses_expired", "", "", "reason=enemy_turns count=%d" % timed_out)
		var expired_statuses: int = statuses.expire_all_boundary(&"enemy_phase_end")
		if expired_statuses > 0:
			battle._emit_event("statuses_expired", "", "", "boundary=enemy_phase_end count=%d" % expired_statuses)
		battle._begin_player_turn()


## Absolute Guard pulls eligible single-target attacks onto its holder. This runs
## before the action branch so the redirected intent resolves against the guardian.
static func redirect_to_guardian(battle, intent, guardian_id: String) -> void:
	var actors = battle.actors
	if not actors.has(guardian_id) or not actors[guardian_id].is_alive() or not actors.has(intent.source_actor_id):
		return
	if intent.target_mode != BattleIntentScript.TargetMode.ACTOR_LOCKED and intent.target_mode != BattleIntentScript.TargetMode.TILE_LOCKED:
		return
	var source = actors[intent.source_actor_id]
	var target = actors[guardian_id]
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
		_:
			# Charged strikes are AREA_LOCKED sweeps; the mode filter above
			# already excludes them, and a sweep has nothing to redirect.
			return
	if not legal:
		return
	# Record the pull on the intent: the tile-slot re-check in the resolver
	# must know this intent was redirected, or it cancels the two-cell melee
	# the taunt just made legal.
	intent.target_actor_id = guardian_id
	intent.target_cell = target.cell
	var redirected_cells: Array[Vector2i] = [target.cell]
	intent.affected_cells = redirected_cells
	battle._emit_event("absolute_guard_taunt", intent.source_actor_id, guardian_id, "intent=%s action=%s" % [intent.intent_id, intent.action_id])


static func absolute_guard_counter(battle, intent) -> void:
	var actors = battle.actors
	var statuses = battle.statuses
	var guardian_id: String = battle.get_absolute_guardian()
	if guardian_id.is_empty() or not actors.has(guardian_id) or not actors[guardian_id].is_alive():
		return
	if not actors.has(intent.source_actor_id) or not actors[intent.source_actor_id].is_alive():
		return
	if battle.absolute_guard_countered_enemies.has(intent.source_actor_id):
		return
	battle.absolute_guard_countered_enemies[intent.source_actor_id] = true
	var marked: bool = statuses.has_status(intent.source_actor_id, &"oathkeeper_mark")
	var multiplier: float = ABSOLUTE_GUARD_MARKED_MULTIPLIER if marked else ABSOLUTE_GUARD_PLAIN_MULTIPLIER
	var raw_damage: int = CombatMathScript.calculate_raw_damage(actors[guardian_id].defense, multiplier)
	battle._apply_damage(intent.source_actor_id, raw_damage, guardian_id, "absolute_guard_counter", "physical", false, intent.intent_id)
	battle._emit_event("counter_resolved", guardian_id, intent.source_actor_id, "skill=absolute_guard multiplier=%.2f raw=%d" % [multiplier, raw_damage])


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
	var source = actors[intent.source_actor_id]
	var current_distance: int = GridRulesScript.manhattan_distance(source.cell, intent.target_cell)
	var chebyshev: int = maxi(absi(source.cell.x - intent.target_cell.x), absi(source.cell.y - intent.target_cell.y))
	if intent.action_id == "basic_melee" and current_distance != 1 and intent.target_actor_id.is_empty():
		# A plain tile-lock whiffs when the target steps away (it does not
		# follow a moved actor). A redirected melee carries the guardian's
		# id and is legal anywhere inside the two-cell taunt radius.
		intent.cancel("melee_out_of_range")
		battle._emit_event("enemy_action_missed", intent.source_actor_id, "", "action=%s cell=%s" % [intent.action_id, str(intent.target_cell)])
		return
	if intent.action_id == "light_shot" and (chebyshev < 2 or chebyshev > 6):
		intent.cancel("shot_out_of_range")
		battle._emit_event("enemy_action_missed", intent.source_actor_id, "", "action=%s cell=%s" % [intent.action_id, str(intent.target_cell)])
		return
	if intent.action_id == "light_shot":
		if not GridRulesScript.has_clear_line_of_sight(source.cell, intent.target_cell, battle.blocked_cells, battle.get_occupied_cells(intent.source_actor_id)):
			intent.cancel("marked_cell_line_blocked")
			battle._emit_event("enemy_action_missed", intent.source_actor_id, "", "action=%s cell=%s" % [intent.action_id, str(intent.target_cell)])
			return
	elif intent.action_id != "echo_bolt" and intent.target_actor_id.is_empty() and not GridRulesScript.has_clear_orthogonal_line(source.cell, intent.target_cell, battle.blocked_cells, battle.get_occupied_cells(intent.source_actor_id)):
		intent.cancel("marked_cell_line_blocked")
		battle._emit_event("enemy_action_missed", intent.source_actor_id, "", "action=%s cell=%s" % [intent.action_id, str(intent.target_cell)])
		return

	var target_id := ""
	for actor_id in actors:
		var candidate = actors[actor_id]
		if candidate.is_alive() and candidate.team == "player" and candidate.cell == intent.target_cell:
			target_id = actor_id
			break
	if not target_id.is_empty():
		battle._apply_damage(target_id, intent.damage, intent.source_actor_id, intent.action_id, intent.damage_type, true, intent.intent_id)
		intent.mark_resolved()
		battle._emit_event("enemy_action_resolved", intent.source_actor_id, target_id, intent.action_id)
		return
	if battle.damage_beacon_at(intent.target_cell, intent.damage, intent.source_actor_id, intent.action_id):
		intent.mark_resolved()
		battle._emit_event("enemy_action_resolved", intent.source_actor_id, "beacon", intent.action_id)
		return
	intent.cancel("marked_cell_empty")
	battle._emit_event("enemy_action_missed", intent.source_actor_id, "", "action=%s cell=%s" % [intent.action_id, str(intent.target_cell)])


static func _area_attack(battle, intent) -> void:
	var actors = battle.actors
	var source = actors.get(intent.source_actor_id)
	if intent.action_id in ["charged_strike", "aimed_shot", "ground_pulse"] and source != null:
		source.skill_charge = 0
	var hit_any := false
	for actor_id in actors:
		var target = actors[actor_id]
		if target.team != "player" or not target.is_alive() or not intent.affected_cells.has(target.cell):
			continue
		battle._apply_damage(actor_id, intent.damage, intent.source_actor_id, intent.action_id, intent.damage_type, true, intent.intent_id)
		hit_any = true
	for area_cell in intent.affected_cells:
		if battle.damage_beacon_at(area_cell, intent.damage, intent.source_actor_id, intent.action_id):
			hit_any = true
	if not hit_any:
		intent.cancel("marked_area_empty")
		battle._emit_event("enemy_action_missed", intent.source_actor_id, "", "action=%s cell=%s" % [intent.action_id, str(intent.target_cell)])
		return
	intent.mark_resolved()
	battle._emit_event("enemy_action_resolved", intent.source_actor_id, "", intent.action_id)


## 古木壁垒: hand the intent's payload to the ally as a shield. Re-checks the
## world like every branch here - the ally may have died, or the warden may have
## been pushed away since planning, and a ward cast across three cells would be
## a lie the telegraph already told the player.
static func _ward_ally(battle, intent) -> void:
	var actors = battle.actors
	var source = actors[intent.source_actor_id]
	if not actors.has(intent.target_actor_id):
		intent.cancel("ward_target_gone")
		return
	var ally = actors[intent.target_actor_id]
	if not ally.is_alive():
		intent.cancel("ward_target_gone")
		return
	if GridRulesScript.manhattan_distance(source.cell, ally.cell) > 2:
		intent.cancel("ward_target_out_of_range")
		battle._emit_event("enemy_action_missed", intent.source_actor_id, "", "action=ward_ally")
		return
	var granted: int = ally.grant_shield(intent.damage)
	if source.skill_charge_max > 0:
		source.skill_charge = 0
	intent.mark_resolved()
	battle._emit_event(
		"enemy_ward_applied", intent.source_actor_id, intent.target_actor_id,
		"requested=%d shield=%d" % [intent.damage, granted]
	)


static func _pursuit(battle, intent) -> void:
	var actors = battle.actors
	var source = actors[intent.source_actor_id]
	var path: Array = intent.affected_cells
	var budget: int = 2
	if "move_steps" in source:
		budget = clampi(int(source.move_steps), 1, 4)
	if path.is_empty() or path.size() > budget:
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


## Walks the intent's recorded reposition path step by step, re-validating each
## cell against the CURRENT board (the player may have moved or the path may have
## been blocked since planning). Cancels the whole intent if any step is illegal,
## rather than teleporting through a wall.
static func _apply_reposition(battle, intent) -> bool:
	var actors = battle.actors
	if not actors.has(intent.source_actor_id):
		return false
	var source = actors[intent.source_actor_id]
	if not source.is_alive():
		intent.cancel("source_defeated")
		return false
	var cursor: Vector2i = source.cell
	for destination in intent.move_path:
		if not GridRulesScript.is_inside_bounds(destination, battle.grid_size):
			intent.cancel("reposition_out_of_bounds")
			return false
		if battle.blocked_cells.has(destination) or battle.get_occupied_cells(intent.source_actor_id).has(destination):
			intent.cancel("reposition_blocked")
			return false
		if GridRulesScript.manhattan_distance(cursor, destination) != 1:
			intent.cancel("reposition_not_adjacent")
			return false
		cursor = destination
	source.cell = cursor
	battle._emit_event("actor_moved", intent.source_actor_id, "", "reposition dest=%s" % str(cursor))
	return true
