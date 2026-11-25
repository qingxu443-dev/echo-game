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

const DEFAULT_ARCHETYPE: String = "vanguard"


static func definitions() -> Array:
	return [VANGUARD_DEFINITION, MARKSMAN_DEFINITION, AREA_CONTROLLER_DEFINITION]


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
