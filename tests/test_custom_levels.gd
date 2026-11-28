extends "res://tests/framework/test_case.gd"

var shell: Node
var file_path := "user://custom_level_test_%d.json" % OS.get_process_id()
var wallet_path := "user://custom_wallet_test_%d.json" % OS.get_process_id()


func _run() -> void:
	shell = root.get_node("GameShell")
	shell.animations_enabled = false
	SessionSave.path_override = "user://custom_suspend_test_%d.json" % OS.get_process_id()
	_test_model()
	_test_file_validation()
	await _test_editor_interactions()
	await _test_play_and_suspend()
	SessionSave.clear()
	SessionSave.path_override = ""
	for path in [file_path, wallet_path, CustomLevelBridge.draft_path()]: DirAccess.remove_absolute(path)
	CustomLevelBridge.design = null
	for voice in shell.audio.voices: voice.stop()


func _test_model() -> void:
	var level := CustomLevelData.demo()
	_check(level.error(true).is_empty(), "the starter design is playable")
	var original := level.to_dict()
	_check(not level.place_unit("enemy", "vanguard", Vector2i(2, 6)).is_empty(), "placement rejects occupied hero cells")
	_check(level.to_dict() == original, "a rejected placement leaves the design untouched")
	_check(level.move_unit(Vector2i(2, 6), Vector2i(1, 6)).is_empty(), "a hero can move freely in edit mode")
	_check(level.data.heroes[0].cell == [1, 6], "the hero's spawn position follows the edit")
	_check(level.place_unit("hero", "sevrin", Vector2i(3, 6)).is_empty() and level.data.heroes.size() == 1, "placing the same hero relocates it rather than duplicating identity")
	_check(level.place_unit("hero", "sakura", Vector2i(1, 6)).is_empty() and level.data.heroes.size() == 2, "both playable heroes can be authored together")
	_check(not level.paint(Vector2i(1, 6), "wall").is_empty(), "a wall cannot overwrite a character")
	_check(level.paint(Vector2i(7, 7), "wall").is_empty(), "a wall can be placed on an empty tile")
	_check(level.paint(Vector2i(7, 7), "floor").is_empty() and not level.occupied(Vector2i(7, 7)), "removing a wall restores walkable floor")
	_check(not level.resize_board(4, 4), "shrinking a map cannot silently erase out-of-bounds contents")
	var grid := CustomLevelData.new()
	_check(grid.resize_board(4, 6), "an empty map can use rectangular dimensions")
	for definition in EnemyCatalog.definitions():
		var index: int = grid.data.enemies.size()
		var cell := Vector2i(index % 4, index / 4)
		_check(grid.place_unit("enemy", str(definition.archetype_id), cell).is_empty(), "the palette can place %s" % definition.display_name_zh)
	_check(grid.error().is_empty(), "ordinary, elite and boss profiles remain valid authoring data")
	var fresh := CustomLevelData.new()
	_check(not fresh.error(true).is_empty(), "an empty board is editable but cannot start a fight")
	fresh.place_unit("hero", "sevrin", Vector2i(1, 1))
	fresh.place_unit("enemy", "vanguard", Vector2i(2, 2))
	_check(fresh.resize_board(4, 4) and fresh.error(true).is_empty(), "a small custom board can be played")


func _test_file_validation() -> void:
	var level := CustomLevelData.demo()
	_check(CustomLevelBridge.save_file(level, file_path), "custom designs save to JSON")
	var loaded := CustomLevelBridge.load_file(file_path)
	_check(loaded != null and loaded.to_dict() == level.to_dict(), "JSON loading preserves every authored value")
	var data := level.to_dict()
	data.enemies[0].cell = [2.0, 6.0]
	_check(CustomLevelData.from_dict(data) == null, "integer and float coordinates cannot bypass overlap validation")
	data = level.to_dict()
	data.enemies[0].attack = -1
	_check(CustomLevelData.from_dict(data) == null, "negative combat values are rejected")
	data = level.to_dict()
	data.enemies[0].id = "missing_profile"
	_check(CustomLevelData.from_dict(data) == null, "missing enemy profiles are rejected")
	data = level.to_dict()
	data.walls.append([999, 0])
	_check(CustomLevelData.from_dict(data) == null, "out-of-bounds terrain is rejected")
	data = level.to_dict()
	data.heroes[0].health = "bad"
	_check(CustomLevelData.from_dict(data) == null, "incorrect nested stat types are rejected")
	data = level.to_dict()
	data.enemies[0].skill_charge = 9
	_check(CustomLevelData.from_dict(data) == null, "charge cannot exceed the authored maximum")
	_check(not CustomLevelBridge.save_file(level, "user://missing_custom_directory/file.json"), "failed saves are reported")
	SaveFile.write_json(file_path, {"version": 999})
	_check(CustomLevelBridge.load_file(file_path) == null, "a corrupt or unsupported file cannot replace the current design")


func _test_editor_interactions() -> void:
	CustomLevelBridge.design = CustomLevelData.demo()
	var editor: Node = load(CustomLevelBridge.EDITOR_PATH).instantiate()
	root.add_child(editor)
	current_scene = editor
	await process_frame
	_check(editor.left_panel.get_global_rect().end.x <= editor.center_panel.global_position.x, "the palette does not overlap the editable map")
	_check(editor.name_input.text == "回声试炼", "the editor opens with the actual design name")
	_check(editor.enemy_choice.item_count == EnemyCatalog.definitions().size(), "all enemy profiles appear in the dropdown")
	_check(editor.grid.cell_at(editor.grid.cell_rect(Vector2i(3, 4)).get_center()) == Vector2i(3, 4), "grid hit testing matches the rendered tile")
	editor._choose_tool("enemy")
	editor._grid_pressed(Vector2i(6, 4), MOUSE_BUTTON_LEFT)
	editor._grid_released(Vector2i(6, 4))
	_check(editor.design.data.enemies.size() == 3, "the actual placement tool adds a monster")
	var attack_control: SpinBox = editor.inspector.find_child("Stat_attack", true, false)
	attack_control.value = 777
	_check(editor.design.unit_at(Vector2i(6, 4)).attack == 777, "editing the inspector changes the selected monster")
	_check(editor.design.data.enemies[0].attack != 777, "other copies of that archetype keep their own values")
	editor._choose_tool("select")
	editor._grid_pressed(Vector2i(6, 4), MOUSE_BUTTON_LEFT)
	editor._grid_released(Vector2i(6, 5))
	_check(editor.design.unit_at(Vector2i(6, 5)).attack == 777, "dragging moves a monster with all its edited attributes")
	editor._undo()
	_check(not editor.design.unit_at(Vector2i(6, 4)).is_empty(), "undo restores a dragged unit")
	editor._redo()
	_check(not editor.design.unit_at(Vector2i(6, 5)).is_empty(), "redo reapplies the move")
	editor._choose_tool("wall")
	var count: int = editor.undo_stack.size()
	editor._grid_pressed(Vector2i(7, 0), MOUSE_BUTTON_LEFT)
	editor._grid_dragged(Vector2i(7, 1))
	editor._grid_released(Vector2i(7, 1))
	_check(editor.design.data.walls.has([7, 0]) and editor.design.data.walls.has([7, 1]), "drag painting creates a continuous wall stroke")
	_check(editor.undo_stack.size() == count + 1, "a brush stroke is one undo action")
	editor._undo()
	_check(not editor.design.data.walls.has([7, 0]) and not editor.design.data.walls.has([7, 1]), "one undo removes the whole brush stroke")
	editor.name_input.text = ""
	editor.name_input.text_changed.emit("")
	editor.name_input.text = "新试炼"
	editor.name_input.text_changed.emit("新试炼")
	editor._undo()
	_check(editor.design != null and editor.name_input.text.is_empty(), "undo can restore an in-progress empty name without invalidating the editor")
	editor._undo()
	_check(editor.name_input.text == "回声试炼", "another undo restores the original valid name")
	editor.width_input.value = 4
	_check(editor.design.data.width == 8 and editor.width_input.value == 8, "unsafe map shrinking reports the issue and restores its spinner")
	editor._clear()
	_check(editor.design.data.enemies.is_empty() and editor.design.data.heroes.is_empty(), "Clear Map removes units and terrain")
	editor._undo()
	_check(not editor.design.data.heroes.is_empty(), "clearing the map is reversible")
	editor.queue_free()
	await process_frame


func _test_play_and_suspend() -> void:
	var design := CustomLevelData.demo()
	design.data.ap = 6
	design.data.heroes[0].health = 2468
	design.data.heroes[0].attack = 555
	design.data.enemies[0].health = 4321
	design.data.enemies[0].attack = 333
	design.data.enemies[0].shield = 123
	design.data.enemies[0].move_steps = 4
	design.data.enemies[0].skill_charge = 1
	design.data.enemies[0].skill_damage = 987
	design.place_unit("hero", "sakura", Vector2i(1, 6))
	design.data.heroes[1].resource_current = 3
	CustomLevelBridge.design = design
	_check(AtelierStash.save_state({"shards": 123, "loadout": ["item_dusk_potion"]}, wallet_path), "the test wallet exists")
	var before := FileAccess.get_file_as_string(wallet_path)
	SpringBattleBridge.tutorial_loadout_requested = true
	var view: Node = load(CustomLevelBridge.BATTLE_PATH).instantiate()
	view.atelier_save_path = wallet_path
	root.add_child(view)
	current_scene = view
	await process_frame
	_check(view.controller.ap.current == 6 and view.controller.ap.maximum == 6, "authored AP is used by the real battle")
	_check(view.controller.get_active_character().health == 2468 and view.controller.get_active_character().attack == 555, "custom hero stats replace tutorial defaults")
	var enemy: BattleActor = view.controller.get_actor("vanguard_00")
	_check(enemy.health == 4321 and enemy.attack == 333 and enemy.shield == 123, "per-instance enemy values reach the runtime")
	_check(enemy.move_steps == 4 and enemy.skill_damage == 987 and enemy.skill_charge == 1, "enemy movement, signature damage and charge reach the runtime before intent planning")
	_check(view.controller.get_actor("sakura").resource_current == 3, "the second hero keeps its chosen initial resource")
	_check(view.controller.beacons.size() == 1 and view.controller.beacons.has(Vector2i(0, 4)), "custom chest placement replaces automatic tutorial chests")
	_check(FileAccess.get_file_as_string(wallet_path) == before, "starting a custom fight never claims paid tutorial supplies")
	view.controller.ap.spend(1)
	var snapshot := BattleSession.capture(view)
	var corrupt := snapshot.duplicate(true)
	corrupt.custom_level = {"version": 999}
	_check(not SessionSave.valid(corrupt), "invalid custom designs cannot enter the resume path")
	corrupt = snapshot.duplicate(true)
	corrupt.spring_mode = true
	_check(not SessionSave.valid(corrupt), "a custom snapshot cannot impersonate a spring run")
	_check(SessionSave.write(snapshot), "custom battles support the existing pause-save system")
	_check(SessionSave.stage() == CustomLevelBridge.BATTLE_PATH, "Continue Journey routes to the custom battle")
	view.queue_free()
	await process_frame
	var resumed: Node = load(CustomLevelBridge.BATTLE_PATH).instantiate()
	resumed.atelier_save_path = wallet_path
	root.add_child(resumed)
	current_scene = resumed
	_check(resumed.controller.ap.current == 5 and resumed.controller.get_active_character().health == 2468, "a suspended custom battle restores exact AP and HP")
	_check(resumed.levels[0].level_id == &"custom_sandbox", "restoring custom play never substitutes the first tutorial")
	for actor in resumed.controller.actors.values():
		if actor.team == "enemy": actor.health = 0; actor._is_defeated = true
	resumed.controller._check_battle_end()
	_check(resumed.controller.phase == BattleController.BattlePhase.FINISHED, "custom play uses the real victory rules")
	_check(FileAccess.get_file_as_string(wallet_path) == before, "custom victory cannot mint persistent shards")
	_check(CustomLevelBridge.design.to_dict() == design.to_dict(), "playing and winning never mutate the editor's source layout")
	resumed._begin_fresh_run()
	_check(resumed.controller.get_actor("vanguard_00").health == 4321, "restart rebuilds the same authored values")
	var key := InputEventKey.new()
	key.keycode = KEY_F2
	key.pressed = true
	Input.parse_input_event(key)
	await scene_changed
	_check(current_scene.scene_file_path == CustomLevelBridge.EDITOR_PATH, "the actual F2 shortcut returns to the editor without touching a detached viewport")
	_check(current_scene.design.to_dict() == design.to_dict(), "returning from play preserves all editor values")
	current_scene.queue_free()
	await process_frame
