extends "res://tests/framework/test_case.gd"

const MenuScript = preload("res://scripts/ui/main_menu.gd")


func _run() -> void:
	var menu := Control.new()
	menu.set_script(MenuScript)
	root.add_child(menu)
	menu.size = Vector2(1280.0, 720.0)

	_check(menu.selected_option == 0, "main menu initially selects Start Expedition")
	_check(menu.OPTIONS.size() == 3, "tutorial, 未尽之春 and Exit are the three options")
	_check(str(menu.OPTIONS[1]["label"]) == "未尽之春", "the second option opens the season run")

	menu._move_selection(1)
	_check(menu.selected_option == 1, "down navigation selects 未尽之春")
	menu._move_selection(1)
	_check(menu.selected_option == 2, "down navigation selects Exit Game")
	menu._move_selection(1)
	_check(menu.selected_option == 0, "down navigation wraps back to Start Expedition")
	menu._move_selection(-1)
	_check(menu.selected_option == 2, "up navigation wraps to Exit Game")

	var start_rect: Rect2 = menu._option_rect(0)
	var spring_rect: Rect2 = menu._option_rect(1)
	var exit_rect: Rect2 = menu._option_rect(2)
	_check(start_rect.size.x > 0.0 and start_rect.size.y > 0.0, "Start Expedition hit area is non-empty")
	_check(spring_rect.size.x > 0.0 and spring_rect.size.y > 0.0, "未尽之春 hit area is non-empty")
	_check(exit_rect.size.x > 0.0 and exit_rect.size.y > 0.0, "Exit Game hit area is non-empty")
	_check(not start_rect.intersects(spring_rect), "Start Expedition and 未尽之春 do not overlap")
	_check(not spring_rect.intersects(exit_rect), "未尽之春 and Exit Game do not overlap")
	_check(spring_rect.position.y > start_rect.end.y, "未尽之春 sits cleanly below Start Expedition")
	_check(exit_rect.position.y > spring_rect.end.y, "Exit Game sits cleanly below 未尽之春")
	_check(exit_rect.end.y <= 720.0, "the third option still fits on a 720-high screen")

	menu.size = Vector2(1600.0, 900.0)
	var wide_start: Rect2 = menu._option_rect(0)
	_check(wide_start.size.x > start_rect.size.x, "option hit rect scales cleanly on wider viewports")

	menu.queue_free()
	await _test_spring_entry_loads()
	_report()


## The menu is the only way into 春之境, so a wrong path there would ship as a
## dead button that no gameplay suite could see. Load the scene for real and let
## its _ready() build a run.
func _test_spring_entry_loads() -> void:
	_check(ResourceLoader.exists(MenuScript.SPRING_SCENE_PATH), "the 春之境 scene exists at the menu's path")
	var packed = load(MenuScript.SPRING_SCENE_PATH)
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
