class_name SquadLoadoutStore
extends RefCounted

## Persistent hub loadouts. Tutorial encounters deliberately never read this store.
const SAVE_PATH: String = "user://squad_loadouts.json"
const TEAM_COUNT: int = 3
const PARTY_LIMIT: int = 3
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
static var last_error: String = ""

static func _default_state() -> Dictionary:
	return {
		"version": 1,
		"active_team": 0,
		"teams": [
			{"name": "编队1", "members": ["sakura"]},
			{"name": "编队2", "members": []},
			{"name": "编队3", "members": []},
		],
	}

static func load_state(path: String = SAVE_PATH) -> Dictionary:
	var state := read_state(path)
	return _default_state() if state.is_empty() else state


## CONTRACT: _test_bad_disk_edits
static func read_state(path: String = SAVE_PATH) -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(path):
		return _default_state()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _read_failure()
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK: return _read_failure()
	var state := from_dict(parser.data)
	return _read_failure() if state.is_empty() else state


static func _read_failure() -> Dictionary:
	last_error = "编队存档无法读取或来自不支持的版本，原文件已保留。"
	return {}


## CONTRACT: _test_bad_new_states
static func from_dict(data: Variant) -> Dictionary:
	if not data is Dictionary or not data.get("teams") is Array: return {}
	if not _whole(data.get("version", 1)) or data.get("version", 1) != 1: return {}
	var active: Variant = data.get("active_team", 0)
	if not _whole(active) or active < 0 or active >= TEAM_COUNT: return {}
	var teams: Array = data.teams
	if teams.size() != TEAM_COUNT: return {}
	var state := {"version": 1, "active_team": int(active), "teams": []}
	for index in range(TEAM_COUNT):
		var saved: Variant = teams[index]
		if not saved is Dictionary or not saved.get("name", "") is String or not saved.get("members", []) is Array: return {}
		var name: String = saved.get("name", "编队%d" % (index + 1)).strip_edges()
		if name.is_empty():
			name = "编队%d" % (index + 1)
		var members: Array[String] = []
		var seen: Dictionary = {}
		for raw_id in saved.get("members", []):
			if not (raw_id is String or raw_id is StringName): return {}
			var character_id := str(raw_id)
			if not CharacterCatalogScript.has_definition(character_id) or seen.has(character_id) or members.size() >= PARTY_LIMIT: return {}
			seen[character_id] = true
			members.append(character_id)
		state.teams.append({"name": name.left(12), "members": members})
	if state.teams[int(active)].members.is_empty(): return {}
	return state


static func _whole(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))


static func save_state(state: Dictionary, path: String = SAVE_PATH) -> bool:
	last_error = ""
	var validated := from_dict(state)
	if validated.is_empty():
		last_error = "编队数据无效，未保存。"
		return false
	if read_state(path).is_empty(): return false
	if SaveFile.write_json(path, validated): return true
	last_error = "编队写入失败，原文件已保留。"
	return false

static func active_character_ids(path: String = SAVE_PATH) -> Array[String]:
	var state := load_state(path)
	var team: Dictionary = state.teams[int(state.active_team)]
	var result: Array[String] = []
	for raw_id in team.get("members", []):
		var character_id := str(raw_id)
		if CharacterCatalogScript.has_definition(character_id):
			result.append(character_id)
	if result.is_empty():
		result.append("sakura")
	return result

static func set_active_team(index: int, path: String = SAVE_PATH) -> bool:
	last_error = ""
	if index < 0 or index >= TEAM_COUNT:
		return false
	var state := read_state(path)
	if state.is_empty(): return false
	var team: Dictionary = state.teams[index]
	var members: Array = team.get("members", [])
	if members.is_empty():
		return false
	state["active_team"] = index
	return save_state(state, path)

static func set_team_name(index: int, value: String, path: String = SAVE_PATH) -> bool:
	last_error = ""
	if index < 0 or index >= TEAM_COUNT:
		return false
	var cleaned := value.strip_edges()
	if cleaned.is_empty():
		return false
	var state := read_state(path)
	if state.is_empty(): return false
	var team: Dictionary = state.teams[index]
	team["name"] = cleaned.left(12)
	state.teams[index] = team
	return save_state(state, path)

static func set_team_members(index: int, values: Array[String], path: String = SAVE_PATH) -> bool:
	last_error = ""
	if index < 0 or index >= TEAM_COUNT or values.size() > PARTY_LIMIT:
		return false
	var members: Array[String] = []
	var seen: Dictionary = {}
	for character_id in values:
		if not CharacterCatalogScript.has_definition(character_id) or seen.has(character_id):
			return false
		seen[character_id] = true
		members.append(character_id)
	var state := read_state(path)
	if state.is_empty(): return false
	if members.is_empty() and index == int(state.active_team):
		return false
	var team: Dictionary = state.teams[index]
	team["members"] = members
	state.teams[index] = team
	return save_state(state, path)

static func team_name(index: int, path: String = SAVE_PATH) -> String:
	if index < 0 or index >= TEAM_COUNT:
		return ""
	return str(load_state(path).teams[index].get("name", "编队%d" % (index + 1)))

static func active_team_index(path: String = SAVE_PATH) -> int:
	return int(load_state(path).get("active_team", 0))
