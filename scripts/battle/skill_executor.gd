class_name SkillExecutor
extends RefCounted

## Every player skill action, in one file.
##
## Each function validates first and only then mutates, so a rejected cast never
## spends AP, never applies a status and never emits a "resolved" event. The two
## legacy v1 skills (oathguard_stance, echo_counter, watchwall, judgment_mark,
## oath_severance) are kept here because the controller still exposes them and
## five test suites still exercise them; they are marked for removal once those
## suites migrate to the v2 kit.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const AreaEffectScript = preload("res://scripts/battle/battle_area_effect.gd")

const ABSOLUTE_GUARD_AP: int = 2
const ABSOLUTE_GUARD_ENERGY: int = 5
const OATH_SHIELD_AP: int = 1
const OATH_SHIELD_DEFENSE_RATIO: float = 0.3
const OATH_SHIELD_VOW_BONUS: float = 0.1
const OATH_SHIELD_RANGE: int = 2
const JUDGMENT_MARK_AP: int = 1
const JUDGMENT_MARK_MIN_RANGE: int = 1
const JUDGMENT_MARK_MAX_RANGE: int = 4
const JUDGMENT_MARK_DEFENSE_MULTIPLIER: float = 0.8
const OATH_SEVERANCE_AP: int = 2
const OATH_SEVERANCE_MAX_RANGE: int = 2
const OATH_SEVERANCE_MULTIPLIER: float = 1.4
const WATCHWALL_REDUCTION_PERCENT: int = 20

const MARKABLE_ACTIONS: Array[String] = ["basic_melee", "aimed_shot", "charged_strike", "ground_pulse"]


static func absolute_guard(battle) -> bool:
	## Ultimate: taunt eligible single-target attacks and counter once per enemy.
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has("sevrin"):
		return false
	var caster = actors["sevrin"]
	if not caster.is_alive() or not battle.ap.can_spend(ABSOLUTE_GUARD_AP) or caster.ultimate_energy < ABSOLUTE_GUARD_ENERGY:
		return false
	if not battle.statuses.apply_status(&"absolute_guard", "sevrin", "sevrin", 1, 1, -1, &"player_phase_start", &"replace"):
		return false
	if not battle.ap.spend(ABSOLUTE_GUARD_AP) or not caster.spend_ultimate_energy(ABSOLUTE_GUARD_ENERGY):
		battle.statuses.remove_status("sevrin", &"absolute_guard")
		return false
	gain_active_energy(battle, "sevrin")
	battle._emit_event("skill_resolved", "sevrin", "sevrin", "skill=absolute_guard ap=2 energy=5 radius=2 expires=next_player_phase_start")
	return true


static func gain_active_energy(battle, actor_id: String) -> void:
	var actors = battle.actors
	if not actors.has(actor_id):
		return
	var actor = actors[actor_id]
	if actor.team != "player" or not actor.is_alive() or actor.active_energy_gain_turn == battle.turn_number:
		return
	actor.active_energy_gain_turn = battle.turn_number
	var before: int = actor.ultimate_energy
	actor.gain_ultimate_energy(1)
	if actor.ultimate_energy != before:
		battle._emit_event("ultimate_energy_gained", actor_id, actor_id, "source=active_action energy=%d" % actor.ultimate_energy)


static func oath_shield(battle, target_actor_id: String) -> bool:
	## Applies a DEF-scaled shield to Sevrin and one selected allied actor.
	## The target may be Sevrin himself; allied units are supported by the API
	## without adding a companion to the prototype encounter roster.
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has("sevrin") or not actors.has(target_actor_id):
		return false
	var caster = actors["sevrin"]
	var target = actors[target_actor_id]
	if not caster.is_alive() or not target.is_alive() or target.team != "player":
		return false
	if GridRulesScript.manhattan_distance(caster.cell, target.cell) > OATH_SHIELD_RANGE:
		return false
	if not battle.ap.can_spend(OATH_SHIELD_AP):
		return false
	var vow_stacks: int = battle.get_oath_vow_stacks("sevrin")
	var raw_shield: int = floori(float(caster.defense) * OATH_SHIELD_DEFENSE_RATIO * (1.0 + OATH_SHIELD_VOW_BONUS * float(vow_stacks)))
	var shielded_ids: Array[String] = ["sevrin"]
	if target_actor_id != "sevrin":
		shielded_ids.append(target_actor_id)
	if not battle.ap.spend(OATH_SHIELD_AP):
		return false
	for shielded_id in shielded_ids:
		var shielded = actors[shielded_id]
		var previous_shield: int = shielded.shield
		var final_shield: int = shielded.grant_shield(raw_shield)
		# Reapplication refreshes the two-player-turn duration even when the
		# retained shield amount is stronger than the newly calculated amount.
		battle.oath_shield_expiry_turn[shielded_id] = battle.turn_number + 1
		battle._emit_event(
			"oath_shield_applied",
			"sevrin",
			shielded_id,
			"raw=%d previous=%d current=%d cap=%d expires_after_player_turn=%d" % [
				raw_shield,
				previous_shield,
				final_shield,
				floori(float(shielded.max_health) * 0.15),
				battle.turn_number + 1
			]
		)
	gain_active_energy(battle, "sevrin")
	if vow_stacks > 0:
		battle.statuses.remove_status("sevrin", &"oath_vow")
		battle._emit_event("status_consumed", "sevrin", "sevrin", "status=oath_vow stacks=%d" % vow_stacks)
	battle._emit_event("skill_resolved", "sevrin", target_actor_id, "skill=oath_shield ap=1 vow_stacks=%d shield=%d" % [vow_stacks, raw_shield])
	return true


static func marked_target(battle) -> String:
	for actor_id in battle.actors.keys():
		if battle.statuses.has_status(String(actor_id), &"oathkeeper_mark"):
			return String(actor_id)
	return ""


static func judgment_mark_v2(battle, target_actor_id: String) -> bool:
	## V2 Judgment Mark: a DEF-scaled strike and a single replaceable mark.
	## This is deliberately separate from the legacy judgment_mark status/API.
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has("sevrin") or not actors.has(target_actor_id):
		return false
	var caster = actors["sevrin"]
	var target = actors[target_actor_id]
	if not caster.is_alive() or not target.is_alive() or target.team != "enemy":
		return false
	var distance: int = GridRulesScript.manhattan_distance(caster.cell, target.cell)
	if distance < JUDGMENT_MARK_MIN_RANGE or distance > JUDGMENT_MARK_MAX_RANGE:
		return false
	if not GridRulesScript.has_clear_line_of_sight(caster.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells()):
		return false
	if not battle.ap.can_spend(JUDGMENT_MARK_AP):
		return false
	if not battle.ap.spend(JUDGMENT_MARK_AP):
		return false
	for actor_id in actors.keys():
		battle.statuses.remove_status(String(actor_id), &"oathkeeper_mark")
	if not battle.statuses.apply_status(&"oathkeeper_mark", "sevrin", target_actor_id, 1, 1, -1, &"enemy_phase_end", &"replace"):
		battle.ap.current += 1
		return false
	gain_active_energy(battle, "sevrin")
	var raw_damage: int = CombatMathScript.calculate_raw_damage(caster.defense, JUDGMENT_MARK_DEFENSE_MULTIPLIER)
	battle._apply_damage(target_actor_id, raw_damage, "sevrin", "oathkeeper_judgment_mark", "physical")
	battle._emit_event(
		"skill_resolved",
		"sevrin",
		target_actor_id,
		"skill=oathkeeper_judgment_mark ap=1 raw=%d mark=oathkeeper_mark expires=enemy_phase_end" % raw_damage
	)
	battle._check_battle_end()
	return true


static func player_attack(battle, target_actor_id: String, damage_multiplier: float = 1.0) -> bool:
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has("sevrin") or not actors.has(target_actor_id):
		return false
	var player = actors["sevrin"]
	var target = actors[target_actor_id]
	if not player.is_alive() or not target.is_alive() or target.team != "enemy":
		return false
	if GridRulesScript.manhattan_distance(player.cell, target.cell) != 1:
		return false
	if damage_multiplier <= 0.0 or not battle.ap.can_spend(1):
		return false
	if not battle.ap.spend(1):
		return false
	var damage: int = CombatMathScript.calculate_raw_damage(player.attack, damage_multiplier)
	battle._apply_damage(target_actor_id, damage, "sevrin", "player_attack", "physical")
	battle._emit_event("attack_resolved", "sevrin", target_actor_id, "倍率=%.2f 伤害=%d" % [damage_multiplier, damage])
	battle._check_battle_end()
	return true


static func oathguard_stance(battle, caster_actor_id: String = "sevrin") -> bool:
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has(caster_actor_id):
		return false
	var caster = actors[caster_actor_id]
	if not caster.is_alive() or caster.team != "player" or not battle.ap.can_spend(1):
		return false
	if not battle.ap.spend(1):
		return false
	if not battle.statuses.apply_status(&"oathguard", caster_actor_id, caster_actor_id, 1, 1, 1, &"enemy_phase_end"):
		battle.ap.current += 1
		return false
	battle._emit_event("skill_resolved", caster_actor_id, caster_actor_id, "skill=oathguard_stance ap=1")
	return true


static func echo_counter(battle, caster_actor_id: String = "sevrin") -> bool:
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has(caster_actor_id):
		return false
	var caster = actors[caster_actor_id]
	if not caster.is_alive() or caster.team != "player" or not battle.ap.can_spend(1):
		return false
	if not battle.ap.spend(1):
		return false
	if not battle.statuses.apply_status(&"echo_counter", caster_actor_id, caster_actor_id, 1, 1, 1, &"enemy_phase_end"):
		battle.ap.current += 1
		return false
	battle._emit_event("skill_resolved", caster_actor_id, caster_actor_id, "skill=echo_counter ap=1")
	return true


static func watchwall(battle) -> bool:
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has("sevrin"):
		return false
	var caster = actors["sevrin"]
	if not caster.is_alive() or not battle.ap.can_spend(1):
		return false
	var affected_cells: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for offset in offsets:
		var cell: Vector2i = caster.cell + offset
		if GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			affected_cells.append(cell)
	var effect = AreaEffectScript.new(
		&"watchwall",
		AreaEffectScript.EFFECT_DAMAGE_REDUCTION,
		caster.actor_id,
		caster.team,
		caster.cell,
		affected_cells,
		AreaEffectScript.TARGET_SAME_TEAM,
		WATCHWALL_REDUCTION_PERCENT,
		&"player_phase_start"
	)
	if not effect.is_valid() or not battle.ap.spend(1):
		return false
	if not battle.area_effects.apply_effect(effect):
		battle.ap.current += 1
		return false
	battle._emit_event("area_effect_applied", caster.actor_id, "", "effect=watchwall center=%s cells=%d reduction=20%%" % [str(caster.cell), affected_cells.size()])
	battle._emit_event("skill_resolved", caster.actor_id, "", "skill=watchwall ap=1")
	return true


static func judgment_mark(battle, target_actor_id: String) -> bool:
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has("sevrin") or not actors.has(target_actor_id):
		return false
	var player = actors["sevrin"]
	var target = actors[target_actor_id]
	if not player.is_alive() or not target.is_alive() or target.team != "enemy":
		return false
	var distance: int = GridRulesScript.manhattan_distance(player.cell, target.cell)
	if distance < JUDGMENT_MARK_MIN_RANGE or distance > JUDGMENT_MARK_MAX_RANGE:
		return false
	if not GridRulesScript.has_clear_line_of_sight(player.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells()):
		return false
	if not battle.ap.can_spend(JUDGMENT_MARK_AP):
		return false
	if not battle.ap.spend(JUDGMENT_MARK_AP):
		return false
	if not battle.statuses.apply_status(&"judgment_mark", "sevrin", target_actor_id, 1, 1, -1, &"enemy_phase_end"):
		battle.ap.current += 1
		return false
	for intent in battle.intents:
		if intent.source_actor_id == target_actor_id and intent.state == BattleIntentScript.IntentState.ACTIVE and intent.action_id in MARKABLE_ACTIONS:
			intent.judgment_marked = true
			battle._emit_event("intent_judgment_marked", target_actor_id, intent.target_actor_id, "intent=%s action=%s" % [intent.intent_id, intent.action_id])
			break
	battle._emit_event("skill_resolved", "sevrin", target_actor_id, "skill=judgment_mark ap=1")
	return true


static func oath_severance(battle, target_actor_id: String) -> bool:
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has("sevrin") or not actors.has(target_actor_id):
		return false
	var player = actors["sevrin"]
	var target = actors[target_actor_id]
	if not player.is_alive() or not target.is_alive() or target.team != "enemy":
		return false
	if not battle.statuses.has_status(target_actor_id, &"judgment_mark"):
		return false
	var distance: int = GridRulesScript.manhattan_distance(player.cell, target.cell)
	if distance < 1 or distance > OATH_SEVERANCE_MAX_RANGE:
		return false
	if not GridRulesScript.has_clear_line_of_sight(player.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells()):
		return false
	if not battle.ap.can_spend(OATH_SEVERANCE_AP) or not battle.ap.spend(OATH_SEVERANCE_AP):
		return false
	battle.statuses.remove_status(target_actor_id, &"judgment_mark")
	var interrupted := false
	for intent in battle.intents:
		if intent.source_actor_id == target_actor_id and intent.state == BattleIntentScript.IntentState.ACTIVE:
			interrupted = intent.cancel("oath_severance")
			if interrupted:
				battle._emit_event("intent_severed", "sevrin", target_actor_id, "intent=%s action=%s" % [intent.intent_id, intent.action_id])
			break
	var damage: int = CombatMathScript.calculate_raw_damage(player.attack, OATH_SEVERANCE_MULTIPLIER)
	battle._apply_damage(target_actor_id, damage, "sevrin", "oath_severance", "physical")
	battle._emit_event("skill_resolved", "sevrin", target_actor_id, "skill=oath_severance interrupted=%s raw=%d" % [str(interrupted), damage])
	battle._check_battle_end()
	return true
