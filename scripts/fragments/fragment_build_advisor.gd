class_name FragmentBuildAdvisor
extends RefCounted

const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")

const DIRECTION_ATTACK := "attack"
const DIRECTION_DEFENSE := "defense"
const DIRECTION_SUPPORT := "support"
const DIRECTION_BALANCED := "balanced"


static func directions_for_character(character_id: String) -> Array[String]:
	var result: Array[String] = [DIRECTION_ATTACK, DIRECTION_DEFENSE, DIRECTION_BALANCED]
	if _healing_weight(character_id) > 0.0:
		result.insert(2, DIRECTION_SUPPORT)
	return result


static func _healing_weight(character_id: String) -> float:
	var total := 0.0
	for skill in SkillRegistryScript.skills_for_character(character_id):
		total += float(skill.healing_multiplier)
	return total


static func _weights(character_id: String, direction: String) -> Dictionary:
	var character = CharacterCatalogScript.get_definition(character_id)
	if character == null:
		return {}
	var attack_weight := 1.0
	for skill in SkillRegistryScript.skills_for_character(character_id):
		var multipliers: Array = skill.hit_multipliers
		if multipliers.is_empty():
			attack_weight += float(skill.damage_multiplier)
		else:
			for multiplier in multipliers:
				attack_weight += float(multiplier)
	var def_weight := float(character.defense) / float(1000 + character.defense)
	var res_weight := float(character.magic_resistance) / float(1000 + character.magic_resistance)
	var crit_rate_weight := 0.5
	var crit_damage_weight := 0.025
	var heal_weight := _healing_weight(character_id)
	match direction:
		DIRECTION_ATTACK:
			return {"attack": attack_weight, "health": 0.0, "defense": 0.0, "crit_rate": crit_rate_weight * attack_weight, "crit_damage": crit_damage_weight * attack_weight, "magic_resistance": 0.0, "healing_efficiency": 0.0}
		DIRECTION_DEFENSE:
			return {"attack": 0.0, "health": 1.0, "defense": def_weight * 0.7, "crit_rate": 0.0, "crit_damage": 0.0, "magic_resistance": res_weight * 0.3, "healing_efficiency": 0.0}
		DIRECTION_SUPPORT:
			return {"attack": 0.0, "health": 0.2, "defense": def_weight * 0.14, "crit_rate": 0.0, "crit_damage": 0.0, "magic_resistance": res_weight * 0.06, "healing_efficiency": heal_weight * 0.8}
		DIRECTION_BALANCED:
			return {"attack": attack_weight * 0.5, "health": 0.5, "defense": def_weight * 0.35, "crit_rate": crit_rate_weight * attack_weight * 0.5, "crit_damage": crit_damage_weight * attack_weight * 0.5, "magic_resistance": res_weight * 0.15, "healing_efficiency": 0.0}
	return {}


static func _module_score(module: Dictionary, weights: Dictionary) -> float:
	var score := 0.0
	var attrs: Dictionary = module.get("attributes", {})
	for stat in attrs:
		score += float(attrs[stat]) * float(weights.get(str(stat), 0.0))
	return score


static func recommend(store: FragmentStore, character_id: String, direction: String) -> Dictionary:
	if store == null or not directions_for_character(character_id).has(direction):
		return {"ok": false, "message": "当前角色不支持该构筑方向。"}
	var weights := _weights(character_id, direction)
	var candidates := store.available_modules(character_id)
	var current := store.equipped_ids(character_id)
	var dp: Array = []
	for slots in range(FragmentCatalog.SLOT_COUNT + 1):
		var row: Array = []
		for capacity in range(FragmentCatalog.CAPACITY_LIMIT + 1):
			row.append(null)
		dp.append(row)
	dp[0][0] = {"score": 0.0, "ids": [], "kept": 0}
	for module in candidates:
		var cost := FragmentCatalog.capacity_of(str(module.size))
		var value := _module_score(module, weights)
		var id := str(module.instance_id)
		for slot_count in range(FragmentCatalog.SLOT_COUNT - 1, -1, -1):
			for used_capacity in range(FragmentCatalog.CAPACITY_LIMIT - cost, -1, -1):
				var state: Variant = dp[slot_count][used_capacity]
				if state == null:
					continue
				var next_ids: Array = state.ids.duplicate()
				next_ids.append(id)
				var next := {
					"score": float(state.score) + value,
					"ids": next_ids,
					"kept": int(state.kept) + (1 if current.has(id) else 0),
				}
				var target_capacity := used_capacity + cost
				var existing: Variant = dp[slot_count + 1][target_capacity]
				if _better(next, existing):
					dp[slot_count + 1][target_capacity] = next
	var best: Dictionary = {"score": 0.0, "ids": [], "kept": 0}
	for slot_count in range(FragmentCatalog.SLOT_COUNT + 1):
		for capacity in range(FragmentCatalog.CAPACITY_LIMIT + 1):
			var state: Variant = dp[slot_count][capacity]
			if state != null and _better(state, best):
				best = state
	var selected: Array[String] = []
	for id in current:
		if best.ids.has(id):
			selected.append(id)
	for id in best.ids:
		if not selected.has(str(id)):
			selected.append(str(id))
	selected.sort_custom(func(a: String, b: String) -> bool:
		var a_current := current.find(a)
		var b_current := current.find(b)
		if a_current >= 0 and b_current >= 0:
			return a_current < b_current
		if a_current >= 0:
			return true
		if b_current >= 0:
			return false
		return a < b
	)
	var unchanged := selected.size() == current.size()
	if unchanged:
		for i in range(selected.size()):
			if selected[i] != current[i]:
				unchanged = false
				break
	return {
		"ok": true,
		"direction": direction,
		"instance_ids": selected,
		"score": float(best.score),
		"capacity": _capacity_for(store, selected),
		"already_optimal": unchanged,
		"message": "当前配置已经是最优搭配。" if unchanged else "已生成当前库存下的最佳可行搭配。",
	}


static func _capacity_for(store: FragmentStore, ids: Array[String]) -> int:
	var total := 0
	for id in ids:
		total += FragmentCatalog.capacity_of(str(store.module_by_id(id).get("size", "")))
	return total


static func _better(candidate: Dictionary, existing: Variant) -> bool:
	if existing == null:
		return true
	if float(candidate.score) > float(existing.score) + 0.000001:
		return true
	if float(candidate.score) < float(existing.score) - 0.000001:
		return false
	if int(candidate.kept) != int(existing.kept):
		return int(candidate.kept) > int(existing.kept)
	if candidate.ids.size() != existing.ids.size():
		return candidate.ids.size() < existing.ids.size()
	var a := PackedStringArray()
	var b := PackedStringArray()
	for id in candidate.ids:
		a.append(str(id))
	for id in existing.ids:
		b.append(str(id))
	a.sort()
	b.sort()
	return "|".join(a) < "|".join(b)
