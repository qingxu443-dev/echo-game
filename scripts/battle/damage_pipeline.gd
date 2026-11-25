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
	var target = actors[target_actor_id]

	var damage_result: Dictionary = target.apply_damage_with_result(amount, damage_type)
	var applied: int = int(damage_result.get("health_damage", 0))
	var was_hit: bool = bool(damage_result.get("hit", false))

	## Unified hit semantics: any damage instance that reached this living actor
	## counts as a hit, even when a shield fully absorbs it. Guard bookkeeping and
	## Oath Vow follow this one rule. The settlement tallies below intentionally
	## stay health-based so they report real attrition.
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

	battle._emit_event("damage_applied", source_actor_id, target_actor_id, "action=%s type=%s public_intent=%s raw=%d absorbed=%d applied=%d health=%d shield=%d" % [action_id, damage_type, str(is_public_intent), amount, int(damage_result.get("absorbed", 0)), applied, target.health, target.shield])

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
