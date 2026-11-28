class_name CharacterCatalog
extends RefCounted

## Loads playable characters from data/characters/.
##
## The roster is an explicit array rather than a directory scan, for the same
## reason the level catalog is: the set of playable characters is a design
## decision that should be reviewable in one place, not a side effect of which
## files happen to be on disk.

const CatalogScript = preload("res://scripts/battle/character_definition.gd")

const SEVRIN = preload("res://data/characters/sevrin.tres")
const SAKURA = preload("res://data/characters/sakura.tres")
const DEST_LEE = preload("res://data/characters/dest_lee.tres")


static func all_definitions() -> Array[CharacterDefinition]:
	var definitions: Array[CharacterDefinition] = []
	for entry in [SEVRIN, SAKURA, DEST_LEE]:
		var definition := entry as CharacterDefinition
		if definition == null:
			push_error("CharacterCatalog: %s is not a CharacterDefinition" % str(entry))
			continue
		definitions.append(definition)
	return definitions


static func has_definition(character_id: String) -> bool:
	return get_definition(character_id) != null


static func get_definition(character_id: String):
	for definition in all_definitions():
		if String(definition.character_id) == character_id:
			return definition
	return null


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for definition in all_definitions():
		ids.append(String(definition.character_id))
	return ids


## The character the prototype starts with when a level does not name one.
static func default_id() -> String:
	return "sevrin"
