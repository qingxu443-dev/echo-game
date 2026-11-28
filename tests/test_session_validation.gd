extends "res://tests/framework/test_case.gd"

const Scene = preload("res://scenes/main/main.tscn")

func _run() -> void:
	var shell = root.get_node_or_null("GameShell")
	if shell != null: shell.animations_enabled = false
	SessionSave.path_override = "user://validation_%d.json" % OS.get_process_id()
	SessionSave.clear()
	SpringBattleBridge.clear_pending()
	var view = Scene.instantiate()
	root.add_child(view)
	await process_frame
	var hero = view.controller.get_active_character()
	var battle: BattleController = view.controller
	battle._apply_damage(hero.actor_id, 333, "vanguard_00", "validation_probe", "true")
	_check(battle.request_player_move([Vector2i(3, 3)]), "fixture includes a real movement and its live hop animation")
	battle.damage_beacon_at(battle.beacons.keys()[0], 1, hero.actor_id, "validation_probe")
	view.controller.statuses.apply_status(&"validation_probe", hero.actor_id, hero.actor_id, 2)
	var snapshot := BattleSession.capture(view)
	_check(SessionSave.valid(snapshot), "real damaged battle with spent AP is a valid checkpoint")
	_check(not snapshot.fx.actor_hop_state.is_empty() and not snapshot.fx.floating_popups.is_empty() and not snapshot.fx.impact_flashes.is_empty(), "checkpoint includes nonempty effects produced by real battle events")
	_test_snapshot_fields(snapshot)
	_test_codec()
	_test_map_boundary()
	await _test_rejection_before_mutation(snapshot)
	_test_corrupt_disk(snapshot)
	_check(SessionSave.write(snapshot), "valid checkpoint can replace the private test slot")
	_check(SessionSave.stage() == SessionSave.BATTLE_PATH, "valid checkpoint still stages through title routing")
	view.queue_free()
	await process_frame
	var resumed = Scene.instantiate()
	root.add_child(resumed)
	await process_frame
	_check(resumed.controller.get_active_character().health == int(snapshot.actors[0].health), "valid JSON restore retains damaged health")
	_check(resumed.controller.ap.current == 2, "valid JSON restore retains spent AP")
	_check(not FileAccess.file_exists(SessionSave.path()), "successful restore consumes the checkpoint")
	resumed.queue_free()
	await process_frame
	SessionSave.clear()
	SessionSave.path_override = ""
	if shell != null:
		for voice in shell.audio.voices:
			voice.stop()
			voice.stream = null
		await create_timer(0.12, true).timeout


func _change(data: Dictionary, path: Array, value: Variant) -> Dictionary:
	var copy := data.duplicate(true)
	var cursor: Variant = copy
	for i in range(path.size() - 1): cursor = cursor[path[i]]
	cursor[path.back()] = value
	return copy


func _test_snapshot_fields(data: Dictionary) -> void:
	var cases := [
		[["actors", 0, "health"], str(data.actors[0].health), "string health"],
		[["actors", 0, "health"], float(data.actors[0].health), "float health"],
		[["actors", 0, "attack"], -1, "negative attack"],
		[["actors", 0, "fragment_bonuses"], {"attack": "4"}, "fragment percentage type"],
		[["actors", 0, "fragment_bonuses"], {"attack": -1}, "negative fragment percentage"],
		[["actors", 0, "fragment_bonuses"], {"attack": INF}, "nonfinite fragment percentage"],
		[["actors", 0, "fragment_bonuses"], {"unknown": 1}, "unknown fragment stat"],
		[["actors", 0, "stolen_equipment"], [3], "typed equipment rows"],
		[["ap", "current"], "2", "string AP"],
		[["ap", "current"], 2.0, "float AP"],
		[["ap", "current"], 6, "AP beyond the temporary overflow limit"],
		[["ap", "maximum"], 0, "empty maximum AP"],
		[["controller", "phase"], "0", "string phase"],
		[["controller", "active_character_id"], "missing", "unknown commanded member"],
		[["actors", 0, "character_id"], &"missing", "unknown player character"],
		[["actors", 1, "archetype"], "missing", "unknown enemy profile"],
		[["controller", "blocked_cells"], {"1,2": true}, "wall coordinate type"],
		[["controller", "blocked_cells"], {Vector2i(99, 99): true}, "wall coordinate bounds"],
		[["controller", "deploy_zone"], ["cell"], "typed deployment coordinates"],
		[["controller", "actors"], {"shadow": {}}, "shadow actor container"],
		[["controller", "intents"], ["shadow"], "shadow intent container"],
		[["run_state", "mods"], [17], "typed mod IDs"],
		[["run_state", "backpack"], [false], "typed backpack rows"],
		[["ledger", "pressure_refund_count"], "0", "ledger scalar type"],
		[["intents", 0, "damage"], "1000", "intent damage type"],
		[["intents", 0, "state"], 999, "unknown intent state"],
		[["intents", 0, "target_mode"], "3", "string target mode"],
		[["intents", 0, "action_id"], "missing_action", "unknown enemy action"],
		[["statuses", 0, "stacks"], 2.0, "status scalar type"],
		[["fx", "enemy_step_timer"], "0.5", "FX timer type"],
		[["fx", "actor_visual_pos"], {"sevrin": 7}, "nested visual position type"],
		[["fx", "floating_popups"], [{"pos": Vector2.ZERO, "text": "x", "age": 0.0, "duration": -1.0, "color": Color.RED}], "popup duration"],
		[["fx", "impact_flashes"], [{"cell": "bad", "age": 0.0, "duration": 1.0, "color": Color.RED}], "impact tile type"],
		[["fx", "actor_hop_state"], {"sevrin": {}}, "incomplete hop state"],
		[["fx", "time"], NAN, "nonfinite timer"],
		[["view", "inventory_open"], "false", "view boolean type"],
		[["view", "pending_rewards"], [7], "typed pending rewards"],
		[["camera"], -1, "camera bounds"],
		[["level"], "0", "level type"],
		[["loot_state"], "123", "RNG state type"],
	]
	for row in cases:
		_check(not SessionSave.valid(_change(data, row[0], row[1])), "reject malformed checkpoint: " + row[2])
	var duplicate := data.duplicate(true)
	duplicate.intents.append(duplicate.intents[0].duplicate(true))
	_check(not SessionSave.valid(duplicate), "duplicate intent IDs cannot alias the event ledger")
	var missing := data.duplicate(true)
	missing.actors[0].erase("attack")
	_check(not SessionSave.valid(missing), "missing core actor stats do not silently become constructor defaults")
	var legacy := data.duplicate(true)
	legacy.controller.erase("law_overrides")
	legacy.controller.erase("attenuation_k")
	legacy.controller.erase("enemy_stat_multiplier")
	legacy.ledger.erase("rewards_settled")
	for actor in legacy.actors: actor.erase("attenuation_k")
	_check(SessionSave.valid(legacy), "missing optional fields from older checkpoints retain their defaults")


func _test_codec() -> void:
	for text in ["9223372036854775807", "-9223372036854775808", "0"]:
		_check(str(SessionCodec.decode({"$": "int", "v": text})) == text, "64-bit integer boundary remains exact: " + text)
	for raw in [
		{"$": "int", "v": "12junk"}, {"$": "int", "v": "1.5"},
		{"$": "int", "v": "9223372036854775808"}, {"$": "int", "v": "-9223372036854775809"},
		{"$": "int", "v": 12}, {"$": "v2i", "x": 1.5, "y": 2},
		{"$": "v2i", "x": 2147483648, "y": 0}, {"$": "v2", "x": INF, "y": 0},
		{"$": "name", "v": []}, {"$": "color", "v": "not-a-color"},
		{"$": "dict", "v": [["same", 1], ["same", 2]]},
	]:
		_check(SessionCodec.decode(raw) == null, "malformed codec tag is rejected: " + str(raw))
	var nullable: Variant = SessionCodec.decode(SessionCodec.encode([null, {"value": null}]))
	_check(nullable is Array and nullable[0] == null and nullable[1].value == null, "legitimate nested null values remain round-trippable")
	_check(SessionCodec.decode(RefCounted.new()) == null, "codec never accepts live objects as JSON data")
	var state := RunState.new()
	var legacy_names := {"mods": ["echo_stride"]}
	_check(SessionCodec.fields_error(RunState, legacy_names).is_empty(), "legacy string IDs remain compatible with StringName arrays")
	SessionCodec.apply_fields(state, legacy_names)
	_check(state.has_mod(&"echo_stride"), "accepted string-name conversion is actually restored")


func _test_map_boundary() -> void:
	var run := SpringRun.begin(12)
	var data := {"scene": "map", "run": run.to_dict(), "ui": {"selected_cell": Vector2i(5, 5), "shop_open": true, "shop_tab": 2}}
	_check(SessionSave.valid(data), "map validation uses the template's one-based edge coordinates")
	for row in [
		[["ui"], []], [["ui", "selected_cell"], "5,5"],
		[["ui", "selected_cell"], Vector2i.ZERO], [["ui", "shop_tab"], 3], [["ui", "shop_open"], "true"],
	]:
		_check(not SessionSave.valid(_change(data, row[0], row[1])), "malformed map UI is rejected before setters: " + str(row[0]))
	var map = load("res://scripts/spring/spring_map_view.gd").new()
	map.run = SpringRun.begin(1)
	var prior = map.run
	_check(not PlaySession.restore_map(map, _change(data, ["ui", "selected_cell"], "5,5")), "map restore rejects malformed UI before replacing its run")
	_check(map.run == prior and map.selected_cell == Vector2i(-1, -1), "failed map restore leaves run and selection unchanged")
	map.free()


func _test_rejection_before_mutation(data: Dictionary) -> void:
	var target = Scene.instantiate()
	root.add_child(target)
	await process_frame
	var prior = target.controller
	var prior_health: int = prior.get_active_character().health
	var prior_rng: int = LootCatalog._rng.state
	var malformed := _change(data, ["actors", 0, "health"], str(data.actors[0].health))
	_check(not BattleSession.restore(target, malformed), "real restore rejects string HP instead of healing to full")
	_check(target.controller == prior and prior.get_active_character().health == prior_health and LootCatalog._rng.state == prior_rng, "rejected restore leaves the controller, health and RNG unchanged")
	target.queue_free()
	await process_frame


func _test_corrupt_disk(data: Dictionary) -> void:
	var encoded: Dictionary = SessionCodec.encode(data)
	encoded.v.append(["unused_metadata", {"$": "int", "v": "broken"}])
	SaveFile.write_json(SessionSave.path(), {"version": SessionSave.VERSION, "data": encoded})
	var before := FileAccess.get_file_as_string(SessionSave.path())
	_check(SessionSave.read().is_empty(), "invalid nested codec node rejects the whole disk checkpoint")
	_check(SessionSave.last_read_error.contains("保留"), "failed read exposes a useful preservation diagnostic")
	_check(FileAccess.get_file_as_string(SessionSave.path()) == before, "failed read preserves the original file for diagnosis")
	var title = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(title)
	_check(title.notice.contains("保留") and title.entries[0].get("action") != "resume", "title explains the invalid checkpoint instead of silently hiding Continue")
	title.queue_free()
