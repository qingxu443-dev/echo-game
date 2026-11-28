extends "res://tests/framework/test_case.gd"

var run_path := "user://settlement_json_run_%d.json" % OS.get_process_id()
var stash_path := "user://settlement_json_stash_%d.json" % OS.get_process_id()

class SettlementProbe extends "res://scripts/spring/spring_battle_settlement_view.gd":
	var destination := ""
	func _change_scene(path: String) -> Error:
		destination = path
		return OK


func _run() -> void:
	_test_json_roundtrip_and_award()
	_test_numeric_rejection_boundaries()
	_test_interrupted_journal_recovery()
	await _test_actual_confirmation_button()
	for path in [run_path, stash_path, SpringSaveTransaction.journal_path(stash_path)]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)


func _prepared_run() -> SpringRun:
	var run := SpringRun.begin(3)
	run.party_character_ids.assign(["sakura", "sevrin", "dest_lee"])
	var state := RunState.new()
	state.reset(1800, 520, 180, 111)
	var battle := BattleController.new()
	battle.single_active_party = true
	battle.run_state = state
	root.add_child(battle)
	battle.start_encounter(Vector2i(3, 5), [Vector2i(3, 1)], [], [], run.party_character_ids, [Vector2i(2, 5), Vector2i(4, 5)])
	state.add_to_backpack(LootCatalog.get_item(&"armor_echo_mantle"))
	state.equip_from_backpack(0, battle.actors.sakura)
	battle.actors.sakura.health = 1500
	PartyLoadout.capture(battle)
	var vitals := {}
	for actor in battle.actors.values():
		if actor.team == "player": vitals[actor.actor_id] = {"health": actor.health, "max_health": actor.max_health, "base_max_health": PartyLoadout.unscaled_max_health(actor)}
	var result := {"result": "victory", "kind": "battle", "place": "battle_1", "hero_health": 1500, "hero_max_health": 1800, "party_vitals": vitals, "carry": SpringBattleBridge.pack_carry(state), "chests_saved": 2, "loot": [], "seed": 3}
	var outcome := SpringBattleBridge.settle_result(run, result)
	run.pending_battle_settlement = {"id": "json-roundtrip-once", "phase": "prepared", "result": result, "outcome": outcome}
	battle.free()
	return run


func _test_json_roundtrip_and_award() -> void:
	var run := _prepared_run()
	_check(run.save_to_file(run_path), "write a prepared three-role settlement through the actual JSON writer")
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(run_path))
	_check(parsed.battle_carry.party_loadouts.sakura.base_max_health is float, "ordinary JSON actually returns integral gameplay numbers as float")
	var before := JSON.stringify(parsed)
	_check(SpringSaveValidation.invalid_field(parsed).is_empty(), "valid JSON gameplay integers pass disk preflight")
	_check(JSON.stringify(parsed) == before, "validation never mutates the source image")
	var restored := SpringRun.load_from_file(run_path)
	_check(restored != null, "prepared settlement with character loadouts reloads from disk")
	if restored == null: return
	_check(restored.battle_carry.party_loadouts.sakura.base_max_health is int, "loaded role fields are canonical typed integers")
	_check(restored.battle_carry.party_loadouts.sakura.equipped_armor.defense is int, "equipped item stats are normalized at the same JSON boundary")
	_check(restored.pending_battle_settlement.result.carry.party_loadouts.sakura.hero_health is int, "pending battle payload is normalized too")
	_check(restored.hero_health == 1500 and restored.pending_battle_settlement.phase == "prepared", "repair preserves wounded health and already prepared rewards")
	_check(AtelierStash.save_state({"shards": 100, "loadout": ["item_dusk_potion"]}, stash_path), "seed an isolated real wallet path without the headless reward bypass")
	var shards: int = restored.pending_battle_settlement.outcome.atelier_shards
	var coins: int = restored.coins
	_check(SpringRunStorage.settle(restored, run_path, stash_path, shards, "json-roundtrip-once"), "three-role settlement completes the actual two-file transaction")
	_check(AtelierStash.read_state(stash_path).shards == 100 + shards, "wallet receives the battle reward exactly once")
	_check(not SpringSaveTransaction.is_pending(stash_path), "successful recovery removes the journal")
	restored = SpringRun.load_from_file(run_path)
	_check(restored != null and restored.settled_battle_ids.has("json-roundtrip-once"), "settlement receipt survives another plain JSON reload")
	if restored == null: return
	_check(SpringRunStorage.settle(restored, run_path, stash_path, shards, "json-roundtrip-once"), "retry after restart is accepted")
	_check(AtelierStash.read_state(stash_path).shards == 100 + shards and restored.coins == coins, "restart retry cannot duplicate shards, coins or loot")
	_check(AtelierStash.read_state(stash_path).loadout == ["item_dusk_potion"], "wallet loadout remains intact")
	restored.pending_battle_settlement = {}
	_check(restored.save_to_file(run_path) and SpringRun.load_from_file(run_path).pending_battle_settlement.is_empty(), "confirmation can durably clear the pending record")


func _test_numeric_rejection_boundaries() -> void:
	var base := _prepared_run().to_dict()
	for value in [1800.5, "1800", true, NAN, INF, 9.223372036854775e18, -1]:
		var bad := base.duplicate(true)
		bad.battle_carry.party_loadouts.sakura.base_max_health = value
		_check(not SpringSaveValidation.invalid_field(bad).is_empty(), "JSON boundary still rejects invalid numeric stat: " + str(value))
	var carry: Dictionary = base.battle_carry.duplicate(true)
	carry.party_loadouts.sakura.base_max_health = 1800.0
	_check(not PartyLoadout.carry_error(carry).is_empty(), "typed session snapshots retain strict int validation")
	for value in [1.5, "90", true, INF]:
		var bad := base.duplicate(true)
		bad.battle_carry.party_loadouts.sakura.equipped_armor.defense = value
		_check(not SpringSaveValidation.invalid_field(bad).is_empty(), "equipped JSON item retains numeric rejection: " + str(value))
	var nested := base.duplicate(true)
	nested.pending_battle_settlement.result.carry.party_loadouts.sakura.hero_health = 1.5
	_check(not SpringSaveValidation.invalid_field(nested).is_empty(), "malformed pending role payload is rejected before recovery")


func _test_interrupted_journal_recovery() -> void:
	var run := _prepared_run()
	var journal := SpringSaveTransaction.journal_path(stash_path)
	var image := run.to_dict()
	image.settled_battle_ids = ["json-roundtrip-once"]
	_check(SaveFile.write_json(journal, {"version": 1, "run_path": run_path, "run": image, "atelier": {"shards": 135, "loadout": []}}), "persist an interrupted journal with real plain JSON loadout data")
	_check(SpringSaveTransaction.recover(run_path, stash_path), "journal accepts integral JSON numbers and replays both valid images")
	var restored := SpringRun.load_from_file(run_path)
	_check(restored != null and restored.settled_battle_ids.has("json-roundtrip-once"), "recovered run preserves receipt and pending outcome")
	_check(AtelierStash.read_state(stash_path).shards == 135, "recovery restores the intended wallet amount")
	_check(SpringSaveTransaction.recover(run_path, stash_path) and AtelierStash.read_state(stash_path).shards == 135, "recovery itself remains idempotent")


func _test_actual_confirmation_button() -> void:
	var run := _prepared_run()
	_check(run.save_to_file(run_path) and AtelierStash.save_state({"shards": 100, "loadout": []}, stash_path), "seed the same prepared JSON inputs as the blocked screenshot")
	var view := SettlementProbe.new()
	view.run_path = run_path
	view.atelier_path = stash_path
	root.add_child(view)
	_check(view.prepared and view.status_message.is_empty(), "actual settlement screen restores the prepared record without rerolling")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.RETURN_BUTTON.get_center()
	view._gui_input(click)
	_check(view.destination == view.MAP_SCENE_PATH and view.status_message.is_empty(), "actual confirmation click can finish saving and return to the map")
	_check(AtelierStash.read_state(stash_path).shards == 135, "actual button grants the expected 35 shards once")
	_check(SpringRun.load_from_file(run_path).pending_battle_settlement.is_empty(), "actual button clears the durable pending marker")
	view._gui_input(click)
	_check(AtelierStash.read_state(stash_path).shards == 135, "a duplicate queued button event cannot duplicate the reward")
	view.queue_free()
	await process_frame
