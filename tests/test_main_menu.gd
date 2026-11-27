extends "res://tests/framework/test_case.gd"

const MenuScript = preload("res://scripts/ui/main_menu.gd")
const LobbyScript = preload("res://scripts/ui/lobby_view.gd")


func _run() -> void:
	_test_main_menu_navigation_and_layout()
	await _test_lobby_scene_and_map_selector()
	await _test_spring_entry_loads()
	_report()


func _test_main_menu_navigation_and_layout() -> void:
	var menu := Control.new()
	menu.set_script(MenuScript)
	root.add_child(menu)
	menu.size = Vector2(1280.0, 720.0)

	_check(menu.selected_option == 0, "main menu initially selects Enter Lobby")
	_check(menu.OPTIONS.size() == 2, "Enter Lobby and Exit are the two main menu options")
	_check(str(menu.OPTIONS[0]["label"]) == "进入大厅", "the primary menu option leads into the Camp Lobby")

	menu._move_selection(1)
	_check(menu.selected_option == 1, "down navigation selects Exit Game")
	menu._move_selection(1)
	_check(menu.selected_option == 0, "down navigation wraps back to Enter Lobby")
	menu._move_selection(-1)
	_check(menu.selected_option == 1, "up navigation wraps to Exit Game")

	var start_rect: Rect2 = menu._option_rect(0)
	var exit_rect: Rect2 = menu._option_rect(1)
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://spring_run.json"))
	var map = packed.instantiate()
	root.add_child(map)
	await process_frame
	_check(map.run != null, "opening the map starts a run")
	if map.run != null:
		_check(map.run.exploration.stamina == ExplorationState.STAMINA_MAX, "the map opens with ten stamina")
		_check(map.run.template.places.size() == 11, "the opened map carries eleven places")
	map.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://spring_run.json"))
