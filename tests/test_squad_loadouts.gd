extends "res://tests/framework/test_case.gd"

const SquadStoreScript = preload("res://scripts/meta/squad_loadout_store.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const SpringEncounterCatalogScript = preload("res://scripts/spring/spring_encounter_catalog.gd")
const SpringRunScript = preload("res://scripts/spring/spring_run.gd")
const SpringRunMigrationScript = preload("res://scripts/spring/spring_run_migration.gd")
const LevelCatalogScript = preload("res://scripts/battle/level_catalog.gd")

const TEST_SAVE_PATH := "user://squad_loadouts_test.json"

func _run() -> void:
	_test_three_persistent_teams()
	_test_party_constraints()
	_test_spring_encounters_use_the_selected_party()
	_test_tutorial_roster_remains_fixed()
	_test_v3_saves_migrate_without_losing_progress()
	_cleanup()
	_report()

func _test_three_persistent_teams() -> void:
	var state := SquadStoreScript.load_state(TEST_SAVE_PATH)
	_check(state.teams.size() == 3, "the hub creates exactly three named squads")
	_check(state.teams[0].members == ["sakura"], "the first squad preserves the existing Spring lead")
	_check(state.active_team == 0, "the first squad is selected by default")
	_check(SquadStoreScript.set_team_name(1, "春日远征", TEST_SAVE_PATH), "a squad can be renamed")
	_check(SquadStoreScript.team_name(1, TEST_SAVE_PATH) == "春日远征", "renamed squad persists")
	_check(SquadStoreScript.set_team_members(1, ["sevrin", "sakura"], TEST_SAVE_PATH), "a squad can save two distinct characters")
	_check(SquadStoreScript.set_active_team(1, TEST_SAVE_PATH), "a populated squad can become active")
	_check(SquadStoreScript.active_character_ids(TEST_SAVE_PATH) == ["sevrin", "sakura"], "active squad order is preserved after reload")
	_check(not SquadStoreScript.set_active_team(2, TEST_SAVE_PATH), "an empty squad cannot become the active formation")

func _test_party_constraints() -> void:
	_check(not SquadStoreScript.set_team_members(0, ["sakura", "sakura"], TEST_SAVE_PATH), "duplicate characters are rejected")
	_check(not SquadStoreScript.set_team_members(0, ["sakura", "sevrin", "sakura", "sevrin"], TEST_SAVE_PATH), "party size above three is rejected")
	_check(not SquadStoreScript.set_team_name(0, "   ", TEST_SAVE_PATH), "blank squad names are rejected")
	_check(SquadStoreScript.set_team_name(0, "12345678901234567890", TEST_SAVE_PATH), "long names are safely accepted and shortened")
	_check(SquadStoreScript.team_name(0, TEST_SAVE_PATH).length() <= 12, "squad names are capped at twelve characters")

func _test_spring_encounters_use_the_selected_party() -> void:
	var party: Array[String] = ["sevrin", "sakura"]
	var encounter = SpringEncounterCatalogScript.build(&"B001", party)
	_check(encounter != null, "Spring encounter accepts a two-character squad")
	_check(encounter.character_ids == party, "Spring encounter preserves squad order")
	_check(encounter.ally_cells.size() == 1, "a second character receives a distinct deployment cell")
	var expanded = SpringEncounterCatalogScript.build(&"B001", party)
	_check(expanded.ally_cells[0] == Vector2i(2, 6), "second member uses the left deployment slot")
	var invalid: Array[String] = ["sakura", "sakura"]
	_check(SpringEncounterCatalogScript.build(&"B001", invalid) == null, "duplicate party members cannot enter an encounter")
	var unknown_party: Array[String] = ["sakura", "sevrin", "missing"]
	_check(SpringEncounterCatalogScript.build(&"B001", unknown_party) == null, "unknown party members cannot enter an encounter")

func _test_tutorial_roster_remains_fixed() -> void:
	var levels := LevelCatalogScript.create_prototype_levels()
	_check(not levels.is_empty(), "tutorial levels remain registered")
	_check(levels[0].character_ids == ["sevrin"], "tutorial chapter keeps its authored Sevrin roster")

func _test_v3_saves_migrate_without_losing_progress() -> void:
	var legacy := {"version": 3, "seed": 17, "template_id": 1, "hero": {"health": 1500}}
	var defaults := {
		"hero_character_id": SpringRunScript.HERO_CHARACTER_ID,
		"base_max_health": SpringRunScript.HERO_BASE_MAX_HEALTH,
		"base_attack": SpringRunScript.HERO_BASE_ATTACK,
		"base_defense": SpringRunScript.HERO_BASE_DEFENSE,
		"base_magic_resistance": SpringRunScript.HERO_BASE_MAGIC_RESISTANCE,
	}
	var error := SpringRunMigrationScript.migrate_to_current(legacy, SpringRunScript.SAVE_VERSION, defaults)
	_check(error.is_empty(), "Spring version 3 save migrates to version 4")
	_check(int(legacy.get("version", 0)) == 4, "migration advances the save version")
	_check(legacy.get("party_character_ids", []) == [], "legacy run has no forced new squad snapshot")
	_check(legacy.get("hero", {}).get("character_id", "") == "sakura", "legacy Spring lead remains Sakura")
	_check(int(legacy.get("hero", {}).get("health", 0)) == 1500, "migration preserves existing hero health")

func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
