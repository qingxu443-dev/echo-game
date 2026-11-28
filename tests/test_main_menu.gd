extends "res://tests/framework/test_case.gd"

const MenuScript = preload("res://scripts/ui/main_menu.gd")
const LobbyScript = preload("res://scripts/ui/lobby_view.gd")


func _run() -> void:
	_test_main_menu_navigation_and_layout()
	_test_failed_atelier_write_keeps_wallet()
	await _test_lobby_scene_and_map_selector()
	await _test_spring_entry_loads()
	_test_expedition_write_failure_recovers()
	await _test_battle_reward_replay()
	await _test_tutorial_loadout_requires_ready_encounter()
	await _test_spring_event_response_resumes()


func _test_main_menu_navigation_and_layout() -> void:
	var menu := Control.new()
	menu.set_script(MenuScript)
	root.add_child(menu)
	menu.size = Vector2(1280.0, 720.0)

	_check(menu.selected_option == 0, "main menu initially selects Enter Lobby")
	_check(menu.OPTIONS.size() == 3, "the title exposes Lobby, Custom Level and Exit")
	_check(str(menu.OPTIONS[0]["label"]) == "进入大厅", "the primary menu option leads into the Camp Lobby")

	menu._move_selection(1)
	_check(menu.selected_option == 1, "down navigation selects Custom Level")
	menu._move_selection(1)
	_check(menu.selected_option == 2, "next selection is Exit Game")
	menu._move_selection(1)
	_check(menu.selected_option == 0, "down navigation wraps back to Enter Lobby")
	menu._move_selection(-1)
	_check(menu.selected_option == 2, "up navigation wraps to Exit Game")

	var start_rect: Rect2 = menu._option_rect(0)
	var exit_rect: Rect2 = menu._option_rect(2)
	_check(start_rect.size.x > 0.0 and start_rect.size.y > 0.0, "Enter Lobby hit area is non-empty")
	_check(exit_rect.size.x > 0.0 and exit_rect.size.y > 0.0, "Exit Game hit area is non-empty")
	_check(not start_rect.intersects(exit_rect), "Enter Lobby and Exit Game do not overlap")
	_check(exit_rect.position.y > start_rect.end.y, "Exit Game sits cleanly below Enter Lobby")
	_check(exit_rect.end.y <= 720.0, "the last menu option fits on a 720-high screen")

	menu.size = Vector2(1600.0, 900.0)
	var wide_start: Rect2 = menu._option_rect(0)
	_check(wide_start.size.x > start_rect.size.x, "option hit rect scales cleanly on wider viewports")
	menu.queue_free()


func _test_lobby_scene_and_map_selector() -> void:
	_check(ResourceLoader.exists(MenuScript.LOBBY_SCENE_PATH), "the lobby scene exists at the menu's path")
	var packed = load(MenuScript.LOBBY_SCENE_PATH)
	_check(packed != null, "the lobby scene loads")
	if packed == null:
		return

	var lobby = packed.instantiate()
	root.add_child(lobby)
	await process_frame
	lobby.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lobby.size = Vector2(1280.0, 720.0)

	var exp_btn: Rect2 = lobby.expedition_button_rect()
	_check(exp_btn.position.x > 640.0 and exp_btn.position.y > 360.0, "the Select Map button sits in the bottom-right quadrant")
	_check(exp_btn.end.x <= 1280.0 and exp_btn.end.y <= 720.0, "the Select Map button stays inside the 1280x720 viewport")
	_check(not lobby.map_selector_open, "the map selector starts closed on lobby entry")

	# Clicking the bottom-right button opens the map selector overlay.
	lobby._handle_click(exp_btn.get_center())
	_check(lobby.map_selector_open, "clicking the bottom-right button opens the map selector")
	_check(lobby.MAP_ENTRIES.size() == 3, "the selector lists Tutorial, 春之境, and an upcoming slot")

	var card0: Rect2 = lobby.map_card_rect(0)
	var card1: Rect2 = lobby.map_card_rect(1)
	var card2: Rect2 = lobby.map_card_rect(2)
	_check(not card0.intersects(card1) and not card1.intersects(card2), "map selector cards do not overlap")
	_check(card2.end.x <= lobby.selector_panel_rect().end.x, "all map cards fit inside the selector panel")
	var normal_btn: Rect2 = lobby.spring_normal_button_rect()
	var hard_btn: Rect2 = lobby.spring_hard_button_rect()
	_check(not normal_btn.intersects(hard_btn), "春之境 normal and hard buttons do not overlap")
	_check(card1.encloses(normal_btn) and card1.encloses(hard_btn), "春之境 normal and hard buttons fit inside the card")

	lobby.move_map_selection(1)
	_check(lobby.selected_map_index == 1, "right navigation advances to 春之境")
	_check(not lobby.activate_map(2), "locked upcoming region cannot be launched")
	_check(not lobby.status_notice.is_empty(), "clicking a locked region reports a clear notice")

	lobby._handle_click(lobby.close_selector_rect().get_center())
	_check(not lobby.map_selector_open, "clicking the close button dismisses the map selector")

	_check(ResourceLoader.exists(LobbyScript.BATTLE_SCENE_PATH), "tutorial battle scene exists at the lobby's path")
	_check(ResourceLoader.exists(LobbyScript.SPRING_SCENE_PATH), "春之境 scene exists at the lobby's path")
	lobby.queue_free()


## The lobby is the way into 春之境, so a wrong path there would ship as a
## dead card that no gameplay suite could see. Load the scene for real and let
## its _ready() build a run.
func _test_spring_entry_loads() -> void:
	_check(ResourceLoader.exists(LobbyScript.SPRING_SCENE_PATH), "the 春之境 scene exists at the lobby's path")
	var packed = load(LobbyScript.SPRING_SCENE_PATH)
	_check(packed != null, "the 春之境 scene loads")
	if packed == null:
		return
	var save_path := "user://spring_menu_test_%d.json" % OS.get_process_id()
	var stash_path := "user://atelier_menu_test_%d.json" % OS.get_process_id()
	_check(AtelierStash.save_state({"shards": 105, "loadout": ["item_dusk_potion"]}, stash_path), "the test stash is persisted")
	var map = packed.instantiate()
	map.save_path = save_path
	map.atelier_save_path = stash_path
	root.add_child(map)
	await process_frame
	_check(map.run != null, "opening the map starts a run")
	if map.run != null:
		_check(map.run.exploration.stamina == ExplorationState.STAMINA_MAX, "the map opens with ten stamina")
		_check(map.run.template.places.size() == 11, "the opened map carries eleven places")
		_check(map.run.battle_backpack().size() == 1, "a fresh expedition receives the packed item")
	var checkpoint := SpringRun.load_from_file(save_path)
	_check(checkpoint != null and checkpoint.battle_backpack().size() == 1, "the starting pack survives an immediate restart")
	_check(AtelierStash.load_state(stash_path)["loadout"].is_empty(), "a fresh expedition clears the atelier pack")
	map.queue_free()
	await process_frame

	_check(AtelierStash.buy_and_pack(AtelierStash.load_state(stash_path), "item_echo_hourglass", stash_path)["ok"],
		"a second pack can be prepared while a spring save exists")
	var resumed = packed.instantiate()
	resumed.save_path = save_path
	resumed.atelier_save_path = stash_path
	root.add_child(resumed)
	await process_frame
	_check(resumed.run.battle_backpack().size() == 1, "resuming uses the saved run backpack")
	_check(AtelierStash.load_state(stash_path)["loadout"] == ["item_echo_hourglass"], "resuming leaves paid atelier supplies packed")
	resumed.queue_free()
	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(stash_path)


func _test_spring_event_response_resumes() -> void:
	var packed: PackedScene = load(LobbyScript.SPRING_SCENE_PATH)
	var path := "user://spring_event_resume_test_%d.json" % OS.get_process_id()
	var run := SpringRun.begin(3)
	run.random_event_id = &"forest_noise"
	run.supplies = 4
	var place := run.template.place_by_id(&"event_random")
	var map = packed.instantiate()
	map.run = run
	map.save_path = path
	root.add_child(map)
	map._open_event(place)
	map._choose_event_option(&"forest_noise", 1)
	_check(FileAccess.file_exists(path), "choosing the event option writes its checkpoint")
	map.queue_free()
	await process_frame

	var resumed = packed.instantiate()
	resumed.save_path = path
	root.add_child(resumed)
	_check(resumed.event_open and resumed.event_place.id == place.id, "resuming reopens the committed event panel")
	_check(StringName(resumed.event_result.get("battle", "")) == &"B001" and resumed.run.supplies == 2,
		"the ambush persists and its already-paid cost is not charged again")
	resumed.queue_free()
	DirAccess.remove_absolute(path)


func _test_failed_atelier_write_keeps_wallet() -> void:
	var state := {"shards": 105, "loadout": ["item_dusk_potion"]}
	var before := state.duplicate(true)
	var directory := "user://atelier_failed_write_%d" % OS.get_process_id()
	_check(DirAccess.make_dir_absolute(directory) == OK, "use a directory where the save file must go")
	_check(not AtelierStash.buy_and_pack(state, "item_echo_hourglass", directory)["ok"], "a failed write rejects the purchase")
	_check(state == before, "a failed purchase leaves the wallet and loadout intact")
	_check(not AtelierStash.unpack_and_refund(state, "item_dusk_potion", directory)["ok"], "a failed write rejects the refund")
	_check(state == before, "a failed refund leaves the wallet and loadout intact")
	_check(DirAccess.dir_exists_absolute(directory), "a failed write leaves the existing destination intact")
	DirAccess.remove_absolute(directory)


func _test_expedition_write_failure_recovers() -> void:
	var run_path := "user://spring_checkpoint_blocked_%d" % OS.get_process_id()
	var stash_path := "user://spring_checkpoint_stash_%d.json" % OS.get_process_id()
	var wallet := {"shards": 105, "loadout": ["item_dusk_potion"]}
	_check(AtelierStash.save_state(wallet, stash_path), "seed the expedition wallet")
	var journal := SpringSaveTransaction.journal_path(stash_path)
	_check(DirAccess.make_dir_absolute(journal) == OK, "block the write-ahead record")
	_check(SpringRunStorage.start(3, true, run_path, stash_path) == null, "an expedition cannot start without its recovery record")
	_check(not FileAccess.file_exists(run_path) and AtelierStash.load_state(stash_path) == wallet,
		"neither destination changes if recording the transfer fails")
	DirAccess.remove_absolute(journal)
	_check(DirAccess.make_dir_absolute(run_path) == OK, "block the checkpoint destination")
	_check(SpringRunStorage.start(3, true, run_path, stash_path) == null, "a failed checkpoint prevents play")
	_check(SpringSaveTransaction.is_pending(stash_path), "the transfer remains recoverable")
	_check(AtelierStash.load_state(stash_path) == wallet, "the pack is still in the wallet before recovery")
	_check(not AtelierStash.buy_and_pack(wallet, "item_echo_hourglass", stash_path)["ok"], "a pending transfer blocks wallet mutations")
	DirAccess.remove_absolute(run_path)
	_check(SpringSaveTransaction.recover(run_path, stash_path), "the next load finishes the expedition transfer")
	var restored := SpringRun.load_from_file(run_path)
	_check(restored != null and restored.route_plan.hard_mode and restored.battle_backpack().size() == 1,
		"recovery opens the original expedition with its pack")
	_check(AtelierStash.load_state(stash_path) == {"shards": 105, "loadout": []}, "the paid pack is removed once")
	_check(SpringSaveTransaction.recover(run_path, stash_path) and not SpringSaveTransaction.is_pending(stash_path),
		"repeating recovery is a no-op")
	DirAccess.remove_absolute(run_path)
	DirAccess.remove_absolute(stash_path)


func _test_battle_reward_replay() -> void:
	var run_path := "user://spring_settlement_run_%d.json" % OS.get_process_id()
	var stash_path := "user://spring_settlement_blocked_%d" % OS.get_process_id()
	var original := SpringRun.begin(3)
	_check(original.save_to_file(run_path), "write the pre-fight checkpoint")
	_check(DirAccess.make_dir_absolute(stash_path) == OK, "block the second write of battle settlement")

	var result := {"result": "victory", "kind": "battle", "place": "battle_1", "chests_saved": 1}
	SpringBattleBridge.last_result = result
	var scene: PackedScene = load(LobbyScript.SPRING_SCENE_PATH)
	var map = scene.instantiate()
	map.save_path = run_path
	map.atelier_save_path = stash_path
	root.add_child(map)
	_check(map.run == null and SpringSaveTransaction.is_pending(stash_path), "a partially written settlement pauses play")
	var checkpoint_after_first_attempt := SpringRun.load_from_file(run_path)
	_check(checkpoint_after_first_attempt != null and checkpoint_after_first_attempt.battles_won == 1,
		"the checkpoint was written before the blocked wallet")
	var coins_after_first_attempt: int = checkpoint_after_first_attempt.coins if checkpoint_after_first_attempt != null else -1
	map.queue_free()
	await process_frame

	DirAccess.remove_absolute(stash_path)
	SpringBattleBridge.last_result = result
	var resumed = scene.instantiate()
	resumed.save_path = run_path
	resumed.atelier_save_path = stash_path
	root.add_child(resumed)
	_check(resumed.run != null and resumed.run.battles_won == 1 and resumed.run.coins == coins_after_first_attempt,
		"resuming consumes a replayed result without reapplying it")
	_check(AtelierStash.load_state(stash_path)["shards"] == AtelierStash.STARTING_SHARDS + 35,
		"the recovered reward credits the wallet once")
	_check(not SpringBattleBridge.has_result() and not SpringSaveTransaction.is_pending(stash_path),
		"the scene clears the completed handoff")
	resumed.queue_free()
	DirAccess.remove_absolute(run_path)
	DirAccess.remove_absolute(stash_path)


func _test_tutorial_loadout_requires_ready_encounter() -> void:
	var path := "user://atelier_tutorial_pack_%d.json" % OS.get_process_id()
	_check(AtelierStash.save_state({"shards": 105, "loadout": ["item_dusk_potion"]}, path), "seed tutorial supplies")
	var packed: PackedScene = load(LobbyScript.BATTLE_SCENE_PATH)
	var level: EncounterDefinition = LevelCatalog.create_prototype_levels()[0]
	var valid_position := level.player_cell
	level.player_cell = Vector2i(-1, -1)
	SpringBattleBridge.tutorial_loadout_requested = true
	var rejected = packed.instantiate()
	rejected.atelier_save_path = path
	root.add_child(rejected)
	level.player_cell = valid_position
	_check(rejected.controller.phase == BattleController.BattlePhase.FINISHED, "invalid tutorial encounter never becomes playable")
	_check(AtelierStash.load_state(path)["loadout"] == ["item_dusk_potion"], "rejected encounter preserves the pack")
	rejected.queue_free()
	await process_frame

	SpringBattleBridge.tutorial_loadout_requested = true
	var tutorial = packed.instantiate()
	tutorial.atelier_save_path = path
	root.add_child(tutorial)
	_check(tutorial.controller.phase == BattleController.BattlePhase.PLAYER, "valid tutorial opens for play")
	_check(tutorial.run_state.backpack.size() == 1, "the playable tutorial receives its pack")
	_check(AtelierStash.load_state(path)["loadout"].is_empty(), "the pack is claimed once")
	tutorial._begin_fresh_run()
	_check(tutorial.run_state.backpack.is_empty(), "tutorial retries do not reclaim the pack")
	tutorial.queue_free()
	DirAccess.remove_absolute(path)
