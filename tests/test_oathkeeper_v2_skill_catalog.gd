extends "res://tests/framework/test_case.gd"

## The Oathkeeper catalog: one normal attack (§15) plus the three V2 actives.
##
## Looked up by id rather than by list position, so adding a slot or reordering
## the catalog does not silently shift what these assertions are checking.

const CatalogScript = preload("res://scripts/battle/oathkeeper_v2_skill_catalog.gd")
const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")


func _run() -> void:
	var skills: Array[SkillDefinition] = CatalogScript.create_prototype_skills()
	_check(skills.size() == 4, "the catalog holds a normal attack plus three active skills")

	var normal = _find(skills, &"oathblade")
	_check(normal != null, "the normal attack is present")
	_check(normal.is_valid(), "the normal attack definition validates")
	_check(normal.ap_cost == 1 and normal.damage_multiplier == 1.0, "the normal attack costs one AP at full attack")
	_check(normal.min_range == 1 and normal.max_range == 1, "the normal attack reaches one cell")
	_check(String(normal.slot) == "normal", "the normal attack sits in the normal slot")

	var judgment = _find(skills, &"oathkeeper_judgment_mark")
	var shield = _find(skills, &"oath_shield")
	var guard = _find(skills, &"absolute_guard")
	_check(judgment != null and judgment.is_valid(), "Judgment Mark is present and valid")
	_check(shield != null and shield.is_valid(), "Oath Shield is present and valid")
	_check(guard != null and guard.is_valid(), "Absolute Guard is present and valid")

	_check(judgment.ap_cost == 1 and judgment.damage_multiplier == 0.55 and judgment.max_range == 4, "Judgment Mark data matches the solo rework baseline")
	_check(shield.ap_cost == 1 and guard.ap_cost == 2, "Oath Shield and Absolute Verdict AP costs match the baseline")
	_check(shield.target_mode == SkillDefinitionScript.TARGET_SELF and shield.min_range == 0 and shield.max_range == 0, "Oath Shield metadata represents an instant self-cast shield")

	var passive: SkillDefinition = CatalogScript.create_passive_skill()
	_check(passive.is_passive and passive.ap_cost == 0, "Oath Vow is represented as a zero-AP passive")
	_check(passive.is_valid(), "Oath Vow passive definition validates")
	_report()


func _find(skills: Array, skill_id: StringName):
	for skill in skills:
		if skill.skill_id == skill_id:
			return skill
	return null
