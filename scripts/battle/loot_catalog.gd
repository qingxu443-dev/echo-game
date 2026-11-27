class_name LootCatalog
extends RefCounted

## Explicit loot roster, one .tres per item under data/loot/ - the same
## reviewable-manifest discipline as the enemy sheets (M1) and the levels.
## Tuning an item means touching its resource file, not this code.
##
## The runtime contract stays a Dictionary: every definition converts through
## LootItemDefinition.to_dict(), so RunState, the inventory view, and the enemy
## chest-steal path keep working unchanged.
##
## Rolls come from a seeded RandomNumberGenerator instead of the global randi().
## The default seed is fixed (0) so headless runs are reproducible; the battle
## view reseeds per fresh run so real players get a different drop sequence each
## run. seed_rng() is the single entry point for that.

const KIND_WEAPON: String = "weapon"
const KIND_ARMOR: String = "armor"
const KIND_CONSUMABLE: String = "consumable"
const KIND_SKILL_UPGRADE: String = "skill_upgrade"

const _WEAPON_OATH_GREATSWORD = preload("res://data/loot/weapon_oath_greatsword.tres")
const _WEAPON_echo_HALBERD = preload("res://data/loot/weapon_echo_halberd.tres")
const _WEAPON_DUSK_BLADE = preload("res://data/loot/weapon_dusk_blade.tres")
const _ARMOR_IRON_BULWARK = preload("res://data/loot/armor_iron_bulwark.tres")
const _ARMOR_ECHO_MANTLE = preload("res://data/loot/armor_echo_mantle.tres")
const _ARMOR_WARDEN_PLATE = preload("res://data/loot/armor_warden_plate.tres")
const _ITEM_DUSK_POTION = preload("res://data/loot/item_dusk_potion.tres")
const _ITEM_ECHO_HOURGLASS = preload("res://data/loot/item_echo_hourglass.tres")
const _ITEM_VOW_TALISMAN = preload("res://data/loot/item_vow_talisman.tres")
const _UPG_HEAVY_PUSH = preload("res://data/loot/upg_heavy_push.tres")
const _UPG_SHATTER_SLAM = preload("res://data/loot/upg_shatter_slam.tres")
const _UPG_SHOCK_SHIELD = preload("res://data/loot/upg_shock_shield.tres")
const _UPG_WIDE_VERDICT = preload("res://data/loot/upg_wide_verdict.tres")

static var _definitions: Array[LootItemDefinition] = [
	_WEAPON_OATH_GREATSWORD,
	_WEAPON_echo_HALBERD,
	_WEAPON_DUSK_BLADE,
	_ARMOR_IRON_BULWARK,
	_ARMOR_ECHO_MANTLE,
	_ARMOR_WARDEN_PLATE,
	_ITEM_DUSK_POTION,
	_ITEM_ECHO_HOURGLASS,
	_ITEM_VOW_TALISMAN,
	_UPG_HEAVY_PUSH,
	_UPG_SHATTER_SLAM,
	_UPG_SHOCK_SHIELD,
	_UPG_WIDE_VERDICT,
]

static var _rng := RandomNumberGenerator.new()


static func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value


static func current_seed() -> int:
	return _rng.seed


static func roll_random_item() -> Dictionary:
	if _definitions.is_empty():
		return {}
	var index: int = _rng.randi_range(0, _definitions.size() - 1)
	return _definitions[index].to_dict()


## True when an item belongs to no specific character or matches the active roster.
static func is_item_usable_by_roster(item: Dictionary, roster: Array[String]) -> bool:
	var req := String(item.get("character_id", &""))
	return req.is_empty() or roster.is_empty() or roster.has(req)


## Rolls a loot item valid for the current party roster, filtering out other
## characters' exclusive skill upgrades and already-owned / duplicate upgrades.
static func roll_item_for_roster(roster: Array[String], owned_mods: Array[StringName] = [], exclude_ids: Array[StringName] = []) -> Dictionary:
	var pool: Array[LootItemDefinition] = []
	for def in _definitions:
		var req := String(def.character_id)
		if not req.is_empty() and not roster.is_empty() and not roster.has(req):
			continue
		if def.kind == KIND_SKILL_UPGRADE:
			if owned_mods.has(def.mod_id) or exclude_ids.has(def.id):
				continue
		pool.append(def)
	if pool.is_empty():
		return roll_random_item()
	var index: int = _rng.randi_range(0, pool.size() - 1)
	return pool[index].to_dict()


static func get_item(item_id: StringName) -> Dictionary:
	for definition in _definitions:
		if definition.id == item_id:
			return definition.to_dict()
	return {}


static func item_count() -> int:
	return _definitions.size()


## Every sheet must stay valid, or a typo in one .tres silently ships a broken
## roll. Exposed for tests.
static func all_definitions_valid() -> bool:
	var seen: Dictionary = {}
	for definition in _definitions:
		if not definition.is_valid():
			return false
		if seen.has(definition.id):
			return false
		seen[definition.id] = true
	return true
