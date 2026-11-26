extends "res://tests/framework/test_case.gd"

## Covers the hunter summon: a free single strike on a two-turn cooldown that
## leaves no unit behind. Exercises the cooldown accounting, the deterministic
## appearance cell, the refusal paths, and the interaction with battle end.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const SummonCatalogScript = preload("res://scripts/battle/summon_catalog.gd")


func _run() -> void:
	_check_ready_on_a_fresh_encounter()
	_check_strike_cost_and_cooldown()
	_check_no_appearance_room()
	_check_invalid_targets()
	_check_lethal_strike_ends_the_battle()

	_test_summon_framework()
	_report()


## The summon is data now, not a controller constant with a view-side roster.
func _test_summon_framework() -> void:
	_check(SummonCatalogScript.has_definition(&"yu_bubble"), "the summon catalog exposes the starter summon")
	var definition = SummonCatalogScript.get_definition(&"yu_bubble")
	_check(definition.is_valid(), "the summon definition validates")
	_check(definition.cooldown_turns == 2, "the cooldown comes from the definition")
	_check(definition.ap_cost == 0, "the summon is free as the plan states")

	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 4)])
	_check(not battle.request_skill(&"summon:missing", "vanguard_00"), "an unknown summon id is refused")

	# Summons belong to the player, so a character without one still offers it.
	var sakura_ids: Array[String] = ["sakura"]
	var sakura_battle = ControllerScript.new()
	root.add_child(sakura_battle)
	sakura_battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], sakura_ids, [])
	_check(sakura_battle.request_skill(&"summon:yu_bubble", "vanguard_00"), "Sakura can call the summon")
	_check(sakura_battle.summon_cooldown_remaining(&"yu_bubble") > 0, "the summon enters its cooldown for any character")
	battle.queue_free()
	sakura_battle.queue_free()


func _check_ready_on_a_fresh_encounter() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(7, 7)]), "a fresh encounter starts")
	_check(battle.summon_cooldown_remaining() == 0, "the summon is ready on turn one")
	_check(battle.can_summon(), "the summon reports available without a target")
	_check(battle.can_summon("vanguard_00"), "the summon reports available for a living enemy")
	battle.queue_free()


func _check_strike_cost_and_cooldown() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(7, 7)])
	var enemy = battle.get_actor("vanguard_00")
	var ap_before: int = battle.ap.current
	var actors_before: int = battle.actors.size()
	var occupied_before: int = battle.get_occupied_cells().size()
	var intents_before: int = battle.intents.size()

	# The strike magnitude is a prototype baseline; pin it so a silent change
	# here cannot slip past the documentation.
	var definition = SummonCatalogScript.get_definition(&"yu_bubble")
	var raw: int = CombatMathScript.calculate_raw_damage(definition.attack, definition.damage_multiplier)
	_check(raw == 1260, "the summon raw strike is the documented baseline of 1260")

	var expected_damage: int = CombatMathScript.calculate_damage(raw, enemy.defense)
	var enemy_health_before: int = enemy.health
	_check(battle.request_hunter_summon("vanguard_00"), "the hunter can be summoned on a living enemy")
	_check(battle.ap.current == ap_before, "the summon does not spend action points", "ap %d -> %d" % [ap_before, battle.ap.current])
	_check(enemy.health == enemy_health_before - expected_damage, "the strike deals defence-mitigated damage", "health=%d" % enemy.health)
	_check(battle.actors.size() == actors_before, "the hunter is not added as a battlefield unit")
	_check(battle.get_occupied_cells().size() == occupied_before, "the hunter does not occupy a cell")
	_check(battle.intents.size() == intents_before, "the hunter does not enter the intent order")

	_check(battle.summon_cooldown_remaining() == 2, "the summon starts a two-turn cooldown")
	_check(not battle.can_summon("vanguard_00"), "the summon is unavailable during the cooldown")
	var health_during_cooldown: int = enemy.health
	_check(not battle.request_hunter_summon("vanguard_00"), "a second summon is refused during the cooldown")
	_check(enemy.health == health_during_cooldown, "a refused summon deals no damage")
	_check(battle.summon_cooldown_remaining() == 2, "a refused summon does not restart the cooldown")

	battle.end_player_turn()
	_check(battle.turn_number == 2, "the turn advances after the enemy phase")
	_check(battle.summon_cooldown_remaining() == 1, "the cooldown counts down on the next turn")
	_check(not battle.can_summon("vanguard_00"), "the summon is still blocked one turn later")

	battle.end_player_turn()
	_check(battle.turn_number == 3, "the turn advances again")
	_check(battle.summon_cooldown_remaining() == 0, "the cooldown reaches zero")
	_check(battle.can_summon("vanguard_00"), "the summon is available again after the cooldown")
	_check(battle.request_hunter_summon("vanguard_00"), "the summon can be used again after the cooldown")
	battle.queue_free()


func _check_no_appearance_room() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	# Surround the target completely: three blocked cells and one enemy.
	var blocked: Array[Vector2i] = [Vector2i(3, 4), Vector2i(4, 3), Vector2i(4, 5)]
	_check(
		battle.start_encounter(Vector2i(0, 0), [Vector2i(4, 4), Vector2i(5, 4)], blocked),
		"an encounter with a surrounded target starts"
	)
	var target = battle.get_actor("vanguard_00")
	var health_before: int = target.health
	_check(not battle.can_summon("vanguard_00"), "a fully surrounded target reports unavailable")
	_check(not battle.request_hunter_summon("vanguard_00"), "a summon with no free neighbour is refused")
	_check(target.health == health_before, "a refused summon leaves the target untouched")
	_check(battle.summon_cooldown_remaining() == 0, "a refused summon does not start the cooldown")
	battle.queue_free()


func _check_invalid_targets() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(7, 7)])
	_check(not battle.can_summon("sevrin"), "the summon rejects a friendly target")
	_check(not battle.can_summon("nobody"), "the summon rejects an unknown target")
	_check(not battle.request_hunter_summon("sevrin"), "requesting the summon on a friendly actor fails")
	_check(not battle.request_hunter_summon("nobody"), "requesting the summon on an unknown actor fails")
	_check(battle.summon_cooldown_remaining() == 0, "invalid requests do not start the cooldown")
	battle.queue_free()


func _check_lethal_strike_ends_the_battle() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)])
	var enemy = battle.get_actor("vanguard_00")
	enemy.health = 300
	_check(battle.request_hunter_summon("vanguard_00"), "the summon lands on a nearly dead enemy")
	_check(enemy.health == 0 and enemy.is_defeated(), "a lethal summon strike defeats the enemy")
	_check(battle.battle_result == "victory", "defeating the last enemy reports victory")
	_check(battle.phase == ControllerScript.BattlePhase.FINISHED, "the battle ends after the summon")
	_check(not battle.can_summon(), "the summon is unavailable once the battle ended")
	_check(not battle.request_hunter_summon("vanguard_00"), "a summon after the battle ends is refused")
	battle.queue_free()
