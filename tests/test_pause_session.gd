extends "res://tests/framework/test_case.gd"

const BattleScene = preload("res://scenes/main/main.tscn")
var shell: Node


func _run() -> void:
	SessionSave.path_override = "user://pause_session_%d.json" % OS.get_process_id()
	SessionSave.clear()
	shell = root.get_node_or_null("GameShell")
	_check(shell != null, "persistent shell is autoloaded in the real project")
	if shell == null: return
	shell.animations_enabled = false
	await _test_pause_freezes_enemy_and_all_buttons()
	await _test_battle_roundtrip()
	await _test_spring_and_map_roundtrip()
	_test_invalid_save_and_failed_write()
	await _test_return_to_title_actions()
	await _test_transition_and_audio()
	SessionSave.clear()
	SessionSave.path_override = ""
	shell.resume()
	for voice in shell.audio.voices: voice.stop()


func _battle() -> Node:
	SpringBattleBridge.clear_pending()
	var view := BattleScene.instantiate()
	root.add_child(view)
	current_scene = view
	return view


func _test_pause_freezes_enemy_and_all_buttons() -> void:
	var view := _battle()
	await process_frame
	view._end_player_turn()
	view.fx.enemy_step_timer = 0.5
	shell.open_pause()
	_check(paused and shell.menu.visible, "pause opens a modal and freezes the scene tree")
	var before := JSON.stringify(SessionCodec.encode(BattleSession.capture(view)))
	await create_timer(0.12, true).timeout
	_check(before == JSON.stringify(SessionCodec.encode(BattleSession.capture(view))), "enemy resolution, AP, HP and animation timers remain frozen")
	_check(shell.menu.buttons.size() == 8, "all six requested actions and confirmation controls exist")
	shell.menu.buttons.about.pressed.emit()
	_check(shell.menu.detail.visible and paused, "About opens while gameplay stays paused")
	_check(shell.menu.detail_text.text.contains("Godot") and shell.menu.detail_text.text.contains("ECHO"), "About contains actual project information")
	shell.menu.buttons.back.pressed.emit()
	_check(not shell.menu.detail.visible and paused, "About returns to the paused menu")
	shell.menu.buttons.exit.pressed.emit()
	_check(current_scene == view and paused and shell.menu.confirm_exit, "Exit requires confirmation before leaving the current scene")
	_check(shell.menu.detail_text.text.contains("返回标题"), "exit confirmation explains the actual destination")
	shell.menu.buttons.back.pressed.emit()
	var save_path := SessionSave.path_override
	SessionSave.path_override = "user://missing_pause_directory/ui.json"
	shell.menu.buttons.save_exit.pressed.emit()
	_check(current_scene == view and paused and shell.menu.note.text.contains("保存失败"), "a failed save never leaves or unpauses the current battle")
	SessionSave.path_override = save_path
	shell.menu.buttons.resume.pressed.emit()
	_check(not paused and not shell.menu.visible, "Continue unpauses and dismisses the modal")
	view.queue_free()
	await process_frame


func _test_battle_roundtrip() -> void:
	var view := _battle()
	await process_frame
	view.controller.get_active_character().health -= 137
	view.controller.ap.spend(1)
	view.controller.ledger.free_move_used_turn = view.controller.turn_number
	view.controller.statuses.apply_status(&"test_pause", "defender", "defender", 2)
	_check(view.controller.statuses.has_status("defender", &"test_pause"), "the checkpoint includes a real nonempty status container")
	view.run_state.add_to_backpack({"id": &"pause_test_item", "kind": "consumable", "name": "测试补给", "heal": 100})
	view._end_player_turn()
	view.fx.enemy_step_timer = 0.47
	shell.open_pause()
	var snapshot := BattleSession.capture(view)
	_check(SessionSave.valid(snapshot), "an in-progress enemy phase is a valid suspend point")
	_check(SessionSave.write(snapshot), "the paused battle checkpoint is persisted")
	var loaded := SessionSave.read()
	_check(not loaded.is_empty(), "suspended battle can be read from JSON")
	var title: Node = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(title)
	_check(title.entries[0].get("action") == "resume", "a fresh title screen exposes Continue Journey for a valid save")
	title.queue_free()
	_check(SessionSave.stage() == SessionSave.BATTLE_PATH, "Continue Journey routes to the battle scene")
	shell.resume()
	view.queue_free()
	await process_frame
	var resumed := BattleScene.instantiate()
	root.add_child(resumed)
	current_scene = resumed
	shell.open_pause()
	var after := BattleSession.capture(resumed)
	for key in ["controller", "actors", "ap", "ledger", "statuses", "intents", "run_state", "fx", "loot_state", "pressure_refunds"]:
		_check(JSON.stringify(SessionCodec.encode(snapshot[key])) == JSON.stringify(SessionCodec.encode(after[key])), "resume restores exact %s state without replaying actions" % key)
	_check(not FileAccess.file_exists(SessionSave.path()), "successful resume consumes the suspend slot to prevent reward replay")
	shell.resume()
	resumed.queue_free()
	await process_frame


func _test_spring_and_map_roundtrip() -> void:
	var run := SpringRun.begin(12)
	var place: SpringPlace
	for candidate in run.template.places:
		if candidate.kind == SpringPlace.Kind.BATTLE:
			place = candidate
			break
	_check(SpringBattleBridge.prepare(run, place.payload, place.id), "spring fight captures its original parent map")
	var view := BattleScene.instantiate()
	root.add_child(view)
	current_scene = view
	shell.open_pause()
	var snapshot := BattleSession.capture(view)
	_check(SessionSave.write(snapshot), "deployment phase can be suspended")
	_check(SessionSave.stage() == SessionSave.BATTLE_PATH, "spring suspension targets the battle scene")
	shell.resume()
	view.queue_free()
	await process_frame
	var resumed := BattleScene.instantiate()
	root.add_child(resumed)
	current_scene = resumed
	shell.open_pause()
	_check(resumed.spring_mode and resumed.controller.phase == BattleController.BattlePhase.DEPLOY, "spring resumes deployment without starting the encounter twice")
	_check(SpringBattleBridge.restore_map and SpringBattleBridge.suspended_map == run.to_dict(), "resumed battle retains the matching parent map")
	shell.resume()
	resumed.queue_free()
	await process_frame
	SpringBattleBridge.clear_pending()
	SpringBattleBridge.restore_map = false
	var data := {"scene": "map", "run": run.to_dict(), "ui": {"shop_open": true, "shop_tab": 2, "selected_cell": Vector2i(2, 3)}}
	_check(SessionSave.write(data), "map and open-shop state are saved")
	_check(SessionSave.stage() == SessionSave.MAP_PATH, "map resume chooses the map scene")
	var map: Node = load(SessionSave.MAP_PATH).instantiate()
	map.save_path = "user://pause_map_%d.json" % OS.get_process_id()
	map.atelier_save_path = "user://pause_stash_%d.json" % OS.get_process_id()
	root.add_child(map)
	current_scene = map
	shell.open_pause()
	_check(map.run.seed_value == 12 and map.run.exploration.stamina == run.exploration.stamina, "map resume keeps its seed and stamina")
	_check(map.shop_open and map.shop_tab == 2 and map.selected_cell == Vector2i(2, 3), "map resume preserves open shop and selected location")
	shell.resume()
	map.queue_free()
	await process_frame


func _test_invalid_save_and_failed_write() -> void:
	_check(not SessionSave.valid({"scene": "battle"}), "incomplete battle data is rejected")
	_check(not SessionSave.valid({"scene": "map", "run": {}}), "invalid map data is rejected")
	var path := SessionSave.path()
	SaveFile.write_json(path, {"version": 999, "data": {}})
	_check(SessionSave.read().is_empty(), "future-format saves are not interpreted as current data")
	SessionSave.path_override = "user://missing_pause_directory/save.json"
	_check(not SessionSave.write({"scene": "map", "run": SpringRun.begin(1).to_dict()}), "failed disk writes are reported")
	SessionSave.path_override = path
	SessionSave.clear()
	var typed: Variant = SessionCodec.decode(SessionCodec.encode({Vector2i(1, 2): [StringName("test"), Color.RED, 9223372036854775800]}))
	_check(typed[Vector2i(1, 2)][2] == 9223372036854775800, "JSON roundtrip preserves 64-bit RNG integers and vector dictionary keys")
	_check(SessionCodec.decode({"$": "v2i", "x": [], "y": 0}) == null, "invalid encoded coordinates are rejected without conversion errors")


func _test_return_to_title_actions() -> void:
	var old_save := {"scene": "map", "run": SpringRun.begin(7).to_dict()}
	_check(SessionSave.write(old_save), "an earlier suspend slot exists before unsaved exit")
	var before := FileAccess.get_file_as_string(SessionSave.path())
	var run := SpringRun.begin(12)
	for place in run.template.places:
		if place.kind == SpringPlace.Kind.BATTLE:
			SpringBattleBridge.prepare(run, place.payload, place.id)
			break
	var battle := BattleScene.instantiate()
	root.add_child(battle)
	current_scene = battle
	shell.open_pause()
	SpringBattleBridge.last_result = {"result": "victory"}
	SpringBattleBridge.restore_map = true
	shell.menu.buttons.exit.pressed.emit()
	_check(current_scene == battle, "opening exit confirmation leaves the spring battle intact")
	shell.menu.buttons.confirm.pressed.emit()
	await scene_changed
	_check(current_scene.scene_file_path == shell.TITLE_PATH, "confirmed Exit really changes to the title scene")
	_check(not paused and not shell.is_paused and not shell.menu.visible, "the returned title is unpaused and interactive")
	_check(FileAccess.get_file_as_string(SessionSave.path()) == before, "unsaved exit preserves the earlier checkpoint byte for byte")
	_check(not SpringBattleBridge.has_pending() and not SpringBattleBridge.has_result(), "returning to title discards old encounter and result handoffs")
	_check(not SpringBattleBridge.restore_map and SpringBattleBridge.suspended_map.is_empty(), "returning to title discards stale map restoration state")
	_check(current_scene.entries[0].get("action") == "resume", "an earlier saved journey remains available on the title")
	# Enter a tutorial after leaving a spring fight; it must not resume that fight.
	_check(SceneTravel.change(self, SessionSave.BATTLE_PATH) == OK, "another mode can be started after exit")
	await scene_changed
	_check(not current_scene.spring_mode, "starting again cannot accidentally enter the previous spring encounter")
	current_scene.controller.get_active_character().health -= 137
	current_scene.controller.ap.spend(1)
	shell.open_pause()
	shell.menu.buttons.save_exit.pressed.emit()
	await scene_changed
	_check(current_scene.scene_file_path == shell.TITLE_PATH and not paused, "Save and Exit also returns to an interactive title")
	_check(FileAccess.file_exists(SessionSave.path()) and current_scene.entries[0].get("action") == "resume", "the new checkpoint is immediately resumable without restarting the program")
	current_scene.selected_option = 0
	current_scene._activate_selected()
	await scene_changed
	_check(current_scene.controller.get_active_character().health == 3463 and current_scene.controller.ap.current == 2, "Continue Journey restores the newly saved health and AP in the same process")
	_check(root.get_node("GameShell") == shell and shell.audio.music != null, "returning to title keeps the application and audio service running")
	_check(not FileAccess.file_exists(SessionSave.path()), "resuming from title still consumes the saved slot")
	shell.animations_enabled = true
	shell.open_pause()
	shell.menu.buttons.exit.pressed.emit()
	shell.menu.buttons.confirm.pressed.emit()
	_check(shell.stage == "closing" and paused, "returning to title uses the normal closing transition")
	await scene_changed
	await create_timer(0.75, true).timeout
	_check(current_scene.scene_file_path == shell.TITLE_PATH and not paused and shell.stage.is_empty(), "animated title return completes and releases title input")
	shell.animations_enabled = false
	current_scene.queue_free()
	await process_frame


func _test_transition_and_audio() -> void:
	var original_music: bool = shell.audio.music_enabled
	var original_effects: bool = shell.audio.effects_enabled
	_check(shell.audio.set_enabled("music", false), "music preference is persisted")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music toggle really mutes the music bus")
	_check(shell.audio.set_enabled("effects", false), "effects preference is persisted")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "effects toggle really mutes the effects bus")
	shell.menu.buttons.music.pressed.emit()
	shell.menu.buttons.effects.pressed.emit()
	_check(shell.audio.music_enabled and shell.audio.effects_enabled, "the actual menu buttons enable both audio channels")
	shell.menu.buttons.music.pressed.emit()
	shell.menu.buttons.effects.pressed.emit()
	var copy := GameAudio.new()
	copy.settings_path = shell.audio.settings_path
	root.add_child(copy)
	_check(not copy.music_enabled and not copy.effects_enabled, "audio preferences survive a fresh audio service")
	_check(copy.music.stream != null and copy.cue_streams.size() == 4, "music and sound effects have real playable streams")
	copy.queue_free()
	shell.audio.set_enabled("music", original_music)
	shell.audio.set_enabled("effects", original_effects)
	_check(shell.travel("res://missing_pause_scene.tscn", "missing") == ERR_FILE_NOT_FOUND, "missing destinations do not start a transition")
	_check(not paused and shell.stage.is_empty(), "a failed transition leaves the game usable")
	shell.animations_enabled = true
	shell.reveal("TEST")
	_check(paused and shell.transition.visible and shell.transition.coverage == 1.0, "entry transition covers the scene and holds gameplay")
	_check(shell.travel(SessionSave.BATTLE_PATH, "duplicate") == ERR_BUSY, "a second transition cannot replace an in-flight one")
	await create_timer(0.8, true).timeout
	_check(not paused and shell.stage.is_empty() and not shell.transition.visible, "entry transition fades away and releases gameplay")
	_check(shell.travel("res://scenes/lobby/lobby.tscn", "工坊") == OK, "scene travel starts a closing transition")
	_check(paused and shell.stage == "closing", "scene travel freezes input before replacing the scene")
	await create_timer(1.2, true).timeout
	_check(current_scene.scene_file_path == "res://scenes/lobby/lobby.tscn" and not paused, "closing, scene replacement and opening complete as one transition")
	current_scene.queue_free()
	await process_frame
	shell.animations_enabled = false
