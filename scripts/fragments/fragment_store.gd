class_name FragmentStore
extends RefCounted

const SAVE_PATH := "user://save_slots/default/fragments.json"
const VERSION := 1
const SLOT_COUNT := FragmentCatalog.SLOT_COUNT
const CAPACITY_LIMIT := FragmentCatalog.CAPACITY_LIMIT

var modules: Array[Dictionary] = []
var equipped_by_character: Dictionary = {}
var revision: int = 0
var path_override: String = ""
static var default_path_override: String = ""


## Applies a character's equipped health modules to a base maximum. Shared by
## the map and battle layers so both agree on the cap the player sees.
static func health_max(character_id: String, base: int) -> int:
	var store := load_store()
	if store == null:
		return base
	var pct := store.total_bonus(character_id, "health")
	return maxi(base, roundi(float(base) * (1.0 + pct / 100.0)))


static func load_store(path: String = "") -> FragmentStore:
	var store := FragmentStore.new()
	var resolved_path := path
	if resolved_path.is_empty():
		resolved_path = default_path_override if not default_path_override.is_empty() else SAVE_PATH
	store.path_override = resolved_path
	path = resolved_path
	if not FileAccess.file_exists(path):
		return store
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION:
		return null
	if not parsed.get("modules", []) is Array or not parsed.get("equipped", {}) is Dictionary:
		return null
	store.modules = []
	for item in parsed.get("modules", []):
		if not item is Dictionary or not FragmentCatalog.validate_module(item):
			return null
		store.modules.append(item.duplicate(true))
	store.equipped_by_character = parsed.get("equipped", {}).duplicate(true)
	store.revision = maxi(0, int(parsed.get("revision", 0)))
	if not store.validate_equipment():
		return null
	return store


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"revision": revision,
		"modules": modules.duplicate(true),
		"equipped": equipped_by_character.duplicate(true),
	}


func save() -> bool:
	if path_override == SAVE_PATH and DisplayServer.get_name() == "headless":
		return true
	var absolute := ProjectSettings.globalize_path(path_override)
	var directory := absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK and not DirAccess.dir_exists_absolute(directory):
		return false
	if not validate_equipment():
		return false
	var next := revision + 1
	var data := to_dict()
	data["revision"] = next
	if not SaveFile.write_json(path_override, data):
		return false
	revision = next
	return true


func validate_equipment() -> bool:
	var ids := {}
	for module in modules:
		if not FragmentCatalog.validate_module(module):
			return false
		var instance_id := str(module.instance_id)
		if ids.has(instance_id):
			return false
		ids[instance_id] = true
	var used := {}
	for character_id in equipped_by_character:
		var slots: Variant = equipped_by_character[character_id]
		if not slots is Array or slots.size() > SLOT_COUNT:
			return false
		var capacity := 0
		for module_id in slots:
			var id := str(module_id)
			if id.is_empty():
				continue
			if not ids.has(id) or used.has(id):
				return false
			used[id] = true
			capacity += FragmentCatalog.capacity_of(str(module_by_id(id).get("size", "")))
		if capacity > CAPACITY_LIMIT:
			return false
	return true


func module_by_id(instance_id: String) -> Dictionary:
	for module in modules:
		if str(module.get("instance_id", "")) == instance_id:
			return module
	return {}


func equipped_ids(character_id: String) -> Array[String]:
	var result: Array[String] = []
	var slots: Array = equipped_by_character.get(character_id, [])
	for id in slots:
		if not str(id).is_empty():
			result.append(str(id))
	return result


func equipped_capacity(character_id: String) -> int:
	var total := 0
	for id in equipped_ids(character_id):
		total += FragmentCatalog.capacity_of(str(module_by_id(id).get("size", "")))
	return total


func total_bonus(character_id: String, stat: String) -> float:
	var total := 0.0
	for id in equipped_ids(character_id):
		var attrs: Dictionary = module_by_id(id).get("attributes", {})
		total += float(attrs.get(stat, 0.0))
	return total


func available_modules(character_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var own := {}
	for id in equipped_ids(character_id):
		own[id] = true
	for module in modules:
		var id := str(module.get("instance_id", ""))
		if own.has(id) or not _is_equipped_elsewhere(id):
			result.append(module.duplicate(true))
	return result


func _is_equipped_elsewhere(instance_id: String) -> bool:
	for character_id in equipped_by_character:
		for id in equipped_by_character[character_id]:
			if str(id) == instance_id:
				return true
	return false


func install(character_id: String, slot_index: int, instance_id: String) -> Dictionary:
	if character_id.is_empty() or slot_index < 0 or slot_index >= SLOT_COUNT:
		return {"ok": false, "message": "槽位无效。"}
	var module := module_by_id(instance_id)
	if module.is_empty():
		return {"ok": false, "message": "找不到该模块。"}
	var slots: Array = equipped_by_character.get(character_id, [])
	while slots.size() < SLOT_COUNT:
		slots.append("")
	for index in range(slots.size()):
		if index != slot_index and str(slots[index]) == instance_id:
			return {"ok": false, "message": "同一模块实例不能安装在两个槽位。"}
	if _is_equipped_elsewhere(instance_id) and not equipped_ids(character_id).has(instance_id):
		return {"ok": false, "message": "该模块已装备给其他角色。"}
	var old_id := str(slots[slot_index])
	if old_id == instance_id:
		return {"ok": true, "message": "该槽位已经安装此模块。"}
	var used_capacity := equipped_capacity(character_id)
	if not old_id.is_empty():
		used_capacity -= FragmentCatalog.capacity_of(str(module_by_id(old_id).get("size", "")))
	var next_capacity := used_capacity + FragmentCatalog.capacity_of(str(module.size))
	if next_capacity > CAPACITY_LIMIT:
		return {"ok": false, "message": "容量不足：需要 %d，剩余 %d。" % [FragmentCatalog.capacity_of(str(module.size)), CAPACITY_LIMIT - used_capacity]}
	slots[slot_index] = instance_id
	equipped_by_character[character_id] = slots
	return {"ok": true, "message": "模块已安装。"}


func uninstall(character_id: String, slot_index: int) -> Dictionary:
	var slots: Array = equipped_by_character.get(character_id, [])
	if slot_index < 0 or slot_index >= slots.size() or str(slots[slot_index]).is_empty():
		return {"ok": false, "message": "该槽位没有模块。"}
	slots[slot_index] = ""
	equipped_by_character[character_id] = slots
	return {"ok": true, "message": "模块已卸下，可转移给其他角色。"}


func apply_loadout(character_id: String, instance_ids: Array[String]) -> Dictionary:
	if character_id.is_empty() or instance_ids.size() > SLOT_COUNT:
		return {"ok": false, "message": "构筑或槽位数据无效。"}
	var slots: Array = []
	var used := {}
	var capacity := 0
	for id in instance_ids:
		var module := module_by_id(id)
		if module.is_empty() or used.has(id):
			return {"ok": false, "message": "推荐配置包含无效或重复模块。"}
		if _is_equipped_elsewhere(id) and not equipped_ids(character_id).has(id):
			return {"ok": false, "message": "推荐配置包含其他角色正在使用的模块。"}
		used[id] = true
		capacity += FragmentCatalog.capacity_of(str(module.size))
		slots.append(id)
	if capacity > CAPACITY_LIMIT:
		return {"ok": false, "message": "推荐配置超过容量上限。"}
	while slots.size() < SLOT_COUNT:
		slots.append("")
	equipped_by_character[character_id] = slots
	return {"ok": true, "message": "构筑已应用。"}


func add_modules(new_modules: Array[Dictionary]) -> bool:
	var known := {}
	for module in modules:
		known[str(module.instance_id)] = true
	for module in new_modules:
		if not FragmentCatalog.validate_module(module) or known.has(str(module.instance_id)):
			return false
		known[str(module.instance_id)] = true
	for module in new_modules:
		modules.append(module.duplicate(true))
	return true
