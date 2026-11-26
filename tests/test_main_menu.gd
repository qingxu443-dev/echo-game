extends "res://tests/framework/test_case.gd"

const MenuScript = preload("res://scripts/ui/main_menu.gd")


func _run() -> void:
	var menu := Control.new()
	menu.set_script(MenuScript)
	root.add_child(menu)
	menu.size = Vector2(1280.0, 720.0)

	_check(menu.selected_option == 0, "main menu initially selects Start Expedition")
	_check(menu.OPTIONS.size() == 2, "only Start Expedition and Exit Game are actionable")

	menu._move_selection(1)
	_check(menu.selected_option == 1, "down navigation selects Exit Game")
	menu._move_selection(1)
	_check(menu.selected_option == 0, "down navigation wraps to Start Expedition")
	menu._move_selection(-1)
	_check(menu.selected_option == 1, "up navigation selects Exit Game")

	var start_rect: Rect2 = menu._option_rect(0)
	var exit_rect: Rect2 = menu._option_rect(1)
	_check(start_rect.size.x > 0.0 and start_rect.size.y > 0.0, "Start Expedition hit area is non-empty")
	_check(exit_rect.size.x > 0.0 and exit_rect.size.y > 0.0, "Exit Game hit area is non-empty")
	_check(not start_rect.intersects(exit_rect), "the two actionable hit areas do not overlap")
	_check(exit_rect.position.y > start_rect.end.y, "Exit Game sits cleanly below Start Expedition")

	menu.size = Vector2(1600.0, 900.0)
	var wide_start: Rect2 = menu._option_rect(0)
	_check(wide_start.size.x > start_rect.size.x, "option hit rect scales cleanly on wider viewports")

	menu.queue_free()
	_report()
