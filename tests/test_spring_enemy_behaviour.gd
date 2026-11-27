extends "res://tests/framework/test_case.gd"

## 春之境敌人的战斗行为：它们必须真的会打人。
##
## Why this suite exists: the elite and boss sheets originally listed only an
## attack, never `pursuit`. The planner only repositions an enemy whose action
## list contains `pursuit`, so every elite and every boss stood still for the
## whole fight - a 5040 HP statue the player could walk away from. The sheets
## now carry `pursuit` plus `move_steps`; these assertions drive real turns and
## check that the enemy either closes the distance or lands a hit, which is the
## only thing a player would notice.
##
## Everything here runs the controller (not the data files) because reading
## `actions` back would stay green even if the planner ignored them.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const PlannerScript = preload("res://scripts/battle/intent_planner.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")

## The fourteen archetypes the spring templates can field (§13-§15).
const SPRING_ARCHETYPES := [
	"petal_warrior", "petal_archer", "withered_guard", "wind_ranger", "spring_blight",
	"crimson_sword_guard", "hundred_bloom_sniper", "ancient_bulwark", "gale_blade",
	"sakura_beast", "rotten_blossom_witch",
	"boss_petalfall", "boss_thousand_boughs", "boss_spring_echo",
]

const HERO_CELL := Vector2i(1, 3)
const ENEMY_CELL := Vector2i(7, 3)
const START_DISTANCE := 6


func _run() -> void:
	_test_every_enemy_advances_or_strikes()
	_test_move_steps_come_from_the_profile()
	_test_elite_and_boss_movement_matches_the_document()
	_test_bosses_are_not_statues()
	_test_bulwark_shields_an_ordinary_ally()
	_test_bulwark_never_shields_an_elite()
	_test_bulwark_range_is_two_cells()
	_test_bulwark_ward_waits_for_its_cooldown()
	_test_move_steps_must_be_positive()


## Builds a one-on-one fight. Beacons are removed and the intents replanned so
## the enemy is looking at the hero, not at a relic objective it would rather
## attack - the default spawn puts two beacons down and they would steal the
## target from this scenario.
func _spawn(archetype: String, hero_cell: Vector2i, enemy_cell: Vector2i):
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(hero_cell, [enemy_cell], [], [archetype])
	battle.beacons.clear()
	battle.intents = PlannerScript.plan(battle)
	return battle


## Same setup with several enemies, so warden/ally pairs can share a board.
## The literal arrays are untyped, and start_encounter wants typed ones, so they
## are converted here rather than every call site declaring two more variables.
func _spawn_group(enemy_cells: Array, archetypes: Array):
	var cells: Array[Vector2i] = []
	cells.assign(enemy_cells)
	var roster: Array[String] = []
	roster.assign(archetypes)
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(HERO_CELL, cells, [], roster)
	battle.beacons.clear()
	battle.intents = PlannerScript.plan(battle)
	return battle


func _planned_action(battle, actor_id: String) -> String:
	for intent in battle.intents:
		if intent.source_actor_id == actor_id:
			return String(intent.action_id)
	return ""


func _test_every_enemy_advances_or_strikes() -> void:
	var checked := 0
	for archetype in SPRING_ARCHETYPES:
		var battle = _spawn(archetype, HERO_CELL, ENEMY_CELL)
		var hero = battle.get_defender()
		var start_health: int = hero.health
		for turn in range(4):
			if battle.phase == battle.BattlePhase.FINISHED:
				break
			battle.end_player_turn()
		var enemy = battle.get_actor(String(archetype) + "_00")
		_check(enemy != null, "%s stays on the board" % archetype)
		if enemy == null:
			battle.queue_free()
			continue
		checked += 1
		var distance: int = GridRulesScript.manhattan_distance(enemy.cell, HERO_CELL)
		var closed_in: bool = distance < START_DISTANCE
		var struck: bool = hero.health < start_health
		_check(
			closed_in or struck,
			"%s either closes the gap or lands a hit in four turns" % archetype,
			"distance=%d health=%d->%d" % [distance, start_health, hero.health]
		)
		battle.queue_free()
	_check(checked == SPRING_ARCHETYPES.size(), "every spring archetype was exercised, not skipped")


## One turn from the same tile, three different budgets. If the planner ignored
## `move_steps` every case would end two cells closer and the heavy guard would
## silently catch up with the wind runner.
func _test_move_steps_come_from_the_profile() -> void:
	var cases := [
		{"archetype": "withered_guard", "steps": 1, "expected": Vector2i(6, 3)},
		{"archetype": "vanguard", "steps": 2, "expected": Vector2i(5, 3)},
		{"archetype": "wind_ranger", "steps": 3, "expected": Vector2i(4, 3)},
	]
	for case in cases:
		var archetype: String = case["archetype"]
		var battle = _spawn(archetype, HERO_CELL, ENEMY_CELL)
		var enemy = battle.get_actor(archetype + "_00")
		_check(enemy.move_steps == case["steps"], "%s carries its profile's move budget (%d)" % [archetype, case["steps"]])
		battle.end_player_turn()
		_check(
			enemy.cell == case["expected"],
			"%s covers exactly %d cells in its first turn" % [archetype, case["steps"]],
			"cell=%s expected=%s" % [str(enemy.cell), str(case["expected"])]
		)
		battle.queue_free()


## §14 and §15 both print a movement column for the six elites and three bosses,
## so those nine numbers are the document's own, not a draft. The ordinary
## archetypes have no such column, which is why their 1/2/3 budgets are draft and
## are exercised in the scenario above instead of pinned here.
func _test_elite_and_boss_movement_matches_the_document() -> void:
	var table := {
		"crimson_sword_guard": 2,
		"hundred_bloom_sniper": 2,
		"ancient_bulwark": 1,
		"gale_blade": 3,
		"rotten_blossom_witch": 1,
		"sakura_beast": 1,
		"boss_petalfall": 2,
		"boss_thousand_boughs": 1,
		"boss_spring_echo": 1,
	}
	for archetype in table:
		var definition: EnemyDefinition = EnemyCatalogScript.get_definition(archetype)
		_check(definition != null, "%s has a sheet" % archetype)
		if definition == null:
			continue
		_check(
			definition.move_steps == table[archetype],
			"%s moves %d cells (§14/§15)" % [archetype, table[archetype]],
			"sheet says %d" % definition.move_steps
		)


## The three bosses are solo fights, so a boss that cannot move is a fight that
## cannot be lost. Six turns against a hero who never acts is the cheapest proof
## that it reaches the player.
func _test_bosses_are_not_statues() -> void:
	for boss in ["boss_petalfall", "boss_thousand_boughs", "boss_spring_echo"]:
		var battle = _spawn(boss, HERO_CELL, ENEMY_CELL)
		var hero = battle.get_defender()
		var start_health: int = hero.health
		for turn in range(6):
			if battle.phase == battle.BattlePhase.FINISHED:
				break
			battle.end_player_turn()
		_check(
			hero.health < start_health,
			"%s damages a hero who never moves" % boss,
			"health=%d->%d" % [start_health, hero.health]
		)
		battle.queue_free()


## 古木壁垒 (§14): 500 shield onto one *ordinary* ally within two cells. The
## fight is built around this - "壁垒" that does not shield anybody is just a
## slow guard - so the assertion reads the ally's actual shield after a turn.
func _test_bulwark_shields_an_ordinary_ally() -> void:
	var battle = _spawn_group(
		[Vector2i(4, 4), Vector2i(5, 4)],
		["ancient_bulwark", "petal_warrior"]
	)
	var warden = battle.get_actor("ancient_bulwark_00")
	var ally = battle.get_actor("petal_warrior_01")
	_check(warden.ward_shield == 500, "the bulwark carries the document's 500 shield")
	var planned := _planned_action(battle, "ancient_bulwark_00")
	_check(planned == "ward_ally", "the bulwark opens with its ward, not a walk", "planned=%s" % planned)
	battle.end_player_turn()
	_check(ally.shield == 500, "the ordinary ally receives the 500 shield", "shield=%d" % ally.shield)
	_check(warden.skill_charge == 0, "the ward spends the charge bar that serves as its cooldown")
	battle.queue_free()


## §14 says the ward protects an ordinary enemy and explicitly not an elite or a
## boss. With only an elite inside two cells the warden must do something else.
func _test_bulwark_never_shields_an_elite() -> void:
	var battle = _spawn_group(
		[Vector2i(4, 4), Vector2i(5, 4)],
		["ancient_bulwark", "crimson_sword_guard"]
	)
	var elite = battle.get_actor("crimson_sword_guard_01")
	var planned := _planned_action(battle, "ancient_bulwark_00")
	_check(planned != "ward_ally", "the bulwark does not ward an elite", "planned=%s" % planned)
	battle.end_player_turn()
	_check(elite.shield == 0, "the elite's shield stays at zero", "shield=%d" % elite.shield)
	battle.queue_free()


## Two cells is the reach. At three the ward is out of range and the warden must
## fall back to walking instead of shielding across the board.
func _test_bulwark_range_is_two_cells() -> void:
	var battle = _spawn_group(
		[Vector2i(2, 2), Vector2i(2, 5)],
		["ancient_bulwark", "petal_warrior"]
	)
	var ally = battle.get_actor("petal_warrior_01")
	var planned := _planned_action(battle, "ancient_bulwark_00")
	_check(planned != "ward_ally", "a ward cannot reach three cells", "planned=%s" % planned)
	battle.end_player_turn()
	_check(ally.shield == 0, "the out-of-range ally stays unshielded", "shield=%d" % ally.shield)
	battle.queue_free()


## The charge bar is the cooldown (§14: 3 敌方行动阶段). After the first ward the
## bar is empty, so a second, still-unshielded ally next to the warden must wait -
## otherwise "cooldown" is a word in a document and nothing more.
func _test_bulwark_ward_waits_for_its_cooldown() -> void:
	var battle = _spawn_group(
		[Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5)],
		["ancient_bulwark", "petal_warrior", "petal_warrior"]
	)
	var warden = battle.get_actor("ancient_bulwark_00")
	_check(_planned_action(battle, "ancient_bulwark_00") == "ward_ally", "the first ward is available")
	battle.end_player_turn()
	var second_ally = battle.get_actor("petal_warrior_02")
	_check(second_ally.shield == 0, "the second ally is still unshielded")
	_check(warden.skill_charge == 0, "the ward left the charge bar empty")
	var planned := _planned_action(battle, "ancient_bulwark_00")
	_check(planned != "ward_ally", "an empty charge bar blocks the second ward", "planned=%s" % planned)
	battle.queue_free()


func _test_move_steps_must_be_positive() -> void:
	var definition := EnemyDefinition.new()
	definition.archetype_id = &"probe"
	definition.display_name_zh = "探针"
	definition.health = 10
	definition.actions = [&"basic_melee"]
	definition.move_steps = 0
	_check(not definition.is_valid(), "a profile with no movement budget is invalid")
	definition.move_steps = -1
	_check(not definition.is_valid(), "a negative movement budget is invalid")
	definition.move_steps = 2
	_check(definition.is_valid(), "the default movement budget is valid")
	definition.tier = 3
	_check(not definition.is_valid(), "a tier outside ordinary/elite/boss is invalid")
