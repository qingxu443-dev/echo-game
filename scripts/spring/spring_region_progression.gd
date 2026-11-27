class_name SpringRegionProgression
extends RefCounted

## Region order, persistent unlocks and the handoff between seasonal regions.
## A region is enterable only when it is unlocked and its scene exists.

const REGION_SPRING: StringName = &"spring"
const REGION_SUMMER: StringName = &"summer"
const UNLOCK_SAVE_PATH: String = "user://region_progression.cfg"

const REGION_NAMES := {
	"spring": "春之境",
	"summer": "夏之境",
}

const NEXT_REGION := {
	"spring": "summer",
}

const REGION_SCENE_PATHS := {
	"spring": "res://scenes/spring/spring_map.tscn",
	"summer": "res://scenes/summer/summer_map.tscn",
}

## Static handoff survives change_scene_to_file, just like the battle bridge.
static var pending_transition: Dictionary = {}


static func scene_path_for(region_id: StringName) -> String:
	return str(REGION_SCENE_PATHS.get(String(region_id), ""))


## 春之境 is available in a fresh profile. Further unlocks persist separately
## from the per-run spring save and therefore survive ending or deleting a run.
static func get_unlocked_region_ids(save_path: String = UNLOCK_SAVE_PATH) -> Array[StringName]:
	var unlocked: Array[StringName] = [REGION_SPRING]
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return unlocked
	var saved: Variant = config.get_value("progression", "unlocked_regions", [])
	if saved is Array:
		for value in saved:
			var region_id := StringName(str(value))
			if REGION_NAMES.has(String(region_id)) and not unlocked.has(region_id):
				unlocked.append(region_id)
	return unlocked


## Called by the account/progression reward that unlocks a region. Unknown ids
## are rejected; an already-unlocked region is an idempotent success.
static func unlock_region(region_id: StringName, save_path: String = UNLOCK_SAVE_PATH) -> bool:
	if not REGION_NAMES.has(String(region_id)):
		return false
	var unlocked := get_unlocked_region_ids(save_path)
	if not unlocked.has(region_id):
		unlocked.append(region_id)
	var config := ConfigFile.new()
	var load_error := config.load(save_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return false
	var stored: Array[String] = []
	for unlocked_id in unlocked:
		stored.append(String(unlocked_id))
	config.set_value("progression", "unlocked_regions", stored)
	return config.save(save_path) == OK


## The caller supplies current unlock data and the result of checking the scene.
## Keeping these separate prevents an unlocked-but-unimplemented region from
## producing a broken scene change.
static func resolve_next(
	region_id: StringName,
	unlocked_region_ids: Array = [],
	scene_available: bool = false
) -> Dictionary:
	var next_id := StringName(str(NEXT_REGION.get(String(region_id), "")))
	if next_id == &"":
		return {
			"from_region": region_id,
			"next_region": &"",
			"next_region_name": "",
			"status": "complete",
			"is_unlocked": false,
			"scene_available": false,
			"can_enter": false,
			"scene_path": "",
		}

	var unlocked: bool = unlocked_region_ids.has(next_id)
	var status := "locked"
	if unlocked:
		status = "available" if scene_available else "content_unavailable"
	return {
		"from_region": region_id,
		"next_region": next_id,
		"next_region_name": str(REGION_NAMES.get(String(next_id), String(next_id))),
		"status": status,
		"is_unlocked": unlocked,
		"scene_available": scene_available,
		"can_enter": unlocked and scene_available,
		"scene_path": scene_path_for(next_id),
	}


static func set_pending_transition(run, transition: Dictionary) -> void:
	pending_transition = {
		"run": run,
		"region_transition": transition.duplicate(true),
	}


static func consume_pending_transition() -> Dictionary:
	var result: Dictionary = pending_transition
	pending_transition = {}
	return result


static func clear_pending_transition() -> void:
	pending_transition = {}
