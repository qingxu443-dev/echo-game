class_name SpringRouteOverlay
extends RefCounted

## Visual renderer & hit-tester for 春之境 Hard Mode (定轨规划模式).
##
## Kept outside spring_map_view.gd so the map view stays under its module line
## ceiling while gaining rich route lines, waypoint numbers, boss-tail cues, and
## dedicated planning / locked-step bottom controls.

const P = preload("res://scripts/ui/theme_palette.gd")

const UNDO_BTN := Rect2(560.0, 648.0, 124.0, 44.0)
const CLEAR_BTN := Rect2(694.0, 648.0, 124.0, 44.0)
const LOCK_BTN := Rect2(828.0, 648.0, 202.0, 44.0)
const ADVANCE_BTN := Rect2(824.0, 648.0, 206.0, 44.0)

const HARD_ACCENT := Color("#e46d68")
const HARD_GLOW := Color("#f2c172")
const ROUTE_DONE := Color(0.60, 0.56, 0.48, 0.65)
const ROUTE_NEXT := Color("#ffd97d")
const ROUTE_PLAN := Color("#e69a68")


static func draw_mode_badge(canvas: CanvasItem, run) -> void:
	if run == null or run.route_plan == null or not run.route_plan.hard_mode:
		return
	var font := ThemeDB.fallback_font
	var badge := Rect2(142.0, 14.0, 128.0, 24.0)
	canvas.draw_rect(badge, Color(0.32, 0.12, 0.13, 0.94), true)
	canvas.draw_rect(badge, HARD_ACCENT, false, 1.3)
	var label := "困难 · 规划中" if run.route_plan.is_planning() else "困难 · 定轨"
	canvas.draw_string(font, badge.position + Vector2(12.0, 17.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffe2dc"))


static func draw_route_on_grid(canvas: CanvasItem, view, run, elapsed: float) -> void:
	if run == null or run.route_plan == null or not run.route_plan.hard_mode:
		return
	var plan: SpringRoutePlan = run.route_plan
	var font := ThemeDB.fallback_font
	var pulse: float = 0.5 + 0.5 * sin(elapsed * 4.2)

	# Highlight Boss cell strongly during planning so the tail requirement is unmistakable.
	if plan.is_planning():
		var boss_rect: Rect2 = view.cell_rect(run.template.boss_cell)
		var reached: bool = plan.ends_at_boss(run.template)
		var ring_col: Color = Color("#74d99f") if reached else HARD_ACCENT.lerp(HARD_GLOW, pulse * 0.45)
		canvas.draw_rect(boss_rect.grow(3.0), ring_col, false, 2.6)
		var boss_tag := "终点已锁定" if reached else "终点必达 · 王"
		canvas.draw_string(font, Vector2(boss_rect.position.x - 4.0, boss_rect.position.y - 8.0), boss_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ring_col)

	# Build full polyline nodes: start_cell -> waypoints[0] -> ... -> waypoints[n-1]
	var prev_cell: Vector2i = run.template.start_cell
	for i in range(plan.waypoints.size()):
		var curr_cell: Vector2i = plan.waypoints[i]
		var a: Vector2 = view.cell_rect(prev_cell).get_center()
		var b: Vector2 = view.cell_rect(curr_cell).get_center()
		var seg_color: Color = ROUTE_PLAN
		var width: float = 3.6
		if plan.is_locked_active():
			if i < plan.cursor:
				seg_color = ROUTE_DONE
				width = 2.4
			elif i == plan.cursor:
				seg_color = ROUTE_NEXT
				width = 4.6
			else:
				seg_color = Color(0.88, 0.54, 0.42, 0.72)
				width = 3.0
		_draw_route_segment(canvas, a, b, seg_color, width)
		prev_cell = curr_cell

	# Draw numbered badges on each planned waypoint.
	for i in range(plan.waypoints.size()):
		var cell: Vector2i = plan.waypoints[i]
		var rect: Rect2 = view.cell_rect(cell)
		var is_tail: bool = (i == plan.waypoints.size() - 1) and (cell == run.template.boss_cell)
		var is_next: bool = plan.is_locked_active() and i == plan.cursor
		var is_done: bool = plan.is_locked_active() and i < plan.cursor

		if is_next:
			var glow_col: Color = ROUTE_NEXT.lerp(Color.WHITE, pulse * 0.35)
			canvas.draw_rect(rect.grow(3.0), glow_col, false, 2.8)
			var step_cost: int = run.exploration.cost_to(cell)
			canvas.draw_string(font, Vector2(rect.position.x, rect.position.y - 8.0), "下一站 · %d 体力" % step_cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ROUTE_NEXT)

		var badge_center := Vector2(rect.position.x + 15.0, rect.position.y + 15.0)
		var badge_bg: Color = Color(0.24, 0.26, 0.25, 0.92) if is_done else (Color("#70302e") if is_tail else (Color("#5e4720") if is_next else Color("#3b2c22")))
		var badge_border: Color = ROUTE_DONE if is_done else (HARD_GLOW if (is_next or is_tail) else ROUTE_PLAN)
		canvas.draw_circle(badge_center, 11.0, badge_bg)
		canvas.draw_arc(badge_center, 11.0, 0.0, TAU, 20, badge_border, 1.6, true)
		var badge_text: String = "终" if is_tail else str(i + 1)
		canvas.draw_string(font, badge_center + Vector2(-5.0, 4.5), badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#fff4de"))

	# Left-side compact guide banner explaining hard-mode rules
	_draw_side_panel(canvas, font, run)


static func _draw_route_segment(canvas: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var dir := (b - a)
	var dist := dir.length()
	if dist < 2.0:
		return
	var u := dir / dist
	var p1 := a + u * 18.0
	var p2 := b - u * 18.0
	if (p2 - p1).dot(u) <= 0.0:
		p1 = a
		p2 = b
	canvas.draw_line(p1, p2, Color(0.02, 0.03, 0.04, 0.55), width + 2.6, true)
	canvas.draw_line(p1, p2, color, width, true)
	# Small arrowhead near the destination node
	var tip := p2
	var perp := Vector2(-u.y, u.x)
	var arrow := PackedVector2Array([tip, tip - u * 11.0 + perp * 5.5, tip - u * 11.0 - perp * 5.5])
	canvas.draw_colored_polygon(arrow, color)


static func _draw_side_panel(canvas: CanvasItem, font: Font, run) -> void:
	var plan: SpringRoutePlan = run.route_plan
	var panel := Rect2(32.0, 136.0, 318.0, 214.0)
	canvas.draw_rect(panel, Color(0.08, 0.10, 0.12, 0.90), true)
	canvas.draw_rect(Rect2(panel.position, Vector2(4.0, panel.size.y)), HARD_ACCENT if plan.is_planning() else HARD_GLOW, true)
	canvas.draw_rect(panel, Color(0.75, 0.42, 0.38, 0.45), false, 1.2)

	var used_cost: int = plan.total_cost(run.template.start_cell)
	var budget: int = run.exploration.stamina
	if plan.is_planning():
		canvas.draw_string(font, panel.position + Vector2(18.0, 30.0), "困难模式 · 战前绘线", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#ffd6ce"))
		canvas.draw_string(font, panel.position + Vector2(18.0, 58.0), "1. 依次点击地图节点连出探索路线", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12.5, P.TEXT_BODY)
		canvas.draw_string(font, panel.position + Vector2(18.0, 80.0), "2. 路线尾部必须落在「王（首领）」格", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12.5, HARD_GLOW)
		canvas.draw_string(font, panel.position + Vector2(18.0, 102.0), "3. 锁定后必须按路线顺序打完不可偏离", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12.5, P.TEXT_BODY)
		canvas.draw_string(font, panel.position + Vector2(18.0, 138.0), "规划站数：%d 站" % plan.waypoints.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_STRONG)
		canvas.draw_string(font, panel.position + Vector2(18.0, 162.0), "预计体力：%d / %d" % [used_cost, budget], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.CYAN if used_cost <= budget else HARD_ACCENT)
		var tail_ok := plan.ends_at_boss(run.template)
		canvas.draw_string(font, panel.position + Vector2(18.0, 188.0), "终点校验：%s" % ("已连接首领（可启程）" if tail_ok else "尚未连至首领（王）"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12.5, Color("#74d99f") if tail_ok else HARD_ACCENT)
	else:
		canvas.draw_string(font, panel.position + Vector2(18.0, 30.0), "困难模式 · 强制按轨推进", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, HARD_GLOW)
		canvas.draw_string(font, panel.position + Vector2(18.0, 60.0), "路线已锁定，无法偏离预定轨迹。", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12.5, P.TEXT_BODY)
		canvas.draw_string(font, panel.position + Vector2(18.0, 92.0), "已完成：%d / %d 站" % [mini(plan.cursor, plan.waypoints.size()), plan.waypoints.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_STRONG)
		var next_cell := plan.next_stop()
		if next_cell != Vector2i(-1, -1):
			var next_place: SpringPlace = run.template.place_at(next_cell)
			var next_name: String = run.title_of(next_place) if next_place != null else "空地 (%d,%d)" % [next_cell.x, next_cell.y]
			canvas.draw_string(font, panel.position + Vector2(18.0, 124.0), "下一站：%s" % next_name, HORIZONTAL_ALIGNMENT_LEFT, 284.0, 13.5, ROUTE_NEXT)
			canvas.draw_string(font, panel.position + Vector2(18.0, 152.0), "所需体力：%d 点" % run.exploration.cost_to(next_cell), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.CYAN)
			canvas.draw_string(font, panel.position + Vector2(18.0, 184.0), "自动沿路线推进中（点击可立即出发）", HORIZONTAL_ALIGNMENT_LEFT, 286.0, 12, ROUTE_NEXT)
		else:
			canvas.draw_string(font, panel.position + Vector2(18.0, 124.0), "已抵达路线终点，请完成首领决战。", HORIZONTAL_ALIGNMENT_LEFT, 284.0, 13, HARD_GLOW)


## Advances automatically along the locked route whenever no overlay/dialog is
## blocking the map, giving a brief visual beat so the player sees each leg.
static func tick_auto_march(view, run, delta: float) -> bool:
	if run == null or run.route_plan == null or not run.route_plan.is_locked_active():
		return false
	if run.exploration.finished:
		return false
	var plan: SpringRoutePlan = run.route_plan
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
		view._draw_button(UNDO_BTN, "撤销上步", not plan.waypoints.is_empty())
		view._draw_button(CLEAR_BTN, "清空路线", not plan.waypoints.is_empty())
		view._draw_button(LOCK_BTN, "锁定路线 · 启程", plan.can_lock(run.template, run.exploration.stamina))
		view._draw_button(view.END_BTN, "结束探索", true)
		return true

	# Locked execution phase
	var can_step: bool = plan.has_next_stop() and run.exploration.can_move_to(plan.next_stop())
	view._draw_button(ADVANCE_BTN, "立即推进下一站", can_step)
	view._draw_button(view.END_BTN, "结束探索", true)
	if run.exploration.can_interact():
		var place: SpringPlace = run.exploration.place_here()
		view._draw_button(Rect2(612.0, 648.0, 196.0, 44.0), "进入 · %s" % run.title_of(place), true)
	return true


## Handles map-level clicks in hard mode. Returns true when consumed.
static func handle_tap(view, run, point: Vector2) -> bool:
	if run == null or run.route_plan == null or not run.route_plan.hard_mode:
		return false
	var plan: SpringRoutePlan = run.route_plan

	if plan.is_planning():
		if UNDO_BTN.has_point(point):
			view.status_message = "已撤销上一步。" if plan.pop_last() else "尚未绘制任何节点。"
			view._save()
			return true
		if CLEAR_BTN.has_point(point):
			plan.clear_plan()
			view.status_message = "已清空路线，请重新规划（尾部须为王）。"
			view._save()
			return true
		if LOCK_BTN.has_point(point):
			var res: Dictionary = plan.lock_plan(run.template, run.exploration.stamina)
			view.status_message = str(res.get("message", ""))
			view._save()
			return true
		var cell: Vector2i = view.cell_at(point)
		if cell != Vector2i(-1, -1):
			var toggled: Dictionary = plan.toggle_waypoint(cell, run.template, run.exploration.stamina)
			view.status_message = str(toggled.get("message", ""))
			view._save()
			return true
		return false

	# Locked execution phase: player must follow the locked route strictly.
	if ADVANCE_BTN.has_point(point):
		_step_next(view, run)
		return true
	var cell: Vector2i = view.cell_at(point)
	if cell != Vector2i(-1, -1):
		if cell == run.exploration.position and run.exploration.can_interact():
			view._enter_here()
			return true
		if plan.is_allowed_destination(cell):
			_step_next(view, run)
		elif plan.has_next_stop():
			var next_c := plan.next_stop()
			view.status_message = "困难模式已锁轨：必须先前往第 %d 站「%s」。" % [plan.cursor + 1, view._place_label(next_c)]
		else:
			view.status_message = "已抵达终点，请完成当前首领战。"
		return true
	return false


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
	if not run.exploration.move_to(target):
		view.status_message = "体力不足以推进至下一站（需 %d / 剩 %d）。" % [run.exploration.cost_to(target), run.exploration.stamina]
		return
	plan.advance_cursor()
	plan.auto_step_timer = SpringRoutePlan.AUTO_STEP_DELAY if plan.has_next_stop() else -1.0
	view.selected_cell = target
	view.status_message = "定轨推进：抵达第 %d / %d 站「%s」· 剩余体力 %d。" % [plan.cursor, plan.waypoints.size(), view._place_label(target), run.exploration.stamina]
	view._save()
	if run.exploration.can_interact():
		view._enter_here()
