extends "res://tests/framework/test_case.gd"

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const ActorScript = preload("res://scripts/actors/battle_actor.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const IntentPlannerScript = preload("res://scripts/battle/intent_planner.gd")
const IntentResolverScript = preload("res://scripts/battle/intent_resolver.gd")


func _run() -> void:
	_test_oath_vow_passive_and_shield_application()
	_test_oath_vow_counts_once_per_intent_and_caps_at_three()
	_test_v2_judgment_mark_damage_replacement_and_expiry()
	_test_v2_judgment_mark_amplifies_and_consumes_on_next_hit()
	_test_v2_judgment_mark_rejects_invalid_targets()
	_test_oath_shield_validation_and_duration()
	_test_absolute_verdict_aoe_knockback_and_energy()
	_test_one_action_grants_vow_per_carrier()
	_test_oathblade_knockback_collisions()
	_test_oathblade_knockback_unit_collision_and_chest_break()
	_test_guard_taunt_pulls_a_dodged_melee_within_two_cells()
	_test_guard_taunt_redirects_single_target_ranged_intents()
	_test_guard_counters_each_independent_enemy_intent()
	_test_knockback_shifts_active_telegraphs()
	_report()


func _test_oath_vow_passive_and_shield_application() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "Oath Vow encounter starts")
	battle.beacons.clear()
	battle.intents = IntentPlannerScript.plan(battle)
	battle.actors["ally_test"] = ActorScript.new("ally_test", "player", Vector2i(1, 2), 1000, "support", 500, 200, 200)

	_check(battle.get_oath_vow_stacks() == 0, "Oath Vow begins with zero stacks")
	_check(battle.request_oath_shield("ally_test"), "Oath Shield can target a nearby allied test unit")
	_check(battle.ap.current == battle.ap.maximum - 1, "Oath Shield spends exactly one AP")
	_check(battle.get_actor("sevrin").shield == 720, "Sevrin receives the base shield equal to 200% DEF")
	_check(battle.get_actor("ally_test").shield == 300, "ally shield independently respects 30 percent max-health cap")
	_check(battle.get_oath_vow_stacks() == 0, "Oath Shield works with zero Oath Vow stacks")

	_check(battle.end_player_turn(), "enemy attack resolves against Sevrin")
	_check(battle.get_oath_vow_stacks() == 1, "successful enemy active attack grants one Oath Vow stack")
	_check(battle.get_actor("sevrin").shield < 720, "incoming damage is absorbed by Sevrin's shield")
	_check(battle.get_actor("sevrin").health < battle.get_actor("sevrin").max_health, "damage beyond shield reduces health")

	_check(battle.request_oath_shield("sevrin"), "Oath Shield can target Sevrin alone")
	_check(battle.get_oath_vow_stacks() == 0, "Oath Shield consumes all current Oath Vow stacks")
	_check(battle.get_actor("sevrin").shield == 820, "one Oath Vow stack increases the newly calculated shield by 100")
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
	battle.beacons.clear()
	var first_target = battle.get_actor("vanguard_00")
	var first_health: int = first_target.health
	# Sevrin 360 DEF * 0.55 = 198 raw -> floor(198 * 1000 / 1450) = 136
	var expected_damage: int = 136
	_check(battle.request_oathkeeper_judgment_mark("vanguard_00"), "v2 Judgment Mark accepts a legal enemy target")
	_check(first_target.health == first_health - expected_damage, "v2 Judgment Mark deals DEF times 0.55 physical damage")
	_check(battle.get_oathkeeper_marked_target() == "vanguard_00", "v2 Judgment Mark records the selected target")
	_check(battle.statuses.has_status("vanguard_00", &"oathkeeper_mark"), "v2 mark uses its isolated status ID")
	_check(not battle.statuses.has_status("vanguard_00", &"judgment_mark"), "v2 mark does not create the legacy judgment status")
	_check(battle.request_oathkeeper_judgment_mark("vanguard_01"), "v2 Judgment Mark can be recast on another enemy")
	_check(not battle.statuses.has_status("vanguard_00", &"oathkeeper_mark"), "recasting removes the previous v2 mark")
	_check(battle.get_oathkeeper_marked_target() == "vanguard_01", "only the latest enemy remains marked")
	_check(battle.end_player_turn(), "marked enemy phase resolves")
	_check(battle.get_oathkeeper_marked_target().is_empty(), "v2 mark expires at the end of the enemy phase after application")
	battle.queue_free()


func _test_v2_judgment_mark_amplifies_and_consumes_on_next_hit() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "mark amplification encounter starts")
	battle.beacons.clear()
	var enemy = battle.get_actor("vanguard_00")
	_check(battle.request_oathkeeper_judgment_mark("vanguard_00"), "Judgment Mark applies the vulnerability mark")
	var health_after_mark: int = enemy.health
	_check(battle.request_skill(&"oathblade", "vanguard_00"), "follow-up Oathblade strikes the marked enemy")
	var follow_up_dmg: int = health_after_mark - enemy.health
	# Base Oathblade vs 450 DEF is 448; with +30% vulnerability mark it is > 448.
	_check(follow_up_dmg > 448, "marked enemy takes amplified damage on the next hit")
	_check(not battle.statuses.has_status("vanguard_00", &"oathkeeper_mark"), "vulnerability mark is consumed when triggered")
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
	battle.beacons.clear()
	battle.intents = IntentPlannerScript.plan(battle)
	battle.actors["ally_near"] = ActorScript.new("ally_near", "player", Vector2i(3, 1), 1000, "support", 500, 200, 200)
	battle.actors["ally_far"] = ActorScript.new("ally_far", "player", Vector2i(4, 1), 1000, "support", 500, 200, 200)

	_check(not battle.request_oath_shield("missing_actor"), "Oath Shield rejects unknown targets")
	_check(not battle.request_oath_shield("vanguard_00"), "Oath Shield rejects enemy targets")
	_check(not battle.request_oath_shield("ally_far"), "Oath Shield rejects allies beyond two Manhattan cells")
	_check(battle.ap.current == battle.ap.maximum, "invalid Oath Shield targets do not spend AP")
	_check(battle.request_oath_shield("ally_near"), "Oath Shield accepts an ally exactly two cells away")
	var initial_shield: int = battle.get_actor("sevrin").shield
	_check(initial_shield == 720, "initial self shield matches 200% DEF formula")
	_check(battle.request_oath_shield("ally_near"), "recasting Oath Shield refreshes duration")
	_check(battle.get_actor("sevrin").shield == initial_shield, "recasting an equal shield does not stack shield values")

	_check(battle.end_player_turn(), "first player turn ends")
	_check(battle.get_actor("sevrin").shield == initial_shield, "shield remains through the first enemy phase and next player turn")
	_check(battle.end_player_turn(), "second player turn ends")
	_check(battle.get_actor("sevrin").shield == 0, "shield expires at the end of the second player turn")
	_check(battle.get_actor("ally_near").shield == 0, "ally shield expires at the same two-turn boundary")
	battle.queue_free()


func _test_absolute_verdict_aoe_knockback_and_energy() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(2, 2), [Vector2i(3, 2), Vector2i(2, 1), Vector2i(6, 6)]), "Absolute Verdict encounter starts")
	battle.beacons.clear()
	var sevrin = battle.get_actor("sevrin")
	var east = battle.get_actor("vanguard_00")
	var north = battle.get_actor("vanguard_01")
	var far = battle.get_actor("vanguard_02")

	_check(sevrin.ultimate_energy == 1, "each player turn start grants one ultimate energy")
	sevrin.ultimate_energy = 3
	_check(not battle.request_absolute_guard(), "Absolute Verdict rejects activation below four energy")
	_check(sevrin.ultimate_energy == 3 and battle.ap.current == battle.ap.maximum, "failed activation preserves energy and AP")

	sevrin.ultimate_energy = 4
	var east_before: int = east.health
	var north_before: int = north.health
	var far_before: int = far.health
	_check(battle.request_absolute_guard(), "Absolute Verdict activates at four energy")
	_check(sevrin.ultimate_energy == 0 and battle.ap.current == battle.ap.maximum - 2, "Absolute Verdict spends four energy and two AP")
	# 360 DEF raw vs 450 DEF -> 248 physical damage. The opening strike no longer knocks back.
	_check(east_before - east.health == 248, "adjacent enemy receives 100% DEF mitigated physical damage")
	_check(east.cell == Vector2i(3, 2), "opening ultimate strike does not knock back the first enemy")
	_check(north_before - north.health == 248, "second adjacent enemy also takes full AoE damage")
	_check(north.cell == Vector2i(2, 1), "opening ultimate strike does not knock back the second enemy")
	_check(far.health == far_before and far.cell == Vector2i(6, 6), "distant enemy outside 1-tile radius is untouched")
	var guard_status = battle.statuses.get_status(sevrin.actor_id, &"absolute_guard")
	_check(guard_status != null and guard_status.enemy_turns_remaining == 2, "Absolute Guard starts with two enemy-phase ticks")
	battle.statuses.tick_enemy_phase()
	_check(battle.statuses.has_status(sevrin.actor_id, &"absolute_guard"), "Absolute Guard remains active after the first enemy phase")
	battle.statuses.tick_enemy_phase()
	_check(not battle.statuses.has_status(sevrin.actor_id, &"absolute_guard"), "Absolute Guard expires after the second enemy phase")
	battle.queue_free()


func _test_one_action_grants_vow_per_carrier() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var archetypes: Array[String] = ["area_controller"]
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)], [], archetypes), "vow-per-carrier encounter starts")
	battle.beacons.clear()
	battle.intents = IntentPlannerScript.plan(battle)
	var fellow = ActorScript.new("fellow", "player", Vector2i(1, 2), 3200, "support", 650, 360, 230)
	fellow.character_id = &"sevrin"
	battle.actors["fellow"] = fellow

	_check(battle.has_passive("fellow", &"oath_vow"), "the fellow carries the vow passive through its sheet")

	battle.end_player_turn()
	_check(battle.get_oath_vow_stacks("sevrin") == 1, "the pulse grants Sevrin his single stack")
	_check(battle.get_oath_vow_stacks("fellow") == 1, "the same pulse grants the fellow carrier its own stack")
	battle.queue_free()


## The knockback is the headline mechanic of the 2.5D rework and had no coverage:
## deleting the wall branch left every suite green. Three outcomes are separable
## by damage, which is what makes them worth asserting separately.
##
## Oathblade is 100% ATK: floor(650 * 1000 / 1450) = 448 against the vanguard's
## 450 defence. A collision adds 450 true damage, which ignores that defence - so
## a colliding push deals 898 and a clean one deals 448.
func _test_oathblade_knockback_collisions() -> void:
	# Wall: the target has nowhere to go, so it takes the collision and stays put.
	var wall = ControllerScript.new()
	root.add_child(wall)
	_check(wall.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [Vector2i(3, 1)]), "walled encounter starts")
	wall.beacons.clear()
	var wall_enemy = wall.get_actor("vanguard_00")
	var wall_before: int = wall_enemy.health
	_check(wall.request_skill(&"oathblade", "vanguard_00"), "the Oathblade resolves into a wall")
	_check(wall_before - wall_enemy.health == 898, "a wall slam adds 450 true damage on top of the strike")
	_check(wall_enemy.cell == Vector2i(2, 1), "a target with a wall behind it is not pushed")
	wall.queue_free()

	# Relic beacon: the target slams into it and the beacon takes the same 450.
	var beacon = ControllerScript.new()
	root.add_child(beacon)
	_check(beacon.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "beacon encounter starts")
	var beacon_enemy = beacon.get_actor("vanguard_00")
	var beacon_cell := Vector2i(3, 1)
	_check(beacon.beacons.has(beacon_cell), "a relic beacon sits behind the target")
	var beacon_health_before: int = int(beacon.beacons[beacon_cell]["health"])
	var beacon_before: int = beacon_enemy.health
	_check(beacon.request_skill(&"oathblade", "vanguard_00"), "the Oathblade resolves into a beacon")
	_check(beacon_before - beacon_enemy.health == 898, "slamming into a beacon deals the same collision damage")
	_check(int(beacon.beacons[beacon_cell]["health"]) == beacon_health_before - 1, "the chest loses one hit of its 2-hit durability")
	beacon.queue_free()

	# Free cell: the target moves one cell and takes only the strike. This is the
	# control - without it the collision assertions could pass for a push that
	# always adds damage.
	var open = ControllerScript.new()
	root.add_child(open)
	_check(open.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "open encounter starts")
	open.beacons.clear()
	var open_enemy = open.get_actor("vanguard_00")
	var open_before: int = open_enemy.health
	_check(open.request_skill(&"oathblade", "vanguard_00"), "the Oathblade resolves into open ground")
	_check(open_before - open_enemy.health == 448, "a clean push deals only the strike")
	_check(open_enemy.cell == Vector2i(3, 1), "a clean push moves the target one cell")
	open.queue_free()


func _test_guard_taunt_redirects_single_target_ranged_intents() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(6, 1)]), "ranged taunt encounter starts")
	battle.beacons.clear()
	var guardian = battle.get_actor("sevrin")
	var light_shot = IntentScript.new("taunt_light_shot", "vanguard_00", "light_shot", IntentScript.TargetMode.TILE_LOCKED, "", Vector2i(1, 1), [Vector2i(1, 1)], 100)
	IntentResolverScript.redirect_to_guardian(battle, light_shot, guardian.actor_id)
	_check(light_shot.target_actor_id == guardian.actor_id and light_shot.target_cell == guardian.cell, "tile-locked ranged attack is redirected to the guardian")
	var locked_shot = IntentScript.new("taunt_locked_shot", "vanguard_00", "locked_shot", IntentScript.TargetMode.ACTOR_LOCKED, "vanguard_00", Vector2i(1, 1), [Vector2i(1, 1)], 100)
	IntentResolverScript.redirect_to_guardian(battle, locked_shot, guardian.actor_id)
	_check(locked_shot.target_actor_id == guardian.actor_id, "actor-locked elite shot is redirected away from its previous mark")
	var sweep = IntentScript.new("taunt_area", "vanguard_00", "charged_strike", IntentScript.TargetMode.AREA_LOCKED, "", Vector2i(1, 1), [Vector2i(1, 1)], 100)
	IntentResolverScript.redirect_to_guardian(battle, sweep, guardian.actor_id)
	_check(sweep.affected_cells == [Vector2i(1, 1)] and sweep.target_actor_id.is_empty(), "area attacks retain their telegraphed geometry")
	battle.queue_free()


func _test_guard_counters_each_independent_enemy_intent() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(3, 1)]), "counter cadence encounter starts")
	battle.beacons.clear()
	var guardian = battle.get_actor("sevrin")
	var attacker = battle.get_actor("vanguard_00")
	_check(battle.statuses.apply_status(&"absolute_guard", guardian.actor_id, guardian.actor_id, 1, 1, -1, &"", &"replace"), "Absolute Guard status is active")
	var before: int = attacker.health
	var first = IntentScript.new("counter_intent_one", attacker.actor_id, "light_shot", IntentScript.TargetMode.ACTOR_LOCKED, guardian.actor_id, guardian.cell, [guardian.cell], 100)
	IntentResolverScript.absolute_guard_counter(battle, first)
	var after_first: int = attacker.health
	var second = IntentScript.new("counter_intent_two", attacker.actor_id, "light_shot", IntentScript.TargetMode.ACTOR_LOCKED, guardian.actor_id, guardian.cell, [guardian.cell], 100)
	IntentResolverScript.absolute_guard_counter(battle, second)
	_check(after_first < before and attacker.health < after_first, "two independent actions from one enemy each trigger a counter")
	_check(attacker.cell.x >= 5, "each counter applies the existing knockback displacement")
	battle.queue_free()


## The collision branch the trio above does not reach: a unit in the way pays
## the same 450, and the chest-break path drops the loot on the tile.
func _test_oathblade_knockback_unit_collision_and_chest_break() -> void:
	var pair = ControllerScript.new()
	root.add_child(pair)
	_check(pair.start_encounter(Vector2i(1, 1), [Vector2i(2, 1), Vector2i(3, 1)]), "unit-collision encounter starts")
	pair.beacons.clear()
	var pushed = pair.get_actor("vanguard_00")
	var blocker = pair.get_actor("vanguard_01")
	var pushed_before: int = pushed.health
	var blocker_before: int = blocker.health
	_check(pair.request_skill(&"oathblade", "vanguard_00"), "the Oathblade resolves into a blocking unit")
	_check(pushed.health == pushed_before - 898, "a unit slam adds the collision to the strike on the pushed target")
	_check(blocker.health == blocker_before - 450, "the unit in the way takes the same true damage")
	_check(pushed.cell == Vector2i(2, 1), "a blocked push leaves the target in place")
	pair.queue_free()

	var chest = ControllerScript.new()
	root.add_child(chest)
	_check(chest.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "chest encounter starts")
	var chest_cell := Vector2i(3, 1)
	_check(chest.beacons.has(chest_cell), "a beacon sits behind the target")
	chest.beacons[chest_cell]["health"] = 1
	var chest_enemy = chest.get_actor("vanguard_00")
	_check(chest.request_skill(&"oathblade", "vanguard_00"), "the Oathblade slams into the cracked chest")
	_check(int(chest.beacons[chest_cell]["health"]) == 0, "the chest breaks")
	_check(chest.dropped_loot.has(chest_cell) and not chest.dropped_loot[chest_cell].is_empty(), "the chest's loot drops on its tile for pickup")
	_check(chest_enemy.cell == Vector2i(2, 1), "a chest slam leaves the target in place")
	chest.queue_free()


## Core displacement promise: displacing an enemy moves its active telegraph
## by the same vector, so the sweep lands relative to where the enemy now stands.
func _test_knockback_shifts_active_telegraphs() -> void:
	var sweep = ControllerScript.new()
	root.add_child(sweep)
	_check(sweep.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "sweep encounter starts")
	sweep.beacons.clear()
	var sweep_enemy = sweep.get_actor("vanguard_00")
	var sweep_intent = sweep.intents[0]
	var planned_target: Vector2i = sweep_intent.target_cell
	var planned_affected: Array = sweep_intent.affected_cells.duplicate()
	_check(sweep_intent.action_id == "charged_strike", "the opening sweep is telegraphed at full starting charge")
	_check(sweep.request_skill(&"oathblade", "vanguard_00"), "the Oathblade pushes the sweep's owner")
	_check(sweep_enemy.cell == Vector2i(3, 1), "the sweep's owner is pushed clear")
	_check(sweep_intent.target_cell == planned_target + Vector2i(1, 0), "the telegraph target moves with its owner")
	_check(sweep_intent.affected_cells.size() == planned_affected.size(), "the sweep keeps its shape when it moves")
	for i in range(planned_affected.size()):
		_check(sweep_intent.affected_cells.find(planned_affected[i] + Vector2i(1, 0)) != -1, "sweep cell %d shifts by the same vector" % i)
	sweep.queue_free()


## The taunt's promise: a melee aimed at the tile the player abandoned is pulled
## onto the guardian anywhere inside the two-cell radius. Before this pin, the
## redirect legalised the pull but the tile re-check cancelled it as
## melee_out_of_range, so the taunt silently did nothing for a dodged melee.
func _test_guard_taunt_pulls_a_dodged_melee_within_two_cells() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)])
	battle.beacons.clear()
	# Empty the charge so the opening plan is a plain melee against (1,1).
	battle.get_actor("vanguard_00").skill_charge = 0
	battle.intents = IntentPlannerScript.plan(battle)
	var melee = battle.intents[0]
	_check(melee.action_id == "basic_melee", "a charge-less opening plan is a melee on the hero's tile")
	_check(melee.target_cell == Vector2i(1, 1), "the melee is telegraphed on the hero's cell")

	_check(battle.request_player_move([Vector2i(1, 2)]), "the hero steps out of the marked tile")
	var sevrin = battle.get_actor("sevrin")
	_check(sevrin.cell == Vector2i(1, 2), "the hero stands two cells from the waiting melee")
	_check(battle.statuses.apply_status(&"absolute_guard", "sevrin", "sevrin", 1, 1, -1, &"player_phase_start", &"replace"), "the guard stance goes up")

	var health_before: int = sevrin.health
	battle.end_player_turn()
	_check(sevrin.health < health_before, "the redirected melee lands on the guardian from two cells")
	_check(melee.state == IntentScript.IntentState.RESOLVED, "the pulled melee resolves instead of cancelling")
	battle.queue_free()
