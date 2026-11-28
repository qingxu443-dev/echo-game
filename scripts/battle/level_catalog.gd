class_name LevelCatalog
extends RefCounted

## Loads the three prototype lessons from data/levels/.
##
## The play order is this explicit array, not a directory scan: a scan would make
## the sequence depend on filesystem ordering, and the encounter design principles
## require the progression to be fixed and reviewable. Levels are ordered from a
## single-rule lesson to a mixed roster. Adding a lesson means adding one .tres
## and one entry here.

const LESSON_CHARGE = preload("res://data/levels/lesson_charge.tres")
const LESSON_LANE = preload("res://data/levels/lesson_lane.tres")
const LESSON_MIXED = preload("res://data/levels/lesson_mixed.tres")
const ANOMALY_DEMO = preload("res://data/levels/anomaly_resonance.tres")

## Explicit optional scene registry, also used to validate suspended demo IDs.
static func optional_encounter(id: StringName) -> EncounterDefinition:
	return ANOMALY_DEMO if id == ANOMALY_DEMO.level_id else null


static func create_prototype_levels() -> Array[EncounterDefinition]:
	var levels: Array[EncounterDefinition] = []
	for level_file in [LESSON_CHARGE, LESSON_LANE, LESSON_MIXED]:
		var definition := level_file as EncounterDefinition
		if definition == null:
			push_error("LevelCatalog: %s is not an EncounterDefinition" % str(level_file))
			continue
		levels.append(definition)
	return levels


static func level_count() -> int:
	return create_prototype_levels().size()
