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
	_test_ward_node_blocks_movement_but_not_sight()
	_test_ranged_boss_shoots_across_its_own_nodes()
	_test_ward_stance_shield_scales_with_nodes()
	_test_ward_stance_shield_expires()
	_test_planning_is_idempotent()
	_test_single_target_attacks_choose_players_not_chests()
	_test_real_boss_area_skill_can_damage_a_chest()
	_test_boss_encounters_scale_all_four_core_stats()
	_test_move_steps_must_be_positive()


## Builds a one-on-one fight. Beacons are removed and the intents replanned so
## the enemy is looking at the hero, not at a relic objective it would rather
## attack - the default spawn puts two beacons down and they would steal the
## target from this scenario.
## 规划是只读的：同一局面连算两次必须得到同样的意图。
## 这条以前只是注释里的承诺——旧实现会在 plan() 里写 enemy.cell，重复调用
## 就会把敌人走两次，预告和实际结果对不上。
func _test_planning_is_idempotent() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var first: Array = PlannerScript.plan(battle)
	var second: Array = PlannerScript.plan(battle)
	_check(first.size() == second.size(), "两次规划得到同样数量的意图")
	if first.size() != second.size():
		return
	for i in range(first.size()):
		_check(first[i].action_id == second[i].action_id, "第 %d 条意图的 action 相同" % i)
		_check(first[i].target_cell == second[i].target_cell, "第 %d 条意图的目标格相同" % i)
		_check(first[i].damage == second[i].damage, "第 %d 条意图的伤害相同" % i)
	_check(battle.actors["crimson_sword_guard_00"].cell == Vector2i(3, 2), "规划没有挪动敌人")


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

func _intent_for_actor(battle, actor_id: String):
	for intent in battle.intents:
		if intent.source_actor_id == actor_id:
			return intent
	return null


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
		"boss_thousand_boughs": 3,
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


## Isolate each boss to smoke-test its own movement/attack behavior; the
## mixed escort composition is covered by the encounter catalog and runtime tests.
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
	var boss_intent = _intent_for_actor(battle, "boss_thousand_boughs_00")
	_check(boss_intent != null, "the boss still produces an intent without the chests")
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
## §15.2: "节点占格阻挡移动但不阻挡视线". Before this split the node lived in the
## same occupancy table as everything else, so it walled off archery lanes the
## document says it must leave open - a wall the player could not reason about.
func _test_ward_node_blocks_movement_but_not_sight() -> void:
	var battle = _begin_boss_fight(&"boss_thousand_boughs")
	var nodes: Array[Dictionary] = _ward_node_list(battle)
	_check(nodes.size() == 2, "the boss brought its nodes")
	var node = nodes[0]
	var node_cell: Vector2i = node["cell"]
	_check(not bool(node.get("blocks_sight", true)), "a spawned node records that it does not block sight")
	_check(battle.get_occupied_cells().has(node_cell), "it still holds its cell against movement")
	_check(not battle.get_sight_blockers().has(node_cell), "it does not appear in the sight table")

	# Two identical spans across two different occupants: the node's span is open,
	# the chest's span is not. Same geometry, same call, one flag apart.
	var node_lane := Vector2i(1, 5)
	battle.beacons[node_lane] = {
		"id": "probe_node", "cell": node_lane, "health": 700, "max_health": 700,
		"opened": false, "loot": {}, "kind": "ward_node", "blocks_sight": false,
	}
	var chest_lane := Vector2i(2, 5)
	battle.beacons[chest_lane] = {
		"id": "probe_chest", "cell": chest_lane, "health": 2000, "max_health": 2000,
		"opened": false, "loot": {}, "blocks_sight": true,
	}
	_check(
		GridRulesScript.has_clear_line_of_sight(node_lane + Vector2i(0, -1), node_lane + Vector2i(0, 1), battle.blocked_cells, battle.get_sight_blockers()),
		"sight passes straight through a 结界 node"
	)
	_check(
		not GridRulesScript.has_clear_line_of_sight(chest_lane + Vector2i(0, -1), chest_lane + Vector2i(0, 1), battle.blocked_cells, battle.get_sight_blockers()),
		"sight is still stopped by a relic chest"
	)
	battle.queue_free()


## The split only matters if the *planner* uses it: a boss that stands behind its
## own 结界 should still be able to cast across the node, and the same shot should
## be refused the moment that cell is a solid object instead.
func _test_ranged_boss_shoots_across_its_own_nodes() -> void:
	var battle = _spawn("boss_spring_echo", Vector2i(1, 3), Vector2i(5, 3))
	for id in battle.actors:
		var actor = battle.actors[id]
		if actor.team == "enemy":
			actor.skill_charge = actor.skill_charge_max
	var lane := Vector2i(3, 3)
	battle.beacons[lane] = {
		"id": "probe_node", "cell": lane, "health": 700, "max_health": 700,
		"opened": false, "loot": {}, "kind": "ward_node", "blocks_sight": false,
		# Same as a spawned node: the boss must not pick it as a target, or the
		# test would be measuring target choice instead of the sight lane.
		"enemy_objective": false,
	}
	battle.intents = PlannerScript.plan(battle)
	_check(battle.intents[0].action_id == "spring_bloom", "the boss casts through its own node", "action=%s" % battle.intents[0].action_id)

	# Same cell, same distance, but now the object in the lane blocks sight too.
	# `kind` stays ward_node so the boss does not simply retarget the object - the
	# assertion is about the lane, not about target choice.
	battle.beacons[lane]["blocks_sight"] = true
	battle.intents = PlannerScript.plan(battle)
	_check(battle.intents[0].action_id != "spring_bloom", "a solid object in the lane refuses the cast", "action=%s" % battle.intents[0].action_id)
	battle.queue_free()


func _test_ward_stance_shield_scales_with_nodes() -> void:
	var battle = _begin_boss_fight(&"boss_thousand_boughs")
	var boss = battle.get_actor("boss_thousand_boughs_00")
	battle.intents = PlannerScript.plan(battle)
	var opening = _intent_for_actor(battle, "boss_thousand_boughs_00")
	_check(opening != null, "the boss produces its opening intent")
	if opening != null:
		_check(opening.action_id == "ward_stance", "the boss opens with its stance", "action=%s" % opening.action_id)
		_check(opening.damage == 504, "two nodes give 6% + 2x2% of 5040 = 504", "damage=%d" % opening.damage)
	battle.end_player_turn()
	_check(boss.shield == 504, "the stance raises the shield", "shield=%d" % boss.shield)

	var nodes: Array[Dictionary] = _ward_node_list(battle)
	battle.damage_beacon_at(nodes[0]["cell"], 700, "sevrin", "probe")
	boss.skill_charge = boss.skill_charge_max
	battle.intents = PlannerScript.plan(battle)
	var one_node_stance = _intent_for_actor(battle, "boss_thousand_boughs_00")
	_check(one_node_stance != null, "the boss still plans its stance with one node")
	if one_node_stance != null:
		_check(one_node_stance.damage == 403, "one node left means 6% + 2% of 5040 = 403", "damage=%d" % one_node_stance.damage)
	battle.queue_free()

	var bare = _begin_boss_fight(&"boss_thousand_boughs")
	for node in _ward_node_list(bare):
		bare.damage_beacon_at(node["cell"], 700, "sevrin", "probe")
	var bare_boss = bare.get_actor("boss_thousand_boughs_00")
	bare_boss.skill_charge = bare_boss.skill_charge_max
	bare.intents = PlannerScript.plan(bare)
	var bare_stance = _intent_for_actor(bare, "boss_thousand_boughs_00")
	_check(bare_stance != null, "the boss still plans its stance after both nodes break")
	if bare_stance != null:
		_check(bare_stance.damage == 302, "no nodes left means the 6% base only", "damage=%d" % bare_stance.damage)
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



## A single-target shot must lock a living player, even when a chest is nearer.
## The archer's charged area shot is disabled so this exercises its true single
## tile attack rather than an area footprint that may legitimately splash a chest.
func _test_single_target_attacks_choose_players_not_chests() -> void:
	var battle = _spawn("petal_archer", Vector2i(2, 3), Vector2i(7, 3))
	var hero = battle.get_defender()
	var archer = battle.get_actor("petal_archer_00")
	var chest_cell := Vector2i(6, 4)
	battle.beacons[chest_cell] = {
		"id": "single_target_probe", "cell": chest_cell,
		"health": 2, "max_health": 2, "opened": false, "loot": {},
	}
	archer.skill_charge = 0
	battle.intents = PlannerScript.plan(battle)
	var shot = null
	for intent in battle.intents:
		if intent.source_actor_id == archer.actor_id and intent.action_id == "light_shot":
			shot = intent
			break
	_check(shot != null, "the archer plans a legal single-target light shot")
	if shot != null:
		_check(shot.target_cell == hero.cell, "the single-target intent locks the player tile")
	var hero_health_before: int = hero.health
	battle.end_player_turn()
	_check(int(battle.beacons[chest_cell]["health"]) == 2, "the single-target shot does not damage the nearer chest")
	_check(hero.health < hero_health_before, "the single-target shot damages the player")
	battle.queue_free()


## This drives a real boss skill from the planner through enemy-phase resolution.
## The chest is placed on a cell telegraphed by 春痕绽放 after planning, and the
## area resolver must damage it just as it damages other destructible objects.
func _test_real_boss_area_skill_can_damage_a_chest() -> void:
	var battle = _spawn("boss_spring_echo", Vector2i(2, 3), Vector2i(7, 3))
	battle.turn_number = 2
	battle.intents = PlannerScript.plan(battle)
	var bloom = null
	for intent in battle.intents:
		if intent.source_actor_id == "boss_spring_echo_00" and intent.action_id == "spring_bloom":
			bloom = intent
			break
	_check(bloom != null, "the boss planner creates its real 春痕绽放 intent")
	if bloom == null:
		battle.queue_free()
		return
	var chest_cell := Vector2i(-1, -1)
	for cell in bloom.affected_cells:
		if cell != battle.get_defender().cell and cell != battle.get_actor("boss_spring_echo_00").cell and not battle.get_occupied_cells().has(cell):
			chest_cell = cell
			break
	_check(chest_cell != Vector2i(-1, -1), "the telegraphed boss area has a free cell for the chest probe")
	if chest_cell == Vector2i(-1, -1):
		battle.queue_free()
		return
	battle.beacons[chest_cell] = {
		"id": "area_skill_probe", "cell": chest_cell,
		"health": 2, "max_health": 2, "opened": false, "loot": {},
	}
	battle.end_player_turn()
	_check(int(battle.beacons[chest_cell]["health"]) < 2, "the real area skill damages a chest inside its telegraphed footprint")
	battle.queue_free()


## Verify runtime scaling, not just the encounter data. 千枝神将's node defense
## is additive after the boss's base defense has received the 20 percent increase.
func _test_boss_encounters_scale_all_four_core_stats() -> void:
	for boss_id in ["boss_petalfall", "boss_thousand_boughs", "boss_spring_echo"]:
		var definition = SpringEncounterCatalogScript.build(StringName(boss_id), ["sevrin"])
		var battle = ControllerScript.new()
		root.add_child(battle)
		var started: bool = battle.start_encounter(
			definition.player_cell, definition.enemy_cells, definition.obstacles,
			definition.enemy_archetypes, definition.character_ids, definition.ally_cells,
			definition.chest_items, definition.ward_nodes, definition.deploy_cells,
			false, definition.enemy_stat_multiplier
		)
		_check(started, "%s starts with its approved roster and multiplier" % boss_id)
		if not started:
			battle.queue_free()
			continue
		for index in range(definition.enemy_archetypes.size()):
			var archetype: String = definition.enemy_archetypes[index]
			var profile: EnemyDefinition = EnemyCatalogScript.get_definition(archetype)
			var enemy = battle.get_actor("%s_%02d" % [archetype, index])
			_check(enemy != null, "%s spawns %s" % [boss_id, archetype])
			if enemy == null or profile == null:
				continue
			_check(enemy.max_health == roundi(float(profile.health) * 1.2), "%s scales %s max HP" % [boss_id, archetype])
			_check(enemy.health == enemy.max_health, "%s starts at scaled full HP" % archetype)
			_check(enemy.attack == roundi(float(profile.attack) * 1.2), "%s scales %s attack" % [boss_id, archetype])
			var expected_defense: int = roundi(float(profile.defense) * 1.2)
			if boss_id == "boss_thousand_boughs" and archetype == boss_id:
				expected_defense += 160
			_check(enemy.defense == expected_defense, "%s scales %s defense and preserves node bonuses" % [boss_id, archetype])
			_check(enemy.magic_resistance == roundi(float(profile.magic_resistance) * 1.2), "%s scales %s magic resistance" % [boss_id, archetype])
			_check(enemy.skill_damage == profile.skill_damage, "%s preserves %s signature skill damage" % [boss_id, archetype])
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
