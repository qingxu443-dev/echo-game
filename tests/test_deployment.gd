extends "res://tests/framework/test_case.gd"

## §11.1 部署阶段。
##
## The document puts a placement step between "the board exists" and "the first
## turn starts", with four hard negatives that are easy to get wrong: it spends no
## AP, advances no turn, lets no enemy act, and does not fire the effects that
## belong to battle start. A naive implementation that simply reuses the normal
## start would pass a "can I place my character" test and fail all four.
##
## The spring run is the only path that defers today, so these assertions drive
## the controller the way the spring battle view does.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const PlannerScript = preload("res://scripts/battle/intent_planner.gd")
const BattleActorScript = preload("res://scripts/actors/battle_actor.gd")

const HERO_CELL := Vector2i(3, 6)
const ENEMY_CELL := Vector2i(3, 1)


## The spring battle passes `defer_start = true`; `deploy_cells` empty means the
## battlefield's default southern zone.
func _begin_deploying(obstacles: Array[Vector2i] = [], deploy_cells: Array[Vector2i] = []):
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ok := battle.start_encounter(
		HERO_CELL, [ENEMY_CELL], obstacles, ["petal_warrior"], [], [], [], 0, deploy_cells, true
	)
	_check(ok, "the encounter accepts a deferred start")
	return battle


func _run() -> void:
	_test_deployment_pauses_the_clock()
	_test_deployment_spends_no_ap_and_fires_no_start_effects()
	_test_only_the_zone_accepts_a_placement()
	_test_obstacles_and_enemies_are_not_placeable()
	_test_placement_can_be_adjusted_before_confirming()
	_test_confirm_requires_everyone_placed()
	_test_confirm_starts_the_first_turn()
	_test_custom_zone_overrides_the_default()


## §11.1: "部署阶段不消耗AP、不计回合、不触发敌人行动".
func _test_deployment_pauses_the_clock() -> void:
	var battle = _begin_deploying()
	_check(battle.phase == battle.BattlePhase.DEPLOY, "the encounter opens in DEPLOY", "phase=%d" % battle.phase)
	_check(battle.turn_number == 0, "no turn has started yet", "turn=%d" % battle.turn_number)
	_check(battle.intents.is_empty(), "no enemy intent has been planned", "n=%d" % battle.intents.size())
	_check(not battle.end_player_turn(), "the player cannot end a turn that has not begun")
	_check(battle.phase == battle.BattlePhase.DEPLOY, "the refused turn did not advance the phase")
	_check(battle.turn_number == 0, "the refused turn did not advance the clock")
	battle.queue_free()


## Start-of-battle effects live in begin_player_turn (§11.1 says they belong to
## the real battle, not to placement). If deferring ever collapses into "start
## normally then flip a flag", the resource tick is the first thing that leaks.
func _test_deployment_spends_no_ap_and_fires_no_start_effects() -> void:
	var battle = _begin_deploying()
	var hero = battle.get_actor("sevrin")
	var ap_before: int = battle.ap.current
	var resource_before: int = hero.resource_current
	var energy_before: int = hero.ultimate_energy

	battle.request_deploy(Vector2i(4, 6))

	_check(battle.ap.current == ap_before, "placing a character costs no AP", "ap=%d" % battle.ap.current)
	_check(hero.resource_current == resource_before, "no turn-start resource tick during deployment")
	_check(hero.ultimate_energy == energy_before, "no turn-start energy tick during deployment")
	_check(hero.cell == Vector2i(4, 6), "the character is where the player put them")
	battle.queue_free()


## §11.1: "玩家只能在指定部署区部署，不能放入敌方区域".
func _test_only_the_zone_accepts_a_placement() -> void:
	var battle = _begin_deploying()
	var hero = battle.get_actor("sevrin")
	var home: Vector2i = hero.cell

	_check(not battle.request_deploy(Vector2i(3, 1)), "the enemy's own tile is not a deployment cell")
	_check(not battle.request_deploy(Vector2i(3, 4)), "the midfield is outside the zone")
	_check(hero.cell == home, "a refused placement does not move the character")

	_check(battle.is_deploy_cell(Vector2i(0, 7)), "the south-west corner is inside the zone")
	_check(battle.is_deploy_cell(Vector2i(7, 5)), "the north edge of the zone is inside it")
	_check(not battle.is_deploy_cell(Vector2i(0, 4)), "one row above the zone is outside it")
	battle.queue_free()


func _test_obstacles_and_enemies_are_not_placeable() -> void:
	var blocked := Vector2i(5, 7)
	var battle = _begin_deploying([blocked] as Array[Vector2i])
	_check(not battle.request_deploy(blocked), "an obstacle cell rejects placement")

	var occupied := Vector2i(6, 7)
	var blocker = BattleActorScript.new("boss_probe_00", "enemy", occupied, 100, "petal_warrior", 10, 0, 0)
	battle.actors[blocker.actor_id] = blocker
	_check(not battle.request_deploy(occupied), "a cell held by an enemy rejects placement")

	var chest_cell := Vector2i(1, 5)
	battle.beacons[chest_cell] = {"id": "chest_block", "cell": chest_cell, "health": 2, "max_health": 2}
	_check(not battle.request_deploy(chest_cell), "a cell holding an intact relic chest rejects placement")
	battle.queue_free()


## §11.1: "确认前可调整位置".
func _test_placement_can_be_adjusted_before_confirming() -> void:
	var battle = _begin_deploying()
	var hero = battle.get_actor("sevrin")

	_check(battle.request_deploy(Vector2i(1, 6)), "first placement")
	_check(hero.cell == Vector2i(1, 6), "the hero is on the first cell")
	_check(battle.all_deployed(), "a one-character roster is placed after one tap")

	_check(battle.request_deploy(Vector2i(6, 7)), "second tap relocates instead of being refused")
	_check(hero.cell == Vector2i(6, 7), "the hero moved to the adjusted cell")
	_check(battle.all_deployed(), "the roster is still fully placed after adjusting")
	battle.queue_free()


func _test_confirm_requires_everyone_placed() -> void:
	var battle = _begin_deploying()
	var hero = battle.get_actor("sevrin")
	# Start the hero off-zone by hand: the only way to reach "confirm before
	# placing" is a roster that still has an unplaced member.
	hero.cell = ENEMY_CELL + Vector2i(1, 0)
	battle.deploy_index = 0
	_check(not battle.all_deployed(), "the roster is not placed yet")
	_check(not battle.request_begin_battle(), "confirm is refused while someone is unplaced")
	_check(battle.phase == battle.BattlePhase.DEPLOY, "the refused confirm keeps the deployment phase")
	battle.queue_free()


func _test_confirm_starts_the_first_turn() -> void:
	var battle = _begin_deploying()
	var hero = battle.get_actor("sevrin")
	battle.request_deploy(Vector2i(4, 6))
	var energy_before: int = hero.ultimate_energy

	_check(battle.request_begin_battle(), "confirm is accepted once the roster is placed")
	_check(battle.phase == battle.BattlePhase.PLAYER, "the battle is now in the player phase", "phase=%d" % battle.phase)
	_check(battle.turn_number == 1, "the first turn started", "turn=%d" % battle.turn_number)
	_check(not battle.intents.is_empty(), "enemy intents are planned only now", "n=%d" % battle.intents.size())
	_check(hero.ultimate_energy == energy_before + 1, "the turn-start gauge tick fires on battle start, not before")
	_check(battle.ap.current == battle.team_ap, "the turn starts with a full AP pool", "ap=%d" % battle.ap.current)
	battle.queue_free()


## §11.1: "部署区形状可变化". A level that passes its own cells must get exactly
## those, not the default southern band as well.
func _test_custom_zone_overrides_the_default() -> void:
	var corridor: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4)]
	var battle = _begin_deploying([], corridor)
	_check(battle.deploy_zone.size() == 3, "only the authored cells are in the zone", "n=%d" % battle.deploy_zone.size())
	_check(battle.is_deploy_cell(Vector2i(0, 3)), "an authored cell is accepted")
	_check(not battle.is_deploy_cell(Vector2i(4, 7)), "the default southern band is not added on top")
	_check(battle.request_deploy(Vector2i(0, 3)), "the hero can be placed in the custom zone")
	battle.queue_free()
