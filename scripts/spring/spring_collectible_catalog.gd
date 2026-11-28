class_name SpringCollectibleCatalog
extends RefCounted

## 春之境 collectible definitions. Passive collectibles are unique per run;
## active consumables are stackable and are only applied when the player uses them.

const RARITY_COMMON: String = "普通"
const RARITY_RARE: String = "稀有"
const RARITY_EPIC: String = "史诗"

const COLLECTIBLES := {
	"col_petal_purse": {
		"name": "落樱钱袋", "desc": "获得 60 花钿。", "rarity": RARITY_COMMON,
		"pool": "any", "type": "passive", "effect": {"kind": "coins", "amount": 60},
	},
	"col_dried_ration": {
		"name": "风干干粮", "desc": "获得 3 份补给。", "rarity": RARITY_COMMON,
		"pool": "any", "type": "passive", "effect": {"kind": "supplies", "amount": 3},
	},
	"col_memory_scrap": {
		"name": "残页抄本", "desc": "获得 2 页记忆残页。", "rarity": RARITY_COMMON,
		"pool": "any", "type": "passive", "effect": {"kind": "pages", "amount": 2},
	},
	"col_spring_vial": {
		"name": "凝春小瓶", "desc": "获得 3 滴春露（容量可容纳时）。", "rarity": RARITY_RARE,
		"pool": "any", "type": "passive", "effect": {"kind": "dew", "dew_kind": "spring", "amount": 3},
	},
	"col_old_map": {
		"name": "褪色旧图", "desc": "在地图上标出一处从未留意的地方。", "rarity": RARITY_RARE,
		"pool": "any", "type": "passive", "effect": {"kind": "reveal_hidden"},
	},
	"col_keeper_seal": {
		"name": "守庭印", "desc": "本局最大生命 +250。", "rarity": RARITY_EPIC,
		"pool": "boss", "type": "passive", "effect": {"kind": "max_health", "amount": 250},
	},
	"col_field_ration": {
		"name": "行军口粮", "desc": "主动使用：获得 2 份补给。", "rarity": RARITY_COMMON,
		"pool": "any", "type": "consumable", "effect": {"kind": "supplies", "amount": 2},
	},
	"col_medicinal_pouch": {
		"name": "草药急救包", "desc": "主动使用：恢复 300 点生命。", "rarity": RARITY_RARE,
		"pool": "any", "type": "consumable", "effect": {"kind": "heal", "amount": 300},
	},
}

static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for key in COLLECTIBLES.keys():
		result.append(String(key))
	result.sort()
	return result

static func has_collectible(collectible_id: StringName) -> bool:
	return COLLECTIBLES.has(String(collectible_id))

static func is_consumable(collectible_id: StringName) -> bool:
	return str(COLLECTIBLES.get(String(collectible_id), {}).get("type", "passive")) == "consumable"

static func name_of(collectible_id: StringName) -> String:
	return str(COLLECTIBLES.get(String(collectible_id), {}).get("name", String(collectible_id)))

static func desc_of(collectible_id: StringName) -> String:
	return str(COLLECTIBLES.get(String(collectible_id), {}).get("desc", ""))

static func rarity_of(collectible_id: StringName) -> String:
	return str(COLLECTIBLES.get(String(collectible_id), {}).get("rarity", RARITY_COMMON))

static func effect_of(collectible_id: StringName) -> Dictionary:
	return COLLECTIBLES.get(String(collectible_id), {}).get("effect", {}).duplicate(true)

## Normal battles draw common items; elites exclude epic; bosses may draw the full pool.
static func candidates_for(source: String) -> Array[String]:
	var result: Array[String] = []
	for key in COLLECTIBLES.keys():
		var entry: Dictionary = COLLECTIBLES[key]
		var rarity: String = str(entry.get("rarity", RARITY_COMMON))
		var boss_only: bool = str(entry.get("pool", "any")) == "boss"
		match source:
			"normal":
				if boss_only or rarity != RARITY_COMMON:
					continue
			"elite":
				if boss_only or rarity == RARITY_EPIC:
					continue
			_:
				if source != "boss" and boss_only:
					continue
		result.append(String(key))
	result.sort()
	return result
