extends "res://tests/framework/test_case.gd"

const Scene = preload("res://scenes/main/main.tscn")
var path := "user://vitality_flow_%d.json" % OS.get_process_id()


func _run() -> void:
	FragmentStore.default_path_override = path
	var shell = root.get_node_or_null("GameShell")
	if shell != null: shell.animations_enabled = false
	await _test_fragment_vitality_full_flow()
	FragmentStore.default_path_override = ""
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	SpringBattleBridge.clear_pending()
	if shell != null:
		for voice in shell.audio.voices: voice.stop()
	await create_timer(0.05, true).timeout


func _test_fragment_vitality_full_flow() -> void:
	var store := FragmentStore.load_store(path)
	_check(store.add_modules([{"instance_id": "hp5", "size": "small", "capacity": 1, "main_stat": "health", "sub_stat": "", "attributes": {"health": 5.0}, "created_seed": 0}]), "create isolated vitality module")
	_check(store.install("sakura", 0, "hp5").ok and store.save(), "install the module before the first encounter")
	var run := SpringRun.begin(3)
	run.party_character_ids.assign(["sakura"])
	run.hero_health = 1050
	run.party_vitals = {"sakura": {"health": 1050, "max_health": 2100}}
	for cycle in range(3):
		_check(SpringBattleBridge.prepare(run, &"B001", &"battle_1"), "prepare actual encounter cycle %d" % cycle)
		var view = Scene.instantiate()
		root.add_child(view)
		var hero = view.controller.actors.sakura
		_check(hero.health == 1103 and hero.max_health == 2205, "module composition remains stable on actual battle entry")
		var result := {"result": "victory", "kind": "elite", "place": "battle_1", "hero_health": hero.health, "hero_max_health": hero.max_health, "party_vitals": {"sakura": {"health": hero.health, "max_health": hero.max_health, "base_max_health": PartyLoadout.unscaled_max_health(hero)}}, "carry": SpringBattleBridge.pack_carry(view.run_state)}
		SpringBattleBridge.settle_result(run, result)
		_check(run.carry_max_health == 2100, "settlement stores the unscaled carry maximum")
		for reload_index in range(3):
			run = SpringRun.from_dict(run.to_dict())
			_check(run != null and run.hero_health == 1103 and run.party_vitals.sakura.max_health == 2205 and run.effective_max_health() == 2205, "map JSON reload %d never compounds module scaling" % reload_index)
		view.queue_free()
		SpringBattleBridge.clear_pending()
		await process_frame
	var legacy := run.to_dict()
	legacy.hero.carry_max_health = 2205
	var repaired := SpringRun.from_dict(legacy)
	_check(repaired.hero_health == 1103 and repaired.party_vitals.sakura.max_health == 2205, "known base metadata repairs a previously scaled carry without inflating HP")
	_check(run.heal_hero(9999) == 1102 and run.hero_health == 2205, "map healing can reach the module-scaled maximum")
	_check(run.damage_hero(90) == 90 and run.hero_health == 2115, "map damage preserves the correct scaled clock")
	_check(store.uninstall("sakura", 0).ok and store.save(), "remove module between encounters")
	run.sync_lead_vitals()
	_check(run.effective_max_health() == 2100 and run.hero_health == 2014, "uninstall reclaims maximum and proportionate current HP once")
	run = SpringRun.from_dict(run.to_dict())
	_check(run.hero_health == 2014 and run.party_vitals.sakura.max_health == 2100, "uninstalled module does not regrow after reload")
	run.add_bonus_max_health(200)
	_check(run.hero_health == 2214 and run.effective_max_health() == 2300, "explicit map max-health gain adds its own heal without a second ratio heal")
	run.party_vitals.sakura.health = 0
	run.hero_health = 0
	run = SpringRun.from_dict(run.to_dict())
	_check(run.hero_health == 0, "vitality normalization never revives a retired role")
