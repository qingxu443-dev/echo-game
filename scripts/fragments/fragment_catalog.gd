class_name FragmentCatalog
extends RefCounted

const SIZE_SMALL := "small"
const SIZE_MEDIUM := "medium"
const SIZE_LARGE := "large"
const SIZE_LARGE_MAIN := "large_main"
const SIZE_LARGE_SUB := "large_sub"
const SLOT_COUNT := 6
const CAPACITY_LIMIT := 12

const STAT_KEYS: Array[String] = [
	"attack", "health", "defense", "crit_rate", "crit_damage", "magic_resistance", "healing_efficiency"
]
const STAT_NAMES := {
	"attack": "攻击力",
	"health": "生命值",
	"defense": "防御力",
	"crit_rate": "暴击率",
	"crit_damage": "暴击伤害",
	"magic_resistance": "魔法抗性",
	"healing_efficiency": "治疗效率",
}
const VALUES := {
	SIZE_SMALL: {"attack": 4.0, "health": 5.0, "defense": 3.0, "crit_rate": 1.5, "crit_damage": 6.0, "magic_resistance": 3.0, "healing_efficiency": 5.0},
	SIZE_MEDIUM: {"attack": 3.0, "health": 4.0, "defense": 2.0, "crit_rate": 1.0, "crit_damage": 4.0, "magic_resistance": 2.0, "healing_efficiency": 3.0},
	SIZE_LARGE_MAIN: {"attack": 7.0, "health": 8.0, "defense": 5.0, "crit_rate": 2.5, "crit_damage": 10.0, "magic_resistance": 5.0, "healing_efficiency": 8.0},
	SIZE_LARGE_SUB: {"attack": 1.0, "health": 1.0, "defense": 1.0, "crit_rate": 0.5, "crit_damage": 2.0, "magic_resistance": 1.0, "healing_efficiency": 1.0},
}
const CAPACITY := {SIZE_SMALL: 1, SIZE_MEDIUM: 2, SIZE_LARGE: 3}
const SIZE_NAMES := {SIZE_SMALL: "小型", SIZE_MEDIUM: "中型", SIZE_LARGE: "大型"}


static func stat_name(stat: String) -> String:
	return str(STAT_NAMES.get(stat, stat))


static func capacity_of(size: String) -> int:
	return int(CAPACITY.get(size, 0))


static func _new_id(rng: RandomNumberGenerator) -> String:
	return "fragment_%d_%d" % [Time.get_ticks_usec(), rng.randi()]


static func _make_module(size: String, attributes: Dictionary, main_stat: String, sub_stat: String, rng: RandomNumberGenerator, instance_id: String = "") -> Dictionary:
	var resolved_id := instance_id if not instance_id.is_empty() else _new_id(rng)
	return {
		"instance_id": resolved_id,
		"size": size,
		"capacity": capacity_of(size),
		"main_stat": main_stat,
		"sub_stat": sub_stat,
		"attributes": attributes.duplicate(true),
		"created_seed": rng.seed,
	}


static func create_small(rng: RandomNumberGenerator, instance_id: String = "") -> Dictionary:
	var stat := STAT_KEYS[rng.randi_range(0, STAT_KEYS.size() - 1)]
	return _make_module(SIZE_SMALL, {stat: float(VALUES[SIZE_SMALL][stat])}, stat, "", rng, instance_id)


static func create_medium(rng: RandomNumberGenerator, instance_id: String = "") -> Dictionary:
	var first_index := rng.randi_range(0, STAT_KEYS.size() - 1)
	var second_index := rng.randi_range(0, STAT_KEYS.size() - 2)
	if second_index >= first_index:
		second_index += 1
	var first := STAT_KEYS[first_index]
	var second := STAT_KEYS[second_index]
	var attrs := {first: float(VALUES[SIZE_MEDIUM][first]), second: float(VALUES[SIZE_MEDIUM][second])}
	return _make_module(SIZE_MEDIUM, attrs, "", "", rng, instance_id)


static func create_large(main_stat: String, rng: RandomNumberGenerator, instance_id: String = "") -> Dictionary:
	if not STAT_KEYS.has(main_stat):
		return {}
	var candidates: Array[String] = []
	for stat in STAT_KEYS:
		if stat != main_stat:
			candidates.append(stat)
	var sub_stat := candidates[rng.randi_range(0, candidates.size() - 1)]
	var attrs := {
		main_stat: float(VALUES[SIZE_LARGE_MAIN][main_stat]),
		sub_stat: float(VALUES[SIZE_LARGE_SUB][sub_stat]),
	}
	return _make_module(SIZE_LARGE, attrs, main_stat, sub_stat, rng, instance_id)


static func create_fixed_large_bundle(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var distribution := {
		"attack": 2,
		"health": 2,
		"defense": 1,
		"crit_rate": 1,
		"crit_damage": 1,
		"magic_resistance": 1,
		"healing_efficiency": 2,
	}
	var result: Array[Dictionary] = []
	for stat in STAT_KEYS:
		for _i in range(int(distribution[stat])):
			result.append(create_large(stat, rng))
	return result


static func generate_mail_bundle(rng: RandomNumberGenerator, ordinary_large_mains: Array[String]) -> Dictionary:
	if ordinary_large_mains.size() != 10:
		return {}
	for main_stat in ordinary_large_mains:
		if not STAT_KEYS.has(main_stat):
			return {}
	var small: Array[Dictionary] = []
	var medium: Array[Dictionary] = []
	var ordinary_large: Array[Dictionary] = []
	for _i in range(10):
		small.append(create_small(rng))
		medium.append(create_medium(rng))
		ordinary_large.append(create_large(ordinary_large_mains[_i], rng))
	return {
		"small": small,
		"medium": medium,
		"ordinary_large": ordinary_large,
		"fixed_large": create_fixed_large_bundle(rng),
	}


static func validate_module(module: Dictionary) -> bool:
	var instance_id := str(module.get("instance_id", ""))
	var size := str(module.get("size", ""))
	var attrs: Variant = module.get("attributes", null)
	if instance_id.is_empty() or not CAPACITY.has(size) or not attrs is Dictionary or attrs.is_empty():
		return false
	if int(module.get("capacity", -1)) != capacity_of(size):
		return false
	for stat in attrs:
		if not STAT_KEYS.has(str(stat)) or not (attrs[stat] is int or attrs[stat] is float):
			return false
		if not is_finite(float(attrs[stat])) or float(attrs[stat]) <= 0.0:
			return false
	match size:
		SIZE_SMALL:
			if attrs.size() != 1:
				return false
			var key := str(attrs.keys()[0])
			return is_equal_approx(float(attrs[key]), float(VALUES[SIZE_SMALL][key])) and str(module.get("main_stat", "")) == key and str(module.get("sub_stat", "")).is_empty()
		SIZE_MEDIUM:
			if attrs.size() != 2 or not str(module.get("main_stat", "")).is_empty() or not str(module.get("sub_stat", "")).is_empty():
				return false
			for key in attrs:
				if not is_equal_approx(float(attrs[key]), float(VALUES[SIZE_MEDIUM][str(key)])):
					return false
			return true
		SIZE_LARGE:
			var main := str(module.get("main_stat", ""))
			var sub := str(module.get("sub_stat", ""))
			return attrs.size() == 2 and STAT_KEYS.has(main) and STAT_KEYS.has(sub) and main != sub and attrs.has(main) and attrs.has(sub) and is_equal_approx(float(attrs[main]), float(VALUES[SIZE_LARGE_MAIN][main])) and is_equal_approx(float(attrs[sub]), float(VALUES[SIZE_LARGE_SUB][sub]))
	return false


static func display_name(module: Dictionary) -> String:
	var size_name := str(SIZE_NAMES.get(str(module.get("size", "")), "模块"))
	var attrs: Dictionary = module.get("attributes", {})
	var labels: Array[String] = []
	for stat in STAT_KEYS:
		if attrs.has(stat):
			var unit := "个百分点" if stat in ["crit_rate", "crit_damage"] else "%"
			labels.append("%s +%s%s" % [stat_name(stat), str(attrs[stat]), unit])
	return "%s模块 · %s" % [size_name, " / ".join(labels)]


static func format_bonus(stat: String, value: float) -> String:
	var unit := "个百分点" if stat in ["crit_rate", "crit_damage"] else "%"
	return "+%s%s" % [str(value), unit]
