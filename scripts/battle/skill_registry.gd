class_name SkillRegistry
extends RefCounted

## Resolves skill ids to definitions across every character kit.
##
## One lookup point means a character's .tres only has to name skill ids; it does
## not need to know which catalog file they came from. Adding a character adds a
## catalog here and nothing else.

const OathkeeperCatalogScript = preload("res://scripts/battle/oathkeeper_v2_skill_catalog.gd")
const SakuraCatalogScript = preload("res://scripts/battle/sakura_skill_catalog.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")


static func all_skills() -> Array[SkillDefinition]:
	var skills: Array[SkillDefinition] = []
	skills.append_array(OathkeeperCatalogScript.create_prototype_skills())
	skills.append(OathkeeperCatalogScript.create_passive_skill())
	skills.append_array(SakuraCatalogScript.create_skills())
	return skills


static func get_skill(skill_id: StringName) -> SkillDefinition:
	if skill_id == &"":
		return null
	for skill in all_skills():
		if skill.skill_id == skill_id:
			return skill
	return null


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
