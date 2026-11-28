class_name SpringRunMigration
extends RefCounted

## 版本迁移表：键是「从这一版升上去」，值是把该版数据改写成下一版的函数。
## 加版本时只加一行；缺一行会让旧档加载失败并报出确切版本，而不是静默读错
## 字段——静默读错是最坏的一种：玩家看到的是血量翻倍或资源归零。
const MIGRATIONS := {
	1: "_migrate_v1_to_v2",
	2: "_migrate_v2_to_v3",
	3: "_migrate_v3_to_v4",
	4: "_migrate_v4_to_v5",
}


## 就地把 data 推到 current_version。返回空串表示成功，否则返回拒绝原因。
## 未来版本（比本程序新）一律拒绝：读得动不代表读得对。
static func migrate_to_current(data: Dictionary, current_version: int, defaults: Dictionary) -> String:
	var version: int = int(data.get("version", 1))
	if version > current_version:
		return "save is version %d, this build reads up to %d" % [version, current_version]
	while version < current_version:
		var step: String = str(MIGRATIONS.get(version, ""))
		if step.is_empty():
			return "no migration from version %d" % version
		# 传副本进去：迁移函数返回的是它自己那份时，下面的 clear() 会把
		# 返回值一起清空，v1 档就这样丢过全部字段。
		var migrated: Dictionary = Callable(SpringRunMigration, step).call(data.duplicate(true), defaults)
		data.clear()
		data.merge(migrated, true)
		version += 1
	data["version"] = current_version
	return ""


static func _migrate_v1_to_v2(data: Dictionary, _defaults: Dictionary) -> Dictionary:
	# v2 只是加了字段，每个默认值都等于 v1 的语义，所以这一步不改写任何东西。
	# 留一个空迁移是有意的：表必须覆盖每一个中间版本，否则 1 → 4 会找不到路。
	return data


static func _migrate_v2_to_v3(data: Dictionary, _defaults: Dictionary) -> Dictionary:
	# v3 把探索者从 瑟弗林（3600 血）换成 樱（1800）。v2 存档带着旧上限，
	# 留着会让樱以两倍血量开局——这是唯一一次「照读不误比丢弃更糟」。
	var result: Dictionary = data.duplicate(true)
	var hero: Dictionary = result.get("hero", {})
	hero.erase("carry_max_health")
	result["hero"] = hero
	return result


static func _migrate_v3_to_v4(data: Dictionary, defaults: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	result["party_character_ids"] = []
	var hero: Dictionary = result.get("hero", {})
	hero["character_id"] = str(defaults.get("hero_character_id", "sakura"))
	hero["base_max_health"] = int(defaults.get("base_max_health", 1800))
	hero["base_attack"] = int(defaults.get("base_attack", 520))
	hero["base_defense"] = int(defaults.get("base_defense", 180))
	hero["base_magic_resistance"] = int(defaults.get("base_magic_resistance", 111))
	result["hero"] = hero
	result["party_vitals"] = {}
	return result




static func _migrate_v4_to_v5(data: Dictionary, _defaults: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	var resources: Dictionary = result.get("resources", {})
	resources["collectible_consumables"] = {}
	result["resources"] = resources
	return result
