extends "res://tests/framework/test_case.gd"

const Demo = preload("res://scenes/examples/anomaly_demo.tscn")

func _run() -> void:
	var shell = root.get_node_or_null("GameShell")
	if shell != null: shell.animations_enabled = false
	_test_schema()
	_test_damage_and_budget()
	_test_reinforcements_and_reset()
	await _test_demo_and_resume()
	await process_frame
	if shell != null:
		for voice in shell.audio.voices: voice.stop()
		await create_timer(0.05, true).timeout


func _start(battle: BattleController, overrides: Dictionary) -> bool:
	return battle.start_encounter(Vector2i(2, 3), [Vector2i(4, 3)], [], ["vanguard"], ["sevrin"], [], [], 0, [], false, 1.0, overrides)


func _spawn(overrides: Dictionary) -> BattleController:
	var battle := BattleController.new()
	root.add_child(battle)
	_check(_start(battle, overrides), "valid law configuration starts through the controller")
	battle.beacons.clear()
	return battle


func _test_schema() -> void:
	_check(EncounterLaws.resolve({}).attenuation_k == 1000, "default K retains established damage math")
	_check(EncounterLaws.resolve({}, 5).ap_pool == 5, "empty override preserves the controller's configured AP")
	_check(EncounterLaws.resolve({&"ap_pool": 4}).ap_pool == 4, "StringName keys have the same real reader as string keys")
	_check(EncounterLaws.describe_error({"telegraph_lead_turns": 1, "telegraph_mutable": false}).is_empty(), "current telegraph behavior can be declared explicitly")
	for invalid in [{"typo_k": 500}, {"attenuation_k": 0}, {"attenuation_k": 500.0}, {"attenuation_k": "500"}, {"ap_pool": true}, {"ap_pool": 0}, {"ap_pool": -1}, {"telegraph_lead_turns": 2}, {"telegraph_mutable": true}, {"echo_lock_mode": "actor"}, {"action_cost": 0}, {"residue_repeat_ratio": 0.5}, {7: 500}]:
		_check(not EncounterLaws.describe_error(invalid).is_empty(), "invalid or unsupported law override is diagnosed: %s" % str(invalid))
	var definition: EncounterDefinition = LevelCatalog.ANOMALY_DEMO.duplicate(true)
	_check(definition.is_valid() and definition.describe_layout_error().is_empty(), "authored anomaly resource is a valid layout")
	definition.anomaly_overrides["unknown"] = 1
	_check(not definition.is_valid(), "resource validation rejects inert parameter declarations")
	_check(LevelCatalog.level_count() == 3, "optional anomaly does not change the three-lesson route")
	_check(EncounterLaws.summary({"attenuation_k": 500, "ap_pool": 4}).contains("抗性更有效"), "HUD explanation describes the gameplay consequence")


func _test_damage_and_budget() -> void:
	var normal := _spawn({})
	var laws := {"attenuation_k": 500, "ap_pool": 4}
	var battle := _spawn(laws)
	laws.attenuation_k = 2000
	_check(battle.law_overrides.attenuation_k == 500, "runtime copies authored overrides instead of borrowing mutable data")
	_check(battle.ap.maximum == 4 and battle.ap.current == 4, "AP override affects the actual shared budget")
	var hero = battle.get_active_character()
	var enemy = battle.get_actor("vanguard_00")
	_check(hero.attenuation_k == 500 and enemy.attenuation_k == 500, "both sides inherit encounter K")
	var intent = battle.intents[0]
	var quote: int = intent.preview_health_damage(battle)
	_check(quote == floori(intent.damage * 500.0 / (500.0 + hero.defense)), "single intent quote reads overridden K")
	var total := BoardThreatView.incoming_threats_at(battle, hero.cell)
	_check(total.total_dmg == quote, "sequential HUD projection clones the same overridden resistance math")
	_check(quote < normal.intents[0].preview_health_damage(normal), "smaller K strengthens resistance without changing other battles")
	var before: int = hero.health
	_check(battle.end_player_turn(), "normal enemy phase resolves under overridden laws")
	_check(before - hero.health == quote, "actual health loss exactly matches the overridden telegraph")
	_check(battle.ap.current == 4, "next player turn refreshes the overridden pool")
	before = enemy.health
	battle._apply_damage(enemy.actor_id, 1000, hero.actor_id, "laws_probe", "physical")
	_check(before - enemy.health == floori(1000 * 500.0 / (500.0 + enemy.defense)), "outgoing damage also uses encounter K")
	_check(hero.preview_damage(1000, "true") == mini(1000, hero.health), "true damage still bypasses resistance")
	var original = battle.get_active_character()
	var ap_before := battle.ap.current
	_check(not _start(battle, {"ap_pool": 0}), "invalid law setup fails before replacing a battle")
	_check(battle.get_active_character() == original and battle.ap.current == ap_before and battle.attenuation_k == 500, "rejected setup leaves actors, AP and law state intact")
	_check(_start(battle, {}), "same controller can start an ordinary encounter")
	_check(battle.ap.maximum == 3 and battle.attenuation_k == 1000 and battle.law_overrides.is_empty(), "ordinary restart clears all previous anomaly state")
	for unit in battle.actors.values(): _check(unit.attenuation_k == 1000, "ordinary actor receives the default K after restart")
	normal.queue_free()
	battle.queue_free()


func _test_reinforcements_and_reset() -> void:
	var battle := BattleController.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3)], [], ["boss_thousand_boughs"], ["sakura"], [], [], 0, [], false, 1.2, {"attenuation_k": 500, "ap_pool": 4}), "Boss supports combined stat and law configuration")
	battle.beacons.clear()
	var boss = battle.get_actor("boss_thousand_boughs_00")
	boss.health = int(boss.max_health / 2) + 1
	_check(battle.request_skill(&"sakura_pierce_blossom", boss.actor_id), "real skill crosses the anomaly Boss threshold")
	var count := 0
	for unit in battle.actors.values():
		if str(unit.actor_id).begins_with("escort_"):
			count += 1
			_check(unit.attenuation_k == 500 and unit.attack == roundi(EnemyCatalog.get_definition(unit.archetype).attack * 1.2), "reinforcement inherits K and stat scaling independently")
	_check(count == 2, "phase-two fixture actually spawns both escorts")
	battle.queue_free()


func _test_demo_and_resume() -> void:
	SessionSave.path_override = "user://law_session_%d.json" % OS.get_process_id()
	SessionSave.clear()
	SpringBattleBridge.clear_pending()
	var view = Demo.instantiate()
	root.add_child(view)
	current_scene = view
	await process_frame
	_check(view.levels.size() == 1 and view.levels[0].level_id == &"anomaly_resonance", "real optional scene starts the authored anomaly")
	_check(view.controller.ap.current == 4 and view.controller.attenuation_k == 500, "scene sends resource parameters to the live battle")
	var authored: EncounterDefinition = view.levels[0]
	var invalid: EncounterDefinition = authored.duplicate(true)
	invalid.anomaly_overrides["typo_k"] = 1
	view.levels[0] = invalid
	var prior = view.controller.get_active_character()
	view._start_level(0)
	_check(view.status_message.contains("未知法则参数"), "invalid authored key is visibly diagnosed at the real scene boundary")
	_check(view.controller.get_active_character() == prior and view.controller.ap.current == 4, "invalid resource does not replace the active battle")
	view.levels[0] = authored
	view.controller.ap.spend(1)
	var snapshot := BattleSession.capture(view)
	_check(SessionSave.valid(snapshot) and SessionSave.write(snapshot), "anomaly suspends through real JSON storage")
	for key in ["law_overrides", "attenuation_k"]:
		var broken := snapshot.duplicate(true)
		broken.controller[key] = {"unknown": 1} if key == "law_overrides" else 0
		_check(not SessionSave.valid(broken), "corrupt controller law state is rejected: " + key)
	var bad_actor := snapshot.duplicate(true)
	bad_actor.actors[0].attenuation_k = 1000
	_check(not SessionSave.valid(bad_actor), "snapshot cannot silently restore inconsistent actor K")
	var bad_id := snapshot.duplicate(true)
	bad_id.encounter_override_id = "res://arbitrary.tres"
	_check(not SessionSave.valid(bad_id), "custom scene restore only accepts registered encounter IDs")
	_check(SessionSave.stage() == SessionSave.BATTLE_PATH, "saved anomaly restores through the normal title route")
	view.queue_free()
	await process_frame
	var resumed = load(SessionSave.BATTLE_PATH).instantiate()
	root.add_child(resumed)
	current_scene = resumed
	await process_frame
	_check(resumed.levels[0].level_id == &"anomaly_resonance" and resumed.controller.ap.maximum == 4 and resumed.controller.ap.current == 3, "restore preserves optional encounter identity and spent AP")
	_check(resumed.controller.get_active_character().attenuation_k == 500 and resumed.controller.attenuation_k == 500, "resume preserves actor and encounter K")
	_check(not FileAccess.file_exists(SessionSave.path()), "successful anomaly restore consumes the suspend slot")
	resumed.queue_free()
	await process_frame
	SessionSave.clear()
	SessionSave.path_override = ""
