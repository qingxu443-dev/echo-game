class_name SummonCatalog
extends RefCounted

## Summons come from data/summons/. Explicit list, same reasoning as the level and
## character catalogs: which summons exist is a reviewable decision.

const DefinitionScript = preload("res://scripts/battle/summon_definition.gd")

const YU_BUBBLE = preload("res://data/summons/yu_bubble.tres")

## The summon the prototype starts with.
const DEFAULT_ID: StringName = &"yu_bubble"


static func all_definitions() -> Array[SummonDefinition]:
	var definitions: Array[SummonDefinition] = []
	for entry in [YU_BUBBLE]:
		var definition := entry as SummonDefinition
		if definition == null:
			push_error("SummonCatalog: %s is not a SummonDefinition" % str(entry))
			continue
		definitions.append(definition)
	return definitions


static func get_definition(summon_id: StringName) -> SummonDefinition:
	for definition in all_definitions():
		if definition.summon_id == summon_id:
			return definition
	return null


static func has_definition(summon_id: StringName) -> bool:
	return get_definition(summon_id) != null
