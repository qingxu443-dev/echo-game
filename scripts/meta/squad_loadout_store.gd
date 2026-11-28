class_name SquadLoadoutStore
extends RefCounted

## Persistent hub loadouts. Tutorial encounters deliberately never read this store.
const SAVE_PATH: String = "user://squad_loadouts.json"
const TEAM_COUNT: int = 3
const PARTY_LIMIT: int = 3
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")

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
	if not FileAccess.file_exists(path):
		return _default_state()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _default_state()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("teams", []) is Array:
		return _default_state()
	var teams: Array = parsed.get("teams", [])
	if teams.size() != TEAM_COUNT:
		return _default_state()
	var state := _default_state()
	state["active_team"] = clampi(int(parsed.get("active_team", 0)), 0, TEAM_COUNT - 1)
	for index in range(TEAM_COUNT):
		var saved: Variant = teams[index]
		if not saved is Dictionary:
			continue
		var name := str(saved.get("name", "编队%d" % (index + 1))).strip_edges()
		if name.is_empty():
			name = "编队%d" % (index + 1)
		var members: Array[String] = []
		var seen: Dictionary = {}
		for raw_id in saved.get("members", []):
			var character_id := str(raw_id)
			if character_id.is_empty() or seen.has(character_id) or members.size() >= PARTY_LIMIT:
				continue
			seen[character_id] = true
			members.append(character_id)
		state["teams"][index] = {"name": name.left(12), "members": members}
	return state

static func save_state(state: Dictionary, path: String = SAVE_PATH) -> bool:
	if path == SAVE_PATH and DisplayServer.get_name() == "headless":
		return true
	if state.get("teams", []) is not Array or state.teams.size() != TEAM_COUNT:
		return false
	if int(state.get("active_team", -1)) < 0 or int(state.get("active_team", -1)) >= TEAM_COUNT:
		return false
	return SaveFile.write_json(path, state)

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
	if index < 0 or index >= TEAM_COUNT:
		return false
	var state := load_state(path)
	state["active_team"] = index
	return save_state(state, path)

static func set_team_name(index: int, value: String, path: String = SAVE_PATH) -> bool:
	if index < 0 or index >= TEAM_COUNT:
		return false
	var cleaned := value.strip_edges()
	if cleaned.is_empty():
		return false
	var state := load_state(path)
	var team: Dictionary = state.teams[index]
	team["name"] = cleaned.left(12)
	state.teams[index] = team
	return save_state(state, path)

static func set_team_members(index: int, values: Array[String], path: String = SAVE_PATH) -> bool:
	if index < 0 or index >= TEAM_COUNT or values.size() > PARTY_LIMIT:
		return false
	var members: Array[String] = []
	var seen: Dictionary = {}
	for character_id in values:
		if not CharacterCatalogScript.has_definition(character_id) or seen.has(character_id):
			return false
		seen[character_id] = true
		members.append(character_id)
	var state := load_state(path)
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
