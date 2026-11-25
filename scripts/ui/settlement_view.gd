class_name SettlementView
extends RefCounted

## The end-of-battle panel: result, tallies, and the restart / next controls.
##
## hit() returns the action a tap means, so the view never re-derives button
## geometry and the panel and its hit boxes cannot disagree.

const P = preload("res://scripts/ui/theme_palette.gd")

const ACTION_RESTART: String = "restart"
const ACTION_NEXT: String = "next"


static func draw(canvas: CanvasItem, controller, level, has_next: bool) -> void:
	var font := ThemeDB.fallback_font
	var won: bool = controller.battle_result == "victory"

	canvas.draw_rect(Rect2(Vector2.ZERO, P.VIEW_SIZE), P.OVERLAY_SCRIM, true)
	canvas.draw_rect(P.SETTLEMENT_RECT, P.OVERLAY_BG, true)
	canvas.draw_rect(P.SETTLEMENT_RECT, P.BUTTON_BORDER, false, 2.0)

	var title := "战斗结束 · 胜利" if won else "战斗结束 · 失败"
	canvas.draw_string(font, Vector2(370.0, 262.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.GOLD_PALE if won else P.WARN)

	var level_name: String = "—" if level == null else str(level.display_name_zh)
	_row(canvas, font, 296.0, "关卡", level_name)
	_row(canvas, font, 324.0, "回合数", "%d" % controller.turn_number)
	_row(canvas, font, 352.0, "造成伤害", "%d" % controller.damage_dealt)
	_row(canvas, font, 380.0, "承受伤害", "%d" % controller.damage_taken)
	_row(canvas, font, 408.0, "击败敌人", "%d" % controller.enemies_defeated)

	# The whole party, not one named character: with two members on the field,
	# Sevrin's bar alone reads 0/12000 after a win he did not survive, which looks
	# like a loss on a victory screen.
	var total_health := 0
	var total_max := 0
	for actor in controller.actors.values():
		if actor.team == "player":
			total_health += actor.health
			total_max += actor.max_health
	var health_label := "—" if total_max == 0 else "%d / %d" % [total_health, total_max]
	_row(canvas, font, 436.0, "剩余生命", health_label)

	_button(canvas, font, P.RESTART_BTN, "重开本关")
	if won:
		_button(canvas, font, P.NEXT_BTN, "下一关" if has_next else "从头开始")


## Returns ACTION_RESTART, ACTION_NEXT, or "" when the tap misses both buttons.
## A loss offers restart only, so the next button is not treated as active.
static func hit(position: Vector2, won: bool) -> String:
	if P.RESTART_BTN.has_point(position):
		return ACTION_RESTART
	if won and P.NEXT_BTN.has_point(position):
		return ACTION_NEXT
	return ""


static func _row(canvas: CanvasItem, font: Font, y: float, label: String, value: String) -> void:
	canvas.draw_string(font, Vector2(390.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.TEXT_DIM)
	# draw_string ignores alignment when width is -1, so right-align by measuring.
	var value_width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	canvas.draw_string(font, Vector2(910.0 - value_width, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, P.TEXT)


static func _button(canvas: CanvasItem, font: Font, rect: Rect2, label: String) -> void:
	canvas.draw_rect(rect, P.BUTTON_BG, true)
	canvas.draw_rect(rect, P.BUTTON_BORDER, false, 2.0)
	var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	canvas.draw_string(font, rect.position + Vector2((rect.size.x - text_width) * 0.5, 34.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, P.BUTTON_TEXT)
