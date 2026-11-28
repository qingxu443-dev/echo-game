extends "res://tests/framework/test_case.gd"

## Design plan §12: a party member at zero health is downed, not removed.
##
## Downed means: cannot act, cannot be targeted, still occupies its cell, and can
## be brought back by a revival skill. Defeat only happens when the whole party
## is down. Enemies have no downed state - they die.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const ActorScript = preload("res://scripts/actors/battle_actor.gd")


func _run() -> void:
	_test_zero_health_downs_a_party_member()
	_test_a_downed_body_still_blocks_its_cell()
	_test_a_downed_member_cannot_act()
	_test_revival_restores_the_member()
	_test_a_standing_member_cannot_be_topped_up()
	_test_defeat_requires_the_whole_party_down()
	_test_defeat_without_sevrin()
	_test_command_hands_over_to_a_standing_member()
	_test_oath_shield_revives_a_downed_member()
	_test_revival_is_once_per_member_per_encounter()
	_test_enemies_are_not_downed()
	_report()


func _make_battle() -> Node:
	var battle = ControllerScript.new()
	root.add_child(battle)
	# Enemy at distance 2: inside Judgment Mark range, so a rejected cast can only
	# be about the caster being downed rather than about range or line of sight.
	battle.start_encounter(Vector2i(1, 1), [Vector2i(3, 1)])
	battle.actors["ally"] = ActorScript.new("ally", "player", Vector2i(1, 2), 1000, "support", 300, 100, 100)
	return battle


func _test_zero_health_downs_a_party_member() -> void:
	var battle = _make_battle()
	var sevrin = battle.get_actor("sevrin")
	battle._apply_damage("sevrin", 999999, "vanguard_00", "test_strike", "physical")

	_check(sevrin.health == 0, "lethal damage leaves health at zero")
	_check(sevrin.is_defeated(), "a unit at zero health is out of the fight")
	_check(sevrin.is_downed(), "a party member at zero health is downed, not deleted")
	_check(not sevrin.is_alive(), "a downed member is not alive")
	_check(battle.actors.has("sevrin"), "a downed member stays in the roster")
	battle.queue_free()


func _test_a_downed_body_still_blocks_its_cell() -> void:
	var battle = _make_battle()
	var sevrin = battle.get_actor("sevrin")
	var cell: Vector2i = sevrin.cell
	battle._apply_damage("sevrin", 999999, "vanguard_00", "test_strike", "physical")

	_check(sevrin.blocks_cell(), "a downed body still occupies its cell")
	var occupied: Dictionary = battle.get_occupied_cells()
	_check(occupied.has(cell), "the downed member's cell reads as occupied")
	_check(battle.get_occupied_cells("sevrin").has(cell) == false, "a unit does not block itself when the caller excludes it")
	battle.queue_free()


func _test_a_downed_member_cannot_act() -> void:
	var battle = _make_battle()
	battle._apply_damage("sevrin", 999999, "vanguard_00", "test_strike", "physical")

	_check(not battle.request_oathkeeper_judgment_mark("vanguard_00"), "a downed member cannot cast a targeted skill")
	_check(not battle.request_oath_shield("ally"), "a downed member cannot cast a support skill")
	# Typed first: an inline literal is an untyped Array, so passing one straight
	# into request_player_move raised a type error, and `not <error>` read as a
	# pass. The check has to reach the controller to mean anything.
	var step: Array[Vector2i] = [Vector2i(2, 1)]
	_check(not battle.request_player_move(step), "a downed member cannot move")
	_check(battle.ap.current == battle.ap.maximum, "rejected actions from a downed member spend nothing")
	battle.queue_free()


func _test_revival_restores_the_member() -> void:
	var battle = _make_battle()
	var sevrin = battle.get_actor("sevrin")
	var cell: Vector2i = sevrin.cell
	battle._apply_damage("sevrin", 999999, "vanguard_00", "test_strike", "physical")

	_check(sevrin.revive(600), "a downed member can be revived")
	_check(sevrin.health == 600, "revival restores the health the skill grants")
	_check(sevrin.is_alive() and not sevrin.is_downed(), "a revived member is alive and no longer downed")
	_check(sevrin.cell == cell, "a revived member returns on its original cell")
	_check(battle.request_oathkeeper_judgment_mark("vanguard_00"), "a revived member can act again")
	battle.queue_free()


func _test_a_standing_member_cannot_be_topped_up() -> void:
	var battle = _make_battle()
	var sevrin = battle.get_actor("sevrin")
	sevrin.health = 400

	_check(not sevrin.revive(600), "revival is rejected while the member is still standing")
	_check(sevrin.health == 400, "the rejected revival does not heal a standing member")
	battle.queue_free()


func _test_defeat_requires_the_whole_party_down() -> void:
	var battle = _make_battle()
	var sevrin = battle.get_actor("sevrin")
	var ally = battle.get_actor("ally")

	battle._apply_damage("sevrin", 999999, "vanguard_00", "test_strike", "physical")
	battle._check_battle_end()
	_check(battle.phase != ControllerScript.BattlePhase.FINISHED, "one downed member does not end the battle while another stands")
	_check(battle.battle_result == "", "no result is recorded while the party can still fight")

	battle._apply_damage("ally", 999999, "vanguard_00", "test_strike", "physical")
	battle._check_battle_end()
	_check(battle.phase == ControllerScript.BattlePhase.FINISHED, "the battle ends when the whole party is down")
	_check(battle.battle_result == "defeat", "the result is defeat")
	battle.queue_free()


## Defeat must not hinge on Sevrin being in the party: the guard used to require
## his presence, so any other roster could never lose.
func _test_defeat_without_sevrin() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var roster: Array[String] = ["sakura"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 4)], [], [], roster, [])
	battle._apply_damage("sakura", 999999, "vanguard_00", "test_strike", "physical")
	battle._check_battle_end()
	_check(battle.phase == ControllerScript.BattlePhase.FINISHED, "a party without Sevrin can still be defeated")
	_check(battle.battle_result == "defeat", "the result is defeat whatever the roster holds")
	battle.queue_free()


## A commander who falls during the enemy phase used to stay selected, so the new
## turn opened on a character who could not act.
func _test_command_hands_over_to_a_standing_member() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)], [], [], ids, [Vector2i(1, 2)])

	battle._apply_damage("sevrin", 999999, "vanguard_00", "test_strike", "physical")
	_check(battle.active_character_id == "sevrin", "the downed commander stays selected until the turn turns over")

	battle._begin_player_turn()
	_check(battle.active_character_id == "sakura", "the next player turn hands command to a standing member")
	_check(battle.get_active_character().is_alive(), "the commanded member can act")
	battle.queue_free()


func _test_enemies_are_not_downed() -> void:
	var battle = _make_battle()
	var enemy = battle.get_actor("vanguard_00")
	battle._apply_damage("vanguard_00", 999999, "sevrin", "test_strike", "physical")

	_check(enemy.is_defeated(), "a lethal hit removes an enemy")
	_check(not enemy.is_downed(), "enemies have no downed state")
	battle.queue_free()


## §12 named "a specific skill" as the revival path; Oath Shield is it. The
## design plan leaves the restored health and the revival count to the skill:
## both are defined here as the shield's own DEF-scaled value, and once per
## member per encounter.
func _test_oath_shield_revives_a_downed_member() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	var ally_cells: Array[Vector2i] = [Vector2i(1, 2)]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], [], ids, ally_cells)
	var sakura = battle.get_actor("sakura")
	var cell: Vector2i = sakura.cell
	battle._apply_damage("sakura", 999999, "vanguard_00", "test_strike", "physical")
	_check(sakura.is_downed(), "Sakura is down before the revival")

	_check(battle.request_oath_shield("sakura"), "Oath Shield revives the downed member")
	_check(sakura.is_alive() and not sakura.is_downed(), "the revived member is standing again")
	# Oath Shield = 200% of Sevrin's 360 DEF = 720; Sakura's shield cap is 30% of 2100 max health = 630.
	_check(sakura.health == 720, "revival restores shield-strength health")
	_check(sakura.cell == cell, "revival returns the member to its own cell")
	_check(sakura.shield == 630, "the revived member also carries the shield up to its 30% cap")
	_check(battle.ap.current == 2, "the revival cast spends one AP from the shared pool")

	battle.set_active_character("sakura")
	_check(battle.request_player_move([Vector2i(2, 2)]), "the revived member can act again")
	battle.queue_free()


func _test_revival_is_once_per_member_per_encounter() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	var ally_cells: Array[Vector2i] = [Vector2i(1, 2)]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], [], ids, ally_cells)
	var sakura = battle.get_actor("sakura")

	battle._apply_damage("sakura", 999999, "vanguard_00", "test_strike", "physical")
	_check(battle.request_oath_shield("sakura"), "the first revival resolves")
	battle._apply_damage("sakura", 999999, "vanguard_00", "test_strike", "physical")
	_check(sakura.is_downed(), "the revived member can go down again")
	_check(not battle.request_oath_shield("sakura"), "a second revival of the same member this encounter is refused")
	_check(battle.ap.current == 2, "the refused re-revival spends nothing")

	var distant = ControllerScript.new()
	root.add_child(distant)
	var far_cells: Array[Vector2i] = [Vector2i(6, 1)]
	distant.start_encounter(Vector2i(1, 1), [Vector2i(3, 5)], [], [], ids, far_cells)
	distant._apply_damage("sakura", 999999, "vanguard_00", "test_strike", "physical")
	_check(distant.get_actor("sakura").is_downed(), "the distant member is down")
	_check(not distant.request_oath_shield("sakura"), "a downed member beyond two cells cannot be reached")
	distant.queue_free()
	battle.queue_free()
