class_name SpringRouteOverlay
extends RefCounted

## Pattern-lock renderer & drag/auto-march input handler for 春之境 Hard Mode.
##
## Players hold left mouse button on the 5x5 grid and drag through any number of
## cells like a phone unlock pattern. Releasing on the Boss locks & starts
## automatic forced traversal; releasing anywhere else clears the route with a
## visible red alert banner.

const P = preload("res://scripts/ui/theme_palette.gd")

const ADVANCE_BTN := Rect2(824.0, 648.0, 206.0, 44.0)

const HARD_ACCENT := Color("#e46d68")
const HARD_GLOW := Color("#f2c172")
const ROUTE_DONE := Color(0.60, 0.56, 0.48, 0.65)
const ROUTE_NEXT := Color("#ffd97d")
const ROUTE_PLAN := Color("#f0a868")


static func draw_mode_badge(canvas: CanvasItem, run) -> void:
	if run == null or run.route_plan == null or not run.route_plan.hard_mode:
		return
	var font := ThemeDB.fallback_font
	var badge := Rect2(142.0, 14.0, 140.0, 24.0)
	canvas.draw_rect(badge, Color(0.32, 0.12, 0.13, 0.94), true)
	canvas.draw_rect(badge, HARD_ACCENT, false, 1.3)
	var label := "困难 · 长按绘线" if run.route_plan.is_planning() else "困难 · 定轨行进"
	canvas.draw_string(font, badge.position + Vector2(12.0, 17.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffe2dc"))


static func draw_route_on_grid(canvas: CanvasItem, view, run, elapsed: float) -> void:
	if run == null or run.route_plan == null or not run.route_plan.hard_mode:
		return
	var plan: SpringRoutePlan = run.route_plan
	var font := ThemeDB.fallback_font
	var pulse: float = 0.5 + 0.5 * sin(elapsed * 4.5)

	# Highlight Boss cell strongly during planning so the mandatory tail is unmistakable.
	if plan.is_planning():
		var boss_rect: Rect2 = view.cell_rect(run.template.boss_cell)
		var reached: bool = plan.ends_at_boss(run.template)
		var ring_col: Color = Color("#74d99f") if reached else HARD_ACCENT.lerp(HARD_GLOW, pulse * 0.5)
		canvas.draw_rect(boss_rect.grow(3.5), ring_col, false, 2.8)
		var boss_tag := "松手立即启程！" if reached else "结尾必达 · 王"
		canvas.draw_string(font, Vector2(boss_rect.position.x - 4.0, boss_rect.position.y - 8.0), boss_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ring_col)

	# Pattern-lock polyline: start_cell -> waypoints[0] -> ... -> waypoints[n-1]
	var prev_cell: Vector2i = run.template.start_cell
	for i in range(plan.waypoints.size()):
		var curr_cell: Vector2i = plan.waypoints[i]
		var a: Vector2 = view.cell_rect(prev_cell).get_center()
		var b: Vector2 = view.cell_rect(curr_cell).get_center()
		var seg_color: Color = Color("#74d99f") if (plan.is_planning() and plan.ends_at_boss(run.template)) else ROUTE_PLAN
		var width: float = 4.2
		if plan.is_locked_active():
			if i < plan.cursor:
				seg_color = ROUTE_DONE
				width = 2.4
			elif i == plan.cursor:
				seg_color = ROUTE_NEXT
				width = 4.8
			else:
				seg_color = Color(0.88, 0.54, 0.42, 0.72)
				width = 3.2
		_draw_route_segment(canvas, a, b, seg_color, width)
		prev_cell = curr_cell

	# Live rubber-band line following the pointer while holding/dragging (pattern-lock feel!)
	if plan.is_planning() and plan.dragging and not plan.ends_at_boss(run.template):
		var anchor: Vector2 = view.cell_rect(prev_cell).get_center()
		canvas.draw_line(anchor, plan.drag_point, Color(0.98, 0.80, 0.46, 0.72), 3.0, true)
		canvas.draw_circle(plan.drag_point, 6.0, Color(1.0, 0.88, 0.58, 0.90))

	# Draw numbered pattern-lock badges on each connected node.
	for i in range(plan.waypoints.size()):
		var cell: Vector2i = plan.waypoints[i]
		var rect: Rect2 = view.cell_rect(cell)
		var is_tail: bool = (i == plan.waypoints.size() - 1) and (cell == run.template.boss_cell)
		var is_next: bool = plan.is_locked_active() and i == plan.cursor
		var is_done: bool = plan.is_locked_active() and i < plan.cursor

		if is_next:
			var glow_col: Color = ROUTE_NEXT.lerp(Color.WHITE, pulse * 0.35)
			canvas.draw_rect(rect.grow(3.0), glow_col, false, 2.8)
			canvas.draw_string(font, Vector2(rect.position.x, rect.position.y - 8.0), "自动前往 · 第 %d 站" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ROUTE_NEXT)

		var badge_center := Vector2(rect.position.x + 15.0, rect.position.y + 15.0)
		var badge_bg: Color = Color(0.24, 0.26, 0.25, 0.92) if is_done else (Color("#276348") if is_tail else (Color("#5e4720") if is_next else Color("#3b2c22")))
		var badge_border: Color = ROUTE_DONE if is_done else (Color("#74d99f") if is_tail else (HARD_GLOW if is_next else ROUTE_PLAN))
		canvas.draw_circle(badge_center, 11.5, badge_bg)
		canvas.draw_arc(badge_center, 11.5, 0.0, TAU, 20, badge_border, 1.8, true)
		var badge_text: String = "终" if is_tail else str(i + 1)
		var x_off: float = -7.0 if badge_text.length() > 1 else -5.0
		canvas.draw_string(font, badge_center + Vector2(x_off, 4.5), badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#fff4de"))

	_draw_side_panel(canvas, font, run)

	# Prominent red alert toast when player releases without reaching the Boss.
	if plan.fail_flash_timer > 0.0 and not plan.fail_flash_message.is_empty():
		var alpha: float = minf(1.0, plan.fail_flash_timer * 1.5)
		var toast := Rect2(372.0, 90.0, 536.0, 36.0)
		canvas.draw_rect(toast, Color(0.36, 0.11, 0.12, 0.94 * alpha), true)
		canvas.draw_rect(toast, Color(0.95, 0.44, 0.42, alpha), false, 1.6)
		canvas.draw_string(font, toast.position + Vector2(0.0, 23.0), plan.fail_flash_message, HORIZONTAL_ALIGNMENT_CENTER, toast.size.x, 13, Color(1.0, 0.90, 0.86, alpha))


static func _draw_route_segment(canvas: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var dir := (b - a)
	var dist := dir.length()
	if dist < 2.0:
		return
	var u := dir / dist
	var p1 := a + u * 16.0
	var p2 := b - u * 16.0
	if (p2 - p1).dot(u) <= 0.0:
		p1 = a
		p2 = b
	canvas.draw_line(p1, p2, Color(0.02, 0.03, 0.04, 0.55), width + 2.6, true)
	canvas.draw_line(p1, p2, color, width, true)
	var perp := Vector2(-u.y, u.x)
	var arrow := PackedVector2Array([p2, p2 - u * 11.0 + perp * 5.5, p2 - u * 11.0 - perp * 5.5])
	canvas.draw_colored_polygon(arrow, color)


static func _draw_side_panel(canvas: CanvasItem, font: Font, run) -> void:
	var plan: SpringRoutePlan = run.route_plan
	var panel := Rect2(32.0, 136.0, 318.0, 214.0)
	canvas.draw_rect(panel, Color(0.08, 0.10, 0.12, 0.90), true)
	canvas.draw_rect(Rect2(panel.position, Vector2(4.0, panel.size.y)), HARD_ACCENT if plan.is_planning() else HARD_GLOW, true)
	canvas.draw_rect(panel, Color(0.75, 0.42, 0.38, 0.45), false, 1.2)

	if plan.is_planning():
		canvas.draw_string(font, panel.position + Vector2(18.0, 30.0), "困难模式 · 图案一笔画", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#ffd6ce"))
		canvas.draw_string(font, panel.position + Vector2(18.0, 58.0), "1. 长按鼠标左键拖动，像图案解锁般连线", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12.5, P.TEXT_BODY)
		canvas.draw_string(font, panel.position + Vector2(18.0, 80.0), "2. 不限制连接节点数量（往回划可退格）", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12.5, P.CYAN)
		canvas.draw_string(font, panel.position + Vector2(18.0, 102.0), "3. 结尾必须落在「王」，松手即自动启程", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12.5, HARD_GLOW)
		canvas.draw_string(font, panel.position + Vector2(18.0, 124.0), "4. 若未连到「王」松手将自动清空重画", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12.5, HARD_ACCENT)
		canvas.draw_string(font, panel.position + Vector2(18.0, 160.0), "当前已连：%d 站（不限数量）" % plan.waypoints.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13.5, P.TEXT_STRONG)
		var tail_ok := plan.ends_at_boss(run.template)
		canvas.draw_string(font, panel.position + Vector2(18.0, 188.0), "终点状态：%s" % ("已到首领（松手发车！）" if tail_ok else "请按住连向「王」"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12.5, Color("#74d99f") if tail_ok else HARD_ACCENT)
	else:
		canvas.draw_string(font, panel.position + Vector2(18.0, 30.0), "困难模式 · 自动强制推进", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, HARD_GLOW)
		canvas.draw_string(font, panel.position + Vector2(18.0, 60.0), "路线已锁定，正沿预定轨迹逐站打通。", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12.5, P.TEXT_BODY)
		canvas.draw_string(font, panel.position + Vector2(18.0, 94.0), "推进进度：%d / %d 站" % [mini(plan.cursor, plan.waypoints.size()), plan.waypoints.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_STRONG)
		var next_cell := plan.next_stop()
		if next_cell != Vector2i(-1, -1):
			var next_place: SpringPlace = run.template.place_at(next_cell)
			var next_name: String = run.title_of(next_place) if next_place != null else "空地 (%d,%d)" % [next_cell.x, next_cell.y]
			canvas.draw_string(font, panel.position + Vector2(18.0, 128.0), "下一站：%s" % next_name, HORIZONTAL_ALIGNMENT_LEFT, 284.0, 14, ROUTE_NEXT)
			canvas.draw_string(font, panel.position + Vector2(18.0, 160.0), "自动沿线行进中（点击可跳过等待）", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12, Color("#74d99f"))
		else:
			canvas.draw_string(font, panel.position + Vector2(18.0, 128.0), "已抵达首领终点，请完成决战。", HORIZONTAL_ALIGNMENT_LEFT, 284.0, 13.5, HARD_GLOW)


## Advances automatically along the locked route whenever no overlay/dialog is
## blocking the map, and ticks the red failure flash timer during planning.
static func tick_auto_march(view, run, delta: float) -> bool:
	if run == null or run.route_plan == null or not run.route_plan.hard_mode:
		return false
	var plan: SpringRoutePlan = run.route_plan
	if plan.fail_flash_timer > 0.0:
		plan.fail_flash_timer = maxf(0.0, plan.fail_flash_timer - delta)
	if not plan.is_locked_active() or run.exploration.finished:
		return false
	if view.event_open or view.shop_open or not view.reward_choices.is_empty() or view.revive_prompt or view.confirm_end:
		plan.auto_step_timer = -1.0
		return false
	if not plan.has_next_stop():
		plan.auto_step_timer = -1.0
		return false
	if plan.auto_step_timer < 0.0:
		plan.auto_step_timer = SpringRoutePlan.AUTO_STEP_DELAY
		return false
	plan.auto_step_timer -= delta
	if plan.auto_step_timer <= 0.0:
		plan.auto_step_timer = -1.0
		_step_next(view, run)
		return true
	return false


static func draw_bottom_controls(view, run) -> bool:
	if run == null or run.route_plan == null or not run.route_plan.hard_mode or run.exploration.finished:
		return false
	var plan: SpringRoutePlan = run.route_plan
	if plan.is_planning():
		var hint_r := Rect2(560.0, 648.0, 464.0, 44.0)
		view.draw_rect(hint_r, Color(0.14, 0.11, 0.12, 0.92), true)
		view.draw_rect(hint_r, HARD_ACCENT if not plan.ends_at_boss(run.template) else Color("#74d99f"), false, 1.4)
		var txt := "已连至「王」，松手即锁定发车！" if plan.ends_at_boss(run.template) else "在棋盘上长按拖动一笔画路线（结尾必达「王」）"
		view.draw_string(ThemeDB.fallback_font, hint_r.position + Vector2(0.0, 27.0), txt, HORIZONTAL_ALIGNMENT_CENTER, hint_r.size.x, 14, Color("#ffe9d6"))
		view._draw_button(view.END_BTN, "结束探索", true)
		return true

	# Locked execution phase
	var can_step: bool = plan.has_next_stop()
	view._draw_button(ADVANCE_BTN, "立即前往下一站", can_step)
	view._draw_button(view.END_BTN, "结束探索", true)
	if run.exploration.can_interact():
		var place: SpringPlace = run.exploration.place_here()
		view._draw_button(Rect2(612.0, 648.0, 196.0, 44.0), "进入 · %s" % run.title_of(place), true)
	return true


## Handles mouse down, drag motion, and mouse release for pattern-lock drawing
## and locked-route taps. Leaves all modals and the End button to spring_map_view.
static func handle_gui_event(view, run, event: InputEvent) -> bool:
	if run == null or run.route_plan == null or not run.route_plan.hard_mode:
		return false
	if view.event_open or view.shop_open or not view.reward_choices.is_empty() or view.revive_prompt or view.confirm_end or run.exploration.finished:
		return false
	var plan: SpringRoutePlan = run.route_plan

	if plan.is_planning():
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return false
			var pt: Vector2 = view._to_view(mb.position)
			if mb.pressed:
				if view.END_BTN.has_point(pt):
					return false
				var cell: Vector2i = view.cell_at(pt)
				if cell != Vector2i(-1, -1):
					var res := plan.begin_drag(cell, pt, run.template)
					view.status_message = str(res.get("message", ""))
					return true
				return false
			elif plan.dragging:
				var done := plan.finish_drag(run.template)
				view.status_message = str(done.get("message", ""))
				if bool(done.get("locked", false)):
					view._save()
				return true
		elif event is InputEventMouseMotion and plan.dragging:
			var pt: Vector2 = view._to_view((event as InputEventMouseMotion).position)
			plan.drag_point = pt
			var cell: Vector2i = _drag_cell_at(view, pt)
			if cell != Vector2i(-1, -1):
				var moved := plan.drag_over_cell(cell, run.template)
				if bool(moved.get("changed", false)):
					view.status_message = str(moved.get("message", ""))
			return true
		return false

	# Locked execution phase
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		var pt: Vector2 = view._to_view(mb.position)
		if view.END_BTN.has_point(pt):
			return false
		if ADVANCE_BTN.has_point(pt):
			_step_next(view, run)
			return true
		var cell: Vector2i = view.cell_at(pt)
		if cell != Vector2i(-1, -1):
			if cell == run.exploration.position and run.exploration.can_interact():
				view._enter_here()
				return true
			if plan.is_allowed_destination(cell):
				_step_next(view, run)
			elif plan.has_next_stop():
				var next_c := plan.next_stop()
				view.status_message = "困难模式已锁轨：正自动前往第 %d 站「%s」。" % [plan.cursor + 1, view._place_label(next_c)]
			return true
	return false


## Slightly inset hit box during drag so diagonal swipes glide cleanly between
## cells without accidentally snagging adjacent corners (phone pattern-lock feel).
static func _drag_cell_at(view, pt: Vector2) -> Vector2i:
	for row in range(1, SpringMapTemplate.SIZE + 1):
		for col in range(1, SpringMapTemplate.SIZE + 1):
			var c := Vector2i(row, col)
			if view.cell_rect(c).grow(-10.0).has_point(pt):
				return c
	return Vector2i(-1, -1)


static func _step_next(view, run) -> void:
	var plan: SpringRoutePlan = run.route_plan
	if run.exploration.can_interact():
		var here: SpringPlace = run.exploration.place_here()
		if here != null and here.one_shot and not run.exploration.completed.has(here.id):
			view.status_message = "请先完成当前节点「%s」再继续推进！" % run.title_of(here)
			view._enter_here()
			return
	if not plan.has_next_stop():
		view.status_message = "路线已抵达终点。"
		return
	var target: Vector2i = plan.next_stop()
	var needed: int = run.exploration.cost_to(target)
	var has_more_after: bool = (plan.cursor + 1) < plan.waypoints.size()
	# Hard mode imposes no waypoint count cap, so never exhaust stamina mid-route
	# before reaching the mandatory Boss tail.
	var min_stamina: int = needed + (1 if has_more_after else 0)
	if run.exploration.stamina < min_stamina:
		run.exploration.stamina = min_stamina
	if not run.exploration.move_to(target):
		view.status_message = "无法推进至下一站。"
		return
	plan.advance_cursor()
	plan.auto_step_timer = SpringRoutePlan.AUTO_STEP_DELAY if plan.has_next_stop() else -1.0
	view.selected_cell = target
	view.status_message = "定轨推进：抵达第 %d / %d 站「%s」。" % [plan.cursor, plan.waypoints.size(), view._place_label(target)]
	view._save()
	if run.exploration.can_interact():
		view._enter_here()
