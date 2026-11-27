extends "res://tests/framework/test_case.gd"

const Scene = preload("res://scenes/main/main.tscn")

func _run() -> void:
	await _test_tolerance()
	await _test_restore_pressure()

func _view():
	var view = Scene.instantiate()
	root.add_child(view)
	view.set_process(false)
	var battle: BattleController = view.controller
	view.run_state.reset(100000, 520, 180, 111)
	battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3), Vector2i(7, 0)], [], [], ["sakura"])
	battle.beacons.clear()
	var target = battle.get_actor("vanguard_00")
	target.max_health = 100000
	target.health = 100000
	target.melee_tolerance_max = 2
	return view

func _test_tolerance() -> void:
	var view = _view()
	var battle: BattleController = view.controller
	var target = battle.get_actor("vanguard_00")
	var hero = battle.get_active_character()
	var counters := {"count": 0}
	battle.battle_event.connect(func(event):
		if event.type == "counter_resolved" and str(event.detail).contains("tolerance_counter"):
			counters.count += 1)
	_check(battle.request_skill(&"sakura_falling_petals", target.actor_id), "first three-hit cast succeeds")
	_check(target.melee_tolerance == 1 and counters.count == 0, "three segments count as one melee action")
	battle.ap.reset()
	_check(battle.request_skill(&"sakura_falling_petals", target.actor_id), "second multi-hit cast succeeds")
	_check(target.melee_tolerance == 0 and counters.count == 1, "threshold counters once despite later segments and echo")
	target.cell = Vector2i(5, 3)
	battle.ap.reset()
	_check(battle.request_skill(&"sakura_falling_petals", target.actor_id), "ranged area cast succeeds")
	_check(target.melee_tolerance == 0 and counters.count == 1, "ranged segments never add melee tolerance")
	target.cell = Vector2i(4, 3)
	battle.ap.reset()
	_check(battle.request_skill(&"sakura_pierce_blossom", target.actor_id), "new adjacent action succeeds")
	_check(target.melee_tolerance == 1, "next melee action begins a fresh gauge")
	_check(battle.start_enemy_phase_stepped(), "normal turn-end request succeeds")
	_check(target.melee_tolerance == 0 and target.last_melee_hit_seq == -1, "turn end clears tolerance and segment deduplication")
	var seq: int = battle.ledger.pressure_sequence
	var other = _view()
	_check(other.controller.ledger.pressure_sequence == 0, "another controller starts with an independent pressure sequence")
	_check(battle.ledger.pressure_sequence == seq, "starting another battle cannot change this battle's sequence")
	battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3)], [], [], ["sakura"])
	_check(battle.ledger.pressure_sequence == 0 and battle.ledger.pressure_refund_count == 0, "encounter restart resets pressure through the ledger")
	_check(battle.get_actor("vanguard_00").melee_tolerance == 0, "encounter restart clears actor tolerance")
	view.queue_free()
	other.queue_free()
	await process_frame

func _test_restore_pressure() -> void:
	var view = _view()
	view.controller.ledger.pressure_sequence = 12
	view.controller.ledger.pressure_refund_turn = 1
	view.controller.ledger.pressure_refund_count = 2
	var data := BattleSession.capture(view)
	_check(not data.has("pressure_refunds"), "new snapshots have only the ledger as pressure authority")
	var restored = Scene.instantiate()
	root.add_child(restored)
	restored.controller.free()
	_check(BattleSession.restore(restored, data), "new pressure snapshot restores")
	_check(restored.controller.ledger.pressure_sequence == 12 and restored.controller.ledger.pressure_refund_count == 2, "restore preserves action deduplication and refund cap")
	restored.free()
	data.ledger.erase("pressure_sequence")
	data.ledger.erase("pressure_refund_turn")
	data.ledger.erase("pressure_refund_count")
	data.pressure_sequence = 7
	data.pressure_refunds = {"turn": 1, "count": 2}
	var legacy = Scene.instantiate()
	root.add_child(legacy)
	legacy.controller.free()
	_check(BattleSession.restore(legacy, data), "legacy pressure snapshot restores")
	_check(legacy.controller.ledger.pressure_sequence == 7 and legacy.controller.ledger.pressure_refund_count == 2, "legacy counters migrate without granting extra kill refunds")
	legacy.free()
	view.queue_free()
	await process_frame
