class_name EncounterLaws
extends RefCounted

## Runtime-supported subset of the draft law parameter table. Unsupported
## semantics are rejected rather than accepted as inert resource fields.
const SUPPORTED := ["attenuation_k", "ap_pool", "telegraph_lead_turns", "telegraph_mutable"]
const DEFERRED := ["echo_lock_mode", "action_cost", "settlement_turns", "residue_lifetime_turns", "residue_repeat_ratio"]

static func describe_error(overrides: Dictionary) -> String:
	for key in overrides:
		if not (key is String or key is StringName): return "法则参数名必须是字符串"
		if str(key) in DEFERRED: return "尚未支持覆写法则参数：%s" % key
		if str(key) not in SUPPORTED: return "未知法则参数：%s" % key
		var value: Variant = overrides[key]
		match str(key):
			"attenuation_k", "ap_pool":
				if not value is int or value < 1: return "%s 必须是正整数" % key
			"telegraph_lead_turns":
				if not value is int or value != 1: return "当前只支持提前一个玩家回合的预告"
			"telegraph_mutable":
				if not value is bool or value: return "当前不支持改写已发出的预告"
	return ""


static func resolve(overrides: Dictionary, base_ap: int = 3) -> Dictionary:
	if base_ap < 1 or not describe_error(overrides).is_empty(): return {}
	var named := _named_keys(overrides)
	return {
		"attenuation_k": int(named.get("attenuation_k", CombatMath.ATTENUATION_K)),
		"ap_pool": int(named.get("ap_pool", base_ap)),
		"telegraph_lead_turns": 1, "telegraph_mutable": false,
	}


static func summary(overrides: Dictionary, base_ap: int = 3) -> String:
	if overrides.is_empty(): return ""
	var values := resolve(overrides, base_ap)
	if values.is_empty(): return "异象配置无效"
	var named := _named_keys(overrides)
	var parts: Array[String] = []
	if named.has("attenuation_k"):
		if values.attenuation_k < CombatMath.ATTENUATION_K: parts.append("护甲与抗性更有效")
		elif values.attenuation_k > CombatMath.ATTENUATION_K: parts.append("护甲与抗性效能降低")
	if named.has("ap_pool"): parts.append("共享行动点 %d" % values.ap_pool)
	if parts.is_empty(): parts.append("标准预告规则")
	return "异象 · " + "；".join(parts)


static func _named_keys(overrides: Dictionary) -> Dictionary:
	var named := {}
	for key in overrides: named[str(key)] = overrides[key]
	return named
