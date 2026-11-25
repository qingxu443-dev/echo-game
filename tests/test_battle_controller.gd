extends "res://tests/framework/test_case.gd"

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")


func _run() -> void:
	var charge_battle = ControllerScript.new()
	root.add_child(charge_battle)
	_check(charge_battle.start_encounter(Vector2i(1, 1), [Vector2i(3, 1)]), "encounter starts with valid positions")
	_check(charge_battle.get_actor("sevrin").max_health == 12000 and charge_battle.get_actor("sevrin").attack == 2000, "Oathkeeper receives the scaled base health and attack")
	_check(charge_battle.get_actor("sevrin").defense == 650 and charge_battle.get_actor("sevrin").magic_resistance == 500, "Oathkeeper receives defense and magic resistance")
	_check(charge_battle.intents.size() == 1, "one eligible enemy produces one intent")
	var charge_intent = charge_battle.intents[0]
	_check(charge_intent.action_id == "charged_strike", "distance-two aligned enemy selects charged strike")
	_check(charge_intent.target_mode == IntentScript.TargetMode.TILE_LOCKED, "charged strike captures tile lock")
	_check(charge_intent.target_cell == Vector2i(1, 1), "charged strike captures original player cell")
	var evade_path: Array[Vector2i] = [Vector2i(1, 2)]
	_check(charge_battle.request_player_move(evade_path), "player can move away from marked cell")
	_check(charge_battle.statuses.apply_status(&"oathguard", "sevrin", "sevrin", 1, 1, -1, &"enemy_phase_end"), "battle status can be registered on an actor")
	_check(charge_battle.statuses.has_status("sevrin", &"oathguard"), "status remains active before enemy phase")
	_check(charge_battle.end_player_turn(), "player can end turn")
	_check(not charge_battle.statuses.has_status("sevrin", &"oathguard"), "enemy-phase-end status expires before the next player turn")
	_check(charge_battle.get_actor("sevrin").health == 12000, "tile-locked strike does not follow a moved actor")
	_check(charge_intent.state == IntentScript.IntentState.CANCELED, "empty marked cell cancels tile-locked strike")
	charge_battle.queue_free()

	var pursuit_battle = ControllerScript.new()
	root.add_child(pursuit_battle)
	_check(pursuit_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)]), "second encounter starts")
	var pursuit_intent = pursuit_battle.intents[0]
	_check(pursuit_intent.action_id == "pursuit", "distant enemy selects pursuit")
	_check(pursuit_intent.affected_cells.size() == 2, "pursuit captures a path of up to two cells")
	_check(pursuit_battle.end_player_turn(), "pursuit enemy phase resolves")
	_check(pursuit_battle.get_actor("vanguard_00").cell == Vector2i(2, 1), "pursuit moves two cells toward target")
	pursuit_battle.queue_free()

	var wait_battle = ControllerScript.new()
	root.add_child(wait_battle)
	var cage: Array[Vector2i] = [Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 4), Vector2i(5, 6)]
	_check(wait_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)], cage), "blocked-enemy encounter starts")
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
	var shot_intent = marksman_battle.intents[0]
	_check(marksman_battle.get_actor("marksman_00").archetype == "marksman", "enemy archetype is stored on actor")
	_check(marksman_battle.get_actor("marksman_00").max_health == 2000, "marksman baseline health is 2000")
	_check(shot_intent.action_id == "aimed_shot", "aligned target in range produces aimed shot")
	_check(shot_intent.target_mode == IntentScript.TargetMode.TILE_LOCKED, "aimed shot captures tile lock")
	_check(shot_intent.target_cell == Vector2i(1, 1) and shot_intent.damage == 1200, "aimed shot captures marked cell and damage")
	_check(marksman_battle.end_player_turn(), "aimed shot resolves during enemy phase")
	_check(marksman_battle.get_actor("sevrin").health == 11273, "aimed shot deals 727 mitigated damage")
	_check(shot_intent.state == IntentScript.IntentState.RESOLVED, "aimed shot intent resolves")
	marksman_battle.queue_free()

	var oathguard_battle = ControllerScript.new()
	root.add_child(oathguard_battle)
	_check(oathguard_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "Oathguard damage encounter starts")
	_check(oathguard_battle.statuses.apply_status(&"oathguard", "sevrin", "sevrin", 1, 1, 1, &"enemy_phase_end"), "Oathguard grants one defensive trigger")
	_check(oathguard_battle.end_player_turn(), "Oathguard encounter resolves enemy phase")
	_check(oathguard_battle.get_actor("sevrin").health == 11528, "Oathguard reduces post-resistance aimed shot damage by 35 percent")
	_check(not oathguard_battle.statuses.has_status("sevrin", &"oathguard"), "Oathguard is consumed after one successful hit")
	oathguard_battle.queue_free()

	var marked_shot_battle = ControllerScript.new()
	root.add_child(marked_shot_battle)
	_check(marked_shot_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "Judgment Mark ranged encounter starts")
	_check(marked_shot_battle.request_judgment_mark("marksman_00"), "Judgment Mark accepts a visible enemy within four cells")
	_check(marked_shot_battle.ap.current == 2 and marked_shot_battle.intents[0].judgment_marked, "Judgment Mark spends one AP and annotates the already revealed attack")
	_check(marked_shot_battle.end_player_turn(), "marked aimed shot resolves")
	_check(marked_shot_battle.get_actor("sevrin").health == 11455, "Judgment Mark reduces single-target raw damage by 25 percent before resistance")
	_check(not marked_shot_battle.statuses.has_status("marksman_00", &"judgment_mark"), "Judgment Mark is consumed after the marked attack executes")
	marked_shot_battle.queue_free()

	var marked_charge_battle = ControllerScript.new()
	root.add_child(marked_charge_battle)
	_check(marked_charge_battle.start_encounter(Vector2i(1, 1), [Vector2i(3, 1)]), "Judgment Mark charged-strike encounter starts")
	_check(marked_charge_battle.request_judgment_mark("vanguard_00"), "Judgment Mark can target a nearby Vanguard")
	_check(marked_charge_battle.intents[0].judgment_marked, "charged-strike intent retains the mark without changing its footprint")
	_check(marked_charge_battle.end_player_turn(), "marked charged strike resolves")
	_check(marked_charge_battle.get_actor("sevrin").health == 10728, "marked charged strike keeps its original damage")
	_check(marked_charge_battle.statuses.has_status("vanguard_00", &"exposed"), "marked charged strike applies Exposed to its source")
	var approach_path: Array[Vector2i] = [Vector2i(2, 1)]
	_check(marked_charge_battle.request_player_move(approach_path), "player can approach the Exposed Vanguard")
	_check(marked_charge_battle.request_player_attack("vanguard_00"), "player can attack the Exposed Vanguard")
	_check(marked_charge_battle.get_actor("vanguard_00").health == 1867, "Exposed reduces physical defense by 200 for the next player turn")
	_check(marked_charge_battle.end_player_turn(), "Exposed duration ends after the following player phase")
	_check(not marked_charge_battle.statuses.has_status("vanguard_00", &"exposed"), "Exposed expires at player-phase end")
	marked_charge_battle.queue_free()

	var severance_battle = ControllerScript.new()
	root.add_child(severance_battle)
	_check(severance_battle.start_encounter(Vector2i(1, 1), [Vector2i(3, 1)]), "Oath Severance encounter starts")
	var severance_intent = severance_battle.intents[0]
	_check(not severance_battle.request_oath_severance("vanguard_00"), "Oath Severance rejects an unmarked target")
	_check(severance_battle.ap.current == 3, "rejected Oath Severance does not spend AP")
	_check(severance_battle.request_judgment_mark("vanguard_00"), "Oath Severance target can first be marked")
	_check(severance_battle.request_oath_severance("vanguard_00"), "Oath Severance accepts a marked enemy within two cells")
	_check(severance_battle.ap.current == 0, "Judgment Mark plus Oath Severance spends exactly three AP")
	_check(not severance_battle.statuses.has_status("vanguard_00", &"judgment_mark"), "Oath Severance consumes Judgment Mark before damage")
	_check(severance_intent.state == IntentScript.IntentState.CANCELED and severance_intent.cancel_reason == "oath_severance", "Oath Severance cancels the enemy's current visible intent")
	_check(severance_battle.get_actor("vanguard_00").health == 1553, "Oath Severance deals 1.4 times physical damage after defense")
	_check(severance_battle.end_player_turn(), "Oath Severance enemy phase completes")
	_check(severance_battle.get_actor("sevrin").health == 12000, "severed enemy intent does not execute during this enemy phase")
	severance_battle.queue_free()

	var marked_pursuit_battle = ControllerScript.new()
	root.add_child(marked_pursuit_battle)
	_check(marked_pursuit_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)]), "Judgment Mark pursuit encounter starts")
	_check(marked_pursuit_battle.request_judgment_mark("vanguard_00"), "Judgment Mark can target an enemy preparing to pursue")
	_check(not marked_pursuit_battle.intents[0].judgment_marked, "pursuit does not consume or capture Judgment Mark as an attack")
	_check(marked_pursuit_battle.end_player_turn(), "unmarked pursuit executes")
	_check(marked_pursuit_battle.statuses.has_status("vanguard_00", &"judgment_mark"), "unused mark survives the first enemy phase")
	_check(marked_pursuit_battle.intents[0].action_id == "basic_melee" and marked_pursuit_battle.intents[0].judgment_marked, "mark attaches to the enemy's next attack intent")
	_check(marked_pursuit_battle.end_player_turn(), "next marked attack intent resolves")
	_check(not marked_pursuit_battle.statuses.has_status("vanguard_00", &"judgment_mark"), "mark is consumed by the next attack intent")
	marked_pursuit_battle.queue_free()

	var marked_area_battle = ControllerScript.new()
	root.add_child(marked_area_battle)
	var marked_area_types: Array[String] = ["area_controller"]
	_check(marked_area_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)], [], marked_area_types), "Judgment Mark area-attack encounter starts")
	_check(marked_area_battle.request_judgment_mark("area_controller_00"), "Judgment Mark can target an area attacker")
	_check(marked_area_battle.intents[0].judgment_marked and marked_area_battle.intents[0].affected_cells.size() == 5, "marked area intent keeps its original five-cell footprint")
	_check(marked_area_battle.end_player_turn(), "marked area attack resolves")
	_check(marked_area_battle.get_actor("sevrin").health == 11487, "marked area attack retains its original damage")
	_check(marked_area_battle.statuses.has_status("area_controller_00", &"exposed"), "marked area attack applies Exposed to its source")
	marked_area_battle.queue_free()

	var evaded_marksman_battle = ControllerScript.new()
	root.add_child(evaded_marksman_battle)
	_check(evaded_marksman_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], marksman_types), "evadable marksman encounter starts")
	var evaded_shot = evaded_marksman_battle.intents[0]
	var marksman_evade_path: Array[Vector2i] = [Vector2i(1, 2)]
	_check(evaded_marksman_battle.request_player_move(marksman_evade_path), "player can leave marksman marked cell")
	_check(evaded_marksman_battle.end_player_turn(), "evaded marksman phase resolves")
	_check(evaded_marksman_battle.get_actor("sevrin").health == 12000, "tile-locked aimed shot does not track moved player")
	_check(evaded_shot.state == IntentScript.IntentState.CANCELED, "aimed shot cancels when marked cell is empty")
	evaded_marksman_battle.queue_free()

	var blocked_marksman_battle = ControllerScript.new()
	root.add_child(blocked_marksman_battle)
	_check(blocked_marksman_battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [Vector2i(3, 1)], marksman_types), "blocked marksman encounter starts")
	_check(blocked_marksman_battle.intents[0].action_id == "wait", "blocked firing lane produces wait intent")
	blocked_marksman_battle.queue_free()

	var out_of_range_marksman_battle = ControllerScript.new()
	root.add_child(out_of_range_marksman_battle)
	_check(out_of_range_marksman_battle.start_encounter(Vector2i(1, 1), [Vector2i(3, 1)], [], marksman_types), "out-of-range marksman encounter starts")
	_check(out_of_range_marksman_battle.intents[0].action_id == "wait", "target inside minimum range produces wait intent")
	out_of_range_marksman_battle.queue_free()

	var mixed_battle = ControllerScript.new()
	root.add_child(mixed_battle)
	var mixed_types: Array[String] = ["vanguard", "marksman"]
	_check(mixed_battle.start_encounter(Vector2i(1, 1), [Vector2i(1, 2), Vector2i(5, 1)], [], mixed_types), "mixed vanguard and marksman encounter starts")
	_check(mixed_battle.intents.size() == 2, "mixed encounter creates one intent per living enemy")
	_check(mixed_battle.intents[0].action_id == "basic_melee", "vanguard melee is ordered before ranged shot")
	_check(mixed_battle.intents[1].action_id == "aimed_shot", "marksman shot follows vanguard melee in visible order")
	_check(mixed_battle.intents[0].source_actor_id == "vanguard_00" and mixed_battle.intents[1].source_actor_id == "marksman_01", "mixed execution order retains explicit archetype identities")
	var mixed_intents = mixed_battle.intents
	_check(mixed_battle.end_player_turn(), "mixed enemy phase resolves")
	_check(mixed_battle.get_actor("sevrin").health == 10595, "mixed phase applies melee and ranged damage in order")
	_check(mixed_intents[0].state == IntentScript.IntentState.RESOLVED and mixed_intents[1].state == IntentScript.IntentState.RESOLVED, "both mixed intents resolve")
	mixed_battle.queue_free()


	var all_archetypes_battle = ControllerScript.new()
	root.add_child(all_archetypes_battle)
	var all_archetypes: Array[String] = ["vanguard", "marksman", "area_controller"]
	_check(all_archetypes_battle.start_encounter(Vector2i(1, 3), [Vector2i(2, 3), Vector2i(1, 0), Vector2i(4, 3)], [], all_archetypes), "all three enemy archetypes can share one encounter")
	_check(all_archetypes_battle.intents.size() == 3, "mixed three-archetype encounter creates one intent per enemy")
	_check(all_archetypes_battle.intents[0].source_actor_id == "vanguard_00" and all_archetypes_battle.intents[0].action_id == "basic_melee", "mixed roster places adjacent Vanguard first")
	_check(all_archetypes_battle.intents[1].source_actor_id == "area_controller_02" and all_archetypes_battle.intents[1].action_id == "ground_pulse", "equal-priority Area Controller uses stable battlefield tie-break")
	_check(all_archetypes_battle.intents[2].source_actor_id == "marksman_01" and all_archetypes_battle.intents[2].action_id == "aimed_shot", "higher-priority-number Marksman acts after the first two intents")
	_check(all_archetypes_battle.intents[1].affected_cells.has(Vector2i(1, 3)) and all_archetypes_battle.intents[2].target_cell == Vector2i(1, 3), "mixed roster telegraphs retain their captured area and tile")
	var all_archetypes_intents = all_archetypes_battle.intents
	_check(all_archetypes_battle.end_player_turn(), "all-archetype enemy phase resolves")
	_check(all_archetypes_battle.get_actor("sevrin").health == 10082, "mixed roster resolves Vanguard, area, and ranged damage in displayed order")
	_check(all_archetypes_intents.all(func(intent): return intent.state == IntentScript.IntentState.RESOLVED), "all three mixed-roster intents resolve exactly once")
	all_archetypes_battle.queue_free()

	var lane_block_battle = ControllerScript.new()
	root.add_child(lane_block_battle)
	var lane_block_types: Array[String] = ["vanguard", "marksman"]
	_check(lane_block_battle.start_encounter(Vector2i(1, 3), [Vector2i(1, 1), Vector2i(1, 0)], [], lane_block_types), "mixed lane-block encounter starts")
	_check(lane_block_battle.intents.size() == 2 and lane_block_battle.intents[0].action_id == "charged_strike", "Vanguard telegraphs its fixed-cell strike in the firing lane")
	_check(lane_block_battle.intents[1].action_id == "wait", "occupied firing lane prevents Marksman from telegraphing a shot")
	lane_block_battle.queue_free()

	var area_battle = ControllerScript.new()
	root.add_child(area_battle)
	var area_types: Array[String] = ["area_controller"]
	_check(area_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)], [], area_types), "area controller encounter starts")
	var area_intent = area_battle.intents[0]
	_check(area_battle.get_actor("area_controller_00").max_health == 2600, "area controller baseline health is 2600")
	_check(area_intent.action_id == "ground_pulse", "area controller selects ground pulse in range")
	_check(area_intent.target_mode == IntentScript.TargetMode.AREA_LOCKED, "ground pulse captures area lock")
	_check(area_intent.affected_cells.size() == 5 and area_intent.affected_cells.has(Vector2i(1, 1)), "ground pulse captures fixed orthogonal cross footprint")
	_check(area_battle.end_player_turn(), "ground pulse resolves during enemy phase")
	_check(area_battle.get_actor("sevrin").health == 11487, "ground pulse deals one damage inside marked area")
	_check(area_intent.state == IntentScript.IntentState.RESOLVED, "ground pulse intent resolves")
	area_battle.queue_free()

	var evaded_area_battle = ControllerScript.new()
	root.add_child(evaded_area_battle)
	_check(evaded_area_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)], [], area_types), "evadable area controller encounter starts")
	var evaded_area_intent = evaded_area_battle.intents[0]
	var area_evade_path: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2)]
	_check(evaded_area_battle.request_player_move(area_evade_path), "player can move outside the marked cross area")
	_check(evaded_area_battle.end_player_turn(), "evaded ground pulse phase resolves")
	_check(evaded_area_battle.get_actor("sevrin").health == 12000, "ground pulse misses player outside captured area")
	_check(evaded_area_intent.state == IntentScript.IntentState.CANCELED and evaded_area_intent.cancel_reason == "marked_area_empty", "empty ground pulse area cancels explicitly")
	evaded_area_battle.queue_free()

	var edge_area_battle = ControllerScript.new()
	root.add_child(edge_area_battle)
	_check(edge_area_battle.start_encounter(Vector2i(0, 0), [Vector2i(2, 0)], [], area_types), "edge area controller encounter starts")
	_check(edge_area_battle.intents[0].affected_cells.size() == 3, "ground pulse clips cells beyond the map boundary")
	_check(edge_area_battle.intents[0].affected_cells.has(Vector2i(0, 0)) and edge_area_battle.intents[0].affected_cells.has(Vector2i(1, 0)) and edge_area_battle.intents[0].affected_cells.has(Vector2i(0, 1)), "edge footprint retains only valid cross cells")
	edge_area_battle.queue_free()

	var actor_lock_battle = ControllerScript.new()
	root.add_child(actor_lock_battle)
	_check(actor_lock_battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "actor-lock encounter starts")
	var actor_intent = actor_lock_battle.intents[0]
	_check(actor_intent.target_mode == IntentScript.TargetMode.ACTOR_LOCKED, "adjacent basic attack captures actor lock")
	var retreat_path: Array[Vector2i] = [Vector2i(1, 2), Vector2i(1, 3)]
	_check(actor_lock_battle.request_player_move(retreat_path), "player can retreat two cells after telegraph")
	_check(actor_lock_battle.end_player_turn(), "actor-lock enemy phase resolves")
	_check(actor_lock_battle.get_actor("sevrin").health == 11322, "actor-locked attack tracks target after it moves")
	actor_lock_battle.queue_free()

	var terminal_battle = ControllerScript.new()
	root.add_child(terminal_battle)
	_check(terminal_battle.start_encounter(Vector2i(2, 2), [Vector2i(2, 1), Vector2i(1, 2)]), "terminal-order encounter starts")
	terminal_battle.get_actor("sevrin").health = 1
	_check(terminal_battle.end_player_turn(), "terminal encounter enters enemy phase")
	_check(terminal_battle.phase == ControllerScript.BattlePhase.FINISHED, "player defeat ends battle immediately")
	_check(terminal_battle.battle_result == "defeat", "terminal result is defeat")
	_check(terminal_battle.intents[1].state == IntentScript.IntentState.CANCELED, "remaining enemy intent is canceled after terminal result")
	terminal_battle.queue_free()

	var victory_battle = ControllerScript.new()
	root.add_child(victory_battle)
	_check(victory_battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "victory encounter starts")
	var victory_intent = victory_battle.intents[0]
	_check(victory_battle.statuses.apply_status(&"exposed", "sevrin", "vanguard_00"), "enemy can receive a runtime status")
	_check(victory_battle.request_player_attack("vanguard_00"), "first confirmed attack spends AP")
	_check(victory_battle.request_player_attack("vanguard_00"), "second confirmed attack spends AP")
	_check(victory_battle.request_player_attack("vanguard_00"), "lethal third attack defeats the final enemy")
	_check(victory_battle.phase == ControllerScript.BattlePhase.FINISHED and victory_battle.battle_result == "victory", "defeating the final enemy ends battle in victory")
	_check(victory_intent.state == IntentScript.IntentState.CANCELED, "defeated final enemy intent is canceled")
	_check(not victory_battle.statuses.has_status("vanguard_00", &"exposed"), "defeated actor has all statuses cleared")
	_check(not victory_battle.request_player_attack("vanguard_00"), "actions are rejected after battle victory")
	_check(victory_battle.ap.current == 0, "victory sequence spends exactly three AP")
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
	custom_bounds_battle.player_ap = 0
	_check(not custom_bounds_battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 4)]), "zero AP configuration is rejected")
	custom_bounds_battle.player_ap = 3
	custom_bounds_battle.player_ap = 4
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

	_report()
