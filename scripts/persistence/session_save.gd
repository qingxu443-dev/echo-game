class_name SessionSave
extends RefCounted

const VERSION := 1
const BATTLE_PATH := "res://scenes/main/main.tscn"
const MAP_PATH := "res://scenes/spring/spring_map.tscn"
static var pending: Dictionary = {}
static var path_override: String = ""


static func path() -> String:
	if not path_override.is_empty(): return path_override
	if DisplayServer.get_name() == "headless":
		return "user://session_test_%d.json" % OS.get_process_id()
	return "user://suspended_journey.json"


static func write(data: Dictionary) -> bool:
	if not valid(data): return false
	return SaveFile.write_json(path(), {"version": VERSION, "data": SessionCodec.encode(data)})


static func read() -> Dictionary:
	if not FileAccess.file_exists(path()): return {}
	var file := FileAccess.open(path(), FileAccess.READ)
	if file == null or file.get_length() > 8000000: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("version", 0) != VERSION: return {}
	var data: Variant = SessionCodec.decode(parsed.get("data"))
	return data if data is Dictionary and valid(data) else {}


static func valid(data: Dictionary) -> bool:
	if data.get("scene", "") == "map":
		return data.get("run") is Dictionary and SpringRun.from_dict(data.run) != null
	if data.get("scene", "") != "battle": return false
	for key in ["controller", "run_state", "ap", "ledger", "fx", "view", "bridge", "pressure_refunds"]:
		if not data.get(key, {}) is Dictionary: return false
	if not data.get("statuses", []) is Array: return false
	if not data.get("controller") is Dictionary or not data.get("actors") is Array: return false
	if not data.get("intents") is Array or not data.get("run_state") is Dictionary: return false
	if data.actors.is_empty() or data.actors.size() > 64 or data.intents.size() > 256: return false
	var state: Dictionary = data.controller
	var overrides: Variant = state.get("law_overrides", {})
	if not overrides is Dictionary: return false
	var laws := EncounterLaws.resolve(overrides, int(state.get("team_ap", 3)))
	if laws.is_empty() or state.get("attenuation_k", CombatMath.ATTENUATION_K) != laws.attenuation_k: return false
	if not overrides.is_empty() and data.ap.get("maximum", 0) != laws.ap_pool: return false
	var scaling: Variant = state.get("enemy_stat_multiplier", 1.0)
	if not (scaling is float or scaling is int): return false
	if not is_finite(float(scaling)) or float(scaling) <= 0.0: return false
	if not state.get("grid_size") is Vector2i: return false
	if state.grid_size.x < 1 or state.grid_size.y < 1 or state.grid_size.x > 32 or state.grid_size.y > 32: return false
	if int(state.get("phase", -1)) not in [0, 1, 2, 3]: return false
	if not data.get("ap") is Dictionary or int(data.ap.get("current", -1)) < 0: return false
	var ids: Dictionary = {}
	for actor in data.actors:
		if not actor is Dictionary or not actor.get("cell") is Vector2i: return false
		var id := str(actor.get("actor_id", ""))
		if id.is_empty() or ids.has(id) or actor.get("team", "") not in ["player", "enemy"]: return false
		if int(actor.get("max_health", 0)) <= 0 or int(actor.get("health", -1)) < 0: return false
		if int(actor.health) > int(actor.max_health) or not GridRules.is_inside_bounds(actor.cell, state.grid_size): return false
		if actor.get("attenuation_k", CombatMath.ATTENUATION_K) != laws.attenuation_k: return false
		ids[id] = true
	for intent in data.intents:
		if not intent is Dictionary or not ids.has(str(intent.get("source_actor_id", ""))): return false
		for key in ["intent_id", "action_id"]:
			if not intent.get(key) is String or str(intent[key]).is_empty(): return false
		if int(intent.get("target_mode", -1)) not in [0, 1, 2, 3]: return false
		for key in ["affected_cells", "move_path", "hazard_cells"]:
			if not intent.get(key, []) is Array: return false
			for cell in intent.get(key, []):
				if not cell is Vector2i: return false
	for status in data.get("statuses", []):
		if not status is Dictionary or str(status.get("status_id", "")).is_empty(): return false
		if str(status.get("target_actor_id", "")).is_empty(): return false
	if bool(data.get("spring_mode", false)):
		return data.get("parent_run") is Dictionary and SpringRun.from_dict(data.parent_run) != null and SpringEncounterCatalog.has_encounter(StringName(str(data.get("bridge", {}).get("encounter", ""))))
	var override_id: Variant = data.get("encounter_override_id", "")
	if not override_id is String: return false
	if not override_id.is_empty():
		return LevelCatalog.optional_encounter(StringName(override_id)) != null and int(data.get("level", -1)) == 0
	return int(data.get("level", -1)) >= 0 and int(data.get("level", -1)) < LevelCatalog.create_prototype_levels().size()


static func stage() -> String:
	pending = read()
	if pending.is_empty(): return ""
	return BATTLE_PATH if pending.scene == "battle" else MAP_PATH


static func consume(scene: String) -> Dictionary:
	if pending.get("scene", "") != scene: return {}
	var data := pending
	pending = {}
	return data


static func clear() -> void:
	pending = {}
	if FileAccess.file_exists(path()): DirAccess.remove_absolute(path())
