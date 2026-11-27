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
const SpringEncounterCatalogScript = preload("res://scripts/spring/spring_encounter_catalog.gd")

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
	_test_signature_damage_is_independent_of_attack()
	_test_thousand_boughs_spawns_two_ward_nodes()
	_test_ward_nodes_are_not_boss_objectives()
	_test_breaking_ward_nodes_costs_defense()
	_test_ward_stance_shield_scales_with_nodes()
	_test_ward_stance_shield_expires()
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


## §14: "技能直接伤害需与基础攻击属性解耦". The sheets carry attacks already cut
## by 30%; if the skill kept multiplying that number the cut would silently halve
## the signature hit too. Raising the attack must therefore leave the skill's raw
## damage untouched.
func _test_signature_damage_is_independent_of_attack() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 3), [Vector2i(3, 3)], [], ["crimson_sword_guard"])
	battle.beacons.clear()
	battle.intents = PlannerScript.plan(battle)
	var enemy = battle.get_actor("crimson_sword_guard_00")
	var intent = battle.intents[0]
	_check(intent.action_id == "charged_strike", "the elite opens with its charged strike")
	_check(intent.damage == 1688, "the skill carries its pinned raw damage", "damage=%d" % intent.damage)
	enemy.attack += 1000
	battle.intents = PlannerScript.plan(battle)
	var raised = battle.intents[0]
	_check(raised.damage == 1688, "raising attack by 1000 does not touch the skill", "damage=%d" % raised.damage)
	battle.queue_free()

	# An archetype without a pinned skill keeps deriving damage from its attack.
	var plain = ControllerScript.new()
	root.add_child(plain)
	plain.start_encounter(Vector2i(1, 3), [Vector2i(3, 3)], [], ["vanguard"])
	plain.beacons.clear()
	plain.intents = PlannerScript.plan(plain)
	var vanguard_intent = plain.intents[0]
	_check(vanguard_intent.action_id == "charged_strike", "the vanguard still uses its cleave")
	_check(vanguard_intent.damage == 2100, "an unpinned skill derives 1400 x 1.5")
	plain.queue_free()


## §15.2 春之结界: two 700-HP nodes beside 千枝神将, each lending it 80 defense.
func _begin_boss_fight(encounter_id: StringName):
	var definition: EncounterDefinition = SpringEncounterCatalogScript.build(encounter_id, [])
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(
		definition.player_cell, definition.enemy_cells, definition.obstacles,
		definition.enemy_archetypes, definition.character_ids,
		definition.ally_cells, definition.chest_items, definition.ward_nodes
	)
	return battle


func _ward_node_list(battle) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	for cell in battle.beacons:
		var node: Dictionary = battle.beacons[cell]
		if str(node.get("kind", "")) == "ward_node":
			nodes.append(node)
	return nodes


func _test_thousand_boughs_spawns_two_ward_nodes() -> void:
	var definition: EncounterDefinition = SpringEncounterCatalogScript.build(&"boss_thousand_boughs", [])
	_check(definition.ward_nodes == 2, "the 千枝神将 encounter asks for two nodes")
	var battle = _begin_boss_fight(&"boss_thousand_boughs")
	var nodes: Array[Dictionary] = _ward_node_list(battle)
	_check(nodes.size() == 2, "two nodes are on the board", "count=%d" % nodes.size())
	for node in nodes:
		_check(int(node["max_health"]) == 700, "each node has 700 health (§15.2)")
	var boss = battle.get_actor("boss_thousand_boughs_00")
	_check(boss.defense == 385 + 160, "two standing nodes lend the boss 160 defense", "defense=%d" % boss.defense)
	battle.queue_free()


## The boss must not walk over and hit its own nodes: they are scenery it guards,
## while the relic chests remain attackable objectives for every enemy.
func _test_ward_nodes_are_not_boss_objectives() -> void:
	var battle = _begin_boss_fight(&"boss_thousand_boughs")
	var nodes: Array[Dictionary] = _ward_node_list(battle)
	var node_cells: Array[Vector2i] = []
	for node in nodes:
		node_cells.append(node["cell"])
	# Clear the chests first: one of them sits adjacent to the boss and would be
	# picked ahead of a node either way, which would let this assertion stay green
	# even with the filter removed.
	var chest_cells: Array[Vector2i] = []
	for cell in battle.beacons:
		if str(battle.beacons[cell].get("kind", "")) != "ward_node":
			chest_cells.append(cell)
	for cell in chest_cells:
		battle.beacons.erase(cell)
	battle.intents = PlannerScript.plan(battle)
	var targeted_node := false
	for intent in battle.intents:
		if node_cells.has(intent.target_cell):
			targeted_node = true
	_check(not targeted_node, "no enemy intent is aimed at a ward node")
	_check(battle.intents.size() == 1, "the boss still produces an intent without the chests")
	battle.queue_free()


## Breaking a node permanently removes its 80 defense, and the second node's
## bonus is independent - no double subtraction, no shared counter.
func _test_breaking_ward_nodes_costs_defense() -> void:
	var battle = _begin_boss_fight(&"boss_thousand_boughs")
	var boss = battle.get_actor("boss_thousand_boughs_00")
	var nodes: Array[Dictionary] = _ward_node_list(battle)
	var first: Vector2i = nodes[0]["cell"]
	var second: Vector2i = nodes[1]["cell"]
	battle.damage_beacon_at(first, 700, "sevrin", "probe")
	_check(boss.defense == 385 + 80, "one node destroyed leaves 80 defense", "defense=%d" % boss.defense)
	_check(not battle.get_occupied_cells().has(first), "a destroyed node no longer holds its cell")
	battle.damage_beacon_at(second, 700, "sevrin", "probe")
	_check(boss.defense == 385, "both nodes gone returns the sheet's defense", "defense=%d" % boss.defense)
	battle.damage_beacon_at(second, 700, "sevrin", "probe")
	_check(boss.defense == 385, "hitting an already-broken node cannot subtract twice", "defense=%d" % boss.defense)
	battle.queue_free()


## §15.2 结界守护: 6% max health + 2% per standing node, on a full charge bar.
## 5040 HP gives 302 alone, 403 with one node, 504 with both.
func _test_ward_stance_shield_scales_with_nodes() -> void:
	var battle = _begin_boss_fight(&"boss_thousand_boughs")
	var boss = battle.get_actor("boss_thousand_boughs_00")
	battle.intents = PlannerScript.plan(battle)
	var opening = battle.intents[0]
	_check(opening.action_id == "ward_stance", "the boss opens with its stance", "action=%s" % opening.action_id)
	_check(opening.damage == 504, "two nodes give 6% + 2x2% of 5040 = 504", "damage=%d" % opening.damage)
	battle.end_player_turn()
	_check(boss.shield == 504, "the stance raises the shield", "shield=%d" % boss.shield)

	var nodes: Array[Dictionary] = _ward_node_list(battle)
	battle.damage_beacon_at(nodes[0]["cell"], 700, "sevrin", "probe")
	boss.skill_charge = boss.skill_charge_max
	battle.intents = PlannerScript.plan(battle)
	_check(battle.intents[0].damage == 403, "one node left means 6% + 2% of 5040 = 403", "damage=%d" % battle.intents[0].damage)
	battle.queue_free()

	var bare = _begin_boss_fight(&"boss_thousand_boughs")
	for node in _ward_node_list(bare):
		bare.damage_beacon_at(node["cell"], 700, "sevrin", "probe")
	var bare_boss = bare.get_actor("boss_thousand_boughs_00")
	bare_boss.skill_charge = bare_boss.skill_charge_max
	bare.intents = PlannerScript.plan(bare)
	_check(bare.intents[0].damage == 302, "no nodes left means the 6% base only", "damage=%d" % bare.intents[0].damage)
	bare.queue_free()


## "持续 2 回合" - the shield must be gone by the third player turn, or a boss
## that never stops shielding becomes unkillable.
func _test_ward_stance_shield_expires() -> void:
	var battle = _begin_boss_fight(&"boss_thousand_boughs")
	var boss = battle.get_actor("boss_thousand_boughs_00")
	battle.intents = PlannerScript.plan(battle)
	battle.end_player_turn()
	_check(boss.shield > 0, "the shield exists right after the enemy phase")
	for turn in range(2):
		if battle.phase == battle.BattlePhase.FINISHED:
			break
		battle.end_player_turn()
	_check(boss.shield == 0, "the shield lapses on the third player turn", "shield=%d" % boss.shield)
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
