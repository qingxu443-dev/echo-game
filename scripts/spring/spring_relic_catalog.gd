class_name SpringRelicCatalog
extends RefCounted

## The four 春之境 relics (§5.5 lists where relics come from; the document does
## not name a single one). These are the minimum that events and the shop need in
## order to hand out something real rather than a name with no effect.
##
## Each relic is a flat stat bonus applied when a battle starts, because a flat
## bonus is the only kind of effect the battle layer can honour today. Anything
## conditional ("first move is free", "on kill, ...") would need a hook system
## that does not exist yet, so no such relic is defined - a relic that does
## nothing would be worse than one fewer relic.

const RELICS := {
	"relic_spring_charm": {
		"name": "春痕护符",
		"desc": "最大生命 +300。",
		"max_health": 300,
	},
	"relic_old_hairpin": {
		"name": "旧日发簪",
		"desc": "攻击 +80。",
		"attack": 80,
	},
	"relic_fallen_petal_sachet": {
		"name": "落樱香囊",
		"desc": "防御 +60。",
		"defense": 60,
	},
	"relic_homeward_bell": {
		"name": "归乡铃",
		"desc": "四时花露容量 +2。",
		"dew_cap": 2,
	},
}

const DEFAULT_POOL: Array[String] = [
	"relic_spring_charm",
	"relic_old_hairpin",
	"relic_fallen_petal_sachet",
	"relic_homeward_bell",
]


static func has_relic(relic_id: StringName) -> bool:
	return RELICS.has(String(relic_id))


static func name_of(relic_id: StringName) -> String:
	var entry: Dictionary = RELICS.get(String(relic_id), {})
	return str(entry.get("name", String(relic_id)))


static func desc_of(relic_id: StringName) -> String:
	var entry: Dictionary = RELICS.get(String(relic_id), {})
	return str(entry.get("desc", ""))


## Sums one numeric field over the relics the run owns. Unknown ids contribute
## zero, so a save written by an older build cannot crash a battle.
static func total_bonus(relic_ids: Array, field: String) -> int:
	var total: int = 0
	for relic_id in relic_ids:
		var entry: Dictionary = RELICS.get(String(relic_id), {})
		total += int(entry.get(field, 0))
	return total
