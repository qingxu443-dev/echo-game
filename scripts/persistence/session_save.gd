class_name SessionSave
extends RefCounted

const VERSION := 1
const BATTLE_PATH := "res://scenes/main/main.tscn"
const MAP_PATH := "res://scenes/spring/spring_map.tscn"
static var pending: Dictionary = {}
static var path_override: String = ""
static var last_read_error: String = ""


static func path() -> String:
	if not path_override.is_empty(): return path_override
	if DisplayServer.get_name() == "headless":
		return "user://session_test_%d.json" % OS.get_process_id()
	return "user://suspended_journey.json"


static func write(data: Dictionary) -> bool:
	if not valid(data): return false
	return SaveFile.write_json(path(), {"version": VERSION, "data": SessionCodec.encode(data)})


static func read() -> Dictionary:
	last_read_error = ""
	if not FileAccess.file_exists(path()): return {}
	var file := FileAccess.open(path(), FileAccess.READ)
	if file == null: return _read_failure("暂停存档暂时无法读取")
	if file.get_length() > 8000000: return _read_failure("暂停存档超过可读取大小")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return _read_failure("暂停存档格式损坏")
	if parsed.get("version", 0) != VERSION: return _read_failure("暂停存档来自不支持的版本")
	var decoded := SessionCodec.decode_checked(parsed.get("data"))
	if not decoded.ok: return _read_failure("暂停存档包含无效编码数据")
	var data: Variant = decoded.value
	if not data is Dictionary or not valid(data): return _read_failure("暂停存档校验未通过")
	return data


static func _read_failure(message: String) -> Dictionary:
	last_read_error = message + "，原文件已保留。"
	return {}


static func valid(data: Dictionary) -> bool:
	if data.get("scene", "") == "map":
		if not data.get("run") is Dictionary: return false
		var run := SpringRun.from_dict(data.run)
		return run != null and SessionValidation.map_ui_error(data.get("ui", {}), run.template).is_empty()
	if data.get("scene", "") != "battle": return false
	for key in ["controller", "run_state", "ap", "ledger", "fx", "view", "bridge", "pressure_refunds"]:
		if not data.get(key, {}) is Dictionary: return false
	if not data.get("statuses", []) is Array: return false
	if not data.get("controller") is Dictionary or not data.get("ap") is Dictionary or not data.get("actors") is Array: return false
	if not data.get("intents") is Array or not data.get("run_state") is Dictionary: return false
	if data.actors.is_empty() or data.actors.size() > 64 or data.intents.size() > 256: return false
	if not SessionValidation.battle_fields_error(data).is_empty(): return false
	var state: Dictionary = data.controller
	var overrides: Variant = state.get("law_overrides", {})
	if not overrides is Dictionary: return false
	var base_ap: Variant = state.get("team_ap", 3)
	if not base_ap is int or base_ap < 1: return false
	var laws := EncounterLaws.resolve(overrides, base_ap)
	var active_k: Variant = state.get("attenuation_k", CombatMath.ATTENUATION_K)
	if laws.is_empty() or not active_k is int or active_k != laws.attenuation_k: return false
	if not overrides.is_empty():
		var maximum_ap: Variant = data.ap.get("maximum", 0)
		if not maximum_ap is int or maximum_ap != laws.ap_pool: return false
	var scaling: Variant = state.get("enemy_stat_multiplier", 1.0)
	if not (scaling is float or scaling is int): return false
	if not is_finite(float(scaling)) or float(scaling) <= 0.0: return false
	if not state.get("grid_size") is Vector2i: return false
	if state.grid_size.x < 1 or state.grid_size.y < 1 or state.grid_size.x > 32 or state.grid_size.y > 32: return false
	if state.get("phase", -1) not in [0, 1, 2, 3]: return false
	if not data.ap.get("maximum") is int or not data.ap.get("current") is int: return false
	if data.ap.maximum != laws.ap_pool or data.ap.current < 0 or data.ap.current > APBudget.temporary_limit(data.ap.maximum): return false
	var ids: Dictionary = {}
	var player_ids := {}
	for actor in data.actors:
		if not actor is Dictionary or not actor.get("cell") is Vector2i: return false
		var id := str(actor.get("actor_id", ""))
		if id.is_empty() or ids.has(id) or actor.get("team", "") not in ["player", "enemy"]: return false
		if int(actor.get("max_health", 0)) <= 0 or int(actor.get("health", -1)) < 0: return false
		if int(actor.health) > int(actor.max_health) or not GridRules.is_inside_bounds(actor.cell, state.grid_size): return false
		for key in ["attack", "defense", "magic_resistance"]:
			if not actor.get(key) is int or actor[key] < 0: return false
		for key in ["crit_rate", "crit_damage", "healing_efficiency"]:
			var attribute: Variant = actor.get(key, 0.0 if key != "crit_damage" else 150.0)
			if not (attribute is int or attribute is float) or not is_finite(float(attribute)) or float(attribute) < 0.0: return false
		if float(actor.get("crit_rate", 0.0)) > 100.0 or float(actor.get("crit_damage", 150.0)) < 100.0: return false
		var actor_k: Variant = actor.get("attenuation_k", CombatMath.ATTENUATION_K)
		if not actor_k is int or actor_k != laws.attenuation_k: return false
		if actor.team == "player":
			if not CharacterCatalog.has_definition(String(actor.get("character_id", ""))): return false
			player_ids[id] = true
		elif not EnemyCatalog.has_definition(str(actor.get("archetype", ""))): return false
		ids[id] = true
	if not player_ids.has(state.get("active_character_id", "")): return false
	var intent_ids := {}
	for intent in data.intents:
		if not intent is Dictionary or not ids.has(str(intent.get("source_actor_id", ""))): return false
		for key in ["intent_id", "action_id"]:
			if not intent.get(key) is String or str(intent[key]).is_empty(): return false
		if intent_ids.has(intent.intent_id) or not EnemySkillCatalog.has(StringName(intent.action_id)): return false
		intent_ids[intent.intent_id] = true
		if intent.get("state", 0) not in [0, 1, 2]: return false
		if int(intent.get("target_mode", -1)) not in [0, 1, 2, 3]: return false
		for key in ["affected_cells", "move_path", "hazard_cells"]:
			if not intent.get(key, []) is Array: return false
			for cell in intent.get(key, []):
				if not cell is Vector2i: return false
	for status in data.get("statuses", []):
		if not status is Dictionary or str(status.get("status_id", "")).is_empty(): return false
		if str(status.get("target_actor_id", "")).is_empty(): return false
	if data.has("custom_level"):
		if not data.custom_level is Dictionary or bool(data.get("spring_mode", false)): return false
		var design := CustomLevelData.from_dict(data.custom_level)
		return design != null and design.error(true).is_empty() and int(data.get("level", -1)) == 0
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
	if pending.has("custom_level"): return CustomLevelBridge.BATTLE_PATH
	return BATTLE_PATH if pending.scene == "battle" else MAP_PATH


static func consume(scene: String) -> Dictionary:
	if pending.get("scene", "") != scene: return {}
	var data := pending
	pending = {}
	return data


static func clear() -> void:
	pending = {}
	last_read_error = ""
	if FileAccess.file_exists(path()): DirAccess.remove_absolute(path())
