extends "res://tests/framework/test_case.gd"

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const CatalogScript = preload("res://scripts/battle/enemy_catalog.gd")


func _run() -> void:
	_test_catalog_contents()
	_test_profile_values()
	_test_controller_uses_profiles()
	_test_unknown_archetype_is_rejected()
	_test_default_archetype()


func _test_catalog_contents() -> void:
	var definitions: Array = CatalogScript.definitions()
	_check(definitions.size() == 3, "catalog exposes three enemy profiles")

	for definition in definitions:
		_check(definition != null, "profile %s loads from its .tres" % String(definition.archetype_id))
		_check(definition.is_valid(), "profile %s passes validation" % String(definition.archetype_id))
		_check(not definition.display_name_zh.strip_edges().is_empty(), "profile %s has a display name" % String(definition.archetype_id))

	var ids: Array[String] = CatalogScript.known_archetype_ids()
	_check(ids.has("vanguard"), "catalog knows the vanguard")
	_check(ids.has("marksman"), "catalog knows the marksman")
	_check(ids.has("area_controller"), "catalog knows the area controller")
	_check(CatalogScript.DEFAULT_ARCHETYPE == "vanguard", "the default archetype is the vanguard")


func _test_profile_values() -> void:
	var vanguard = CatalogScript.get_definition("vanguard")
	_check(vanguard.health == 3200, "vanguard health matches the baseline")
	_check(vanguard.attack == 1400, "vanguard attack matches the baseline")
	_check(vanguard.defense == 700, "vanguard defense matches the baseline")
	_check(vanguard.magic_resistance == 350, "vanguard magic resistance matches the baseline")

	var marksman = CatalogScript.get_definition("marksman")
	_check(marksman.health == 2000, "marksman health matches the baseline")
	_check(marksman.attack == 1200, "marksman attack matches the baseline")
	_check(marksman.defense == 350, "marksman defense matches the baseline")
	_check(marksman.magic_resistance == 250, "marksman magic resistance matches the baseline")

	var controller = CatalogScript.get_definition("area_controller")
	_check(controller.health == 2600, "area controller health matches the baseline")
	_check(controller.attack == 1100, "area controller attack matches the baseline")
	_check(controller.defense == 450, "area controller defense matches the baseline")
	_check(controller.magic_resistance == 650, "area controller magic resistance matches the baseline")

	# The board token glyph comes from the profile, so three archetypes are
	# distinguishable at a glance instead of every enemy rendering as 锋.
	_check(vanguard.glyph == "锋", "vanguard carries its board glyph")
	_check(marksman.glyph == "射", "marksman carries its board glyph")
	_check(controller.glyph == "术", "area controller carries its board glyph")

	_check(CatalogScript.get_definition("sorcerer") == null, "an unknown id returns null")
	_check(not CatalogScript.has_definition("sorcerer"), "an unknown id is not reported as known")
	_check(not CatalogScript.has_definition(""), "the empty id is not reported as known")


func _test_controller_uses_profiles() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var archetypes: Array[String] = ["marksman"]
	_check(battle.start_encounter(Vector2i(1, 3), [Vector2i(6, 3)], [], archetypes), "controller accepts a catalog archetype")

	var enemy = battle.get_actor("marksman_00")
	var profile = CatalogScript.get_definition("marksman")
	_check(enemy != null, "the encounter created the marksman actor")
	_check(enemy.health == profile.health, "actor health comes from the profile")
	_check(enemy.attack == profile.attack, "actor attack comes from the profile")
	_check(enemy.defense == profile.defense, "actor defense comes from the profile")
	_check(enemy.magic_resistance == profile.magic_resistance, "actor magic resistance comes from the profile")
	_check(enemy.glyph == profile.glyph and enemy.glyph == "射", "the board token glyph comes from the profile")
	battle.queue_free()


func _test_unknown_archetype_is_rejected() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 3), [Vector2i(5, 3)])
	var survivor = battle.get_actor("vanguard_00")
	var health_before: int = survivor.health

	var bad: Array[String] = ["sorcerer"]
	_check(not battle.start_encounter(Vector2i(1, 3), [Vector2i(2, 3)], [], bad), "controller rejects an unknown archetype")
	_check(battle.get_actor("vanguard_00") != null, "rejected setup leaves the previous encounter in place")
	_check(battle.get_actor("vanguard_00").health == health_before, "rejected setup does not damage the previous actors")
	battle.queue_free()


func _test_default_archetype() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 3), [Vector2i(5, 3)]), "controller accepts a setup without archetypes")
	var enemy = battle.get_actor("vanguard_00")
	_check(enemy != null, "omitting archetypes falls back to the vanguard")
	_check(enemy.health == CatalogScript.get_definition("vanguard").health, "the fallback uses the vanguard profile")
	battle.queue_free()
