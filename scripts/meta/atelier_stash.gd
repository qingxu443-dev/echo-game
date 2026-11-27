class_name AtelierStash
extends RefCounted

## Dusk Supply Shop (黄昏补给商行) meta-progression stash & unlimited loadout.
##
## Players earn Atelier Shards (工坊残晶) from every battle and may purchase any
## number of tactical supplies before departing. Refunding an item in the shop
## restores its full shard cost; departing carries the packed bag into battle.

const SAVE_PATH: String = "user://atelier_stash.json"
const STARTING_SHARDS: int = 120

const RECIPES: Array[Dictionary] = [
	{
		"id": "item_dusk_potion", "name": "黄昏疗伤药", "cost": 15, "tag": "回复", "icon": "potion",
		"accent": "#6cb878",
		"brief": "恢复 1000 生命",
		"flavor": "以暮色药草慢火调制的秘药，入口微甘。",
		"desc": "恢复 1000 点生命值。",
		"payload": {"id": &"item_dusk_potion", "kind": "consumable", "kind_zh": "道具", "name": "黄昏疗伤药", "desc": "使用：恢复 1000 点生命值。", "heal": 1000},
	},
	{
		"id": "item_echo_hourglass", "name": "回声沙漏", "cost": 20, "tag": "战术", "icon": "hourglass",
		"accent": "#8fc7dc",
		"brief": "额外 +1 行动点",
		"flavor": "封存片刻流光的琉璃沙漏，可逆转刹那先机。",
		"desc": "本回合额外获得 1 点行动点，且不触发敌方充能。",
		"payload": {"id": &"item_echo_hourglass", "kind": "consumable", "kind_zh": "道具", "name": "回声沙漏", "desc": "使用：本回合额外获得 1 点行动点，且不触发敌方充能。", "ap_gain": 1},
	},
	{
		"id": "item_vow_talisman", "name": "誓约护符", "cost": 20, "tag": "防护", "icon": "talisman",
		"accent": "#d4b77b",
		"brief": "+650 护盾 · +1 能量",
		"flavor": "刻有古老守誓纹路的黄铜符牌，可凝结护壁。",
		"desc": "获得 650 点护盾与 1 点终极能量。",
		"payload": {"id": &"item_vow_talisman", "kind": "consumable", "kind_zh": "道具", "name": "誓约护符", "desc": "使用：获得 650 点护盾与 1 点终极能量。", "shield_gain": 650, "energy_gain": 1},
	},
	{
		"id": "item_armor_bomb", "name": "破甲爆弹", "cost": 25, "tag": "破甲", "icon": "bomb",
		"accent": "#e07a5f",
		"brief": "全敌 -1 重甲 · 350 真伤",
		"flavor": "装填晶粉的炼金投掷瓶，专克重甲与结界。",
		"desc": "削减全场敌人 1 层重甲，并造成 350 点真实伤害。",
		"payload": {"id": &"item_armor_bomb", "kind": "consumable", "kind_zh": "道具", "name": "破甲爆弹", "desc": "使用：削减全场敌人 1 层重甲，并造成 350 点真实伤害。", "armor_break": 1, "aoe_true_damage": 350},
	},
	{
		"id": "item_calm_sachet", "name": "镇定香囊", "cost": 25, "tag": "控场", "icon": "sachet",
		"accent": "#74ebd5",
		"brief": "清空容忍 · 降 1 格充能",
		"flavor": "散发静谧幽香的草木香囊，能平息强敌躁意。",
		"desc": "清空全场敌人的近战容忍度，并降低 1 格技能充能。",
		"payload": {"id": &"item_calm_sachet", "kind": "consumable", "kind_zh": "道具", "name": "镇定香囊", "desc": "使用：清空全场敌人的近战容忍度，并降低 1 格技能充能。", "clear_tolerance": true, "drain_charge": 1},
	},
	{
		"id": "item_sakura_charm", "name": "瞬影樱符", "cost": 30, "tag": "增益", "icon": "charm",
		"accent": "#e89ab0",
		"brief": "+2 剑意/能量 · +450 护盾",
		"flavor": "浸染春樱灵气的御守符札，出鞘之际锋芒尽显。",
		"desc": "获得 2 点剑意（或 2 点终极能量）与 450 点护盾。",
		"payload": {"id": &"item_sakura_charm", "kind": "consumable", "kind_zh": "道具", "name": "瞬影樱符", "desc": "使用：获得 2 点剑意（或 2 点终极能量）与 450 点护盾。", "resource_gain": 2, "shield_gain": 450},
	},
]


static func _default_state() -> Dictionary:
	return {
		"shards": STARTING_SHARDS,
		"loadout": ["item_dusk_potion", "item_echo_hourglass", "item_vow_talisman"],
	}


static func load_state(path: String = SAVE_PATH) -> Dictionary:
	var state := read_state(path)
	return _default_state() if state.is_empty() else state


## An empty result indicates an existing file could not be safely read.
static func read_state(path: String) -> Dictionary:
	var state := _default_state()
	if not FileAccess.file_exists(path):
		return state
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary) or not (parsed.get("loadout", []) is Array):
		return {}
	if typeof(parsed.get("shards", STARTING_SHARDS)) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	state["shards"] = maxi(0, int(parsed.get("shards", STARTING_SHARDS)))
	var loadout: Array[String] = []
	var saved_loadout = parsed.get("loadout", [])
	for lid in (saved_loadout if saved_loadout is Array else []):
		var sid := str(lid)
		if not recipe_by_id(sid).is_empty():
			loadout.append(sid)
	state["loadout"] = loadout
	return state


static func save_state(state: Dictionary, path: String = SAVE_PATH) -> bool:
	if path == SAVE_PATH and DisplayServer.get_name() == "headless":
		return true
	if SpringSaveTransaction.is_pending(path):
		return false
	return SaveFile.write_json(path, state)


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


static func grouped_loadout(state: Dictionary) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for r in RECIPES:
		var rid := str(r["id"])
		var cnt := count_in_loadout(state, rid)
		if cnt > 0:
			groups.append({"id": rid, "count": cnt, "recipe": r})
	return groups


static func buy_and_pack(state: Dictionary, item_id: String, path: String = SAVE_PATH, quantity: int = 1) -> Dictionary:
	var r := recipe_by_id(item_id)
	if r.is_empty():
		return {"ok": false, "message": "未找到该商品。"}
	var qty: int = maxi(1, quantity)
	var cost: int = int(r.get("cost", 0)) * qty
	var shards: int = int(state.get("shards", 0))
	if shards < cost:
		return {"ok": false, "message": "残晶不足，需要 %d 残晶。" % cost}
	var next := state.duplicate(true)
	next["shards"] = shards - cost
	var loadout: Array = next.get("loadout", [])
	for _i in range(qty):
		loadout.append(item_id)
	next["loadout"] = loadout
	if not save_state(next, path):
		return {"ok": false, "message": "工坊存档写入失败，购买未完成。"}
	state.merge(next, true)
	return {"ok": true, "message": "已购入「%s」×%d。" % [str(r["name"]), qty]}


static func unpack_and_refund(state: Dictionary, item_id: String, path: String = SAVE_PATH) -> Dictionary:
	var next := state.duplicate(true)
	var loadout: Array = next.get("loadout", [])
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
	next["loadout"] = loadout
	next["shards"] = int(next.get("shards", 0)) + refund
	if not save_state(next, path):
		return {"ok": false, "message": "工坊存档写入失败，退货未完成。"}
	state.merge(next, true)
	return {"ok": true, "message": "已退回「%s」×1，返还 %d 残晶。" % [str(r.get("name", item_id)), refund]}


static func award_shards(amount: int, path: String = SAVE_PATH) -> int:
	if amount <= 0:
		return 0
	# Do not pollute the player's real meta stash during headless test runs.
	if path == SAVE_PATH and DisplayServer.get_name() == "headless":
		return 0
	var state := load_state(path)
	state["shards"] = int(state.get("shards", 0)) + amount
	return int(state["shards"]) if save_state(state, path) else 0


static func take_loadout_items(path: String = SAVE_PATH) -> Array[Dictionary]:
	if path == SAVE_PATH and DisplayServer.get_name() == "headless":
		return []
	var state := read_state(path)
	var items := packed_items(state)
	if not items.is_empty():
		state["loadout"] = []
		if not save_state(state, path):
			return []
	return items


static func packed_items(state: Dictionary) -> Array[Dictionary]:
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
