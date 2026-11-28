extends "res://tests/framework/test_case.gd"

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const IntentPlannerScript = preload("res://scripts/battle/intent_planner.gd")


func _run() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)])
	battle.beacons.clear()
	battle.intents = IntentPlannerScript.plan(battle)

	_check(battle.damage_dealt == 0, "damage dealt starts at zero")
	_check(battle.damage_taken == 0, "damage taken starts at zero")
	_check(battle.enemies_defeated == 0, "defeat tally starts at zero")

	var enemy = battle.get_actor("vanguard_00")
	var enemy_health_before: int = enemy.health
	_check(battle.request_oathkeeper_judgment_mark("vanguard_00"), "player skill resolves")
	var dealt: int = enemy_health_before - enemy.health
	_check(dealt > 0, "player skill removed health from the enemy")
	_check(battle.damage_dealt == dealt, "damage dealt matches the health actually removed")
	_check(battle.damage_taken == 0, "player skill does not count as damage taken")

	var player = battle.get_actor("sevrin")
	player.health = 100000
	var player_health_before: int = player.health
	battle.end_player_turn()
	var taken: int = player_health_before - player.health
	_check(taken > 0, "enemy phase removed health from the player")
	_check(battle.damage_taken == taken, "damage taken matches the health actually removed")

	# Kill the enemy and confirm the defeat tally only counts real kills.
	enemy.health = 500
	var guard := 0
	while enemy.is_alive() and guard < 20:
		if not battle.request_oathkeeper_judgment_mark("vanguard_00"):
			battle.end_player_turn()
		guard += 1
	_check(not enemy.is_alive(), "enemy can be defeated in this scenario")
	_check(battle.enemies_defeated == 1, "defeating an enemy increments the tally once")
	battle.queue_free()

	# A fresh encounter clears the tallies.
	var fresh = ControllerScript.new()
	root.add_child(fresh)
	fresh.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)])
	fresh.request_oathkeeper_judgment_mark("vanguard_00")
	_check(fresh.damage_dealt > 0, "second encounter records damage")
	fresh.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)])
	_check(fresh.damage_dealt == 0 and fresh.damage_taken == 0 and fresh.enemies_defeated == 0, "restarting an encounter resets the tallies")
	fresh.queue_free()

	_report()
