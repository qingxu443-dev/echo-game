class_name AtelierStash
extends RefCounted

## Meta-progression Atelier supply stash & expedition loadout (up to 3 slots).
##
## Players earn Atelier Shards (工坊残晶) from every Spring or Tutorial battle,
## unlock tactical counterplay recipes in the twilight Atelier hub, and pack up
## to 3 consumables into their starting backpack before departing.

const SAVE_PATH: String = "user://atelier_stash.json"
const MAX_LOADOUT: int = 3
const STARTING_SHARDS: int = 120

const RECIPES: Array[Dictionary] = [
	{
		"id": "item_dusk_potion", "name": "黄昏疗伤药", "cost": 0, "tag": "续航",
		"accent": "#6cb878", "desc": "立刻回复 1000 生命，稳住高压战线。",
		"payload": {"id": &"item_dusk_potion", "kind": "consumable", "kind_zh": "道具", "name": "黄昏疗伤药", "desc": "使用：立刻回复 1000 生命。", "heal": 1000},
	},
	{
		"id": "item_echo_hourglass", "name": "回声沙漏", "cost": 0, "tag": "节奏",
		"accent": "#8fc7dc", "desc": "本回合 +1 AP（不给敌方充能），衔接连招。",
		"payload": {"id": &"item_echo_hourglass", "kind": "consumable", "kind_zh": "道具", "name": "回声沙漏", "desc": "使用：本回合立刻获得 +1 行动点（不给敌方充能）。", "ap_gain": 1},
	},
	{
		"id": "item_vow_talisman", "name": "誓约护符", "cost": 0, "tag": "防护",
		"accent": "#d4b77b", "desc": "获得 650 护盾与 +1 能量，硬吃 Boss 重击。",
		"payload": {"id": &"item_vow_talisman", "kind": "consumable", "kind_zh": "道具", "name": "誓约护符", "desc": "使用：获得 650 护盾并 +1 终极能量。", "shield_gain": 650, "energy_gain": 1},
	},
	{
		"id": "item_armor_bomb", "name": "破甲爆弹", "cost": 40, "tag": "破甲",
		"accent": "#e07a5f", "desc": "全场敌方重甲 -1 层并造成 350 真伤（不涨容忍）。",
		"payload": {"id": &"item_armor_bomb", "kind": "consumable", "kind_zh": "道具", "name": "破甲爆弹", "desc": "使用：震碎全场敌方 1 层重甲并造成 350 真伤。", "armor_break": 1, "aoe_true_damage": 350},
	},
	{
		"id": "item_calm_sachet", "name": "镇定香囊", "cost": 40, "tag": "破反击",
		"accent": "#74ebd5", "desc": "清空全场敌方近战容忍条，且敌方技能充能 -1。",
		"payload": {"id": &"item_calm_sachet", "kind": "consumable", "kind_zh": "道具", "name": "镇定香囊", "desc": "使用：清空全场敌方近战容忍条且敌方充能 -1。", "clear_tolerance": true, "drain_charge": 1},
	},
	{
		"id": "item_sakura_charm", "name": "瞬影樱符", "cost": 60, "tag": "爆发",
		"accent": "#e89ab0", "desc": "+2 剑意（无剑意则 +2 能量）与 450 护盾。",
		"payload": {"id": &"item_sakura_charm", "kind": "consumable", "kind_zh": "道具", "name": "瞬影樱符", "desc": "使用：获得 +2 剑意/能量与 450 护盾。", "resource_gain": 2, "shield_gain": 450},
	},
]


static func _default_state() -> Dictionary:
	return {
		"shards": STARTING_SHARDS,
		"unlocked": ["item_dusk_potion", "item_echo_hourglass", "item_vow_talisman"],
		"loadout": ["item_dusk_potion", "item_echo_hourglass", "item_vow_talisman"],
	}


static func load_state(path: String = SAVE_PATH) -> Dictionary:
	var state := _default_state()
	if not FileAccess.file_exists(path):
		return state
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return state
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return state
	state["shards"] = maxi(0, int(parsed.get("shards", STARTING_SHARDS)))
	var unlocked: Array[String] = []
	for u in parsed.get("unlocked", []):
		var sid := str(u)
		if not recipe_by_id(sid).is_empty() and not unlocked.has(sid):
			unlocked.append(sid)
	for base_id in ["item_dusk_potion", "item_echo_hourglass", "item_vow_talisman"]:
		if not unlocked.has(base_id):
			unlocked.append(base_id)
	state["unlocked"] = unlocked
	var loadout: Array[String] = []
	for lid in parsed.get("loadout", []):
		var sid := str(lid)
		if unlocked.has(sid) and loadout.size() < MAX_LOADOUT:
			loadout.append(sid)
	state["loadout"] = loadout
	return state


static func save_state(state: Dictionary, path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state, "\t"))
	return true


static func recipe_by_id(item_id: String) -> Dictionary:
	for r in RECIPES:
		if str(r["id"]) == item_id:
			return r
	return {}


static func is_unlocked(state: Dictionary, item_id: String) -> bool:
	return (state.get("unlocked", []) as Array).has(item_id)


static func unlock_recipe(state: Dictionary, item_id: String, path: String = SAVE_PATH) -> Dictionary:
	var r := recipe_by_id(item_id)
	if r.is_empty():
		return {"ok": false, "message": "未知配方。"}
	if is_unlocked(state, item_id):
		return {"ok": true, "message": "已掌握该配方。"}
	var cost: int = int(r.get("cost", 0))
	var shards: int = int(state.get("shards", 0))
	if shards < cost:
		return {"ok": false, "message": "工坊残晶不足（需要 %d，现有 %d）。" % [cost, shards]}
	state["shards"] = shards - cost
	var unlocked: Array = state.get("unlocked", [])
	unlocked.append(item_id)
	state["unlocked"] = unlocked
	save_state(state, path)
	return {"ok": true, "message": "已解锁配方「%s」！" % str(r["name"])}


static func add_to_loadout(state: Dictionary, item_id: String, path: String = SAVE_PATH) -> Dictionary:
	if not is_unlocked(state, item_id):
		return {"ok": false, "message": "请先解锁该配方。"}
	var loadout: Array = state.get("loadout", [])
	if loadout.size() >= MAX_LOADOUT:
		return {"ok": false, "message": "出征行囊已满（最多 %d 件），点击上方槽位可卸下。" % MAX_LOADOUT}
	loadout.append(item_id)
	state["loadout"] = loadout
	save_state(state, path)
	return {"ok": true, "message": "已将「%s」装入出征行囊。" % str(recipe_by_id(item_id).get("name", item_id))}


static func remove_from_loadout(state: Dictionary, slot_index: int, path: String = SAVE_PATH) -> Dictionary:
	var loadout: Array = state.get("loadout", [])
	if slot_index < 0 or slot_index >= loadout.size():
		return {"ok": false, "message": ""}
	var removed_id: String = str(loadout[slot_index])
	loadout.remove_at(slot_index)
	state["loadout"] = loadout
	save_state(state, path)
	return {"ok": true, "message": "已从行囊卸下「%s」。" % str(recipe_by_id(removed_id).get("name", removed_id))}


static func award_shards(amount: int, path: String = SAVE_PATH) -> int:
	if amount <= 0:
		return 0
	var state := load_state(path)
	state["shards"] = int(state.get("shards", 0)) + amount
	save_state(state, path)
	return int(state["shards"])


static func build_loadout_items(path: String = SAVE_PATH) -> Array[Dictionary]:
	var state := load_state(path)
	var items: Array[Dictionary] = []
	for lid in state.get("loadout", []):
		var r := recipe_by_id(str(lid))
		if r.is_empty():
			continue
		var p: Dictionary = (r.get("payload", {}) as Dictionary).duplicate(true)
		p["enemy_buff_zh"] = ""
		p["enemy_attack"] = 0
		p["enemy_shield"] = 0
		p["enemy_heal"] = 0
		p["enemy_charge"] = false
		items.append(p)
	return items
