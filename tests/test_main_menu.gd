extends "res://tests/framework/test_case.gd"

const MenuScript = preload("res://scripts/ui/main_menu.gd")


func _run() -> void:
	var menu := Control.new()
	menu.set_script(MenuScript)
	root.add_child(menu)
	menu.size = Vector2(1260.0, 700.0)

	_check(menu.selected_option == 0, "main menu initially selects Start Game")
	_check(menu.OPTION_COUNT == 2, "only Start Game and Exit Game are actionable")

	menu._move_selection(1)
	_check(menu.selected_option == 1, "down navigation selects Exit Game")
	menu._move_selection(1)
	_check(menu.selected_option == 0, "down navigation wraps to Start Game")
	menu._move_selection(-1)
	_check(menu.selected_option == 1, "up navigation selects Exit Game")

	var start_rect: Rect2 = menu._scaled_option_rect(0)
	var exit_rect: Rect2 = menu._scaled_option_rect(1)
	_check(start_rect.has_point(Vector2(300.0, 340.0)), "Start Game hit area matches the supplied artwork")
	_check(exit_rect.has_point(Vector2(300.0, 530.0)), "Exit Game hit area matches the supplied artwork")
	_check(not start_rect.intersects(exit_rect), "the two actionable hit areas do not overlap")

	# Wider viewports crop the top/bottom evenly while keeping the artwork
	# and its interactive hit targets on the same uniform scale.
	menu.size = Vector2(1600.0, 700.0)
	var wide_start_rect: Rect2 = menu._scaled_option_rect(0)
	_check(is_equal_approx(menu._background_scale(), 1600.0 / 1260.0), "wide viewport uses uniform cover scaling")
	_check(is_equal_approx(menu._background_offset().y, (700.0 - 700.0 * 1600.0 / 1260.0) * 0.5), "wide viewport crops artwork evenly")
	_check(wide_start_rect.has_point(menu._background_offset() + Vector2(300.0, 340.0) * menu._background_scale()), "wide viewport hit area follows the cropped artwork")

	# Taller/narrower viewports crop the left/right evenly.
	menu.size = Vector2(900.0, 700.0)
	var tall_start_rect: Rect2 = menu._scaled_option_rect(0)
	_check(is_equal_approx(menu._background_scale(), 1.0), "tall viewport keeps the artwork at its design scale")
	_check(is_equal_approx(menu._background_offset().x, -180.0), "tall viewport crops both horizontal edges evenly")
	_check(tall_start_rect.has_point(Vector2(120.0, 340.0)), "tall viewport hit area follows the horizontal crop")

	menu.queue_free()
	_report()
