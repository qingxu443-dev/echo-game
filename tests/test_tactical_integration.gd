extends "res://tests/framework/test_case.gd"

func _run() -> void:
	_test_single_and_replayed_death()
	_test_group_kills_and_turn_cap()
	_test_last_enemy()
	_test_boss_threshold(false)
	_test_boss_threshold(true)
	_test_boss_combo()
	_test_scaled_reinforcements()
	_test_reactive_melee()
	_test_items_with_both_characters()
	await process_frame

func _battle(cells: Array[Vector2i], archetypes: Array[String] = [], character: String = "sakura", multiplier: float = 1.0) -> BattleController:
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(3, 3), cells, [], archetypes, [character], [], [], 0, [], false, multiplier)
	battle.beacons.clear()
	var hero = battle.get_active_character()
	hero.max_health = 100000
	hero.health = 100000
	return battle

func _weak(battle) -> void:
	for actor in battle.actors.values():
		if actor.team == "enemy":
			actor.health = 1
			actor.armor_layers = 0

func _events(battle) -> Array:
	var events: Array = []
	battle.battle_event.connect(func(event): events.append(event.duplicate(true)))
	return events

func _count(events: Array, type: String) -> int:
	var count := 0
	for event in events:
		if event.type == type: count += 1
	return count

func _test_single_and_replayed_death() -> void:
	var battle := _battle([Vector2i(4, 3), Vector2i(7, 7)])
	_weak(battle)
	var events := _events(battle)
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "single kill resolves through skill request")
	_check(battle.ap.current == 3 and battle.ledger.pressure_refund_count == 1, "single kill returns exactly the spent AP")
	var hero = battle.get_active_character()
	_check(hero.resource_current == 3 and hero.ultimate_energy == 2, "action then kill credit and active energy have stable values")
	_check(_count(events, "actor_defeated") == 1 and _count(events, "ap_refunded") == 1, "one death emits one defeat and refund")
	battle.ap.spend(1)
	battle._apply_damage("vanguard_00", 100, "sakura", "stale_segment")
	_check(battle.ap.current == 2 and battle.ledger.pressure_refund_count == 1, "replayed dead-target damage cannot refund again")
	_check(battle.enemies_defeated == 1 and _count(events, "actor_defeated") == 1, "replayed damage cannot repeat defeat bookkeeping")
	var refund_index := -1
	var kill_index := -1
	for i in range(events.size()):
		if events[i].type == "ap_refunded": refund_index = i
		if events[i].type == "resource_gained" and str(events[i].detail).contains("reason=kill"): kill_index = i
	_check(refund_index >= 0 and kill_index > refund_index, "refund is settled before skill kill-resource credit")
	battle.queue_free()

func _test_items_with_both_characters() -> void:
	for character in ["sakura", "sevrin"]:
		var battle := _battle([Vector2i(4, 3), Vector2i(7, 7)], [], character)
		var hero = battle.get_active_character()
		battle.run_state = RunState.new()
		battle.run_state.reset(hero.max_health, hero.attack, hero.defense, hero.magic_resistance)
		hero.health = 500
		battle.run_state.hero_health = 500
		var skill: StringName = &"sakura_pierce_blossom" if character == "sakura" else &"oath_shield"
		_check(battle.request_skill(skill, "vanguard_00" if character == "sakura" else ""), "character acts before using supplies: " + character)
		battle.run_state.add_to_backpack({"kind": "consumable", "name": "fixture", "heal": 500, "ap_gain": 1, "energy_gain": 1, "resource_gain": 1})
		_check(not battle.run_state.use_backpack_item(0, battle, hero).is_empty(), "supplies use normal inventory entry: " + character)
		_check(hero.health == 1000 and battle.run_state.hero_health == 1000 and battle.run_state.backpack.is_empty(), "item vitals and inventory settle once: " + character)
		_check(battle.ap.current == 3 and hero.ultimate_energy >= 3, "supplies combine with skill AP and energy: " + character)
		battle.start_enemy_phase_stepped()
		battle.intents.clear()
		battle.finish_enemy_phase_stepped()
		_check(battle.turn_number == 2 and battle.phase == battle.BattlePhase.PLAYER and battle.ap.current == 3, "item and skill state survives normal turn transition: " + character)
		battle.run_state = null
		battle.queue_free()

func _test_group_kills_and_turn_cap() -> void:
	var battle := _battle([Vector2i(4, 3), Vector2i(4, 2), Vector2i(4, 4), Vector2i(3, 4), Vector2i(7, 7)])
	_weak(battle)
	_check(battle.request_skill(&"sakura_falling_petals", "vanguard_00"), "area skill kills three targets")
	_check(battle.enemies_defeated == 3 and battle.ap.current == 3, "group kill refunds at most two AP")
	_check(battle.get_active_character().resource_current == 4, "group kill respects the per-turn intent budget")
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_03"), "fourth target is killed through another action")
	_check(battle.ap.current == 2 and battle.ledger.pressure_refund_count == 2, "later kill cannot exceed the turn refund cap")
	battle.start_enemy_phase_stepped()
	battle.intents.clear()
	battle.finish_enemy_phase_stepped()
	var target = battle.get_actor("vanguard_04")
	target.cell = Vector2i(4, 3)
	battle.actors["reserve"] = EnemyActorFactory.create(EnemyCatalog.get_definition("vanguard"), "reserve", Vector2i(7, 0))
	_check(battle.request_skill(&"sakura_pierce_blossom", target.actor_id), "kill on the next turn succeeds")
	_check(battle.ap.current == 3 and battle.ledger.pressure_refund_count == 1 and battle.ledger.pressure_refund_turn == 2, "new turn grants a fresh refund budget")
	battle.queue_free()

func _test_last_enemy() -> void:
	var battle := _battle([Vector2i(4, 3)])
	_weak(battle)
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "final enemy can be killed")
	_check(battle.battle_result == "victory" and battle.ap.current == 2, "final enemy grants victory without useless AP refund")
	_check(battle.get_active_character().resource_current == 3, "final kill still pays character resource before victory")
	battle.queue_free()

func _test_boss_threshold(no_space: bool) -> void:
	var battle := _battle([Vector2i(4, 3)], ["boss_thousand_boughs"])
	var boss = battle.get_actor("boss_thousand_boughs_00")
	boss.max_health = 100000
	boss.health = 50001
	if no_space:
		var occupied := battle.get_occupied_cells()
		for y in range(8):
			for x in range(8):
				var cell := Vector2i(x, y)
				if not occupied.has(cell): battle.blocked_cells[cell] = true
	var events := _events(battle)
	_check(battle.request_skill(&"sakura_pierce_blossom", boss.actor_id), "hit crosses boss half-health threshold")
	_check(boss.boss_phase == 2 and _count(events, "boss_enraged") == 1, "threshold enters phase two once")
	var escorts: Array = []
	var used := {boss.cell: true, battle.get_active_character().cell: true}
	for actor in battle.actors.values():
		if not str(actor.actor_id).begins_with("escort_"): continue
		escorts.append(actor)
		_check(not used.has(actor.cell) and not battle.blocked_cells.has(actor.cell), "escort spawns without overlap or obstacle")
		used[actor.cell] = true
		var profile := EnemyCatalog.get_definition(actor.archetype)
		_check(actor.attack == profile.attack and actor.basic_attack_multiplier == profile.basic_attack_multiplier and actor.tier == profile.tier, "reinforcements read the same profile fields as encounter enemies")
	_check(escorts.size() == (0 if no_space else 2), "full board safely skips reinforcements")
	battle.ap.reset()
	_check(battle.request_skill(&"sakura_pierce_blossom", boss.actor_id), "next hit after phase transition succeeds")
	_check(_count(events, "boss_enraged") == 1, "later hits cannot retrigger threshold or reinforcements")
	battle.queue_free()

func _test_scaled_reinforcements() -> void:
	for multiplier in [1.0, 1.2]:
		var battle := _battle([Vector2i(4, 3)], ["boss_thousand_boughs"], "sakura", multiplier)
		var boss = battle.get_actor("boss_thousand_boughs_00")
		boss.health = int(boss.max_health / 2) + 1
		_check(battle.request_skill(&"sakura_pierce_blossom", boss.actor_id), "normal skill crosses the scaled boss threshold")
		var count := 0
		for actor in battle.actors.values():
			if not str(actor.actor_id).begins_with("escort_"): continue
			count += 1
			var profile := EnemyCatalog.get_definition(actor.archetype)
			var base_hp := 700 if actor.archetype == "wind_ranger" else 600
			_check(actor.max_health == roundi(base_hp * multiplier) and actor.health == actor.max_health, "escort HP override is scaled once, with full current HP")
			_check(actor.attack == roundi(profile.attack * multiplier), "escort attack inherits the encounter multiplier")
			_check(actor.defense == roundi(profile.defense * multiplier), "escort defense inherits the encounter multiplier")
			_check(actor.magic_resistance == roundi(profile.magic_resistance * multiplier), "escort resistance inherits the encounter multiplier")
			_check(actor.skill_damage == profile.skill_damage and actor.basic_attack_multiplier == profile.basic_attack_multiplier, "fixed skill damage and move multipliers remain authored values")
		_check(count == 2, "scaled phase two still spawns exactly two escorts")
		if multiplier > 1.0:
			_check(battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3)], [], ["boss_thousand_boughs"], ["sakura"]), "same controller can start an unscaled encounter")
			battle.beacons.clear()
			boss = battle.get_actor("boss_thousand_boughs_00")
			boss.health = int(boss.max_health / 2) + 1
			_check(battle.request_skill(&"sakura_pierce_blossom", boss.actor_id), "unscaled restart reaches phase two")
			for actor in battle.actors.values():
				if str(actor.actor_id).begins_with("escort_"):
					_check(actor.attack == EnemyCatalog.get_definition(actor.archetype).attack, "new encounter does not retain the previous scaling")
		battle.queue_free()


func _test_boss_combo() -> void:
	var battle := _battle([Vector2i(4, 3)], ["boss_thousand_boughs"])
	battle.start_enemy_phase_stepped()
	battle.intents.clear()
	battle.finish_enemy_phase_stepped()
	_check(battle.intents.size() == 2, "turn-two boss announces its two-action combo")
	var announced := battle.intents.duplicate()
	var forecast := BoardThreatView.incoming_threats_at(battle, Vector2i(3, 3))
	var before: int = battle.get_active_character().health
	var events := _events(battle)
	_check(battle.end_player_turn(), "combo resolves through normal end-turn request")
	_check(announced[0].state == BattleIntent.IntentState.RESOLVED and announced[1].state == BattleIntent.IntentState.RESOLVED, "both announced boss actions execute")
	_check(before - battle.get_active_character().health == int(forecast.total_dmg), "announced boss damage matches both executed actions")
	battle.queue_free()

func _test_reactive_melee() -> void:
	for tier in [0, 1]:
		for blocked in [false, true]:
			var battle := _battle([Vector2i(5, 3)])
			var source = battle.get_actor("vanguard_00")
			source.tier = tier
			if blocked: battle.blocked_cells[Vector2i(4, 3)] = true
			var intent := BattleIntent.new("react", source.actor_id, "basic_melee", BattleIntent.TargetMode.TILE_LOCKED, "", Vector2i(5, 4), [Vector2i(5, 4)], 100)
			battle.intents = [intent]
			var warned: bool = TacticalPressure.reactive_cells(battle, intent).has(Vector2i(3, 3))
			_check(warned == (tier == 1 and not blocked), "warning matches tier and chase lane")
			_check(BoardThreatView.is_cell_in_danger(battle, Vector2i(3, 3)) == warned, "danger query includes reachable reactive attacks")
			var before: int = battle.get_active_character().health
			battle.end_player_turn()
			_check((before > battle.get_active_character().health) == warned, "warned chase and actual strike agree")
			battle.queue_free()
	var battle := _battle([Vector2i(4, 3)])
	var intent := BattleIntent.new("locked", "vanguard_00", "basic_melee", BattleIntent.TargetMode.ACTOR_LOCKED, "sakura", Vector2i(4, 4), [], 100)
	_check(TacticalPressure.reactive_cells(battle, intent).is_empty(), "actor-locked actions do not advertise tile-lock exceptions")
	intent.target_actor_id = ""
	intent.target_mode = BattleIntent.TargetMode.TILE_LOCKED
	_check(TacticalPressure.reactive_cells(battle, intent).has(Vector2i(3, 3)), "ordinary enemy can pivot to an adjacent player")
	intent.cancel("test")
	_check(TacticalPressure.reactive_cells(battle, intent).is_empty(), "cancelled action loses its warning")
	battle.queue_free()
