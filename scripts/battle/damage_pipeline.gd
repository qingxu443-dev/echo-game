class_name DamagePipeline
extends RefCounted

## The single place where a hit is resolved.
##
## Order is fixed and must not be reordered: resistances (inside BattleActor) ->
## shield absorption -> applied. Everything that reacts to a hit lives here as
## well - stat tallies, Oath Vow accumulation, Absolute Guard bookkeeping and
## defeat cleanup - because they are consequences of damage rather than of the
## action that caused it.
##
## Takes the controller as `battle` instead of inheriting from it, so the file
## can be read without the other thirty functions around it.

const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const TacticalPressureScript = preload("res://scripts/battle/tactical_pressure.gd")
const DestLeeSkillEffectsScript = preload("res://scripts/battle/dest_lee_skill_effects.gd")


static func apply(
	battle,
	target_actor_id: String,
	amount: int,
	source_actor_id: String,
	action_id: String,
	damage_type: String = "physical",
	is_public_intent: bool = false,
	resolving_intent_id: String = ""
) -> void:
	var actors = battle.actors
	var statuses = battle.statuses
	# A stale id (an intent whose source died, a summon aimed at a removed actor)
	# used to raise on the dictionary read and leave the caller mid-action, with
	# AP already spent. Refuse it explicitly instead.
	var target = actors.get(target_actor_id)
	if target == null:
		push_error("DamagePipeline: unknown target '%s'" % target_actor_id)
		return
	if target.is_defeated():
		return

	var effective_amount: int = amount
	# Judgment Mark vulnerability: next hit on a marked enemy deals +30% (or +55% with Deep Judgment mod) and consumes the mark.
	if target.team == "enemy" and action_id != "oathkeeper_judgment_mark" and statuses.has_status(target_actor_id, &"oathkeeper_mark"):
		var vuln_mult: float = battle.run_state.mark_vulnerability_multiplier() if battle.run_state != null else 1.30
		effective_amount = roundi(float(amount) * vuln_mult)
		statuses.remove_status(target_actor_id, &"oathkeeper_mark")
		battle._emit_event("status_consumed", source_actor_id, target_actor_id, "status=oathkeeper_mark mult=%.2f" % vuln_mult)

	effective_amount = TacticalPressureScript.adjust_incoming_damage(battle, target, effective_amount, action_id)
	var critical_multiplier := 1.0
	var attacker = actors.get(source_actor_id)
	if attacker != null and attacker.team == "player" and float(attacker.crit_rate) > 0.0:
		# Hash the persisted action sequence so critical rolls remain reproducible
		# after a suspended battle is resumed.
		var roll_key := "%s|%s|%d|%d|%s" % [source_actor_id, target_actor_id, battle.turn_number, battle.event_sequence, action_id]
		var roll := float(posmod(hash(roll_key), 10000)) / 100.0
		if roll < clampf(float(attacker.crit_rate), 0.0, 100.0):
			critical_multiplier = maxf(1.0, float(attacker.crit_damage) / 100.0)
	var damage_result: Dictionary = target.apply_damage_with_result(effective_amount, damage_type, 0, [], critical_multiplier)
	var applied: int = int(damage_result.get("health_damage", 0))
	var was_hit: bool = bool(damage_result.get("hit", false))

	## Unified hit semantics: any damage instance that reached this living actor
	## counts as a hit, even when a shield fully absorbs it. Guard bookkeeping and
	## Oath Vow follow this one rule. The settlement tallies below intentionally
	## stay health-based so they report real attrition.
	# Oath Vow belongs to the passive, not to a character id: whoever carries the
	# passive accumulates when a telegraphed enemy action lands on them. Guard
	# bookkeeping follows the status, so a guardian other than the prototype's
	# works the same way.
	if was_hit and is_public_intent and actors.has(source_actor_id) and actors[source_actor_id].team == "enemy":
		if statuses.has_status(target_actor_id, &"absolute_guard") and not resolving_intent_id.is_empty():
			battle.ledger.absolute_guard_hit_intents[resolving_intent_id] = true
		if battle.has_passive(target_actor_id, &"oath_vow"):
			# One action grants one stack per carrier: the key names the carrier
			# as well as the action, so a multi-target intent that lands on two
			# passive carriers still grants each of them their single stack, and
			# a multi-segment action still grants a lone carrier only one.
			var intent_key: String = "%s:%s" % [resolving_intent_id, target_actor_id] if not resolving_intent_id.is_empty() else "%d:%s:%s:%s" % [battle.turn_number, source_actor_id, action_id, target_actor_id]
			if not battle.ledger.oath_vow_triggered_intents.has(intent_key):
				battle.ledger.oath_vow_triggered_intents[intent_key] = true
				var current_vow_stacks: int = battle.get_oath_vow_stacks(target_actor_id)
				if current_vow_stacks < 3:
					statuses.apply_status(&"oath_vow", source_actor_id, target_actor_id, 1, 3, -1, &"", &"add")
					battle._emit_event("status_applied", source_actor_id, target_actor_id, "status=oath_vow stacks=%d" % battle.get_oath_vow_stacks(target_actor_id))

	if applied > 0:
		if target.team == "enemy":
			battle.damage_dealt += applied
		elif target.team == "player":
			battle.damage_taken += applied

	battle._emit_event("damage_applied", source_actor_id, target_actor_id, "action=%s type=%s public_intent=%s critical=%s raw=%d absorbed=%d applied=%d health=%d shield=%d" % [action_id, damage_type, str(is_public_intent), str(damage_result.get("was_critical", false)), amount, int(damage_result.get("absorbed", 0)), applied, target.health, target.shield])

	if target.is_defeated():
		# Snapshot death-time statuses before generic defeat cleanup removes them.
		DestLeeSkillEffectsScript.on_target_defeated(battle, target, source_actor_id, action_id)
		var removed_statuses: int = statuses.clear_actor(target_actor_id)
		if removed_statuses > 0:
			battle._emit_event("statuses_cleared", target_actor_id, "", "reason=actor_defeated count=%d" % removed_statuses)
	if target.is_defeated() and target.team == "enemy":
		if applied > 0:
			battle.enemies_defeated += 1
		battle.drop_enemy_equipment(target)
		for intent in battle.intents:
			if intent.source_actor_id == target_actor_id and intent.intent_id != resolving_intent_id:
				intent.cancel("source_defeated")
		battle._emit_event("actor_defeated", target_actor_id, "", "enemy")
		TacticalPressureScript.on_enemy_defeated(battle, target)
	elif was_hit and target.team == "enemy" and target.is_alive():
		TacticalPressureScript.on_enemy_hit(battle, attacker, target, action_id)
