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
const HazardFieldScript = preload("res://scripts/battle/hazard_field.gd")
const IntentSupportScript = preload("res://scripts/battle/intent_support.gd")
const TacticalPressureScript = preload("res://scripts/battle/tactical_pressure.gd")

const ABSOLUTE_GUARD_MARKED_MULTIPLIER: float = 0.7
const ABSOLUTE_GUARD_PLAIN_MULTIPLIER: float = 0.5
## Same six-cell reach the planner uses for 百花锁命. Kept here because the shot
## is re-checked against the live board; changing one without the other would let
## the telegraph promise a shot the resolver then refuses.
const LOCK_ON_MAX_RANGE: int = 6
const ROT_CURSE_MAX_RANGE: int = 4
## "持续至下一敌方行动阶段结束" (§14): two enemy-phase ticks, the one that
## applies it excluded.
const ROT_CURSE_ENEMY_TICKS: int = 2


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
			"ground_pulse", "charged_strike", "aimed_shot", "blight_field", "spring_bloom", "sakura_shock":
				_area_attack(battle, intent)
			"pursuit":
				_pursuit(battle, intent)
			"ward_ally":
				_ward_ally(battle, intent)
			"ward_stance":
				_ward_stance(battle, intent)
			"lock_on":
				_lock_on(battle, intent)
			"locked_shot":
				_locked_shot(battle, intent)
			"shadow_raid":
				_shadow_raid(battle, intent)
			"rot_curse":
				_rot_curse(battle, intent)
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
		_expire_curse_penalties(battle)
		_expire_broken_locks(battle)
		battle._begin_player_turn()


## 腐樱诅咒 lapses at the end of the next enemy phase. turn_number is not
## advanced yet here, so a penalty set during turn T carries expiry T+1 and is
## swept exactly once, on the way out of T+1's enemy phase.
static func _expire_curse_penalties(battle) -> void:
	for actor_id in battle.actors:
		var actor = battle.actors[actor_id]
		if actor.defense_penalty <= 0 or actor.defense_penalty_expiry_turn < 0:
			continue
		if battle.turn_number < actor.defense_penalty_expiry_turn:
			continue
		actor.defense_penalty = 0
		actor.defense_penalty_expiry_turn = -1
		battle._emit_event("enemy_curse_expired", String(actor_id), "", "defense_restored")


## A lock that never became a shot - the hero left the archer's reach or broke
## its line - is dropped here rather than lingering on the archer forever. The
## planner refuses to telegraph an illegal shot, so this is the only place that
## can report the mark going stale.
static func _expire_broken_locks(battle) -> void:
	for actor_id in battle.actors:
		var enemy = battle.actors[actor_id]
		if enemy.team != "enemy" or String(enemy.lock_target_id).is_empty():
			continue
		var target = battle.actors.get(enemy.lock_target_id)
		var reason := ""
		if target == null or not target.is_alive():
			reason = "lock_target_gone"
		elif GridRulesScript.manhattan_distance(enemy.cell, target.cell) > LOCK_ON_MAX_RANGE:
			reason = "lock_range_broken"
		elif not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(String(actor_id))):
			reason = "lock_sight_broken"
		if reason.is_empty():
			continue
		enemy.lock_target_id = ""
		battle._emit_event("enemy_lock_broken", String(actor_id), "", "reason=%s" % reason)


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
		if not GridRulesScript.has_clear_line_of_sight(source.cell, intent.target_cell, battle.blocked_cells, battle.get_sight_blockers(intent.source_actor_id)):
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
	# Reactive melee tracking: if the hero sidestepped around the enemy while
	# staying adjacent (or within 2 cells of an Elite/Boss), pivot/step and strike
	# instead of passively swinging at empty air.
	if target_id.is_empty() and intent.action_id == "basic_melee" and intent.target_actor_id.is_empty():
		var reactive_id: String = TacticalPressureScript.try_reactive_melee_target(battle, source, intent)
		if not reactive_id.is_empty():
			target_id = reactive_id
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
	if intent.action_id in ["charged_strike", "aimed_shot", "ground_pulse", "blight_field", "spring_bloom", "sakura_shock"] and source != null:
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
	# The ground effect lands whether or not anyone was standing in the blast:
	# 樱落领域 cuts the floor, it does not cut a person in particular. Doing this
	# before the empty-area cancel below is deliberate - a swing that missed must
	# not leave the battlefield exactly as it was.
	if not intent.hazard_cells.is_empty() and not intent.hazard_kind.is_empty():
		HazardFieldScript.spawn(
			battle, intent.hazard_cells, intent.hazard_kind,
			intent.hazard_damage, intent.source_actor_id,
			intent.hazard_duration_turns, intent.damage_type
		)
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


## 结界守护: the boss raises a shield for two turns (§15.2). The expiry is set on
## the actor and swept at the start of a later player turn, so "two rounds" means
## two player turns during which the shield is visible and countable.
static func _ward_stance(battle, intent) -> void:
	var actors = battle.actors
	if not actors.has(intent.source_actor_id):
		intent.cancel("source_gone")
		return
	var source = actors[intent.source_actor_id]
	if not source.is_alive():
		intent.cancel("source_defeated")
		return
	var granted: int = source.grant_shield(intent.damage)
	# turn_number increments at the START of each player turn, so +3 keeps the
	# shield visible for the next two player turns and sweeps it on the third.
	source.shield_expiry_turn = battle.turn_number + 3
	if source.skill_charge_max > 0:
		source.skill_charge = 0
	intent.mark_resolved()
	battle._emit_event(
		"enemy_stance_raised", intent.source_actor_id, intent.source_actor_id,
		"requested=%d shield=%d expires=%d" % [intent.damage, granted, source.shield_expiry_turn]
	)


## 百花锁命 第一段: record the mark on the archer and spend its charge. The mark
## is not a status on the hero - it is the archer's own intent, so a dead archer
## takes the threat with it and nothing has to sweep the hero's status list.
static func _lock_on(battle, intent) -> void:
	var actors = battle.actors
	var source = actors.get(intent.source_actor_id)
	if source == null or not source.is_alive():
		intent.cancel("source_defeated")
		return
	var target = actors.get(intent.target_actor_id)
	if target == null or not target.is_alive() or target.team != "player":
		intent.cancel("lock_target_gone")
		return
	source.lock_target_id = intent.target_actor_id
	if source.skill_charge_max > 0:
		source.skill_charge = 0
	intent.mark_resolved()
	battle._emit_event("enemy_lock_on", intent.source_actor_id, intent.target_actor_id, "action=lock_on")


## 百花锁命 第二段: the strengthened arrow. Unlike an ordinary actor-locked
## attack it is not dodge-proof by tile, but it does track the hero - only leaving
## six cells or breaking sight cancels it, which is exactly what the document
## asks for and what the mark's whole telegraph turn is for.
static func _locked_shot(battle, intent) -> void:
	var actors = battle.actors
	var source = actors.get(intent.source_actor_id)
	if source == null or not source.is_alive():
		intent.cancel("source_defeated")
		return
	var target = actors.get(intent.target_actor_id)
	if target == null or not target.is_alive() or target.team != "player":
		_break_lock(battle, source, intent, "lock_target_gone")
		return
	var distance: int = GridRulesScript.manhattan_distance(source.cell, target.cell)
	if distance < 1 or distance > LOCK_ON_MAX_RANGE:
		_break_lock(battle, source, intent, "lock_range_broken")
		return
	if not GridRulesScript.has_clear_line_of_sight(source.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(intent.source_actor_id)):
		_break_lock(battle, source, intent, "lock_sight_broken")
		return
	source.lock_target_id = ""
	battle._apply_damage(target.actor_id, intent.damage, intent.source_actor_id, "locked_shot", intent.damage_type, true, intent.intent_id)
	intent.mark_resolved()
	battle._emit_event("enemy_action_resolved", intent.source_actor_id, target.actor_id, "locked_shot")


static func _break_lock(battle, source, intent, reason: String) -> void:
	source.lock_target_id = ""
	intent.cancel(reason)
	battle._emit_event("enemy_lock_broken", intent.source_actor_id, intent.target_actor_id, "reason=%s" % reason)


## 逐影突袭: the resolver has already walked the intent's path (above), so this
## branch only checks that the landing is still adjacent to a living mark and
## that the blow still has a target. Stepping off the landing tile makes the raid
## whiff, which is the counterplay the path telegraph promises.
static func _shadow_raid(battle, intent) -> void:
	var actors = battle.actors
	var source = actors.get(intent.source_actor_id)
	if source == null or not source.is_alive():
		intent.cancel("source_defeated")
		return
	var target = actors.get(intent.target_actor_id)
	if target == null or not target.is_alive() or target.team != "player":
		intent.cancel("raid_target_gone")
		return
	if GridRulesScript.manhattan_distance(source.cell, target.cell) != 1:
		intent.cancel("raid_missed")
		battle._emit_event("enemy_action_missed", intent.source_actor_id, intent.target_actor_id, "action=shadow_raid")
		return
	battle._apply_damage(target.actor_id, intent.damage, intent.source_actor_id, "shadow_raid", intent.damage_type, true, intent.intent_id)
	if source.skill_charge_max > 0:
		source.skill_charge = 0
	intent.mark_resolved()
	battle._emit_event("enemy_action_resolved", intent.source_actor_id, target.actor_id, "shadow_raid")


## 腐樱诅咒: a flat defence penalty that never stacks. Reapplication refreshes
## the clock and keeps the larger penalty, so two witches cannot strip 200.
static func _rot_curse(battle, intent) -> void:
	var actors = battle.actors
	var source = actors.get(intent.source_actor_id)
	if source == null or not source.is_alive():
		intent.cancel("source_defeated")
		return
	var target = actors.get(intent.target_actor_id)
	if target == null or not target.is_alive() or target.team != "player":
		intent.cancel("curse_target_gone")
		return
	var distance: int = GridRulesScript.manhattan_distance(source.cell, target.cell)
	if distance < 1 or distance > ROT_CURSE_MAX_RANGE:
		intent.cancel("curse_out_of_range")
		battle._emit_event("enemy_action_missed", intent.source_actor_id, intent.target_actor_id, "action=rot_curse")
		return
	if not GridRulesScript.has_clear_line_of_sight(source.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(intent.source_actor_id)):
		intent.cancel("curse_line_blocked")
		battle._emit_event("enemy_action_missed", intent.source_actor_id, intent.target_actor_id, "action=rot_curse")
		return
	var amount: int = maxi(0, intent.damage)
	target.defense_penalty = maxi(target.defense_penalty, amount)
	target.defense_penalty_expiry_turn = battle.turn_number + 1
	battle.statuses.apply_status(&"rot_curse", intent.source_actor_id, target.actor_id, 1, 1, -1, &"", &"replace")
	var status = battle.statuses.get_status(target.actor_id, &"rot_curse")
	if status != null:
		status.enemy_turns_remaining = ROT_CURSE_ENEMY_TICKS
	if source.skill_charge_max > 0:
		source.skill_charge = 0
	intent.mark_resolved()
	battle._emit_event(
		"enemy_curse_applied", intent.source_actor_id, target.actor_id,
		"requested=%d defense_penalty=%d expires_after_turn=%d" % [amount, target.defense_penalty, target.defense_penalty_expiry_turn]
	)


## Finds a living player standing on `cell`, or null if none.
static func _player_at_cell(battle, cell: Vector2i):
	for actor_id in battle.actors:
		var actor = battle.actors[actor_id]
		if actor.team == "player" and actor.is_alive() and actor.cell == cell:
			return actor
	return null


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
	var occupied: Dictionary = battle.get_occupied_cells(intent.source_actor_id)
	var cursor: Vector2i = source.cell
	var steps_used: int = 0
	var blocking_player = null
	var blocked_midway := false
	for destination in path:
		if not GridRulesScript.is_inside_bounds(destination, battle.grid_size) or GridRulesScript.manhattan_distance(cursor, destination) != 1:
			blocked_midway = true
			break
		if battle.blocked_cells.has(destination) or occupied.has(destination):
			blocking_player = _player_at_cell(battle, destination)
			blocked_midway = true
			break
		cursor = destination
		steps_used += 1
	# If an ally/wall blocked the planned tile, dynamically reroute with remaining
	# movement budget so the enemy keeps closing instead of freezing in place.
	if blocked_midway and blocking_player == null and steps_used < budget:
		var hero = battle.get_defender()
		if hero != null and hero.is_alive():
			var detour: Array[Vector2i] = IntentSupportScript.pursuit_path(battle, cursor, hero.cell, intent.source_actor_id, budget - steps_used)
			if not detour.is_empty():
				cursor = detour[detour.size() - 1]
	source.cell = cursor
	# If the player deliberately stepped onto the enemy's charge tile to body-block,
	# the enemy stops right in their face and delivers a collision strike!
	if blocking_player != null and GridRulesScript.manhattan_distance(source.cell, blocking_player.cell) == 1:
		var collide_dmg: int = IntentSupportScript.plain_attack_damage(source, 0.8)
		battle._apply_damage(blocking_player.actor_id, collide_dmg, intent.source_actor_id, "basic_melee", "physical", true, intent.intent_id)
		intent.mark_resolved()
		battle._emit_event("enemy_action_resolved", intent.source_actor_id, blocking_player.actor_id, "pursuit_intercept")
		return
	intent.mark_resolved()
	battle._emit_event("enemy_action_resolved", intent.source_actor_id, "", "pursuit")


## Walks the intent's recorded reposition path step by step against the live board.
## If the player body-blocks a planned step, stops adjacent and lets melee/rush
## intents strike the blocker instead of canceling the entire enemy turn.
static func _apply_reposition(battle, intent) -> bool:
	var actors = battle.actors
	if not actors.has(intent.source_actor_id):
		return false
	var source = actors[intent.source_actor_id]
	if not source.is_alive():
		intent.cancel("source_defeated")
		return false
	var occupied: Dictionary = battle.get_occupied_cells(intent.source_actor_id)
	var budget: int = maxi(intent.move_path.size(), clampi(int(source.move_steps) if "move_steps" in source else 2, 1, 4))
	var cursor: Vector2i = source.cell
	var steps_used: int = 0
	var blocking_player = null
	var blocked_midway := false
	for destination in intent.move_path:
		if not GridRulesScript.is_inside_bounds(destination, battle.grid_size) or GridRulesScript.manhattan_distance(cursor, destination) != 1:
			blocked_midway = true
			break
		if battle.blocked_cells.has(destination) or occupied.has(destination):
			blocking_player = _player_at_cell(battle, destination)
			blocked_midway = true
			break
		cursor = destination
		steps_used += 1
	if blocked_midway and blocking_player == null and steps_used < budget:
		var hero = battle.get_defender()
		if hero != null and hero.is_alive():
			var detour: Array[Vector2i] = IntentSupportScript.pursuit_path(battle, cursor, hero.cell, intent.source_actor_id, budget - steps_used)
			if not detour.is_empty():
				cursor = detour[detour.size() - 1]
	if cursor != source.cell:
		source.cell = cursor
		battle._emit_event("actor_moved", intent.source_actor_id, "", "reposition dest=%s" % str(cursor))
	# Body-blocking a rushing enemy puts you right in front of its swing:
	if blocking_player != null and GridRulesScript.manhattan_distance(source.cell, blocking_player.cell) == 1:
		if intent.action_id == "basic_melee" or intent.action_id == "shadow_raid":
			intent.target_cell = blocking_player.cell
			intent.target_actor_id = blocking_player.actor_id
			intent.affected_cells = [blocking_player.cell]
		elif intent.action_id == "ward_stance":
			# Rush-shield slams into a body-blocking hero on arrival!
			var slam_dmg: int = IntentSupportScript.plain_attack_damage(source, 0.8)
			battle._apply_damage(blocking_player.actor_id, slam_dmg, intent.source_actor_id, "basic_melee", "physical", true, intent.intent_id)
	return true
