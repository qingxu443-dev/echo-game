class_name RunState
extends RefCounted

## Working equipment slot and persistent battle carry for the deployed role:
## - Persists HP, skill mods, equipped weapon/armor, and backpack across stages.
## - Supports equipping, swapping, unequipping back to backpack, and using items.
## - reset() wipes everything cleanly at the end of a run.

const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")
const TacticalPressureScript = preload("res://scripts/battle/tactical_pressure.gd")

var base_max_health: int = 3600
var base_attack: int = 1150
var base_defense: int = 350
var base_magic_resistance: int = 250

var bonus_max_health: int = 0
var hero_max_health: int = 3600
var hero_health: int = 3600
var mods: Array[StringName] = []
var equipped_weapon: Dictionary = {}
var equipped_armor: Dictionary = {}
var backpack: Array[Dictionary] = []
var initialized: bool = false
var party_loadouts: Dictionary = {}
var party_retired: Array[String] = []
var party_owner_id: String = ""
## Loot RNG seed of the current run, set by the battle view when a fresh run
## begins. 0 in headless tests (fixed default seed - reproducible rolls).
var loot_seed: int = 0

const REWARD_POOL: Array[Dictionary] = [
	{
		"id": &"heavy_push",
		"kind": "技能铭文",
		"name": "重盾冲击",
		"desc": "「誓刃」击退距离提升至 2 格，更容易撞墙破招。",
		"repeatable": false,
	},
	{
		"id": &"shatter_slam",
		"kind": "技能铭文",
		"name": "碎石震荡",
		"desc": "击退撞墙 / 撞怪造成的真实伤害翻倍（450 → 900）。",
		"repeatable": false,
	},
	{
		"id": &"deep_judgment",
		"kind": "技能铭文",
		"name": "贯通裁决",
		"desc": "「裁决印记」附加的易伤从 +30% 提升至 +55%。",
		"repeatable": false,
	},
	{
		"id": &"shock_shield",
		"kind": "技能铭文",
		"name": "震荡誓盾",
		"desc": "「誓盾庇护」护盾 +350，且开盾时震退周围 1 格敌人。",
		"repeatable": false,
	},
	{
		"id": &"wide_verdict",
		"kind": "技能铭文",
		"name": "大裁决域",
		"desc": "终极技「绝对裁决」范围扩大至自身周围 2 格。",
		"repeatable": false,
	},
	{
		"id": &"echo_stride",
		"kind": "回声遗物",
		"name": "余响迅步",
		"desc": "每回合首次移动不消耗 AP，且不会为敌人充能。",
		"repeatable": false,
	},
	{
		"id": &"dusk_elixir",
		"kind": "黄昏休整",
		"name": "黄昏秘药",
		"desc": "立刻回复 1200 生命，并将最大生命提升 +400。",
		"repeatable": true,
	},
]


func reset(p_max_health: int = 3600, p_attack: int = 1150, p_defense: int = 350, p_mres: int = 250) -> void:
	base_max_health = maxi(1, p_max_health)
	base_attack = maxi(1, p_attack)
	base_defense = maxi(0, p_defense)
	base_magic_resistance = maxi(0, p_mres)
	bonus_max_health = 0
	hero_max_health = base_max_health
	hero_health = base_max_health
	party_loadouts.clear()
	party_retired.clear()
	party_owner_id = ""
	mods.clear()
	equipped_weapon = {}
	equipped_armor = {}
	backpack.clear()
	initialized = true


func has_mod(mod_id: StringName) -> bool:
	return mods.has(mod_id)


func knockback_steps() -> int:
	return 2 if has_mod(&"heavy_push") else 1


func collision_damage() -> int:
	var base_dmg: int = 900 if has_mod(&"shatter_slam") else 450
	if not equipped_weapon.is_empty():
		base_dmg += int(equipped_weapon.get("collision_bonus", 0))
	return base_dmg


func mark_vulnerability_multiplier() -> float:
	return 1.55 if has_mod(&"deep_judgment") else 1.30


func shield_bonus() -> int:
	return 350 if has_mod(&"shock_shield") else 0


func ultimate_radius() -> int:
	return 2 if has_mod(&"wide_verdict") else 1


# --- equipment & backpack API -----------------------------------------------

func add_to_backpack(item: Dictionary) -> void:
	if item.is_empty():
		return
	backpack.append(item.duplicate(true))


func effective_max_health() -> int:
	var mh: int = base_max_health + bonus_max_health
	if not equipped_weapon.is_empty():
		mh += int(equipped_weapon.get("max_health", 0))
	if not equipped_armor.is_empty():
		mh += int(equipped_armor.get("max_health", 0))
	return maxi(1, mh)


func effective_attack() -> int:
	var val: int = base_attack
	if not equipped_weapon.is_empty():
		val += int(equipped_weapon.get("attack", 0))
	if not equipped_armor.is_empty():
		val += int(equipped_armor.get("attack", 0))
	return maxi(1, val)


func effective_defense() -> int:
	var val: int = base_defense
	if not equipped_weapon.is_empty():
		val += int(equipped_weapon.get("defense", 0))
	if not equipped_armor.is_empty():
		val += int(equipped_armor.get("defense", 0))
	return maxi(0, val)


func effective_magic_resistance() -> int:
	var val: int = base_magic_resistance
	if not equipped_weapon.is_empty():
		val += int(equipped_weapon.get("magic_resistance", 0))
	if not equipped_armor.is_empty():
		val += int(equipped_armor.get("magic_resistance", 0))
	return maxi(0, val)


func equip_from_backpack(index: int, actor = null) -> String:
	if index < 0 or index >= backpack.size():
		return ""
	var item: Dictionary = backpack[index]
	var kind: String = str(item.get("kind", ""))
	if kind != LootCatalogScript.KIND_WEAPON and kind != LootCatalogScript.KIND_ARMOR:
		return ""

	var old_max: int = effective_max_health()
	backpack.remove_at(index)
	if kind == LootCatalogScript.KIND_WEAPON:
		if not equipped_weapon.is_empty():
			backpack.append(equipped_weapon)
		equipped_weapon = item
	else:
		if not equipped_armor.is_empty():
			backpack.append(equipped_armor)
		equipped_armor = item

	_recompute_stats(actor, old_max)
	return "已装备「%s」。" % str(item.get("name", ""))


func unequip_slot(slot: String, actor = null) -> String:
	var old_max: int = effective_max_health()
	if slot == LootCatalogScript.KIND_WEAPON and not equipped_weapon.is_empty():
		var removed: Dictionary = equipped_weapon
		equipped_weapon = {}
		backpack.append(removed)
		_recompute_stats(actor, old_max)
		return "已卸下「%s」并放回背包。" % str(removed.get("name", ""))
	if slot == LootCatalogScript.KIND_ARMOR and not equipped_armor.is_empty():
		var removed: Dictionary = equipped_armor
		equipped_armor = {}
		backpack.append(removed)
		_recompute_stats(actor, old_max)
		return "已卸下「%s」并放回背包。" % str(removed.get("name", ""))
	return ""


func use_backpack_item(index: int, battle, actor) -> String:
	if index < 0 or index >= backpack.size():
		return ""
	var item: Dictionary = backpack[index]
	var kind: String = str(item.get("kind", ""))
	if kind == LootCatalogScript.KIND_WEAPON or kind == LootCatalogScript.KIND_ARMOR:
		return equip_from_backpack(index, actor)

	if kind == LootCatalogScript.KIND_SKILL_UPGRADE:
		var req_char := String(item.get("character_id", &""))
		if not req_char.is_empty() and actor != null and String(actor.character_id) != req_char:
			return "「%s」为其他角色专属技能铭文，当前角色无法激活。" % str(item.get("name", ""))
		var mid: StringName = item.get("mod_id", &"")
		backpack.remove_at(index)
		if mid != &"" and not mods.has(mid):
			mods.append(mid)
		return "已激活技能升级「%s」！" % str(item.get("name", ""))

	if kind == LootCatalogScript.KIND_CONSUMABLE:
		if actor == null or not actor.is_alive():
			return "当前无法使用道具。"
		backpack.remove_at(index)
		var heal: int = int(item.get("heal", 0))
		if heal > 0:
			actor.health = mini(actor.max_health, actor.health + heal)
			hero_health = actor.health
		var ap_gain: int = int(item.get("ap_gain", 0))
		if ap_gain > 0 and battle != null and battle.ap != null:
			battle.ap.current = mini(APBudget.temporary_limit(battle.ap.maximum), battle.ap.current + ap_gain)
		var sh_gain: int = int(item.get("shield_gain", 0))
		if sh_gain > 0:
			actor.grant_shield(actor.shield + sh_gain)
		var en_gain: int = int(item.get("energy_gain", 0))
		if en_gain > 0:
			actor.gain_ultimate_energy(en_gain)
		var res_gain: int = int(item.get("resource_gain", 0))
		if res_gain > 0:
			if actor.has_resource():
				actor.gain_resource(res_gain)
			else:
				actor.gain_ultimate_energy(res_gain)
		var armor_brk: int = int(item.get("armor_break", 0))
		var aoe_true: int = int(item.get("aoe_true_damage", 0))
		if (armor_brk > 0 or aoe_true > 0) and battle != null:
			for aid in battle.actors.keys():
				var e = battle.actors[aid]
				if e == null or e.team != "enemy" or not e.is_alive():
					continue
				if armor_brk > 0:
					TacticalPressureScript.shatter_armor(battle, e, armor_brk, "armor_bomb")
				if aoe_true > 0:
					battle._apply_damage(String(aid), aoe_true, actor.actor_id, "atelier_armor_bomb", "true")
			battle._check_battle_end()
		var clr_tol: bool = bool(item.get("clear_tolerance", false))
		var drain_c: int = int(item.get("drain_charge", 0))
		if (clr_tol or drain_c > 0) and battle != null:
			for aid in battle.actors:
				var e = battle.actors[aid]
				if e == null or e.team != "enemy" or not e.is_alive():
					continue
				if clr_tol:
					e.melee_tolerance = 0
					e.last_melee_hit_seq = -1
				if drain_c > 0 and e.skill_charge > 0:
					e.skill_charge = maxi(0, e.skill_charge - drain_c)
		return "已使用「%s」！" % str(item.get("name", ""))

	return ""


func _recompute_stats(actor, old_max: int) -> void:
	var new_max: int = effective_max_health()
	if actor != null:
		new_max = maxi(1, actor.fragment_scaled("health", new_max))
		old_max = maxi(1, actor.fragment_scaled("health", old_max))
	var delta_hp: int = new_max - old_max
	hero_max_health = new_max
	if actor != null:
		actor.max_health = new_max
		if actor.health > 0:
			actor.health = clampi(actor.health + delta_hp, 1, new_max)
		actor.attack = actor.fragment_scaled("attack", effective_attack())
		actor.defense = actor.fragment_scaled("defense", effective_defense())
		actor.magic_resistance = actor.fragment_scaled("magic_resistance", effective_magic_resistance())
		hero_health = actor.health
	else:
		if hero_health > 0:
			hero_health = clampi(hero_health + delta_hp, 1, new_max)


func sync_from_actor(actor) -> void:
	if actor == null:
		return
	hero_max_health = effective_max_health()
	hero_health = clampi(actor.health, 1, hero_max_health)
	initialized = true


func apply_to_actor(actor) -> void:
	if actor == null:
		return
	if not initialized:
		reset(actor.max_health, actor.attack, actor.defense, actor.magic_resistance)
		return
	hero_max_health = effective_max_health()
	actor.max_health = hero_max_health
	actor.health = clampi(hero_health, 1, hero_max_health)
	actor.attack = effective_attack()
	actor.defense = effective_defense()
	actor.magic_resistance = effective_magic_resistance()


func roll_rewards(count: int = 3) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for item in REWARD_POOL:
		var mid: StringName = item["id"]
		if bool(item["repeatable"]) or not has_mod(mid):
			candidates.append(item)
	candidates.shuffle()
	var result: Array[Dictionary] = []
	for i in range(mini(count, candidates.size())):
		result.append(candidates[i])
	return result


func apply_reward(mod_id: StringName) -> Dictionary:
	for item in REWARD_POOL:
		if item["id"] == mod_id:
			if mod_id == &"dusk_elixir":
				bonus_max_health += 400
				hero_max_health = effective_max_health()
				hero_health = mini(hero_max_health, hero_health + 1200)
			elif not mods.has(mod_id):
				mods.append(mod_id)
			return item
	return {}


func active_mod_names() -> Array[String]:
	var names: Array[String] = []
	for mid in mods:
		for item in REWARD_POOL:
			if item["id"] == mid:
				names.append(String(item["name"]))
				break
	return names
