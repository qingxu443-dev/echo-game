extends "res://tests/framework/test_case.gd"

func _run() -> void:
	_test_multi_hit_chipping()
	_test_heavy_break()
	_test_multiple_targets()
	_test_collision_and_nodes()
	_test_break_window()
	await process_frame

func _battle(character: String = "sakura", wall: bool = false) -> BattleController:
	var battle := BattleController.new()
	root.add_child(battle)
	var obstacles: Array[Vector2i] = []
	if wall:
		obstacles.append(Vector2i(5, 3))
	battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3), Vector2i(7, 0)], obstacles, [], [character])
	battle.beacons.clear()
	var target = battle.get_actor("vanguard_00")
	target.max_health = 100000
	target.health = 100000
	target.defense = 0
	target.armor_max = 2
	target.armor_layers = 2
	target.melee_tolerance_max = 0
	return battle

func _test_multi_hit_chipping() -> void:
	var battle := _battle()
	var target = battle.get_actor("vanguard_00")
	_check(battle.request_skill(&"sakura_falling_petals", target.actor_id), "three-segment ordinary cast succeeds")
	_check(target.armor_layers == 2 and target.armor_chip_hits == 1, "three segments chip only once per cast")
	battle.ap.reset()
	_check(battle.request_skill(&"sakura_falling_petals", target.actor_id), "second ordinary cast succeeds")
	_check(target.armor_layers == 1 and target.armor_chip_hits == 0, "two casts remove exactly one layer including echo follow-up")
	var snapshot := SessionCodec.fields(target)
	_check(snapshot.has("last_armor_chip_seq"), "pause actor snapshot preserves armor deduplication")
	var restored := BattleActor.new("copy", "enemy", Vector2i.ONE, 100000)
	SessionCodec.apply_fields(restored, SessionCodec.decode(SessionCodec.encode(snapshot)))
	_check(restored.last_armor_chip_seq == target.last_armor_chip_seq and restored.armor_chip_hits == target.armor_chip_hits, "JSON roundtrip preserves partial chipping and deduplication")
	battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3)], [], [], ["sakura"])
	_check(battle.get_actor("vanguard_00").get("last_armor_chip_seq") == -1, "new encounter resets armor deduplication")
	battle.queue_free()

func _test_heavy_break() -> void:
	var battle := _battle()
	var hero = battle.get_active_character()
	var target = battle.get_actor("vanguard_00")
	hero.ultimate_energy = hero.ultimate_energy_max
	_check(battle.request_skill(&"sakura_endless_fragrance"), "four-segment heavy cast succeeds")
	_check(target.armor_layers == 1, "four segments including finisher break only one layer")
	var restored := BattleActor.new("copy", "enemy", Vector2i.ONE, 100000)
	var snapshot := SessionCodec.fields(target)
	SessionCodec.apply_fields(restored, SessionCodec.decode(SessionCodec.encode(snapshot)))
	_check(restored.last_armor_break_seq == target.last_armor_break_seq, "JSON roundtrip preserves heavy segment deduplication")
	snapshot.erase("last_armor_break_seq")
	snapshot.erase("last_armor_chip_seq")
	var legacy := BattleActor.new("legacy", "enemy", Vector2i.ONE, 100000)
	SessionCodec.apply_fields(legacy, snapshot)
	_check(legacy.last_armor_break_seq == -1 and legacy.last_armor_chip_seq == -1, "old actor snapshots default missing deduplication fields")
	_check(target.armor_chip_hits == 0, "heavy skill does not also count as an ordinary chip")
	battle.ap.reset()
	hero.ultimate_energy = hero.ultimate_energy_max
	_check(battle.request_skill(&"sakura_endless_fragrance"), "next heavy cast succeeds")
	_check(target.armor_layers == 0 and target.armor_broken_until_turn == battle.turn_number + 1, "next cast breaks the final layer and opens vulnerability")
	battle.queue_free()

func _test_multiple_targets() -> void:
	var battle := _battle()
	var first = battle.get_actor("vanguard_00")
	var second = battle.get_actor("vanguard_01")
	second.cell = Vector2i(4, 4)
	second.max_health = 100000
	second.health = 100000
	second.armor_max = 2
	second.armor_layers = 2
	_check(battle.request_skill(&"sakura_falling_petals", first.actor_id), "area cast hits two armored enemies")
	_check(first.armor_chip_hits == 1 and second.armor_chip_hits == 1, "each target receives its own one-per-cast chip")
	battle.ap.reset()
	_check(battle.request_skill(&"sakura_falling_petals", first.actor_id), "next area cast hits both enemies")
	_check(first.armor_layers == 1 and second.armor_layers == 1, "area deduplication never suppresses another target or next cast")
	battle.queue_free()

func _test_collision_and_nodes() -> void:
	var battle := _battle("sevrin", true)
	var target = battle.get_actor("vanguard_00")
	_check(battle.request_skill(&"oathblade", target.actor_id), "normal attack slams target into wall")
	_check(target.armor_layers == 1, "collision breaks a layer even after the attack chips armor")
	_check(target.cell == Vector2i(4, 3), "wall collision leaves the target on its legal tile")
	battle.ap.reset()
	var armor_before: int = target.armor_layers
	var chips_before: int = target.armor_chip_hits
	_check(battle.request_skill(&"oathkeeper_judgment_mark", target.actor_id), "mark can hit an armored enemy")
	_check(target.armor_layers == armor_before and target.armor_chip_hits == chips_before, "mark bypass does not advance armor chipping")
	target.defense = 80
	var cell := Vector2i(2, 2)
	battle.beacons[cell] = {"id": "test_ward", "kind": "ward_node", "health": 1, "max_health": 1, "owner_id": target.actor_id, "ward_defense": 80, "cell": cell}
	_check(battle.damage_beacon_at(cell, 1, "sevrin", "oathblade"), "ward can be destroyed through the normal beacon API")
	_check(target.armor_layers == 0, "destroying a ward removes its owner's remaining layer")
	_check(target.defense == 0, "ward defense and armor are removed by the same destruction")
	var until_turn: int = target.armor_broken_until_turn
	battle.damage_beacon_at(cell, 1, "sevrin", "oathblade")
	_check(target.armor_broken_until_turn == until_turn, "repeated dead-node damage cannot extend break")
	battle.queue_free()

func _test_break_window() -> void:
	var battle := _battle()
	var target = battle.get_actor("vanguard_00")
	_check(TacticalPressure.adjust_incoming_damage(battle, target, 100, "oathblade") == 65, "intact armor reduces damage to 65 percent")
	TacticalPressure.shatter_armor(battle, target, 2)
	_check(TacticalPressure.adjust_incoming_damage(battle, target, 100, "oathblade") == 125, "break applies 125 percent damage before mitigation")
	_check(TacticalPressure.adjust_incoming_damage(battle, target, 100, "oathkeeper_judgment_mark") == 100, "existing mark bypass stays unchanged")
	for turn in range(2):
		_check(battle.start_enemy_phase_stepped(), "turn boundary starts through the normal request")
		battle.intents.clear()
		battle.finish_enemy_phase_stepped()
		_check(battle.phase == battle.BattlePhase.PLAYER, "turn boundary returns to player")
		var expected := 125 if turn == 0 else 100
		_check(TacticalPressure.adjust_incoming_damage(battle, target, 100, "oathblade") == expected, "break lasts through the next player turn, then expires")
	battle.queue_free()
