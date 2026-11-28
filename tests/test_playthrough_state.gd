extends "res://tests/framework/test_case.gd"

const Scene = preload("res://scenes/main/main.tscn")
const Handoff = preload("res://scripts/spring/spring_battle_settlement_handoff.gd")
var path := "user://playthrough_run_%d.json" % OS.get_process_id()

class HandoffView extends Node2D:
	var status_message: String = ""

func _run() -> void:
	SessionSave.path_override = "user://playthrough_session_%d.json" % OS.get_process_id()
	var shell = root.get_node_or_null("GameShell")
	if shell != null: shell.animations_enabled = false
	await _test_hourglass_suspend()
	await _test_map_vitals_enter_the_next_fight()
	await _test_inventory_after_switching()
	await _test_restored_battle_parent()
	_test_handoff_retries()
	_test_handoff_failures_preserve_state()
	await _test_downed_lead_keeps_downed()
	SessionSave.clear()
	SessionSave.path_override = ""
	SpringBattleBridge.clear_pending()
	SpringBattleBridge.suspended_map = {}
	SpringBattleBridge.restore_map = false
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if shell != null:
		for voice in shell.audio.voices:
			voice.stop()
			voice.stream = null
		await create_timer(0.12, true).timeout


func _test_hourglass_suspend() -> void:
	SpringBattleBridge.clear_pending()
	var view = Scene.instantiate()
	root.add_child(view)
	var battle: BattleController = view.controller
	var hero = battle.get_active_character()
	view.run_state.add_to_backpack(AtelierStash.recipe_by_id("item_echo_hourglass").payload)
	view.run_state.use_backpack_item(0, battle, hero)
	_check(battle.ap.current == 4 and battle.ap.maximum == 3, "a real hourglass grants temporary AP above the base pool")
	_check(PlaySession.save(view), "saving after legitimate temporary AP succeeds")
	var data := SessionSave.read()
	_check(not data.is_empty() and int(data.get("ap", {}).get("current", -1)) == 4, "JSON checkpoint preserves the extra AP")
	for _index in range(3):
		view.run_state.add_to_backpack(AtelierStash.recipe_by_id("item_echo_hourglass").payload)
		view.run_state.use_backpack_item(0, battle, hero)
	_check(battle.ap.current == 5, "repeated hourglasses respect the existing two-point overflow cap")
	_check(PlaySession.save(view) and SessionSave.stage() == SessionSave.BATTLE_PATH, "overflow-cap checkpoint can be staged for resume")
	view.queue_free()
	await process_frame
	var resumed = Scene.instantiate()
	root.add_child(resumed)
	_check(resumed.controller.ap.current == 5 and resumed.controller.ap.maximum == 3, "actual restored scene retains the temporary AP pool")
	var invalid := BattleSession.capture(resumed)
	invalid.ap.current = 6
	_check(not SessionSave.valid(invalid), "values beyond the supported temporary limit still fail validation")
	resumed.controller.end_player_turn()
	_check(resumed.controller.ap.current == 3, "temporary AP is not carried into the next turn")
	resumed.queue_free()
	await process_frame


func _party_run() -> SpringRun:
	var run := SpringRun.begin(3)
	run.party_character_ids.assign(["sakura", "sevrin"])
	run.hero_health = 1050
	run.party_vitals = {"sakura": {"health": 1050, "max_health": 2100}, "sevrin": {"health": 1600, "max_health": 3200}}
	return run


func _test_map_vitals_enter_the_next_fight() -> void:
	for effect in ["heal", "damage", "bonus", "relic", "bonus_loss", "consumable"]:
		var run := _party_run()
		match effect:
			"heal": run.heal_hero(300)
			"damage": run.damage_hero(200)
			"bonus": run.add_bonus_max_health(200)
			"relic": run.add_relic(&"relic_spring_charm")
			"bonus_loss":
				run.add_bonus_max_health(200)
				run.add_bonus_max_health(-200)
			"consumable":
				run.grant_collectible(&"col_medicinal_pouch")
				_check(run.use_collectible(&"col_medicinal_pouch").ok, "actual map healing collectible succeeds")
		var expected_health := run.hero_health
		var expected_max := run.effective_max_health()
		run = SpringRun.from_dict(run.to_dict())
		_check(SpringBattleBridge.prepare(run, &"B001", &"battle_1"), "prepare next encounter after map effect: " + effect)
		var view = Scene.instantiate()
		root.add_child(view)
		_check(view.controller.actors.sakura.health == expected_health, "map effect health survives actual battle entry: " + effect)
		_check(view.controller.actors.sakura.max_health == expected_max, "map effect max health survives actual battle entry: " + effect)
		_check(view.controller.actors.sevrin.health == 1600 and view.controller.actors.sevrin.max_health == 3200, "map effect does not change another member")
		view.queue_free()
		SpringBattleBridge.clear_pending()
		await process_frame


func _test_inventory_after_switching() -> void:
	var run := _party_run()
	SpringBattleBridge.prepare(run, &"B001", &"battle_1")
	var view = Scene.instantiate()
	root.add_child(view)
	for character_id in view.controller.deploy_order:
		_check(view.controller.request_deploy(view.controller.actors[character_id].cell), "place each party member through the normal deployment API")
	_check(view.controller.request_begin_battle(), "confirm deployment before testing party inventory")
	_check(view.controller.set_active_character("sevrin"), "switch command through the controller")
	var member = view.controller.actors.sevrin
	var before := [member.max_health, member.health, member.attack, member.defense, member.magic_resistance]
	view.run_state.add_to_backpack({"id": &"audit_armor", "kind": "armor", "name": "审计护甲", "max_health": 400})
	view._handle_inventory_tap(InventoryView.bag_card_rect(0).get_center())
	_check(member.max_health == before[0] + 400 and member.health == before[1] + 400, "equipping updates only the deployed character's own loadout")
	_check(view.controller.actors.sakura.max_health == 2100 and view.controller.actors.sakura.health == 1050, "reserve vitality is unchanged by active equipment")
	view._handle_inventory_tap(InventoryView.ARMOR_SLOT_RECT.get_center())
	_check([member.max_health, member.health, member.attack, member.defense, member.magic_resistance] == before, "unequipping symmetrically returns the active character's bonus")
	_check(view.controller.actors.sakura.health == 1050, "unequipping cannot heal the reserve")
	view.run_state.add_to_backpack(AtelierStash.recipe_by_id("item_dusk_potion").payload)
	view._handle_inventory_tap(InventoryView.bag_card_rect(1).get_center())
	_check(member.health == 2800 and view.controller.actors.sakura.health == 1050, "consumables target the deployed character")
	_check(view.run_state.hero_health == 2800, "the working loadout tracks the deployed character's persistent health")
	view.queue_free()
	SpringBattleBridge.clear_pending()
	await process_frame


func _test_restored_battle_parent() -> void:
	var original := _party_run()
	original.coins = 41
	SpringBattleBridge.prepare(original, &"B001", &"battle_1")
	var expected := SpringBattleBridge.suspended_map.duplicate(true)
	var source = Scene.instantiate()
	root.add_child(source)
	_check(PlaySession.save(source) and SessionSave.stage() == SessionSave.BATTLE_PATH, "suspend the original battle through the normal save route")
	source.queue_free()
	await process_frame
	var other := SpringRun.begin(8)
	other.coins = 907
	other.save_to_file(path)
	var view = Scene.instantiate()
	root.add_child(view)
	_check(view.spring_mode and SpringBattleBridge.restore_map, "normal scene entry restores the suspended battle and parent map")
	var result := {"result": "victory", "place": "battle_1", "kind": "battle", "hero_health": 1050, "hero_max_health": 2100}
	Handoff.open(view, result, path, func(_tree, _scene): return OK)
	var stored := SpringRun.load_from_file(path)
	_check(stored != null and stored.seed_value == int(expected.seed), "settlement follows the suspended battle's own map, not a newer on-disk journey")
	_check(stored != null and stored.coins == 41 and not stored.pending_battle_settlement.is_empty(), "settlement preserves the original journey resources and pending result")
	view.queue_free()
	await process_frame


func _test_handoff_retries() -> void:
	var run := _party_run()
	SpringBattleBridge.prepare(run, &"B001", &"battle_1")
	var view := HandoffView.new()
	root.add_child(view)
	var result := {"result": "victory", "place": "battle_1", "kind": "battle"}
	Handoff.open(view, result, path, func(_tree, _scene): return ERR_CANT_OPEN)
	var saved := SpringRun.load_from_file(path)
	var record_id: String = saved.pending_battle_settlement.id
	_check(SpringBattleBridge.has_pending() and not SpringBattleBridge.suspended_map.is_empty(), "rejected scene change retains the battle handoff")
	_check(view.status_message.contains("重试"), "rejected scene change has a visible retry explanation")
	Handoff.open(view, result, path, func(_tree, _scene): return OK)
	_check(SpringRun.load_from_file(path).pending_battle_settlement.id == record_id, "retry reuses the durable settlement ID")
	_check(not SpringBattleBridge.has_pending() and SpringBattleBridge.suspended_map.is_empty(), "accepted change clears the handoff")
	view.queue_free()


func _test_downed_lead_keeps_downed() -> void:
	var run := _party_run()
	run.party_vitals.sakura.health = 0
	run.hero_health = 1
	run.add_relic(&"relic_spring_charm")
	run.add_bonus_max_health(200)
	SpringBattleBridge.prepare(run, &"B001", &"battle_1")
	var view = Scene.instantiate()
	root.add_child(view)
	_check(view.controller.actors.sakura.is_defeated() and not view.controller.actors.sakura.is_downed() and view.controller.actors.sakura.health == 0, "a dead legacy lead is permanently retired on battle entry")
	_check(view.controller.actors.sakura.max_health == 2300, "a downed lead still receives the correct new ceiling")
	_check(SpringRun.from_dict(run.to_dict()).hero_health == 0, "map reload does not display a phantom health point for a downed lead")
	_check(run.hero_health == 0 and run.heal_hero(100) == 100 and run.party_vitals.sakura.health == 100, "explicit map healing restores its actual amount without a phantom one-point revival")
	view.queue_free()
	SpringBattleBridge.clear_pending()


func _test_handoff_failures_preserve_state() -> void:
	var run := _party_run()
	var view := HandoffView.new()
	root.add_child(view)
	var result := {"result": "victory", "place": "battle_1", "kind": "battle"}
	SpringBattleBridge.prepare(run, &"B001", &"battle_1")
	_check(SessionSave.write({"scene": "map", "run": run.to_dict(), "ui": {}}), "seed a private checkpoint before a failed handoff")
	var checkpoint := FileAccess.get_file_as_string(SessionSave.path())
	var blocked := path + ".blocked"
	_check(DirAccess.make_dir_absolute(blocked) == OK, "block only the test destination")
	var changes := {"count": 0}
	Handoff.open(view, result, blocked, func(_tree, _scene): changes.count += 1; return OK)
	_check(changes.count == 0 and SpringBattleBridge.has_pending() and FileAccess.get_file_as_string(SessionSave.path()) == checkpoint, "write failure neither travels nor clears the battle/checkpoint")
	DirAccess.remove_absolute(blocked)
	run.save_to_file(path)
	var before := FileAccess.get_file_as_string(path)
	SpringBattleBridge.suspended_map = {"version": 5, "template_id": 99}
	Handoff.open(view, result, path, func(_tree, _scene): changes.count += 1; return OK)
	_check(changes.count == 0 and FileAccess.get_file_as_string(path) == before, "invalid parent snapshot never falls back to a different valid disk journey")
	SpringBattleBridge.suspended_map = {}
	Handoff.open(view, result, path, func(_tree, _scene): return OK)
	_check(not SpringRun.load_from_file(path).pending_battle_settlement.is_empty(), "legacy handoff without a parent snapshot still uses the disk checkpoint")
	view.queue_free()
	await process_frame
	var legacy := _party_run()
	legacy.hero_health = 1200
	SpringBattleBridge.prepare(legacy, &"B001", &"battle_1")
	_check(SpringBattleBridge.pending.party_vitals.sakura.health == 1200, "old healthy snapshots with stale party copies adopt the map's saved healing")
	SpringBattleBridge.clear_pending()
