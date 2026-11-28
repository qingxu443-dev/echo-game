class_name CustomLevelBridge
extends RefCounted

const EDITOR_PATH := "res://scenes/custom/custom_editor.tscn"
const BATTLE_PATH := "res://scenes/custom/custom_battle.tscn"
static var design: CustomLevelData
static var selected: Vector2i = Vector2i(-1, -1)
static var draft_override: String = ""


static func save_file(level: CustomLevelData, path: String) -> bool:
	return level != null and level.error().is_empty() and SaveFile.write_json(path, level.to_dict())


static func load_file(path: String) -> CustomLevelData:
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1000000: return null
	var value: Variant = JSON.parse_string(file.get_as_text())
	return CustomLevelData.from_dict(value) if value is Dictionary else null


static func draft_path() -> String:
	if not draft_override.is_empty(): return draft_override
	return "user://custom_draft_%d.json" % OS.get_process_id() if DisplayServer.get_name() == "headless" else "user://custom_level_draft.json"
