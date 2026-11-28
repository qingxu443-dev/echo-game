class_name SpringRelicCatalog
extends RefCounted

## Relics are unique passive run upgrades. Their effects are consumed by SpringRun
## and SpringBattleBridge so map resources and battle stats stay in sync.

const RELICS := {
	"relic_spring_charm": {"name": "春痕护符", "desc": "最大生命 +300。", "max_health": 300},
	"relic_old_hairpin": {"name": "旧日发簪", "desc": "攻击 +80。", "attack": 80},
	"relic_fallen_petal_sachet": {"name": "落樱香囊", "desc": "防御 +60。", "defense": 60},
	"relic_homeward_bell": {"name": "归乡铃", "desc": "四时花露容量 +2。", "dew_cap": 2},
}

static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for key in RELICS.keys():
		result.append(String(key))
	result.sort()
	return result

static func has_relic(relic_id: StringName) -> bool:
	return RELICS.has(String(relic_id))

static func name_of(relic_id: StringName) -> String:
	return str(RELICS.get(String(relic_id), {}).get("name", String(relic_id)))

static func desc_of(relic_id: StringName) -> String:
	return str(RELICS.get(String(relic_id), {}).get("desc", ""))

static func total_bonus(relic_ids: Array, field: String) -> int:
	var total: int = 0
	for relic_id in relic_ids:
		total += int(RELICS.get(String(relic_id), {}).get(field, 0))
	return total

static func candidates_for(relic_ids: Array) -> Array[String]:
	var result: Array[String] = []
	for relic_id in all_ids():
		if not relic_ids.has(StringName(relic_id)):
			result.append(relic_id)
	return result
