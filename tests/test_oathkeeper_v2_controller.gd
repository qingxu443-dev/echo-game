extends "res://tests/framework/test_case.gd"

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const ActorScript = preload("res://scripts/actors/battle_actor.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")


func _run() -> void:
	_test_oath_vow_passive_and_shield_application()
	_test_oath_vow_counts_once_per_intent_and_caps_at_three()
	_test_v2_judgment_mark_damage_replacement_and_expiry()
	_test_v2_judgment_mark_rejects_invalid_targets()
	_test_oath_shield_validation_and_duration()
	_test_absolute_guard_taunt_counter_and_energy()
	_test_absolute_guard_redirects_distant_melee()
	_test_absolute_guard_end_to_end_enemy_phase()
	_report()


func _test_oath_vow_passive_and_shield_application() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "Oath Vow encounter starts")
	battle.actors["ally_test"] = ActorScript.new("ally_test", "player", Vector2i(1, 2), 1000, "support", 500, 200, 200)

	_check(battle.get_oath_vow_stacks() == 0, "Oath Vow begins with zero stacks")
	_check(battle.request_oath_shield("ally_test"), "Oath Shield can target a nearby allied test unit")
	_check(battle.ap.current == battle.ap.maximum - 1, "Oath Shield spends exactly one AP")
	_check(battle.get_actor("sevrin").shield == 195, "Sevrin receives the DEF-scaled base shield")
	_check(battle.get_actor("ally_test").shield == 150, "ally shield independently respects 15 percent max-health cap")
	_check(battle.get_oath_vow_stacks() == 0, "Oath Shield works with zero Oath Vow stacks")

	_check(battle.end_player_turn(), "enemy attack resolves against Sevrin")
	_check(battle.get_oath_vow_stacks() == 1, "successful enemy active attack grants one Oath Vow stack")
	_check(battle.get_actor("sevrin").shield < 195, "incoming damage is absorbed by Sevrin's shield")
	_check(battle.get_actor("sevrin").health < battle.get_actor("sevrin").max_health, "damage beyond shield reduces health")
	_check(battle.get_actor("ally_test").shield == 150, "the ally's independent shield is not affected by Sevrin being hit")

	_check(battle.request_oath_shield("sevrin"), "Oath Shield can target Sevrin alone")
	_check(battle.get_oath_vow_stacks() == 0, "Oath Shield consumes all current Oath Vow stacks")
	_check(battle.get_actor("sevrin").shield >= 214, "one Oath Vow stack increases the newly calculated shield")
	battle.queue_free()


func _test_oath_vow_counts_once_per_intent_and_caps_at_three() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "Oath Vow stacking encounter starts")
	battle._apply_damage("sevrin", 100, "vanguard_00", "scripted_damage", "physical", false)
	_check(battle.get_oath_vow_stacks() == 0, "non-public damage does not grant Oath Vow")
	battle._apply_damage("sevrin", 100, "vanguard_00", "multi_hit_test", "physical", true, "intent_multi_hit")
	battle._apply_damage("sevrin", 100, "vanguard_00", "multi_hit_test", "physical", true, "intent_multi_hit")
	_check(battle.get_oath_vow_stacks() == 1, "multiple damage instances from one enemy intent grant only one stack")
	battle._apply_damage("sevrin", 100, "vanguard_00", "attack_test", "physical", true, "intent_two")
	battle._apply_damage("sevrin", 100, "vanguard_00", "attack_test", "physical", true, "intent_three")
	battle._apply_damage("sevrin", 100, "vanguard_00", "attack_test", "physical", true, "intent_four")
	_check(battle.get_oath_vow_stacks() == 3, "Oath Vow stacks cap at three")
	battle.queue_free()


func _test_v2_judgment_mark_damage_replacement_and_expiry() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1), Vector2i(1, 4)]), "v2 Judgment Mark encounter starts")
	var first_target = battle.get_actor("vanguard_00")
	var second_target = battle.get_actor("vanguard_01")
	var first_health: int = first_target.health
	var expected_damage: int = 305
	_check(battle.request_oathkeeper_judgment_mark("vanguard_00"), "v2 Judgment Mark accepts a legal enemy target")
	_check(first_target.health == first_health - expected_damage, "v2 Judgment Mark deals DEF times 0.8 physical damage")
	_check(battle.get_oathkeeper_marked_target() == "vanguard_00", "v2 Judgment Mark records the selected target")
	_check(battle.statuses.has_status("vanguard_00", &"oathkeeper_mark"), "v2 mark uses its isolated status ID")
	_check(not battle.statuses.has_status("vanguard_00", &"judgment_mark"), "v2 mark does not create the legacy judgment status")
	_check(battle.request_oathkeeper_judgment_mark("vanguard_01"), "v2 Judgment Mark can be recast on another enemy")
	_check(not battle.statuses.has_status("vanguard_00", &"oathkeeper_mark"), "recasting removes the previous v2 mark")
	_check(battle.get_oathkeeper_marked_target() == "vanguard_01", "only the latest enemy remains marked")
	_check(battle.end_player_turn(), "marked enemy phase resolves")
	_check(battle.get_oathkeeper_marked_target().is_empty(), "v2 mark expires at the end of the enemy phase after application")
	battle.queue_free()


func _test_v2_judgment_mark_rejects_invalid_targets() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(7, 7)]), "v2 Judgment Mark validation encounter starts")
	_check(not battle.request_oathkeeper_judgment_mark("missing"), "v2 Judgment Mark rejects unknown targets")
	_check(not battle.request_oathkeeper_judgment_mark("sevrin"), "v2 Judgment Mark rejects self targeting")
	_check(battle.ap.current == battle.ap.maximum, "invalid v2 Judgment Mark targets do not spend AP")
	battle.queue_free()


func _test_oath_shield_validation_and_duration() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(7, 7)]), "Oath Shield duration encounter starts")
	battle.actors["ally_near"] = ActorScript.new("ally_near", "player", Vector2i(3, 1), 1000, "support", 500, 200, 200)
	battle.actors["ally_far"] = ActorScript.new("ally_far", "player", Vector2i(4, 1), 1000, "support", 500, 200, 200)

	_check(not battle.request_oath_shield("missing_actor"), "Oath Shield rejects unknown targets")
	_check(not battle.request_oath_shield("vanguard_00"), "Oath Shield rejects enemy targets")
	_check(not battle.request_oath_shield("ally_far"), "Oath Shield rejects allies beyond two Manhattan cells")
	_check(battle.ap.current == battle.ap.maximum, "invalid Oath Shield targets do not spend AP")
	_check(battle.request_oath_shield("ally_near"), "Oath Shield accepts an ally exactly two cells away")
	var initial_shield: int = battle.get_actor("sevrin").shield
	_check(initial_shield == 195, "initial self shield matches base formula")
	_check(battle.request_oath_shield("ally_near"), "recasting Oath Shield refreshes duration")
	_check(battle.get_actor("sevrin").shield == initial_shield, "recasting an equal shield does not stack shield values")

	_check(battle.end_player_turn(), "first player turn ends")
	_check(battle.get_actor("sevrin").shield == initial_shield, "shield remains through the first enemy phase and next player turn")
	_check(battle.end_player_turn(), "second player turn ends")
	_check(battle.get_actor("sevrin").shield == 0, "shield expires at the end of the second player turn")
	_check(battle.get_actor("ally_near").shield == 0, "ally shield expires at the same two-turn boundary")
	battle.queue_free()


func _test_absolute_guard_taunt_counter_and_energy() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "Absolute Guard encounter starts")
	var sevrin = battle.get_actor("sevrin")
	var enemy = battle.get_actor("vanguard_00")
	_check(sevrin.ultimate_energy == 1, "each player turn start grants one ultimate energy")
	sevrin.ultimate_energy = 4
	_check(not battle.request_absolute_guard(), "Absolute Guard rejects activation below five energy")
	_check(sevrin.ultimate_energy == 4 and battle.ap.current == battle.ap.maximum, "failed Absolute Guard activation preserves energy and AP")
	sevrin.ultimate_energy = 5
	battle.actors["ally_test"] = ActorScript.new("ally_test", "player", Vector2i(1, 2), 1000, "support", 300, 100, 100)
	_check(battle.request_absolute_guard(), "Absolute Guard can be activated at five energy")
	_check(sevrin.ultimate_energy == 1 and battle.ap.current == battle.ap.maximum - 2, "Absolute Guard spends five energy, gains the once-per-turn active-action point, and spends two AP")
	_check(battle.statuses.has_status("sevrin", &"absolute_guard"), "Absolute Guard status is active after casting")

	var melee = IntentScript.new("taunt_test", "vanguard_00", "basic_melee", IntentScript.TargetMode.ACTOR_LOCKED, "ally_test", Vector2i(1, 2), [Vector2i(1, 2)], 100, 0)
	battle._redirect_single_target_intent_to_sevrin(melee)
	_check(melee.target_actor_id == "sevrin" and melee.target_cell == sevrin.cell, "Absolute Guard redirects a legal single-target melee intent")
	enemy.cell = Vector2i(3, 1)
	var charged = IntentScript.new("charged_test", "vanguard_00", "charged_strike", IntentScript.TargetMode.TILE_LOCKED, "", Vector2i(1, 2), [Vector2i(1, 2)], 100, 0)
	battle._redirect_single_target_intent_to_sevrin(charged)
	_check(charged.target_cell == sevrin.cell and charged.affected_cells == [sevrin.cell], "Absolute Guard redirects a legal two-cell charged strike to Sevrin")
	battle.blocked_cells[Vector2i(2, 1)] = true
	var blocked_charged = IntentScript.new("blocked_charged_test", "vanguard_00", "charged_strike", IntentScript.TargetMode.TILE_LOCKED, "", Vector2i(1, 2), [Vector2i(1, 2)], 100, 0)
	battle._redirect_single_target_intent_to_sevrin(blocked_charged)
	_check(blocked_charged.target_cell == Vector2i(1, 2), "Absolute Guard does not redirect a charged strike through blocked line of sight")
	battle.blocked_cells.erase(Vector2i(2, 1))
	var area_cells: Array[Vector2i] = [Vector2i(3, 1), Vector2i(3, 2)]
	var area_intent = IntentScript.new("area_test", "vanguard_00", "ground_pulse", IntentScript.TargetMode.AREA_LOCKED, "", Vector2i(3, 1), area_cells, 100, 0)
	battle._redirect_single_target_intent_to_sevrin(area_intent)
	_check(area_intent.target_cell == Vector2i(3, 1) and area_intent.affected_cells == area_cells, "Absolute Guard never changes area attack geometry")
	enemy.cell = Vector2i(4, 1)
	var ranged = IntentScript.new("ranged_test", "vanguard_00", "aimed_shot", IntentScript.TargetMode.TILE_LOCKED, "", Vector2i(4, 1), [Vector2i(4, 1)], 100, 0)
	battle._redirect_single_target_intent_to_sevrin(ranged)
	_check(ranged.target_cell == Vector2i(4, 1), "Absolute Guard does not redirect an attack outside its two-cell radius")

	sevrin.shield = 500
	battle._apply_damage("sevrin", 1, "vanguard_00", "basic_melee", "physical", true, "counter_test_intent")
	battle._apply_damage("sevrin", 1, "vanguard_00", "basic_melee", "physical", true, "counter_test_intent")
	_check(battle.absolute_guard_hit_intents.has("counter_test_intent"), "a fully shield-absorbed enemy hit queues an Absolute Guard counter")
	_check(battle.absolute_guard_hit_intents.size() == 1, "multiple hits in one enemy intent queue only one counter")
	var stacks_after_hit: int = battle.get_oath_vow_stacks()
	battle.statuses.apply_status(&"oathkeeper_mark", "sevrin", "vanguard_00", 1, 1, -1, &"enemy_phase_end")
	var counter_intent = IntentScript.new("counter_test_intent", "vanguard_00", "basic_melee", IntentScript.TargetMode.ACTOR_LOCKED, "sevrin", sevrin.cell, [sevrin.cell], 1, 0)
	var enemy_health_before: int = enemy.health
	battle._resolve_absolute_guard_counter(counter_intent)
	_check(enemy.health == enemy_health_before - 267, "marked enemy receives DEF times 0.7 counter damage after defense")
	_check(battle.get_oath_vow_stacks() == stacks_after_hit, "Absolute Guard counter does not generate another Oath Vow stack")
	enemy_health_before = enemy.health
	battle._resolve_absolute_guard_counter(counter_intent)
	_check(enemy.health == enemy_health_before, "each enemy can be countered only once per player turn")
	battle.ap.current = 3
	sevrin.ultimate_energy = 5
	_check(battle.request_absolute_guard(), "Absolute Guard can be recast when resources are available")
	enemy_health_before = enemy.health
	battle._resolve_absolute_guard_counter(counter_intent)
	_check(enemy.health == enemy_health_before, "recasting Absolute Guard does not reset the per-enemy counter limit")

	battle.absolute_guard_countered_enemies.clear()
	battle._begin_player_turn()
	_check(not battle.statuses.has_status("sevrin", &"absolute_guard"), "Absolute Guard expires at the next player turn start")
	_check(sevrin.ultimate_energy == 1, "new player turn restores one energy after the recast spent the remaining ultimate energy")
	_check(battle.get_actor("ally_test").ultimate_energy == 1, "each living allied actor receives independent turn-start ultimate energy")
	battle.queue_free()
	_test_absolute_guard_cleans_up_on_sevrin_death()


func _test_absolute_guard_cleans_up_on_sevrin_death() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "Absolute Guard death-cleanup encounter starts")
	var sevrin = battle.get_actor("sevrin")
	sevrin.ultimate_energy = 5
	_check(battle.request_absolute_guard(), "Absolute Guard activates before Sevrin is defeated")
	_check(battle.statuses.has_status("sevrin", &"absolute_guard"), "Absolute Guard status exists before defeat")
	sevrin.health = 1
	battle._apply_damage("sevrin", 10000, "vanguard_00", "death_test", "physical", false)
	battle._check_battle_end()
	_check(battle.phase == ControllerScript.BattlePhase.FINISHED, "Sevrin defeat ends the encounter")
	_check(not battle.statuses.has_status("sevrin", &"absolute_guard"), "Sevrin defeat clears Absolute Guard immediately")
	battle.queue_free()


## Regression guard for the unified melee redirect semantics: actor-locked
## attacks are dodge-proof, so the taunt covers the whole two-cell radius.
func _test_absolute_guard_redirects_distant_melee() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "distant melee redirect encounter starts")
	battle.statuses.apply_status(&"absolute_guard", "sevrin", "sevrin", 1, 1, -1, &"player_phase_start")
	battle.actors["ally_test"] = ActorScript.new("ally_test", "player", Vector2i(1, 2), 1000, "support", 300, 100, 100)
	var enemy = battle.get_actor("vanguard_00")
	enemy.cell = Vector2i(3, 1)
	var distant_melee = IntentScript.new("distant_melee_test", "vanguard_00", "basic_melee", IntentScript.TargetMode.ACTOR_LOCKED, "ally_test", Vector2i(1, 2), [Vector2i(1, 2)], 100, 0)
	battle._redirect_single_target_intent_to_sevrin(distant_melee)
	_check(distant_melee.target_actor_id == "sevrin" and distant_melee.target_cell == Vector2i(1, 1), "a melee inside the taunt radius redirects even when Sevrin is not adjacent")
	enemy.cell = Vector2i(4, 1)
	var far_melee = IntentScript.new("far_melee_test", "vanguard_00", "basic_melee", IntentScript.TargetMode.ACTOR_LOCKED, "ally_test", Vector2i(1, 2), [Vector2i(1, 2)], 100, 0)
	battle._redirect_single_target_intent_to_sevrin(far_melee)
	_check(far_melee.target_actor_id == "ally_test", "a melee beyond the taunt radius keeps its original target")
	battle.queue_free()


## End-to-end coverage for the wiring that the white-box tests cannot see:
## a real enemy phase must register the public hits, fire the redirect and
## resolve exactly one counter per attacker without any manual intervention.
func _test_absolute_guard_end_to_end_enemy_phase() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1), Vector2i(1, 2)]), "Absolute Guard end-to-end encounter starts")
	var sevrin = battle.get_actor("sevrin")
	var first = battle.get_actor("vanguard_00")
	var second = battle.get_actor("vanguard_01")
	sevrin.ultimate_energy = 5
	_check(battle.request_absolute_guard(), "Absolute Guard activates through the public API")
	var telegraphs = battle.intents
	_check(telegraphs.size() == 2 and telegraphs.all(func(intent): return intent.action_id == "basic_melee"), "two adjacent vanguards telegraph melee attacks")
	_check(battle.end_player_turn(), "the real enemy phase resolves with Absolute Guard active")
	_check(telegraphs.all(func(intent): return intent.state == IntentScript.IntentState.RESOLVED), "both melee intents resolve through the real enemy phase")
	_check(sevrin.health == 12000 - 678 * 2, "both melee attacks land their mitigated damage on Sevrin")
	_check(first.health == 3200 - 191 and second.health == 3200 - 191, "each attacker is countered exactly once by the real enemy-phase pipeline")
	_check(battle.damage_taken == 678 * 2, "the settlement tally records only the real attrition")
	_check(battle.phase == ControllerScript.BattlePhase.PLAYER, "the battle continues into the next player phase")
	battle.queue_free()

