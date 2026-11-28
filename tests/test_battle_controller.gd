extends "res://tests/framework/test_case.gd"

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const IntentPlannerScript = preload("res://scripts/battle/intent_planner.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const RunStateScript = preload("res://scripts/battle/run_state.gd")
const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")


func _run() -> void:
	_test_normal_attack_pays_ultimate_energy()
	_test_relic_chest_enemy_steal_and_equipment_drop()
	_test_planning_does_not_move_enemies()

	var charge_battle = ControllerScript.new()
	root.add_child(charge_battle)
	_check(charge_battle.start_encounter(Vector2i(1, 1), [Vector2i(3, 1)]), "encounter starts with valid positions")
	charge_battle.beacons.clear()
	charge_battle.intents = IntentPlannerScript.plan(charge_battle)
	_check(charge_battle.get_actor("sevrin").max_health == 3200 and charge_battle.get_actor("sevrin").attack == 650, "Oathkeeper receives the solo rework base health and attack")
	_check(charge_battle.get_actor("sevrin").defense == 360 and charge_battle.get_actor("sevrin").magic_resistance == 230, "Oathkeeper receives defense and magic resistance")
	_check(charge_battle.intents.size() == 1, "one eligible enemy produces one intent")
	var charge_intent = charge_battle.intents[0]
	_check(charge_intent.action_id == "charged_strike", "distance-two aligned enemy selects charged strike")
	_check(charge_intent.target_mode == IntentScript.TargetMode.AREA_LOCKED, "charged strike captures 3x2 area lock")
	_check(charge_intent.affected_cells.has(Vector2i(1, 1)), "charged strike sweep includes original player cell")
	var evade_path: Array[Vector2i] = [Vector2i(0, 1)]
	_check(charge_battle.request_player_move(evade_path), "player can move outside the 3x2 sweep area")
	_check(charge_battle.statuses.apply_status(&"oathguard", "sevrin", "sevrin", 1, 1, -1, &"enemy_phase_end"), "battle status can be registered on an actor")
	_check(charge_battle.statuses.has_status("sevrin", &"oathguard"), "status remains active before enemy phase")
	_check(charge_battle.end_player_turn(), "player can end turn")
	_check(not charge_battle.statuses.has_status("sevrin", &"oathguard"), "enemy-phase-end status expires before the next player turn")
	_check(charge_battle.get_actor("sevrin").health == 3200, "area-locked charged strike does not follow a moved actor")
	_check(charge_intent.state == IntentScript.IntentState.CANCELED, "empty marked area cancels charged strike")
	charge_battle.queue_free()

	var pursuit_battle = ControllerScript.new()
	root.add_child(pursuit_battle)
	_check(pursuit_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)]), "second encounter starts")
	pursuit_battle.beacons.clear()
	pursuit_battle.intents = IntentPlannerScript.plan(pursuit_battle)
	var pursuit_intent = pursuit_battle.intents[0]
	_check(pursuit_intent.action_id == "pursuit", "distant enemy selects pursuit")
	_check(pursuit_intent.affected_cells.size() == 2, "pursuit captures a path of up to two cells")
	_check(pursuit_battle.end_player_turn(), "pursuit enemy phase resolves")
	_check(pursuit_battle.get_actor("vanguard_00").cell == Vector2i(3, 1), "pursuit moves two cells toward target")
	pursuit_battle.queue_free()

	var wait_battle = ControllerScript.new()
	root.add_child(wait_battle)
	var cage: Array[Vector2i] = [Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 4), Vector2i(5, 6)]
	_check(wait_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)], cage), "blocked-enemy encounter starts")
	wait_battle.beacons.clear()
	wait_battle.intents = IntentPlannerScript.plan(wait_battle)
	_check(wait_battle.intents.size() == 1, "blocked enemy still receives a visible intent")
	_check(wait_battle.intents[0].action_id == "wait", "enemy with no legal pursuit captures wait intent")
	var wait_intents = wait_battle.intents
	_check(wait_battle.end_player_turn(), "wait intent resolves during enemy phase")
	_check(wait_intents[0].state == IntentScript.IntentState.RESOLVED, "wait intent resolves exactly once")
	_check(wait_battle.get_actor("vanguard_00").cell == Vector2i(5, 5), "waiting enemy remains in place")
	wait_battle.queue_free()

	var marksman_battle = ControllerScript.new()
	root.add_child(marksman_battle)
	var marksman_types: Array[String] = ["marksman"]
	_check(marksman_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "marksman encounter starts with explicit archetype")
	marksman_battle.beacons.clear()
	marksman_battle.intents = IntentPlannerScript.plan(marksman_battle)
	var shot_intent = marksman_battle.intents[0]
	_check(marksman_battle.get_actor("marksman_00").archetype == "marksman", "enemy archetype is stored on actor")
	_check(marksman_battle.get_actor("marksman_00").max_health == 1800, "marksman baseline health is 1800")
	_check(shot_intent.action_id == "aimed_shot", "aligned target in range produces aimed shot")
	_check(shot_intent.target_mode == IntentScript.TargetMode.AREA_LOCKED, "aimed shot captures 3-tile piercing area lock")
	_check(shot_intent.target_cell == Vector2i(1, 1) and shot_intent.damage == 1620, "aimed shot captures target cell and 1.35x ATK raw damage")
	_check(marksman_battle.end_player_turn(), "aimed shot resolves during enemy phase")
	var expected_shot_dmg: int = CombatMathScript.calculate_damage(1620, 360)
	_check(marksman_battle.get_actor("sevrin").health == 3200 - expected_shot_dmg, "aimed shot deals mitigated physical damage")
	_check(shot_intent.state == IntentScript.IntentState.RESOLVED, "aimed shot intent resolves")
	marksman_battle.queue_free()

	var evaded_marksman_battle = ControllerScript.new()
	root.add_child(evaded_marksman_battle)
	_check(evaded_marksman_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "evadable marksman encounter starts")
	evaded_marksman_battle.beacons.clear()
	evaded_marksman_battle.intents = IntentPlannerScript.plan(evaded_marksman_battle)
	var evaded_shot = evaded_marksman_battle.intents[0]
	var marksman_evade_path: Array[Vector2i] = [Vector2i(1, 2)]
	_check(evaded_marksman_battle.request_player_move(marksman_evade_path), "player can leave marksman piercing line")
	_check(evaded_marksman_battle.end_player_turn(), "evaded marksman phase resolves")
	_check(evaded_marksman_battle.get_actor("sevrin").health == 3200, "area-locked aimed shot does not track moved player")
	_check(evaded_shot.state == IntentScript.IntentState.CANCELED, "aimed shot cancels when marked line is empty")
	evaded_marksman_battle.queue_free()

	var blocked_marksman_battle = ControllerScript.new()
	root.add_child(blocked_marksman_battle)
	_check(blocked_marksman_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [Vector2i(3, 1)], marksman_types), "blocked marksman encounter starts")
	blocked_marksman_battle.beacons.clear()
	blocked_marksman_battle.intents = IntentPlannerScript.plan(blocked_marksman_battle)
	_check(blocked_marksman_battle.intents[0].action_id == "pursuit", "blocked firing lane causes marksman to reposition via pursuit")
	blocked_marksman_battle.queue_free()

	var mixed_battle = ControllerScript.new()
	root.add_child(mixed_battle)
	var mixed_types: Array[String] = ["vanguard", "marksman"]
	_check(mixed_battle.start_encounter(Vector2i(1, 1), [Vector2i(1, 2), Vector2i(5, 1)], [], mixed_types), "mixed vanguard and marksman encounter starts")
	mixed_battle.beacons.clear()
	mixed_battle.intents = IntentPlannerScript.plan(mixed_battle)
	_check(mixed_battle.intents.size() == 2, "mixed encounter creates one intent per living enemy")
	_check(mixed_battle.intents[0].action_id == "charged_strike", "full-charge vanguard telegraphs charged_strike first")
	_check(mixed_battle.intents[1].action_id == "aimed_shot", "marksman shot follows vanguard in visible order")
	_check(mixed_battle.intents[0].source_actor_id == "vanguard_00" and mixed_battle.intents[1].source_actor_id == "marksman_01", "mixed execution order retains explicit archetype identities")
	var mixed_intents = mixed_battle.intents
	_check(mixed_battle.end_player_turn(), "mixed enemy phase resolves")
	_check(mixed_battle.get_actor("sevrin").health < 3200, "mixed phase applies vanguard and marksman damage")
	_check(mixed_intents[0].state == IntentScript.IntentState.RESOLVED and mixed_intents[1].state == IntentScript.IntentState.RESOLVED, "both mixed intents resolve")
	mixed_battle.queue_free()

	var all_archetypes_battle = ControllerScript.new()
	root.add_child(all_archetypes_battle)
	var all_archetypes: Array[String] = ["vanguard", "marksman", "area_controller"]
	_check(all_archetypes_battle.start_encounter(Vector2i(1, 3), [Vector2i(2, 3), Vector2i(1, 0), Vector2i(4, 3)], [], all_archetypes), "all three enemy archetypes can share one encounter")
	all_archetypes_battle.beacons.clear()
	all_archetypes_battle.intents = IntentPlannerScript.plan(all_archetypes_battle)
	_check(all_archetypes_battle.intents.size() == 3, "mixed three-archetype encounter creates one intent per enemy")
	_check(all_archetypes_battle.intents[0].source_actor_id == "vanguard_00" and all_archetypes_battle.intents[0].action_id == "charged_strike", "mixed roster places Vanguard charged strike first")
	_check(all_archetypes_battle.intents[1].source_actor_id == "area_controller_02" and all_archetypes_battle.intents[1].action_id == "ground_pulse", "Area Controller telegraphs ground_pulse")
	_check(all_archetypes_battle.intents[2].source_actor_id == "marksman_01" and all_archetypes_battle.intents[2].action_id == "aimed_shot", "Marksman telegraphs aimed_shot")
	var all_archetypes_intents = all_archetypes_battle.intents
	all_archetypes_battle.get_actor("sevrin").max_health = 10000
	all_archetypes_battle.get_actor("sevrin").health = 10000
	_check(all_archetypes_battle.end_player_turn(), "all-archetype enemy phase resolves")
	_check(all_archetypes_battle.get_actor("sevrin").health < 10000, "mixed roster resolves Vanguard, area, and ranged damage")
	_check(all_archetypes_intents.all(func(intent): return intent.state == IntentScript.IntentState.RESOLVED), "all three mixed-roster intents resolve exactly once")
	all_archetypes_battle.queue_free()

	var lane_block_battle = ControllerScript.new()
	root.add_child(lane_block_battle)
	var lane_block_types: Array[String] = ["vanguard", "marksman"]
	_check(lane_block_battle.start_encounter(Vector2i(1, 3), [Vector2i(1, 1), Vector2i(1, 0)], [], lane_block_types), "mixed lane-block encounter starts")
	lane_block_battle.beacons.clear()
	lane_block_battle.intents = IntentPlannerScript.plan(lane_block_battle)
	_check(lane_block_battle.intents.size() == 2 and lane_block_battle.intents[0].action_id == "charged_strike", "Vanguard telegraphs its strike in the firing lane")
	_check(lane_block_battle.intents[1].action_id != "aimed_shot", "occupied firing lane prevents Marksman from telegraphing aimed_shot")
	lane_block_battle.queue_free()

	var area_battle = ControllerScript.new()
	root.add_child(area_battle)
	var area_types: Array[String] = ["area_controller"]
	_check(area_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)], [], area_types), "area controller encounter starts")
	area_battle.beacons.clear()
	area_battle.intents = IntentPlannerScript.plan(area_battle)
	var area_intent = area_battle.intents[0]
	_check(area_battle.get_actor("area_controller_00").max_health == 2200, "area controller baseline health is 2200")
	_check(area_intent.action_id == "ground_pulse", "area controller selects ground pulse in range")
	_check(area_intent.target_mode == IntentScript.TargetMode.AREA_LOCKED, "ground pulse captures area lock")
	_check(area_intent.affected_cells.size() == 5 and area_intent.affected_cells.has(Vector2i(1, 1)), "ground pulse captures fixed orthogonal cross footprint")
	_check(area_battle.end_player_turn(), "ground pulse resolves during enemy phase")
	var expected_pulse_dmg: int = CombatMathScript.calculate_damage(area_intent.damage, 230)
	_check(area_battle.get_actor("sevrin").health == 3200 - expected_pulse_dmg, "ground pulse deals mitigated magic damage inside marked area")
	_check(area_intent.state == IntentScript.IntentState.RESOLVED, "ground pulse intent resolves")
	area_battle.queue_free()

	var evaded_area_battle = ControllerScript.new()
	root.add_child(evaded_area_battle)
	_check(evaded_area_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)], [], area_types), "evadable area controller encounter starts")
	evaded_area_battle.beacons.clear()
	evaded_area_battle.intents = IntentPlannerScript.plan(evaded_area_battle)
	var evaded_area_intent = evaded_area_battle.intents[0]
	var area_evade_path: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2)]
	_check(evaded_area_battle.request_player_move(area_evade_path), "player can move outside the marked cross area")
	_check(evaded_area_battle.end_player_turn(), "evaded ground pulse phase resolves")
	_check(evaded_area_battle.get_actor("sevrin").health == 3200, "ground pulse misses player outside captured area")
	_check(evaded_area_intent.state == IntentScript.IntentState.CANCELED and evaded_area_intent.cancel_reason == "marked_area_empty", "empty ground pulse area cancels explicitly")
	evaded_area_battle.queue_free()

	var edge_area_battle = ControllerScript.new()
	root.add_child(edge_area_battle)
	_check(edge_area_battle.start_encounter(Vector2i(0, 0), [Vector2i(2, 0)], [], area_types), "edge area controller encounter starts")
	edge_area_battle.beacons.clear()
	edge_area_battle.intents = IntentPlannerScript.plan(edge_area_battle)
	_check(edge_area_battle.intents[0].affected_cells.size() == 3, "ground pulse clips cells beyond the map boundary")
	_check(edge_area_battle.intents[0].affected_cells.has(Vector2i(0, 0)) and edge_area_battle.intents[0].affected_cells.has(Vector2i(1, 0)) and edge_area_battle.intents[0].affected_cells.has(Vector2i(0, 1)), "edge footprint retains only valid cross cells")
	edge_area_battle.queue_free()

	# Uncharged vanguard falls back to tile-locked basic_melee, and spending AP charges enemies.
	var uncharged_battle = ControllerScript.new()
	root.add_child(uncharged_battle)
	_check(uncharged_battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "uncharged fallback encounter starts")
	uncharged_battle.beacons.clear()
	uncharged_battle.get_actor("vanguard_00").skill_charge = 0
	uncharged_battle.intents = IntentPlannerScript.plan(uncharged_battle)
	var melee_intent = uncharged_battle.intents[0]
	_check(melee_intent.action_id == "basic_melee" and melee_intent.target_mode == IntentScript.TargetMode.TILE_LOCKED, "uncharged adjacent vanguard falls back to tile-locked basic_melee")
	var retreat_path: Array[Vector2i] = [Vector2i(1, 2)]
	_check(uncharged_battle.request_player_move(retreat_path), "player can dodge tile-locked basic_melee by stepping away")
	_check(uncharged_battle.get_actor("vanguard_00").skill_charge == 1, "spending 1 AP adds 1 skill charge to living enemies")
	_check(uncharged_battle.end_player_turn(), "dodged melee enemy phase resolves")
	_check(uncharged_battle.get_actor("sevrin").health == 3200, "tile-locked basic_melee misses when player steps off the tile")
	uncharged_battle.queue_free()

	var terminal_battle = ControllerScript.new()
	root.add_child(terminal_battle)
	_check(terminal_battle.start_encounter(Vector2i(2, 2), [Vector2i(2, 1), Vector2i(1, 2)]), "terminal-order encounter starts")
	terminal_battle.beacons.clear()
	terminal_battle.intents = IntentPlannerScript.plan(terminal_battle)
	terminal_battle.get_actor("sevrin").health = 1
	_check(terminal_battle.end_player_turn(), "terminal encounter enters enemy phase")
	_check(terminal_battle.phase == ControllerScript.BattlePhase.FINISHED, "player defeat ends battle immediately")
	_check(terminal_battle.battle_result == "defeat", "terminal result is defeat")
	_check(terminal_battle.intents[1].state == IntentScript.IntentState.CANCELED, "remaining enemy intent is canceled after terminal result")
	terminal_battle.queue_free()

	var victory_battle = ControllerScript.new()
	root.add_child(victory_battle)
	_check(victory_battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "victory encounter starts")
	victory_battle.beacons.clear()
	var victory_intent = victory_battle.intents[0]
	# Three DEF-scaled Judgment Marks defeat the 400-HP test enemy in 3 AP.
	victory_battle.get_actor("vanguard_00").health = 400
	_check(victory_battle.statuses.apply_status(&"oathkeeper_mark", "sevrin", "vanguard_00"), "enemy can receive a runtime status")
	_check(victory_battle.request_oathkeeper_judgment_mark("vanguard_00"), "first confirmed skill spends AP")
	_check(victory_battle.request_oathkeeper_judgment_mark("vanguard_00"), "second confirmed skill spends AP")
	_check(victory_battle.request_oathkeeper_judgment_mark("vanguard_00"), "lethal third skill defeats the final enemy")
	_check(victory_battle.phase == ControllerScript.BattlePhase.FINISHED and victory_battle.battle_result == "victory", "defeating the final enemy ends battle in victory")
	_check(victory_intent.state == IntentScript.IntentState.CANCELED, "defeated final enemy intent is canceled")
	_check(not victory_battle.statuses.has_status("vanguard_00", &"oathkeeper_mark"), "defeated actor has all statuses cleared")
	_check(not victory_battle.request_oathkeeper_judgment_mark("vanguard_00"), "actions are rejected after battle victory")
	_check(victory_battle.ap.current == victory_battle.ap.maximum - 3, "victory sequence spends exactly three AP")
	victory_battle.queue_free()

	var custom_bounds_battle = ControllerScript.new()
	root.add_child(custom_bounds_battle)
	custom_bounds_battle.grid_size = Vector2i(6, 6)
	_check(custom_bounds_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)]), "custom-size encounter accepts cells inside configured bounds")
	_check(not custom_bounds_battle.start_encounter(Vector2i(1, 1), [Vector2i(6, 1)]), "enemy outside configured grid bounds is rejected")
	_check(not custom_bounds_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)], [Vector2i(6, 1)]), "obstacle outside configured grid bounds is rejected")
	custom_bounds_battle.grid_size = Vector2i(0, 6)
	_check(not custom_bounds_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 4)]), "zero-width grid configuration is rejected")
	_check(custom_bounds_battle.get_actor("sevrin") != null and custom_bounds_battle.get_actor("sevrin").cell == Vector2i(1, 1), "invalid grid configuration preserves active encounter state")
	custom_bounds_battle.grid_size = Vector2i(6, 6)
	custom_bounds_battle.team_ap = 0
	_check(not custom_bounds_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 4)]), "zero AP configuration is rejected")
	custom_bounds_battle.team_ap = 4
	_check(custom_bounds_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 4)]), "valid encounter can restart after configuration correction")
	_check(custom_bounds_battle.ap.maximum == 4 and custom_bounds_battle.ap.current == 4, "encounter applies the configured AP maximum")
	custom_bounds_battle.queue_free()

	var validation_battle = ControllerScript.new()
	root.add_child(validation_battle)
	_check(validation_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)], [Vector2i(3, 3)]), "validation encounter starts")
	var original_player_cell: Vector2i = validation_battle.get_actor("sevrin").cell
	var original_enemy_cell: Vector2i = validation_battle.get_actor("vanguard_00").cell
	_check(not validation_battle.start_encounter(Vector2i(2, 2), [Vector2i(4, 4), Vector2i(4, 4)]), "duplicate enemy positions are rejected")
	_check(not validation_battle.start_encounter(Vector2i(2, 2), []), "empty enemy roster is rejected")
	var unknown_types: Array[String] = ["sorcerer"]
	_check(not validation_battle.start_encounter(Vector2i(2, 2), [Vector2i(4, 4)], [], unknown_types), "unknown enemy archetype is rejected")
	var mismatched_types: Array[String] = ["vanguard", "marksman"]
	_check(not validation_battle.start_encounter(Vector2i(2, 2), [Vector2i(4, 4)], [], mismatched_types), "mismatched archetype list is rejected")
	_check(validation_battle.get_actor("sevrin").cell == original_player_cell, "invalid setup preserves existing player state")
	_check(validation_battle.get_actor("vanguard_00").cell == original_enemy_cell, "invalid setup preserves existing enemy state")
	_check(validation_battle.blocked_cells.has(Vector2i(3, 3)), "invalid setup preserves existing blockers")
	validation_battle.queue_free()

	_test_enemy_chest_buffs_follow_the_catalogue()
	_report()


func _test_planning_does_not_move_enemies() -> void:
	# Regression for A-01: the planner used to write enemy.cell during plan(),
	# so calling plan() twice walked the enemy twice and the telegraph could
	# disagree with the resolution. Planning must be side-effect free; the move
	# belongs to the enemy phase.
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)]), "reposition encounter starts")
	battle.beacons.clear()
	battle.turn_number = 2  # enemy reposition cadence only runs after turn 1
	var enemy = battle.get_actor("vanguard_00")
	var origin: Vector2i = enemy.cell
	var first = IntentPlannerScript.plan(battle)
	_check(enemy.cell == origin, "planning leaves the enemy where it stands")
	var second = IntentPlannerScript.plan(battle)
	_check(enemy.cell == origin, "planning twice still leaves the enemy where it stands")
	_check(first[0].move_path.size() > 0, "the reposition is recorded as a move path on the intent")
	_check(second[0].move_path == first[0].move_path, "re-planning yields the same move path")
	# Now let the enemy phase apply it.
	battle.intents = first
	_check(battle.end_player_turn(), "enemy phase resolves the recorded reposition")
	_check(enemy.cell != origin, "the enemy actually moves during the enemy phase, not during planning")
	battle.queue_free()


func _test_normal_attack_pays_ultimate_energy() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	# Two adjacent enemies on purpose: the first oathblade knocks its target from
	# (2,1) to (3,1), so a second swing at the SAME id would fail the range check
	# and the per-turn-cap assertion would never run. A second adjacent target
	# lets the second action actually resolve.
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1), Vector2i(1, 2)])
	battle.beacons.clear()
	var sevrin = battle.get_actor("sevrin")
	var before: int = sevrin.ultimate_energy
	_check(battle.request_skill(&"oathblade", "vanguard_00"), "the normal attack resolves")
	_check(sevrin.ultimate_energy == before + 1, "a normal attack pays one ultimate energy")
	var after_attack: int = sevrin.ultimate_energy
	_check(battle.request_skill(&"oathblade", "vanguard_01"), "a second attack on another adjacent target resolves")
	_check(sevrin.ultimate_energy == after_attack, "the per-turn cap still pays only one point")
	battle.queue_free()


func _test_relic_chest_enemy_steal_and_equipment_drop() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var rs = RunStateScript.new()
	battle.run_state = rs
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "relic chest encounter starts")
	var enemy = battle.get_actor("vanguard_00")
	var chest_cell := Vector2i(3, 1)
	battle.beacons.clear()
	battle.beacons[chest_cell] = {
		"id": "chest_test",
		"cell": chest_cell,
		"health": 2,
		"max_health": 2,
		"opened": false,
		"loot": {"id": "test_blade", "name": "测试长刃", "kind": "weapon", "enemy_attack": 200},
	}
	var atk_before: int = enemy.attack
	battle.damage_beacon_at(chest_cell, 600, enemy.actor_id, "charged_strike")
	_check(int(battle.beacons[chest_cell]["health"]) == 1 and enemy.attack == atk_before, "first hit drops chest durability from 2 to 1 without breaking it")
	battle.damage_beacon_at(chest_cell, 600, enemy.actor_id, "charged_strike")
	_check(enemy.attack == atk_before + 400, "second hit breaks the weapon chest and enemy gains 2x attack bonus")
	_check(enemy.stolen_equipment.size() == 1, "stolen weapon is tracked on the enemy for death drop")
	_check(battle.phase != ControllerScript.BattlePhase.FINISHED, "breaking all chests never causes instant defeat")

	battle.drop_enemy_equipment(enemy)
	_check(battle.dropped_loot.has(enemy.cell), "defeated enemy drops stolen weapon onto its tile")
	var picked: Array[Dictionary] = battle.pickup_dropped_loot_at(enemy.cell)
	_check(picked.size() == 1 and rs.backpack.size() == 1, "picking up ground loot moves it into RunState backpack")
	_check(rs.equip_from_backpack(0) and not rs.equipped_weapon.is_empty(), "player can equip the recovered weapon from backpack")
	rs.reset()
	_check(rs.backpack.is_empty() and rs.equipped_weapon.is_empty(), "RunState.reset clears equipment and backpack on run end")
	battle.queue_free()


## Chest buffs follow the catalogue's enemy_* columns, not the player-side
## stats: the dusk blade's enemy variant carries no defense penalty, armor
## becomes shield, and every skill upgrade carries its own numbers instead of
## one hard-coded bonus. Weapons and armor ride the thief until death.
func _test_enemy_chest_buffs_follow_the_catalogue() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)])
	battle.beacons.clear()
	var enemy = battle.get_actor("vanguard_00")

	var dusk = LootCatalogScript.get_item(&"weapon_dusk_blade")
	battle.call("_grant_chest_buff_to_enemy", "vanguard_00", {"id": "chest_dusk", "loot": dusk})
	_check(enemy.attack == 1400 + 640, "the dusk blade's enemy variant adds 2x its declared 320 attack")
	_check(enemy.defense == 450, "the enemy variant carries no defense penalty")
	_check(enemy.stolen_equipment.size() == 1, "an equipped weapon rides the thief until death")

	var bulwark = LootCatalogScript.get_item(&"armor_iron_bulwark")
	var atk_before: int = enemy.attack
	var def_before: int = enemy.defense
	battle.call("_grant_chest_buff_to_enemy", "vanguard_00", {"id": "chest_bulwark", "loot": bulwark})
	_check(enemy.defense == def_before, "armor on an enemy is shield, not defense")
	_check(enemy.shield == 1300, "the bulwark's declared enemy shield lands at 2x")
	_check(enemy.attack == atk_before, "the bulwark adds no attack")

	var shock = LootCatalogScript.get_item(&"upg_shock_shield")
	var atk_again: int = enemy.attack
	battle.call("_grant_chest_buff_to_enemy", "vanguard_00", {"id": "chest_shock", "loot": shock})
	_check(enemy.attack == atk_again, "the shock shield upgrade adds no attack")
	_check(enemy.shield == 1300 + 1400, "the upgrade's declared enemy shield lands at 2x")

	# Weapons and armor drop back to the ground when the wearer dies.
	battle.call("drop_enemy_equipment", enemy)
	_check(battle.dropped_loot.has(Vector2i(2, 1)), "the stolen equipment lands on the thief's cell")
	_check(battle.dropped_loot[Vector2i(2, 1)].size() == 2, "two equipped pieces dropped")
	_check(enemy.stolen_equipment.is_empty(), "the drop clears the thief's equipment list")

	var hourglass = LootCatalogScript.get_item(&"item_echo_hourglass")
	enemy.skill_charge = 0
	battle.call("_grant_chest_buff_to_enemy", "vanguard_00", {"id": "chest_hourglass", "loot": hourglass})
	_check(enemy.skill_charge == enemy.skill_charge_max, "the hourglass's declared enemy charge fills the bar")
	battle.queue_free()
