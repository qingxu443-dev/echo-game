class_name EnemyCatalog
extends RefCounted

## Loads the enemy profiles from data/enemies/.
##
## The roster is an explicit list rather than a directory scan, for the same
## reason the character and level rosters are: which enemies exist is a decision
## worth reviewing, and a stray .tres should not join a fight because it was
## dropped in a folder.
##
## Adding an archetype is therefore one .tres plus one line here. What it *does*
## is its own `actions` list in the data; writing a new behaviour - a new kind of
## action - is the only thing that still needs a branch, in IntentPlanner.

const VANGUARD_DEFINITION = preload("res://data/enemies/vanguard.tres")
const MARKSMAN_DEFINITION = preload("res://data/enemies/marksman.tres")
const AREA_CONTROLLER_DEFINITION = preload("res://data/enemies/area_controller.tres")

## 春之境 (§13). Five ordinary archetypes. §13 fixes their names and rosters but
## the property table it points at ("见第二章") does not exist in the document, so
## these numbers are DRAFT: they sit in the same band as the prototype trio and
## are replaced the moment the author publishes the table. Only the roster and
## the action of each one are design decisions.
const PETAL_WARRIOR_DEFINITION = preload("res://data/enemies/petal_warrior.tres")
const PETAL_ARCHER_DEFINITION = preload("res://data/enemies/petal_archer.tres")
const WITHERED_GUARD_DEFINITION = preload("res://data/enemies/withered_guard.tres")
const WIND_RANGER_DEFINITION = preload("res://data/enemies/wind_ranger.tres")
const SPRING_BLIGHT_DEFINITION = preload("res://data/enemies/spring_blight.tres")

## 精英 (§14). Health / attack / defence / magic resistance are the document's
## post-30%-nerf final values, not drafts.
const CRIMSON_SWORD_GUARD_DEFINITION = preload("res://data/enemies/crimson_sword_guard.tres")
const HUNDRED_BLOOM_SNIPER_DEFINITION = preload("res://data/enemies/hundred_bloom_sniper.tres")
const ANCIENT_BULWARK_DEFINITION = preload("res://data/enemies/ancient_bulwark.tres")
const GALE_BLADE_DEFINITION = preload("res://data/enemies/gale_blade.tres")
const ROTTEN_BLOSSOM_WITCH_DEFINITION = preload("res://data/enemies/rotten_blossom_witch.tres")
const SAKURA_BEAST_DEFINITION = preload("res://data/enemies/sakura_beast.tres")

## Boss (§15). Same: the document's final values. Their signature skills are not
## implemented - the battle layer has no area-telegraph or battlefield-zone
## mechanism yet - so each one currently fights with its normal attack only.
const BOSS_PETALFALL_DEFINITION = preload("res://data/enemies/boss_petalfall.tres")
const BOSS_THOUSAND_BOUGHS_DEFINITION = preload("res://data/enemies/boss_thousand_boughs.tres")
const BOSS_SPRING_ECHO_DEFINITION = preload("res://data/enemies/boss_spring_echo.tres")

const DEFAULT_ARCHETYPE: String = "vanguard"

const PROTOTYPE_DEFINITIONS: Array = [
	VANGUARD_DEFINITION, MARKSMAN_DEFINITION, AREA_CONTROLLER_DEFINITION,
]
const SPRING_COMMON_DEFINITIONS: Array = [
	PETAL_WARRIOR_DEFINITION, PETAL_ARCHER_DEFINITION, WITHERED_GUARD_DEFINITION,
	WIND_RANGER_DEFINITION, SPRING_BLIGHT_DEFINITION,
]
const SPRING_ELITE_DEFINITIONS: Array = [
	CRIMSON_SWORD_GUARD_DEFINITION, HUNDRED_BLOOM_SNIPER_DEFINITION, ANCIENT_BULWARK_DEFINITION,
	GALE_BLADE_DEFINITION, ROTTEN_BLOSSOM_WITCH_DEFINITION, SAKURA_BEAST_DEFINITION,
]
const SPRING_BOSS_DEFINITIONS: Array = [
	BOSS_PETALFALL_DEFINITION, BOSS_THOUSAND_BOUGHS_DEFINITION, BOSS_SPRING_ECHO_DEFINITION,
]


static func definitions() -> Array:
	var all: Array = []
	all.append_array(PROTOTYPE_DEFINITIONS)
	all.append_array(SPRING_COMMON_DEFINITIONS)
	all.append_array(SPRING_ELITE_DEFINITIONS)
	all.append_array(SPRING_BOSS_DEFINITIONS)
	return all


static func get_definition(archetype_id: String) -> EnemyDefinition:
	for definition in definitions():
		if String(definition.archetype_id) == archetype_id:
			return definition
	return null


static func has_definition(archetype_id: String) -> bool:
	return get_definition(archetype_id) != null


static func known_archetype_ids() -> Array[String]:
	var ids: Array[String] = []
	for definition in definitions():
		ids.append(String(definition.archetype_id))
	return ids
