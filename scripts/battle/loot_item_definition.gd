class_name LootItemDefinition
extends Resource

## Data-only loot item sheet. One .tres per item under data/loot/, exactly like
## the enemy sheets under data/enemies/ (M1) and the levels under data/levels/.
## Tuning numbers here means touching a resource file, not the code.
##
## The runtime contract stays a Dictionary: LootCatalog converts a definition
## with to_dict() so every existing consumer (RunState backpack, inventory view,
## enemy chest-steal buffs) keeps working unchanged.

@export var id: StringName = &""
@export var kind: String = ""
@export var kind_zh: String = ""
@export var name: String = ""
@export var desc: String = ""

## Equipment stats (weapon / armor). Zero for non-equipment.
@export var attack: int = 0
@export var defense: int = 0
@export var magic_resistance: int = 0
@export var max_health: int = 0
## Weapon-only: extra true damage on knockback collisions.
@export var collision_bonus: int = 0

## Consumable effects, single use in battle.
@export var heal: int = 0
@export var ap_gain: int = 0
@export var shield_gain: int = 0
@export var energy_gain: int = 0

## Skill upgrade only: which run mod activating this item grants, and which
## character owns that skill (empty = universal item for every character).
@export var mod_id: StringName = &""
@export var character_id: StringName = &""

## What an enemy gains when it cracks this chest open. Every item defines all
## four fields so the steal path never has to special-case a kind.
@export var enemy_buff_zh: String = ""
@export var enemy_attack: int = 0
@export var enemy_shield: int = 0
@export var enemy_heal: int = 0
@export var enemy_charge: bool = false

const KNOWN_KINDS: Array[String] = ["weapon", "armor", "consumable", "skill_upgrade"]


func is_valid() -> bool:
	if id == &"" or not KNOWN_KINDS.has(kind):
		return false
	if name.strip_edges().is_empty() or desc.strip_edges().is_empty():
		return false
	if kind == "skill_upgrade" and mod_id == &"":
		return false
	return true


## The stable Dictionary contract every consumer already speaks.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"kind_zh": kind_zh,
		"name": name,
		"desc": desc,
		"attack": attack,
		"defense": defense,
		"magic_resistance": magic_resistance,
		"max_health": max_health,
		"collision_bonus": collision_bonus,
		"heal": heal,
		"ap_gain": ap_gain,
		"shield_gain": shield_gain,
		"energy_gain": energy_gain,
		"mod_id": mod_id,
		"character_id": character_id,
		"enemy_buff_zh": enemy_buff_zh,
		"enemy_attack": enemy_attack,
		"enemy_shield": enemy_shield,
		"enemy_heal": enemy_heal,
		"enemy_charge": enemy_charge,
	}
