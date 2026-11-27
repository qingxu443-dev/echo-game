class_name AtelierStash
extends RefCounted

## Meta-progression Atelier supply stash & unlimited shard-funded loadout.
##
## Players earn Atelier Shards (工坊残晶) from every battle (win or defeat) and
## may brew and pack ANY number of tactical consumables as long as they have
## enough shards. Removing an item before departure refunds its full shard cost.
## Packing items into an expedition consumes them from the staging bag on depart.

const SAVE_PATH: String = "user://atelier_stash.json"
const STARTING_SHARDS: int = 120

const RECIPES: Array[Dictionary] = [
	{
		"id": "item_dusk_potion", "name": "黄昏疗伤药", "cost": 15, "tag": "续航",
		"accent": "#6cb878", "desc": "立刻回复 1000 生命，稳住高压战线。",
		"payload": {"id": &"item_dusk_potion", "kind": "consumable", "kind_zh": "道具", "name": "黄昏疗伤药", "desc": "使用：立刻回复 1000 生命。", "heal": 1000},
	},
	{
		"id": "item_echo_hourglass", "name": "回声沙漏", "cost": 20, "tag": "节奏",
		"accent": "#8fc7dc", "desc": "本回合 +1 AP（不给敌方充能），衔接连招。",
		"payload": {"id": &"item_echo_hourglass", "kind": "consumable", "kind_zh": "道具", "name": "回声沙漏", "desc": "使用：本回合立刻获得 +1 行动点（不给敌方充能）。", "ap_gain": 1},
	},
	{
		"id": "item_vow_talisman", "name": "誓约护符", "cost": 20, "tag": "防护",
		"accent": "#d4b77b", "desc": "获得 650 护盾与 +1 能量，硬吃 Boss 重击。",
		"payload": {"id": &"item_vow_talisman", "kind": "consumable", "kind_zh": "道具", "name": "誓约护符", "desc": "使用：获得 650 护盾并 +1 终极能量。", "shield_gain": 650, "energy_gain": 1},
	},
	{
		"id": "item_armor_bomb", "name": "破甲爆弹", "cost": 25, "tag": "破甲",
		"accent": "#e07a5f", "desc": "全场敌方重甲 -1 层并造成 350 真伤（不涨容忍）。",
		"payload": {"id": &"item_armor_bomb", "kind": "consumable", "kind_zh": "道具", "name": "破甲爆弹", "desc": "使用：震碎全场敌方 1 层重甲并造成 350 真伤。", "armor_break": 1, "aoe_true_damage": 350},
	},
	{
		"id": "item_calm_sachet", "name": "镇定香囊", "cost": 25, "tag": "破反击",
		"accent": "#74ebd5", "desc": "清空全场敌方近战容忍条，且敌方技能充能 -1。",
		"payload": {"id": &"item_calm_sachet", "kind": "consumable", "kind_zh": "道具", "name": "镇定香囊", "desc": "使用：清空全场敌方近战容忍条且敌方充能 -1。", "clear_tolerance": true, "drain_charge": 1},
	},
	{
		"id": "item_sakura_charm", "name": "瞬影樱符", "cost": 30, "tag": "爆发",
		"accent": "#e89ab0", "desc": "+2 剑意（无剑意则 +2 能量）与 450 护盾。",
		"payload": {"id": &"item_sakura_charm", "kind": "consumable", "kind_zh": "道具", "name": "瞬影樱符", "desc": "使用：获得 +2 剑意/能量与 450 护盾。", "resource_gain": 2, "shield_gain": 450},
	},
]


static func _default_state() -> Dictionary:
	return {
		"shards": STARTING_SHARDS,
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
	var loadout: Array[String] = []
	for lid in parsed.get("loadout", []):
		var sid := str(lid)
		if not recipe_by_id(sid).is_empty():
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


static func count_in_loadout(state: Dictionary, item_id: String) -> int:
	var n := 0
	for lid in state.get("loadout", []):
		if str(lid) == item_id:
			n += 1
	return n


## Returns ordered unique groups [{"id", "count", "recipe"}] for compact UI display.
static func grouped_loadout(state: Dictionary) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for r in RECIPES:
		var rid := str(r["id"])
		var cnt := count_in_loadout(state, rid)
		if cnt > 0:
			groups.append({"id": rid, "count": cnt, "recipe": r})
	return groups


## Brews one consumable using Atelier Shards and packs it into the unlimited loadout.
static func buy_and_pack(state: Dictionary, item_id: String, path: String = SAVE_PATH) -> Dictionary:
	var r := recipe_by_id(item_id)
	if r.is_empty():
		return {"ok": false, "message": "未知配方。"}
	var cost: int = int(r.get("cost", 0))
	var shards: int = int(state.get("shards", 0))
	if shards < cost:
		return {"ok": false, "message": "工坊残晶不足（需要 %d，现有 %d）。" % [cost, shards]}
	state["shards"] = shards - cost
	var loadout: Array = state.get("loadout", [])
	loadout.append(item_id)
	state["loadout"] = loadout
	save_state(state, path)
	return {"ok": true, "message": "消耗 %d 残晶，调配「%s」装入行囊（现有 ×%d）。" % [cost, str(r["name"]), count_in_loadout(state, item_id)]}


## Removes one copy of `item_id` from the staging loadout and refunds its full cost.
static func unpack_and_refund(state: Dictionary, item_id: String, path: String = SAVE_PATH) -> Dictionary:
	var loadout: Array = state.get("loadout", [])
	var found_idx := -1
	for i in range(loadout.size() - 1, -1, -1):
		if str(loadout[i]) == item_id:
			found_idx = i
			break
	if found_idx < 0:
		return {"ok": false, "message": ""}
	var r := recipe_by_id(item_id)
	var refund: int = int(r.get("cost", 0))
	loadout.remove_at(found_idx)
	state["loadout"] = loadout
	state["shards"] = int(state.get("shards", 0)) + refund
	save_state(state, path)
	return {"ok": true, "message": "已退回 1 个「%s」，全额返还 %d 工坊残晶。" % [str(r.get("name", item_id)), refund]}


static func award_shards(amount: int, path: String = SAVE_PATH) -> int:
	if amount <= 0:
		return 0
	var state := load_state(path)
	state["shards"] = int(state.get("shards", 0)) + amount
	save_state(state, path)
	return int(state["shards"])


## Extracts all packed consumables for the departing expedition and clears the
## staging bag so consumed supplies must be brewed again with earned shards.
static func take_loadout_items(path: String = SAVE_PATH) -> Array[Dictionary]:
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
	if not items.is_empty():
		state["loadout"] = []
		save_state(state, path)
	return items
