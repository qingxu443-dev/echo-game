extends "res://tests/framework/test_case.gd"

const SquadStoreScript = preload("res://scripts/meta/squad_loadout_store.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const SpringEncounterCatalogScript = preload("res://scripts/spring/spring_encounter_catalog.gd")
const SpringRunScript = preload("res://scripts/spring/spring_run.gd")
const SpringRunMigrationScript = preload("res://scripts/spring/spring_run_migration.gd")
const SpringBattleBridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")
const LevelCatalogScript = preload("res://scripts/battle/level_catalog.gd")

const TEST_SAVE_PATH := "user://squad_loadouts_test.json"

func _run() -> void:
	_test_three_persistent_teams()
	_test_party_constraints()
	_test_spring_encounters_use_the_selected_party()
	_test_tutorial_roster_remains_fixed()
	_test_v3_saves_migrate_without_losing_progress()
	_test_spring_snapshots_selected_party_and_health()
	await _test_party_vitals_enter_the_battle_scene()
	await _test_fragment_health_bonus_stacks_on_saved_vitals()
	_test_continue_uses_scaled_member_maximum()
	_cleanup()

func _test_three_persistent_teams() -> void:
	var state := SquadStoreScript.load_state(TEST_SAVE_PATH)
	_check(state.teams.size() == 3, "the hub creates exactly three named squads")
	_check(state.teams[0].members == ["sakura"], "the first squad preserves the existing Spring lead")
	_check(state.active_team == 0, "the first squad is selected by default")
	_check(SquadStoreScript.set_team_name(1, "春日远征", TEST_SAVE_PATH), "a squad can be renamed")
	_check(SquadStoreScript.team_name(1, TEST_SAVE_PATH) == "春日远征", "renamed squad persists")
	_check(SquadStoreScript.set_team_members(1, ["sevrin", "sakura"], TEST_SAVE_PATH), "a squad can save two distinct characters")
	_check(SquadStoreScript.set_active_team(1, TEST_SAVE_PATH), "a populated squad can become active")
	_check(not SquadStoreScript.set_team_members(1, [], TEST_SAVE_PATH), "the active squad cannot be emptied")
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
	_check(error.is_empty(), "Spring version 3 save migrates to version 5")
	_check(int(legacy.get("version", 0)) == SpringRunScript.SAVE_VERSION, "migration advances the save version")
	_check(legacy.get("party_character_ids", []) == [], "legacy run has no forced new squad snapshot")
	_check(legacy.get("hero", {}).get("character_id", "") == "sakura", "legacy Spring lead remains Sakura")
	_check(int(legacy.get("hero", {}).get("health", 0)) == 1500, "migration preserves existing hero health")

func _test_spring_snapshots_selected_party_and_health() -> void:
	var run = SpringRunScript.begin(29)
	run.hero_health = 1050
	var selected_party: Array[String] = ["sevrin", "sakura"]
	run.party_character_ids.assign(selected_party)
	_check(SpringBattleBridgeScript.prepare(run, &"B001", &"test_place"), "a Spring fight accepts the selected party snapshot")
	_check(run.hero_character_id == "sevrin", "the first selected member becomes the expedition lead")
	_check(run.hero_base_max_health == 3200 and run.hero_health == 1371, "changing lead preserves the previous health ratio")
	_check(SpringBattleBridgeScript.pending.get("character_ids", []) == ["sevrin", "sakura"], "battle bridge carries the ordered party")
	run.party_vitals = {
		"sevrin": {"health": 1600, "max_health": 3200},
		"sakura": {"health": 1050, "max_health": 2100},
	}
	var restored = SpringRunScript.from_dict(run.to_dict())
	_check(restored != null, "the updated Spring save round-trips")
	_check(restored.party_character_ids == ["sevrin", "sakura"], "the selected party survives save and reload")
	_check(int(restored.party_vitals.sakura.health) == 900, "individual member health survives save and reload")
	SpringBattleBridgeScript.clear_pending()

func _test_party_vitals_enter_the_battle_scene() -> void:
	var run := SpringRunScript.begin(29)
	run.party_character_ids.assign(["sevrin", "sakura", "dest_lee"])
	run.party_vitals = {
		"sevrin": {"health": 1600, "max_health": 3200},
		"sakura": {"health": 0, "max_health": 2100},
		"dest_lee": {"health": 800, "max_health": 2400},
	}
	_check(SpringBattleBridgeScript.prepare(run, &"B001", &"battle_1"), "prepare a wounded three-member party")
	var view = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(view)
	_check(view.spring_mode and view.controller.phase == BattleController.BattlePhase.DEPLOY, "normal battle scene enters deployment with the prepared party")
	_check(view.controller.actors.sevrin.health == 1600 and view.controller.actors.sevrin.max_health == 3200, "lead retains wounded health on entry")
	_check(view.controller.actors.sakura.health == 0 and view.controller.actors.sakura.is_defeated(), "a zero-health legacy member is retired, never revived by scene setup")
	_check(view.controller.actors.dest_lee.health == 800 and view.controller.actors.dest_lee.max_health == 1650, "the new character retains individual vitality")
	view.queue_free()
	SpringBattleBridgeScript.clear_pending()
	await process_frame


func _test_fragment_health_bonus_stacks_on_saved_vitals() -> void:
	var path := "user://squad_fragment_vitality_test.json"
	FragmentStore.default_path_override = path
	var store := FragmentStore.load_store(path)
	_check(store.add_modules([{
		"instance_id": "squad_hp_probe",
		"size": "small",
		"capacity": 1,
		"main_stat": "health",
		"sub_stat": "",
		"attributes": {"health": 5.0},
		"created_seed": 0,
	}]), "the vitality probe installs a valid 5% health module")
	_check(store.install("sakura", 0, "squad_hp_probe").get("ok", false), "the module equips to Sakura")
	_check(store.save(), "the module store persists before the encounter")
	var run := SpringRunScript.begin(31)
	run.party_character_ids.assign(["sakura"])
	run.hero_health = 1050
	run.party_vitals = {"sakura": {"health": 1050, "max_health": 2100}}
	run.sync_lead_vitals()
	_check(run.hero_max_health == 2205, "map vitals expose the module-scaled maximum for healing")
	run.hero_health = 100
	_check(run.heal_fraction(0.5) == 1103, "map healing restores a fraction of the scaled maximum")
	run.hero_health = 1103
	run.sync_lead_vitals()
	_check(SpringBattleBridgeScript.prepare(run, &"B001", &"battle_1"), "prepare a wounded Sakura with a health module")
	var view = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(view)
	_check(view.controller.actors.sakura.max_health == 2205, "the saved 1800 cap is scaled once by the equipped 5% module")
	_check(view.controller.actors.sakura.health == 1103, "wounded health keeps its ratio instead of growing for free")
	var carried := SpringBattleBridgeScript.pack_carry(view.run_state)
	var saved := {}
	for actor_id in view.controller.actors:
		var actor = view.controller.actors[actor_id]
		if actor.team == "player":
			saved[str(actor_id)] = {
				"health": actor.health,
				"max_health": actor.max_health,
				"base_max_health": PartyLoadout.unscaled_max_health(actor),
			}
	view.queue_free()
	SpringBattleBridgeScript.clear_pending()
	await process_frame

	_check(store.uninstall("sakura", 0).get("ok", false) and store.save(), "the module can be unequipped between encounters")
	run.party_vitals = saved
	run.battle_carry = carried
	_check(SpringBattleBridgeScript.prepare(run, &"B001", &"battle_1"), "prepare the same party after unequipping")
	var next_view = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(next_view)
	_check(next_view.controller.actors.sakura.max_health == 2100, "unequipping reclaims exactly the 5% maximum")
	_check(next_view.controller.actors.sakura.health == 1050, "unequipping reclaims the proportional health too")
	next_view.queue_free()
	SpringBattleBridgeScript.clear_pending()
	FragmentStore.default_path_override = ""
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	await process_frame


func _test_continue_uses_scaled_member_maximum() -> void:
	var run := SpringRunScript.begin(37)
	run.hero_character_id = "sakura"
	run.supplies = 5
	run.party_vitals = {"sakura": {"health": 0, "max_health": 2205, "base_max_health": 2100}}
	var outcome: Dictionary = SpringBattleBridgeScript.continue_run(run)
	_check(bool(outcome.get("ok", false)), "a lost legacy run can spend supplies to continue")
	_check(run.hero_health == 662, "continue heals 30% of the module-scaled maximum, not the unscaled one")
	_check(str(outcome.get("message", "")).contains("662 / 2205"), "continue reports the same scaled maximum the map will use")


func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
