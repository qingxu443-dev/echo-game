extends "res://tests/framework/test_case.gd"

## 春之境的两种地面危害：凋零（§15.1 樱落领域）与残春（§15.3 春痕绽放）。
##
## Why this suite exists: both bosses had a signature skill on paper that did
## nothing in play. §15 spells out the rules once - three adjacent tiles, damage
## on enter or stay, at most once per character per player turn, two whole turns,
## never blocking movement or sight - and the battle layer had no ground effects
## at all, so 春痕回响 was a plain kiting archer and 凋樱剑主 was a bigger cultist.
##
## These assertions drive real turns rather than reading the intent back, because
## an intent that is planned but never resolved is exactly the failure mode this
## suite is here to catch.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const PlannerScript = preload("res://scripts/battle/intent_planner.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const HazardFieldScript = preload("res://scripts/battle/hazard_field.gd")

const HERO := "sevrin"


func _run() -> void:
	_test_blight_field_is_a_three_tile_band()
	_test_blight_field_lands_tiles_and_hurts_the_stander()
	_test_one_trigger_per_character_per_turn()
	_test_hazard_expires_after_two_whole_turns()
	_test_standing_still_is_billed_each_whole_turn()
	_test_hazards_never_block_movement_or_sight()
	_test_spring_bloom_seeds_lingering_spring()
	_test_sakura_shock_is_three_tiles_not_six()
	_test_plain_attacks_use_the_sheet_multiplier()
	_test_hazards_do_not_stack()
	_test_band_does_not_shrink_at_an_edge()


# --- setup helpers ------------------------------------------------------------

## A boss with a full charge bar, so its signature action is the first legal one.
func _spawn(archetype: String, hero_cell: Vector2i, enemy_cell: Vector2i):
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(hero_cell, [enemy_cell], [], [archetype])
	battle.beacons.clear()
	battle.intents = PlannerScript.plan(battle)
	return battle


func _filled(battle, actor_id: String = "") -> void:
	for id in battle.actors:
		if actor_id.is_empty() or String(id) == actor_id:
			var actor = battle.actors[id]
			if actor.team == "enemy":
				actor.skill_charge = actor.skill_charge_max


func _hazard_cells(battle, kind: String) -> Array[Vector2i]:
	return HazardFieldScript.cells_of_kind(battle, kind)


# --- 樱落领域 (§15.1) ---------------------------------------------------------

## 3 tiles, 1.00x, and the field it leaves is 0.25x of that hit.
func _test_blight_field_is_a_three_tile_band() -> void:
	var battle = _spawn("boss_petalfall", Vector2i(1, 3), Vector2i(3, 3))
	_filled(battle)
	battle.intents = PlannerScript.plan(battle)
	var intent = battle.intents[0]
	_check(intent.action_id == "blight_field", "凋樱剑主 opens with 樱落领域", "action=%s" % intent.action_id)
	_check(intent.affected_cells.size() == 3, "the sweep covers three tiles", "n=%d" % intent.affected_cells.size())
	_check(intent.affected_cells.has(intent.target_cell), "the aim cell is inside the sweep")
	_check(intent.damage == 1050, "1.00x of the uncut 1050 attack", "damage=%d" % intent.damage)
	_check(intent.hazard_kind == HazardFieldScript.KIND_BLIGHT, "the tiles it cuts turn to 凋零")
	_check(intent.hazard_damage == 263, "凋零 is 0.25x of the skill hit", "dmg=%d" % intent.hazard_damage)
	_check(intent.hazard_duration_turns == 2, "凋零 lasts two whole turns")
	_check(intent.hazard_cells.size() == intent.affected_cells.size(), "every tile it cuts becomes 凋零")
	battle.queue_free()


## The swing lands and the ground keeps hurting: the tile outlives the turn.
func _test_blight_field_lands_tiles_and_hurts_the_stander() -> void:
	var battle = _spawn("boss_petalfall", Vector2i(1, 3), Vector2i(3, 3))
	var hero = battle.get_actor(HERO)
	_filled(battle)
	battle.intents = PlannerScript.plan(battle)
	var aim: Vector2i = battle.intents[0].target_cell

	battle.end_player_turn()
	var tiles: Array[Vector2i] = _hazard_cells(battle, HazardFieldScript.KIND_BLIGHT)
	_check(tiles.size() == 3, "three 凋零 tiles are on the board", "n=%d" % tiles.size())
	_check(tiles.has(aim), "the aimed tile is one of them")

	# Walk the hero onto a tile; the enemy phase already ticked the stay damage,
	# so reset the ledger to count this entry on its own.
	hero.cell = tiles[0]
	var before: int = hero.health
	var expected: int = CombatMathScript.calculate_damage(263, hero.defense)
	battle.ledger.hazard_trigger_turn.clear()
	var taken: int = HazardFieldScript.trigger_for(battle, hero)
	_check(taken == 263, "entering a 凋零 tile asks for 263 raw", "raw=%d" % taken)
	_check(before - hero.health == expected, "the hero pays the mitigated amount", "lost=%d expected=%d" % [before - hero.health, expected])
	battle.queue_free()


## "每名角色每个玩家回合最多触发一次" - two tiles in one turn still cost one tick.
func _test_one_trigger_per_character_per_turn() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(7, 7)], [], ["petal_warrior"])
	battle.beacons.clear()
	var hero = battle.get_actor(HERO)
	battle.ap.reset()
	HazardFieldScript.spawn(battle, [Vector2i(2, 1), Vector2i(3, 1)], HazardFieldScript.KIND_BLIGHT, 263, "boss_petalfall_00", 2)
	var start_health: int = hero.health

	_check(battle.request_player_move([Vector2i(2, 1)]), "stepping onto a 凋零 tile is allowed")
	var after_first: int = hero.health
	_check(after_first < start_health, "the first tile bites", "health=%d" % after_first)

	_check(battle.request_player_move([Vector2i(3, 1)]), "stepping onto a second tile is also allowed")
	_check(hero.health == after_first, "the second tile in the same turn does not bite again", "health=%d" % hero.health)
	battle.queue_free()


## Two whole player turns of hurting, then the ground recovers on its own.
func _test_hazard_expires_after_two_whole_turns() -> void:
	var battle = _spawn("boss_petalfall", Vector2i(1, 3), Vector2i(3, 3))
	_filled(battle)
	battle.intents = PlannerScript.plan(battle)
	# Laid during the enemy phase of turn 1; turns 2 and 3 are the two whole
	# player turns it covers, and turn 4 starts clean.
	battle.end_player_turn()
	_check(_hazard_cells(battle, HazardFieldScript.KIND_BLIGHT).size() == 3, "tiles exist right after they are laid")
	_check(battle.turn_number == 2, "the laying turn was turn 1", "turn=%d" % battle.turn_number)

	battle.end_player_turn()
	_check(_hazard_cells(battle, HazardFieldScript.KIND_BLIGHT).size() == 3, "the field covers its first whole turn")
	_check(battle.turn_number == 3, "that was turn 2", "turn=%d" % battle.turn_number)

	battle.end_player_turn()
	_check(_hazard_cells(battle, HazardFieldScript.KIND_BLIGHT).is_empty(), "the field lapses once the second whole turn ends")
	_check(battle.turn_number == 4, "that was turn 3", "turn=%d" % battle.turn_number)
	battle.queue_free()


## Staying put is not a way to dodge the ground: the stay tick is a different
## code path from the enter tick, and a suite that only ever walked onto a tile
## would stay green with the turn-start sweep deleted entirely.
func _test_standing_still_is_billed_each_whole_turn() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(7, 7)], [], ["petal_warrior"])
	battle.beacons.clear()
	battle.intents.clear()
	var hero = battle.get_actor(HERO)
	HazardFieldScript.spawn(battle, [Vector2i(1, 1)], HazardFieldScript.KIND_BLIGHT, 263, "boss_petalfall_00", 2)
	var expected: int = CombatMathScript.calculate_damage(263, hero.defense)

	var start: int = hero.health
	battle.end_player_turn()
	var after_first: int = hero.health
	_check(start - after_first == expected, "the first whole turn on the tile costs one tick", "lost=%d expected=%d" % [start - after_first, expected])

	battle.end_player_turn()
	var after_second: int = hero.health
	_check(after_first - after_second == expected, "the second whole turn costs another tick", "lost=%d expected=%d" % [after_first - after_second, expected])

	battle.end_player_turn()
	_check(hero.health == after_second, "the lapsed tile stops billing", "health=%d" % hero.health)
	battle.queue_free()


## "不阻挡移动/视线" - the tile hurts, it does not wall anything off.
func _test_hazards_never_block_movement_or_sight() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 3), [Vector2i(7, 3)], [], ["petal_warrior"])
	battle.beacons.clear()
	var hero = battle.get_actor(HERO)
	HazardFieldScript.spawn(battle, [Vector2i(2, 3), Vector2i(3, 3)], HazardFieldScript.KIND_BLIGHT, 263, "boss_petalfall_00", 2)
	battle.ap.reset()

	_check(not battle.blocked_cells.has(Vector2i(2, 3)), "a hazard is not an obstacle")
	_check(
		GridRulesScript.has_clear_line_of_sight(Vector2i(1, 3), Vector2i(4, 3), battle.blocked_cells, battle.get_occupied_cells(HERO)),
		"the enemy can still see through a 凋零 tile"
	)
	_check(battle.request_player_move([Vector2i(2, 3)]), "the hero can still walk onto it")
	_check(hero.cell == Vector2i(2, 3), "the hero ends up standing on the tile")
	battle.queue_free()


# --- 春痕绽放 (§15.3) ---------------------------------------------------------

## 0.75x arcane on three tiles, and the tiles stay as 残春.
func _test_spring_bloom_seeds_lingering_spring() -> void:
	var battle = _spawn("boss_spring_echo", Vector2i(1, 3), Vector2i(5, 3))
	_filled(battle)
	battle.intents = PlannerScript.plan(battle)
	var intent = battle.intents[0]
	_check(intent.action_id == "spring_bloom", "春痕回响 opens with 春痕绽放", "action=%s" % intent.action_id)
	_check(intent.affected_cells.size() == 3, "three tiles, same as the melee boss", "n=%d" % intent.affected_cells.size())
	_check(intent.damage == 675, "0.75x of the uncut 900 attack", "damage=%d" % intent.damage)
	_check(intent.damage_type == "magical", "the burst is arcane damage")
	_check(intent.hazard_kind == HazardFieldScript.KIND_LINGERING_SPRING, "it leaves 残春 rather than 凋零")
	_check(intent.hazard_damage == 135, "残春 is 0.2x of the burst (a draft - the doc says only 少量)", "dmg=%d" % intent.hazard_damage)

	battle.end_player_turn()
	var tiles: Array[Vector2i] = _hazard_cells(battle, HazardFieldScript.KIND_LINGERING_SPRING)
	_check(tiles.size() == 3, "three 残春 tiles are on the board", "n=%d" % tiles.size())
	_check(_hazard_cells(battle, HazardFieldScript.KIND_BLIGHT).is_empty(), "a 残春 field is not 凋零")
	battle.queue_free()


# --- 樱庭震荡 (§14) ----------------------------------------------------------

## The beast used to borrow the six-tile cleave; the document says three.
func _test_sakura_shock_is_three_tiles_not_six() -> void:
	var battle = _spawn("sakura_beast", Vector2i(1, 3), Vector2i(2, 3))
	_filled(battle)
	battle.intents = PlannerScript.plan(battle)
	var intent = battle.intents[0]
	_check(intent.action_id == "sakura_shock", "樱庭镇守兽 uses 樱庭震荡", "action=%s" % intent.action_id)
	_check(intent.affected_cells.size() == 3, "three tiles, as the document pins", "n=%d" % intent.affected_cells.size())
	_check(intent.damage == 975, "0.75x of the uncut 1300 attack", "damage=%d" % intent.damage)
	_check(intent.hazard_cells.is_empty(), "樱庭震荡 leaves no ground effect")
	battle.queue_free()


# --- 普攻倍率 (§15) -----------------------------------------------------------

## Each boss carries its own attendance number; the generic 0.80 would be wrong
## for two of the three.
func _test_plain_attacks_use_the_sheet_multiplier() -> void:
	var cases := [
		{"archetype": "boss_petalfall", "action": "basic_melee", "expected": 588, "note": "樱刃 735 x 0.80"},
		{"archetype": "boss_thousand_boughs", "action": "basic_melee", "expected": 441, "note": "重盾击 630 x 0.70"},
		{"archetype": "boss_spring_echo", "action": "echo_bolt", "expected": 410, "note": "花影弹 630 x 0.65"},
	]
	for case in cases:
		var battle = _spawn(case["archetype"], Vector2i(1, 3), Vector2i(2, 3))
		# Encounter setup hands every enemy a full bar so turn 1 shows its
		# signature threat. Drain it here: the plain attack is what this asserts.
		for id in battle.actors:
			if battle.actors[id].team == "enemy":
				battle.actors[id].skill_charge = 0
		battle.intents = PlannerScript.plan(battle)
		var intent = battle.intents[0]
		_check(intent.action_id == case["action"], "%s falls back to %s" % [case["archetype"], case["action"]], "action=%s" % intent.action_id)
		_check(intent.damage == case["expected"], "%s deals %d" % [case["archetype"], case["expected"]], "damage=%d" % intent.damage)
		battle.queue_free()


# --- 边界 ---------------------------------------------------------------------

## "不清除、不叠加" - the first tile wins, the second lay is a no-op.
func _test_hazards_do_not_stack() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(7, 7)], [], ["petal_warrior"])
	battle.beacons.clear()
	var cell := Vector2i(3, 3)
	HazardFieldScript.spawn(battle, [cell], HazardFieldScript.KIND_BLIGHT, 263, "boss_petalfall_00", 2)
	var first_expiry: int = int(battle.hazards[cell]["expires_turn"])
	HazardFieldScript.spawn(battle, [cell], HazardFieldScript.KIND_BLIGHT, 999, "boss_petalfall_00", 2)
	_check(int(battle.hazards[cell]["damage"]) == 263, "a second lay does not overwrite the damage", "dmg=%d" % int(battle.hazards[cell]["damage"]))
	_check(int(battle.hazards[cell]["expires_turn"]) == first_expiry, "a second lay does not refresh the timer")
	_check(battle.hazards.size() == 1, "there is still exactly one tile there")
	battle.queue_free()


## Near an edge the band slides inward rather than clipping to two tiles: the
## document's number is three, and two would silently weaken the skill.
func _test_band_does_not_shrink_at_an_edge() -> void:
	var battle = _spawn("boss_petalfall", Vector2i(0, 0), Vector2i(0, 2))
	_filled(battle)
	battle.intents = PlannerScript.plan(battle)
	var intent = battle.intents[0]
	_check(intent.action_id == "blight_field", "the boss still casts from the corner")
	_check(intent.affected_cells.size() == 3, "the corner band is still three tiles", "n=%d" % intent.affected_cells.size())
	var all_inside := true
	for cell in intent.affected_cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= battle.grid_size.x or cell.y >= battle.grid_size.y:
			all_inside = false
	_check(all_inside, "every tile of the band is on the board")
	battle.queue_free()
