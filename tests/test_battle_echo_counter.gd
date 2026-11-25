extends "res://tests/framework/test_case.gd"

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")


func _run() -> void:
	_test_oathguard_grants_echo_and_counter()
	_test_marked_attacker_consumes_echo_for_stronger_counter()
	_test_non_intent_damage_does_not_grant_echo()
	_test_evaded_intent_does_not_trigger_counter()
	_test_lethal_counter_preserves_resolved_intent()
	_test_fully_absorbed_hit_triggers_defensive_responses()
	_report()


func _test_oathguard_grants_echo_and_counter() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var marksman_types: Array[String] = ["marksman"]
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "Echo Counter marksman encounter starts")
	_check(battle.request_oathguard_stance(), "Oathguard Stance can be prepared through its skill API")
	_check(battle.request_echo_counter(), "Echo Counter can be prepared through its skill API")
	_check(battle.statuses.apply_status(&"echo_counter", "marksman_00", "marksman_00", 1, 1, -1, &""), "enemy can hold a counter status for recursion protection test")
	_check(battle.end_player_turn(), "public aimed shot resolves against prepared defender")
	_check(battle.get_actor("sevrin").health == 11528, "Oathguard reduces post-resistance shot damage by 35 percent")
	_check(not battle.statuses.has_status("sevrin", &"oathguard"), "Oathguard is consumed by the successful hit")
	_check(battle.statuses.has_status("sevrin", &"echo"), "Oathguard grants Echo only after a public enemy intent hits")
	_check(not battle.statuses.has_status("sevrin", &"echo_counter"), "Echo Counter is consumed after one successful trigger")
	_check(battle.get_actor("marksman_00").health == 815, "unmarked attacker receives a 0.8x physical counter")
	_check(battle.statuses.has_status("marksman_00", &"echo_counter"), "counter damage does not recursively trigger another counter")
	battle.queue_free()


func _test_marked_attacker_consumes_echo_for_stronger_counter() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var marksman_types: Array[String] = ["marksman"]
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "marked Echo Counter encounter starts")
	_check(battle.statuses.apply_status(&"echo", "sevrin", "sevrin", 1, 1, -1, &""), "defender can carry one Echo charge")
	_check(battle.request_judgment_mark("marksman_00"), "attacker can be marked before its revealed shot")
	_check(battle.request_echo_counter(), "defender can prepare Echo Counter alongside the mark")
	_check(battle.end_player_turn(), "marked shot triggers the prepared counter")
	_check(battle.get_actor("sevrin").health == 11455, "marked aimed shot retains its 25 percent raw damage reduction")
	_check(battle.get_actor("marksman_00").health == 519, "marked attacker receives a 1.0x physical counter")
	_check(not battle.statuses.has_status("sevrin", &"echo"), "enhanced counter consumes one Echo charge")
	_check(not battle.statuses.has_status("sevrin", &"echo_counter"), "enhanced counter consumes the prepared trigger")
	battle.queue_free()


func _test_non_intent_damage_does_not_grant_echo() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var marksman_types: Array[String] = ["marksman"]
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "non-intent damage encounter starts")
	_check(battle.request_oathguard_stance(), "Oathguard can be prepared for a non-intent damage check")
	battle._apply_damage("sevrin", 1000, "marksman_00", "scripted_damage", "physical", false)
	_check(not battle.statuses.has_status("sevrin", &"oathguard"), "Oathguard still absorbs one successful damage instance")
	_check(not battle.statuses.has_status("sevrin", &"echo"), "non-intent damage cannot grant Echo")
	battle.queue_free()


func _test_evaded_intent_does_not_trigger_counter() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var marksman_types: Array[String] = ["marksman"]
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "evaded Echo Counter encounter starts")
	var shot_intent = battle.intents[0]
	_check(battle.request_echo_counter(), "Echo Counter can be prepared before evading")
	var retreat_path: Array[Vector2i] = [Vector2i(1, 2)]
	_check(battle.request_player_move(retreat_path), "player can leave the telegraphed tile")
	_check(battle.end_player_turn(), "evaded shot resolves without a hit")
	_check(battle.get_actor("sevrin").health == 12000, "evaded public intent deals no damage")
	_check(shot_intent.state == IntentScript.IntentState.CANCELED, "empty marked tile cancels the shot")
	_check(not battle.statuses.has_status("sevrin", &"echo_counter"), "unused Echo Counter expires at enemy phase end")
	_check(not battle.statuses.has_status("sevrin", &"echo"), "evading does not create Echo")
	battle.queue_free()


func _test_lethal_counter_preserves_resolved_intent() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var marksman_types: Array[String] = ["marksman"]
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "lethal counter encounter starts")
	var shot_intent = battle.intents[0]
	battle.get_actor("marksman_00").health = 1000
	_check(battle.request_echo_counter(), "lethal counter can be prepared")
	_check(battle.end_player_turn(), "public intent resolves before its lethal counter")
	_check(battle.get_actor("marksman_00").is_defeated, "counter can defeat its attacker")
	_check(shot_intent.state == IntentScript.IntentState.RESOLVED, "an intent that landed before a lethal counter remains resolved")
	_check(battle.phase == ControllerScript.BattlePhase.FINISHED and battle.battle_result == "victory", "defeating the final attacker ends the encounter in victory")
	battle.queue_free()


## Unified hit semantics: a public enemy hit that a shield fully absorbs still
## counts as a hit. The defensive stance is consumed, Echo is granted and the
## prepared counter fires -- exactly like any other landed attack.
func _test_fully_absorbed_hit_triggers_defensive_responses() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var marksman_types: Array[String] = ["marksman"]
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "fully absorbed hit encounter starts")
	var sevrin = battle.get_actor("sevrin")
	var marksman = battle.get_actor("marksman_00")
	_check(battle.request_oathguard_stance(), "Oathguard stance is prepared")
	_check(battle.request_echo_counter(), "Echo Counter is prepared")
	sevrin.shield = 500
	var health_before: int = sevrin.health
	_check(battle.end_player_turn(), "the aimed shot resolves against the shielded defender")
	_check(sevrin.health == health_before, "the fully absorbed hit removes no health")
	_check(sevrin.shield == 500 - 472, "the shield absorbs the entire post-reduction damage")
	_check(not battle.statuses.has_status("sevrin", &"oathguard"), "a fully absorbed hit still consumes the defensive stance")
	_check(battle.statuses.has_status("sevrin", &"echo"), "a fully absorbed public hit still grants Echo")
	_check(not battle.statuses.has_status("sevrin", &"echo_counter"), "a fully absorbed public hit still triggers the prepared counter")
	_check(marksman.health == 815, "the counter strikes the attacker at the standard 0.8 multiplier")
	_check(battle.damage_taken == 0, "the settlement tally ignores shield-absorbed damage")
	battle.queue_free()

