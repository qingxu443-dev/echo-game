class_name SkillRegistry
extends RefCounted

## Resolves skill ids to definitions across every character kit.
##
## One lookup point means a character's .tres only has to name skill ids; it does
## not need to know which catalog file they came from. Adding a character adds a
## catalog here and nothing else.
##
## The catalogues build fresh Resource instances on every call, so querying them
## directly meant the target-hint pass allocated roughly seventeen resources per
## enemy per frame - the hints are drawn in _draw, and both can_target() and
## can_target_ally() resolve the same skill again. The tables are built once and
## indexed by id instead.
##
## Treat returned definitions as read-only: they are shared. Nothing mutates them
## today, and per-skill tuning belongs in the catalogue rather than in a caller
## that quietly rewrites the shared copy.

const OathkeeperCatalogScript = preload("res://scripts/battle/oathkeeper_v2_skill_catalog.gd")
const SakuraCatalogScript = preload("res://scripts/battle/sakura_skill_catalog.gd")
const DestLeeCatalogScript = preload("res://scripts/battle/dest_lee_skill_catalog.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")

## Built on first use. GDScript statics live for the process, which is what makes
## this a cache rather than a leak: the set of skills is fixed at load time.
static var _skills: Array[SkillDefinition] = []
static var _by_id: Dictionary = {}


static func _ensure_built() -> void:
	if not _skills.is_empty():
		return
	_skills = []
	_by_id = {}
	_skills.append_array(OathkeeperCatalogScript.create_prototype_skills())
	_skills.append(OathkeeperCatalogScript.create_passive_skill())
	_skills.append_array(SakuraCatalogScript.create_skills())
	_skills.append_array(DestLeeCatalogScript.create_skills())
	for skill in _skills:
		# A duplicated id would silently shadow an earlier skill, and the symptom
		# would be a button that casts something else.
		if _by_id.has(skill.skill_id):
			push_error("SkillRegistry: duplicate skill id '%s'" % skill.skill_id)
			continue
		_by_id[skill.skill_id] = skill


static func all_skills() -> Array[SkillDefinition]:
	_ensure_built()
	return _skills


static func get_skill(skill_id: StringName) -> SkillDefinition:
	if skill_id == &"":
		return null
	_ensure_built()
	return _by_id.get(skill_id)


## The skills a character actually brings, in slot order, skipping empty slots.
static func skills_for_character(character_id: String) -> Array[SkillDefinition]:
	var skills: Array[SkillDefinition] = []
	var definition = CharacterCatalogScript.get_definition(character_id)
	if definition == null:
		return skills
	for skill_id in definition.skill_ids:
		var skill := get_skill(skill_id)
		if skill != null:
			skills.append(skill)
	return skills


## Bar entries: everything except passives, since a passive has no button.
static func active_skills_for_character(character_id: String) -> Array[SkillDefinition]:
	var active: Array[SkillDefinition] = []
	for skill in skills_for_character(character_id):
		if not skill.is_passive:
			active.append(skill)
	return active
