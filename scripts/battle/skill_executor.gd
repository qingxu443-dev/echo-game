class_name SkillExecutor
extends RefCounted

## Every player skill action, in one file.
##
## Each function validates first and only then mutates, so a rejected cast never
## spends AP, never applies a status and never emits a "resolved" event.
##
## The v1 kit (oathguard stance, echo counter, watchwall, the v1 judgment mark and
## oath severance) was removed with the systems only it produced: area effects,
## echo counter, oathguard mitigation and the intent-mark / exposed debuff.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")

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
	# Both spends are guarded above, but revert whichever one landed: spending AP
	# and then failing on energy used to lose the AP silently.
	var spent_energy: bool = caster.spend_ultimate_energy(ABSOLUTE_GUARD_ENERGY)
	var spent_ap: bool = battle.ap.spend(ABSOLUTE_GUARD_AP)
	if not (spent_energy and spent_ap):
		if spent_energy:
			caster.gain_ultimate_energy(ABSOLUTE_GUARD_ENERGY)
		if spent_ap:
			battle.ap.refund(ABSOLUTE_GUARD_AP)
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
	## The caster comes from the active character, not from a fixed id: this was
	## the last skill that read actors["sevrin"] for both the caster and the
	## shield list, which is why a party member could never be shielded.
	##
	## §12 promised that "a specific skill can revive" a downed member; this is
	## that skill. A downed ally within range is a legal target: revival restores
	## health equal to the shield's raw value (one source, DEF-scaled), returns
	## the member to its own cell and then shields it like any living target.
	## Per §12 the count is the skill's to define: once per member per
	## encounter, so a body cannot be resurrected in a loop.
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has(target_actor_id):
		return false
	var caster = battle.get_active_character()
	if caster == null:
		return false
	var target = actors[target_actor_id]
	var reviving: bool = target.is_downed
	if not caster.is_alive() or target.team != "player" or not (target.is_alive() or reviving):
		return false
	if reviving and battle.oath_shield_revived.has(target_actor_id):
		return false
	if GridRulesScript.manhattan_distance(caster.cell, target.cell) > OATH_SHIELD_RANGE:
		return false
	if not battle.ap.can_spend(OATH_SHIELD_AP):
		return false
	var caster_id: String = caster.actor_id
	var vow_stacks: int = battle.get_oath_vow_stacks(caster_id)
	var raw_shield: int = floori(float(caster.defense) * OATH_SHIELD_DEFENSE_RATIO * (1.0 + OATH_SHIELD_VOW_BONUS * float(vow_stacks)))
	var shielded_ids: Array[String] = [caster_id]
	if target_actor_id != caster_id:
		shielded_ids.append(target_actor_id)
	if not battle.ap.spend(OATH_SHIELD_AP):
		return false
	if reviving:
		target.revive(raw_shield)
		battle.oath_shield_revived[target_actor_id] = true
		battle._emit_event("member_revived", caster_id, target_actor_id, "skill=oath_shield restored=%d" % raw_shield)
	for shielded_id in shielded_ids:
		var shielded = actors[shielded_id]
		var previous_shield: int = shielded.shield
		var final_shield: int = shielded.grant_shield(raw_shield)
		# Reapplication refreshes the two-player-turn duration even when the
		# retained shield amount is stronger than the newly calculated amount.
		battle.oath_shield_expiry_turn[shielded_id] = battle.turn_number + 1
		battle._emit_event(
			"oath_shield_applied",
			caster_id,
			shielded_id,
			"raw=%d previous=%d current=%d cap=%d expires_after_player_turn=%d" % [
				raw_shield,
				previous_shield,
				final_shield,
				floori(float(shielded.max_health) * 0.15),
				battle.turn_number + 1
			]
		)
	gain_active_energy(battle, caster_id)
	if vow_stacks > 0:
		battle.statuses.remove_status(caster_id, &"oath_vow")
		battle._emit_event("status_consumed", caster_id, caster_id, "status=oath_vow stacks=%d" % vow_stacks)
	battle._emit_event("skill_resolved", caster_id, target_actor_id, "skill=oath_shield ap=1 vow_stacks=%d shield=%d" % [vow_stacks, raw_shield])
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
		battle.ap.refund(1)
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

