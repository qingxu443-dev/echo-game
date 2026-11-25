class_name DamagePipeline
extends RefCounted

## The single place where a hit is resolved.
##
## Order is fixed and must not be reordered: resistances (inside BattleActor) ->
## area reductions -> shield absorption -> final mitigation (oathguard) ->
## applied. Everything that reacts to a hit lives here as well - stat tallies,
## Oath Vow accumulation, Absolute Guard bookkeeping, defeat cleanup and the echo
## counter - because they are consequences of damage rather than of the action
## that caused it.
##
## Takes the controller as `battle` instead of inheriting from it, so the file
## can be read without the other thirty functions around it.

const CombatMathScript = preload("res://scripts/battle/combat_math.gd")


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
	var area_effects = battle.area_effects
	var target = actors[target_actor_id]

	var resistance_penalty: int = 200 if statuses.has_status(target_actor_id, &"exposed") else 0
	var final_reduction_percent: int = 0
	var triggered_statuses: Array[StringName] = []
	if statuses.has_status(target_actor_id, &"oathguard"):
		final_reduction_percent = 35
		triggered_statuses.append(&"oathguard")

	var area_reductions: Array[int] = area_effects.get_damage_reductions_for_actor(target)
	var damage_result: Dictionary = target.apply_damage_with_result(amount, damage_type, final_reduction_percent, resistance_penalty, area_reductions)
	var applied: int = int(damage_result.get("health_damage", 0))
	var was_hit: bool = bool(damage_result.get("hit", false))

	if was_hit and is_public_intent and target_actor_id == "sevrin" and actors.has(source_actor_id) and actors[source_actor_id].team == "enemy":
		if statuses.has_status("sevrin", &"absolute_guard") and not resolving_intent_id.is_empty():
			battle.absolute_guard_hit_intents[resolving_intent_id] = true
		var intent_key: String = resolving_intent_id if not resolving_intent_id.is_empty() else "%d:%s:%s" % [battle.turn_number, source_actor_id, action_id]
		if not battle.oath_vow_triggered_intents.has(intent_key):
			battle.oath_vow_triggered_intents[intent_key] = true
			var current_vow_stacks: int = battle.get_oath_vow_stacks("sevrin")
			if current_vow_stacks < 3:
				statuses.apply_status(&"oath_vow", source_actor_id, "sevrin", 1, 3, -1, &"", &"add")
				battle._emit_event("status_applied", source_actor_id, "sevrin", "status=oath_vow stacks=%d" % battle.get_oath_vow_stacks("sevrin"))

	if applied > 0:
		if target.team == "enemy":
			battle.damage_dealt += applied
		elif target.team == "player":
			battle.damage_taken += applied
		for status_id in triggered_statuses:
			statuses.consume_trigger(target_actor_id, status_id)
			battle._emit_event("status_triggered", target_actor_id, source_actor_id, "status=%s reduction=%d%%" % [status_id, final_reduction_percent])
			if status_id == &"oathguard" and is_public_intent and target.is_alive():
				statuses.apply_status(&"echo", target_actor_id, target_actor_id, 1, 1, -1, &"")
				battle._emit_event("status_applied", target_actor_id, target_actor_id, "status=echo stacks=1 source=public_enemy_intent")

	battle._emit_event("damage_applied", source_actor_id, target_actor_id, "action=%s type=%s public_intent=%s raw=%d resistance_penalty=%d area_reductions=%s final_reduction=%d%% absorbed=%d applied=%d health=%d shield=%d" % [action_id, damage_type, str(is_public_intent), amount, resistance_penalty, str(area_reductions), final_reduction_percent, int(damage_result.get("absorbed", 0)), applied, target.health, target.shield])

	if target.is_defeated:
		var removed_statuses: int = statuses.clear_actor(target_actor_id)
		if removed_statuses > 0:
			battle._emit_event("statuses_cleared", target_actor_id, "", "reason=actor_defeated count=%d" % removed_statuses)
	if target.is_defeated and target.team == "enemy":
		if applied > 0:
			battle.enemies_defeated += 1
		for intent in battle.intents:
			if intent.source_actor_id == target_actor_id and intent.intent_id != resolving_intent_id:
				intent.cancel("source_defeated")
		battle._emit_event("actor_defeated", target_actor_id, "", "enemy")

	if applied > 0 and is_public_intent and target.is_alive():
		resolve_echo_counter(battle, target_actor_id, source_actor_id, resolving_intent_id)


## Echo Counter is a reaction to being hit, so it belongs to the damage path.
## It re-enters apply() with is_public_intent = false, which is what stops it
## from chaining.
static func resolve_echo_counter(battle, defender_actor_id: String, attacker_actor_id: String, resolving_intent_id: String = "") -> void:
	var actors = battle.actors
	var statuses = battle.statuses
	if not actors.has(defender_actor_id) or not actors.has(attacker_actor_id):
		return
	var defender = actors[defender_actor_id]
	var attacker = actors[attacker_actor_id]
	if not defender.is_alive() or not attacker.is_alive():
		return
	if not statuses.has_status(defender_actor_id, &"echo_counter"):
		return

	var multiplier: float = 0.8
	if statuses.has_status(attacker_actor_id, &"judgment_mark") and statuses.has_status(defender_actor_id, &"echo"):
		statuses.remove_status(defender_actor_id, &"echo")
		multiplier = 1.0
	statuses.consume_trigger(defender_actor_id, &"echo_counter")
	var raw_damage: int = CombatMathScript.calculate_raw_damage(defender.attack, multiplier)
	battle._emit_event("status_triggered", defender_actor_id, attacker_actor_id, "status=echo_counter multiplier=%.2f" % multiplier)
	battle._apply_damage(attacker_actor_id, raw_damage, defender_actor_id, "echo_counter", "physical", false, resolving_intent_id)
	battle._emit_event("counter_resolved", defender_actor_id, attacker_actor_id, "skill=echo_counter multiplier=%.2f raw=%d" % [multiplier, raw_damage])
