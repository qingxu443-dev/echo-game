extends RefCounted

const CollectibleCatalogScript = preload("res://scripts/spring/spring_collectible_catalog.gd")
const RelicCatalogScript = preload("res://scripts/spring/spring_relic_catalog.gd")


static func effective_dew_cap(run) -> int:
	return maxi(0, run.dew_cap + RelicCatalogScript.total_bonus(run.relics, "dew_cap"))


static func add_relic(run, relic_id: StringName) -> bool:
	if relic_id == &"" or not RelicCatalogScript.has_relic(relic_id) or run.relics.has(relic_id):
		return false
	run.relics.append(relic_id)
	return true


static func grant_random_relic(run, rng: RandomNumberGenerator) -> StringName:
	var candidates := RelicCatalogScript.candidates_for(run.relics)
	if candidates.is_empty():
		return &""
	var picked := StringName(candidates[rng.randi_range(0, candidates.size() - 1)])
	return picked if add_relic(run, picked) else &""


static func has_collectible(run, collectible_id: StringName) -> bool:
	if CollectibleCatalogScript.is_consumable(collectible_id):
		return int(run.collectible_consumables.get(String(collectible_id), 0)) > 0
	return run.collectibles.has(collectible_id)


static func grant_collectible(run, collectible_id: StringName) -> bool:
	if collectible_id == &"" or not CollectibleCatalogScript.has_collectible(collectible_id):
		return false
	if CollectibleCatalogScript.is_consumable(collectible_id):
		var key := String(collectible_id)
		run.collectible_consumables[key] = int(run.collectible_consumables.get(key, 0)) + 1
		return true
	if run.collectibles.has(collectible_id):
		return false
	run.collectibles.append(collectible_id)
	return true


static func grant_random_collectible(run, rng: RandomNumberGenerator, source: String) -> StringName:
	var candidates: Array[String] = []
	for candidate_id in CollectibleCatalogScript.candidates_for(source):
		var id := StringName(candidate_id)
		if CollectibleCatalogScript.is_consumable(id) or not run.collectibles.has(id):
			candidates.append(candidate_id)
	if candidates.is_empty():
		return &""
	var picked := StringName(candidates[rng.randi_range(0, candidates.size() - 1)])
	return picked if grant_collectible(run, picked) else &""


static func consume_collectible(run) -> StringName:
	if not run.collectibles.is_empty():
		return run.collectibles.pop_back()
	var active_ids: Array = run.collectible_consumables.keys()
	active_ids.sort()
	for item_id in active_ids:
		var count: int = int(run.collectible_consumables[item_id])
		if count <= 0:
			continue
		if count == 1:
			run.collectible_consumables.erase(item_id)
		else:
			run.collectible_consumables[item_id] = count - 1
		return StringName(item_id)
	return &""


static func collectible_name(collectible_id: StringName) -> String:
	return CollectibleCatalogScript.name_of(collectible_id)


static func relic_name(relic_id: StringName) -> String:
	return RelicCatalogScript.name_of(relic_id)


static func apply_collectible_effect(run, collectible_id: StringName) -> Dictionary:
	if CollectibleCatalogScript.is_consumable(collectible_id):
		return {"ok": false, "message": "这件藏品需要主动使用。"}
	return _apply_collectible_effect_data(run, collectible_id)


static func use_collectible(run, collectible_id: StringName) -> Dictionary:
	var key := String(collectible_id)
	var count: int = int(run.collectible_consumables.get(key, 0))
	if count <= 0 or not CollectibleCatalogScript.is_consumable(collectible_id):
		return {"ok": false, "message": "没有可使用的这件藏品。"}
	var result := _apply_collectible_effect_data(run, collectible_id)
	if not bool(result.get("ok", false)):
		return result
	count -= 1
	if count <= 0:
		run.collectible_consumables.erase(key)
	else:
		run.collectible_consumables[key] = count
	result["message"] = "使用「%s」：%s" % [collectible_name(collectible_id), str(result.get("message", ""))]
	return result


static func _apply_collectible_effect_data(run, collectible_id: StringName) -> Dictionary:
	var effect: Dictionary = CollectibleCatalogScript.effect_of(collectible_id)
	var result := {"ok": false, "message": ""}
	if effect.is_empty():
		return result
	match str(effect.get("kind", "")):
		"coins":
			run.add_coins(int(effect.get("amount", 0)))
		"supplies":
			run.add_supplies(int(effect.get("amount", 0)))
		"pages":
			run.add_memory_pages(int(effect.get("amount", 0)))
		"dew":
			var dew_kind: String = str(effect.get("dew_kind", "spring"))
			if not run.add_dew(dew_kind, int(effect.get("amount", 0))):
				result["message"] = "四时花露容量不足，这件藏品没有消耗。"
				return result
		"max_health":
			run.add_bonus_max_health(int(effect.get("amount", 0)))
		"heal":
			var healed: int = run.heal_hero(int(effect.get("amount", 0)))
			if healed <= 0:
				result["message"] = "生命已满，这件藏品没有消耗。"
				return result
			result["message"] = "恢复 %d 点生命。" % healed
		"reveal_hidden":
			run.pending_hidden_reveal = true
		_:
			return result
	result["ok"] = true
	if str(result.get("message", "")).is_empty():
		result["message"] = CollectibleCatalogScript.desc_of(collectible_id)
	return result
