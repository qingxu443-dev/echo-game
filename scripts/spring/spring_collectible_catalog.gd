class_name SpringCollectibleCatalog
extends RefCounted

## 春之境's collectible pool (§6). The document fixes the rules - no duplicates,
## passive ones are automatic, instant-resource ones count as obtained, elites
## never drop epic or legendary (§6.1, §14) - but it does not name a single
## collectible.
##
## So these six exist to give events, elite rewards and the collector something
## real to hand out. Every one of them has an effect the run layer can honour
## today: an immediate resource, a permanent stat for the run, or a map reveal.
## Nothing conditional is listed here, because a collectible that needs a battle
## hook would ship as a name with no behaviour.
##
## `rarity` follows §6.2's four steps. `pool` says where it may appear:
## "elite" for the elite reward table (common/rare only), "boss" for the boss
## table (which also allows epic), "any" for events and shops.

const RARITY_COMMON: String = "普通"
const RARITY_RARE: String = "稀有"
const RARITY_EPIC: String = "史诗"

const COLLECTIBLES := {
	"col_petal_purse": {
		"name": "落樱钱袋",
		"desc": "立刻获得 60 花钿。",
		"rarity": RARITY_COMMON,
		"pool": "any",
		"effect": {"kind": "coins", "amount": 60},
	},
	"col_dried_ration": {
		"name": "风干干粮",
		"desc": "立刻获得 3 份补给。",
		"rarity": RARITY_COMMON,
		"pool": "any",
		"effect": {"kind": "supplies", "amount": 3},
	},
	"col_memory_scrap": {
		"name": "残页抄本",
		"desc": "立刻获得 2 页记忆残页。",
		"rarity": RARITY_COMMON,
		"pool": "any",
		"effect": {"kind": "pages", "amount": 2},
	},
	"col_spring_vial": {
		"name": "凝春小瓶",
		"desc": "立刻获得 3 滴春露（容量可容纳时）。",
		"rarity": RARITY_RARE,
		"pool": "any",
		"effect": {"kind": "dew", "dew_kind": "spring", "amount": 3},
	},
	"col_old_map": {
		"name": "褪色旧图",
		"desc": "在地图上标出一处从未留意的地方。",
		"rarity": RARITY_RARE,
		"pool": "any",
		"effect": {"kind": "reveal_hidden"},
	},
	"col_keeper_seal": {
		"name": "守庭印",
		"desc": "本局最大生命 +250。",
		"rarity": RARITY_EPIC,
		"pool": "boss",
		"effect": {"kind": "max_health", "amount": 250},
	},
}


static func has_collectible(collectible_id: StringName) -> bool:
	return COLLECTIBLES.has(String(collectible_id))


static func name_of(collectible_id: StringName) -> String:
	var entry: Dictionary = COLLECTIBLES.get(String(collectible_id), {})
	return str(entry.get("name", String(collectible_id)))


static func desc_of(collectible_id: StringName) -> String:
	var entry: Dictionary = COLLECTIBLES.get(String(collectible_id), {})
	return str(entry.get("desc", ""))


static func rarity_of(collectible_id: StringName) -> String:
	var entry: Dictionary = COLLECTIBLES.get(String(collectible_id), {})
	return str(entry.get("rarity", RARITY_COMMON))


static func effect_of(collectible_id: StringName) -> Dictionary:
	var entry: Dictionary = COLLECTIBLES.get(String(collectible_id), {})
	return entry.get("effect", {})


## Ids that may appear in a given reward context. §14: elites never offer epic;
## §15.4: bosses do, at a low weight (the weighting itself is the caller's job).
static func candidates_for(source: String) -> Array[String]:
	var result: Array[String] = []
	for key in COLLECTIBLES.keys():
		var entry: Dictionary = COLLECTIBLES[key]
		var rarity: String = str(entry.get("rarity", RARITY_COMMON))
		var boss_only: bool = str(entry.get("pool", "any")) == "boss"
		match source:
			"boss":
				pass
			"elite":
				# §14: elites never offer epic or legendary.
				if boss_only or rarity == RARITY_EPIC:
					continue
			_:
				# Events and shops draw from the general pool only.
				if boss_only:
					continue
		result.append(String(key))
	# Stable order so a seeded draw is reproducible across runs.
	result.sort()
	return result
