extends "res://tests/framework/test_case.gd"

var path := "user://squad_validation_%d.json" % OS.get_process_id()


func _state() -> Dictionary:
	return {"version": 1, "active_team": 1, "teams": [
		{"name": "樱队", "members": ["sakura"]},
		{"name": "协作队", "members": ["sevrin", "dest_lee"]},
		{"name": "预备队", "members": []},
	]}


func _bad_states() -> Array:
	var result: Array = []
	for row in [["version", 2], ["version", "1"], ["version", 1.5], ["active_team", 3], ["active_team", -1], ["active_team", "1"], ["active_team", 1.5], ["teams", []]]:
		var data := _state()
		data[row[0]] = row[1]
		result.append(data)
	for members in [["missing_character"], ["sakura", "sakura"], ["sakura", "sevrin", "dest_lee", "sakura"], [], "sakura", 9, [2]]:
		var data := _state()
		data.teams[1].members = members
		result.append(data)
	var bad_name := _state()
	bad_name.teams[2].name = []
	result.append(bad_name)
	return result


func _run() -> void:
	_test_bad_disk_edits()
	_test_bad_new_states()
	_test_normal_flow_and_legacy()
	_test_reader_diagnostic()
	_cleanup()


func _edit(action: String) -> bool:
	match action:
		"name": return SquadLoadoutStore.set_team_name(0, "新队", path)
		"active": return SquadLoadoutStore.set_active_team(0, path)
		"members":
			var members: Array[String] = ["sakura", "dest_lee"]
			return SquadLoadoutStore.set_team_members(0, members, path)
	return SquadLoadoutStore.save_state(_state(), path)


func _test_bad_disk_edits() -> void:
	var texts: Array[String] = ['{"teams":']
	for data in _bad_states(): texts.append(JSON.stringify(data))
	for raw in texts:
		for action in ["name", "active", "members", "save"]:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(raw)
			file.close()
			_check(not _edit(action), "malformed or future squad file cannot authorize " + action)
			_check(FileAccess.get_file_as_string(path) == raw, "failed edit preserves every byte of the original file")
			_check(SquadLoadoutStore.last_error.contains("保留"), "failed edit explains that the original squad file was preserved")


func _test_bad_new_states() -> void:
	for data in _bad_states():
		SaveFile.write_json(path, _state())
		var before := FileAccess.get_file_as_string(path)
		_check(not SquadLoadoutStore.save_state(data, path), "invalid proposed squad state is rejected")
		_check(FileAccess.get_file_as_string(path) == before, "invalid proposed state leaves valid squads unchanged")


func _test_normal_flow_and_legacy() -> void:
	_cleanup()
	_check(SquadLoadoutStore.load_state(path).teams[0].members == ["sakura"], "absent file uses the existing default party")
	_check(SquadLoadoutStore.save_state(_state(), path), "valid first save is permitted")
	_check(SquadLoadoutStore.load_state(path) == _state(), "valid order, names and active team round-trip")
	_check(SquadLoadoutStore.set_team_name(1, "  支援队  ", path), "normal rename succeeds")
	_check(SquadLoadoutStore.load_state(path).teams[1].name == "支援队", "rename keeps existing whitespace normalization")
	_check(SquadLoadoutStore.set_active_team(0, path), "normal active-team change succeeds")
	var members: Array[String] = ["sakura", "dest_lee"]
	_check(SquadLoadoutStore.set_team_members(0, members, path), "normal member edit succeeds")
	_check(SquadLoadoutStore.active_character_ids(path) == members, "battle selection receives the saved member order")
	_check(not SquadLoadoutStore.set_active_team(2, path), "empty reserve team is not activated")
	var legacy := _state()
	legacy.erase("version")
	SaveFile.write_json(path, legacy)
	_check(SquadLoadoutStore.load_state(path) == _state(), "missing legacy version defaults to the current schema")
	_cleanup()
	_check(DirAccess.make_dir_absolute(path) == OK, "block the destination with a directory")
	_check(not SquadLoadoutStore.set_team_name(0, "无法保存", path) and DirAccess.dir_exists_absolute(path), "write failure retains the existing destination")
	DirAccess.remove_absolute(path)


func _cleanup() -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)


func _test_reader_diagnostic() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"teams":')
	file.close()
	_check(SquadLoadoutStore.read_state(path).is_empty() and SquadLoadoutStore.last_error.contains("保留"), "strict read distinguishes a damaged file from an absent file")
	_check(SquadLoadoutStore.load_state(path).teams[0].members == ["sakura"], "display fallback remains usable")
	_check(FileAccess.get_file_as_string(path) == '{"teams":', "display fallback never writes over the damaged file")
	_cleanup()
	_check(not SquadLoadoutStore.save_state({"teams": []}, path) and not FileAccess.file_exists(path), "invalid first save does not create a file")
