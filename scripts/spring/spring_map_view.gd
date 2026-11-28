extends Control

## 春之境 map screen (设计汇总 2026-11-26 §8.4).
const P = preload("res://scripts/ui/theme_palette.gd")
const FactoryScript = preload("res://scripts/spring/spring_map_factory.gd")
const EventViewScript = preload("res://scripts/spring/spring_event_view.gd")
const ShopViewScript = preload("res://scripts/spring/spring_shop_view.gd")
const EventCatalogScript = preload("res://scripts/spring/spring_event_catalog.gd")
const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")
const CollectibleCatalogScript = preload("res://scripts/spring/spring_collectible_catalog.gd")
const EndingScript = preload("res://scripts/spring/spring_ending.gd")
const RouteOverlayScript = preload("res://scripts/spring/spring_route_overlay.gd")

const MENU_SCENE_PATH := "res://scenes/lobby/lobby.tscn"
const VIEW: Vector2 = Vector2(1280.0, 720.0)

const CELL_SIZE: float = 88.0
const CELL_GAP: float = 12.0
const GRID_ORIGIN := Vector2(396.0, 136.0)

const TOP_BAR_H: float = 76.0
const BOTTOM_BAR_Y: float = 636.0

const END_BTN := Rect2(1040.0, 648.0, 196.0, 44.0)
const GO_BTN := Rect2(824.0, 648.0, 196.0, 44.0)
const CONFIRM_YES := Rect2(520.0, 408.0, 116.0, 40.0)
const CONFIRM_NO := Rect2(648.0, 408.0, 116.0, 40.0)
const RETURN_BTN := Rect2(566.0, 540.0, 148.0, 44.0)
const COLLECTIBLES_BTN := Rect2(1120.0, 12.0, 132.0, 52.0)
const COLLECTIBLES_CLOSE := Rect2(884.0, 126.0, 76.0, 34.0)
const COLLECTIBLE_PANEL := Rect2(300.0, 100.0, 680.0, 520.0)
const REVIVE_YES := Rect2(520.0, 392.0, 180.0, 46.0)
const REVIVE_NO := Rect2(724.0, 392.0, 180.0, 46.0)

var flow: SpringMapFlow = SpringMapFlow.new()
var run: SpringRun
var selected_cell: Vector2i = Vector2i(-1, -1)
var status_message: String = ""
var confirm_end: bool = false
var elapsed: float = 0.0
var petals: Array[Dictionary] = []
var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO

var event_open: bool = false
var event_place: SpringPlace
var event_result: Dictionary = {}
var shop_open: bool = false
var shop_tab: int = 0
var shop_sell_page: int = 0
var shop_message: String = ""
var collectible_open: bool = false
var save_path := SpringRun.SAVE_PATH
var atelier_save_path := AtelierStash.SAVE_PATH

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	flow.initialize(self)
	if run != null:
		_init_petals()
		queue_redraw()

func start_new_run(seed_value: int, hard_mode: bool = false) -> void:
	flow.start_new_run(self, seed_value, hard_mode)

func _init_petals() -> void:
	petals.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261126
	for index in range(26):
		petals.append({
			"pos": Vector2(rng.randf_range(0.0, VIEW.x), rng.randf_range(0.0, VIEW.y)),
			"speed": rng.randf_range(8.0, 22.0),
			"sway": rng.randf_range(0.6, 1.8),
			"size": rng.randf_range(2.0, 4.0),
			"alpha": rng.randf_range(0.10, 0.26),
		})

func _process(delta: float) -> void:
	elapsed += delta
	for petal in petals:
		var pos: Vector2 = petal["pos"]
		pos.y += float(petal["speed"]) * delta
		pos.x += sin(elapsed * float(petal["sway"])) * 6.0 * delta
		if pos.y > VIEW.y + 8.0:
			pos.y = -8.0
		petal["pos"] = pos
	RouteOverlayScript.tick_auto_march(self, run, delta)
	queue_redraw()

func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(
		GRID_ORIGIN + Vector2(float(cell.x - 1) * (CELL_SIZE + CELL_GAP), float(cell.y - 1) * (CELL_SIZE + CELL_GAP)),
		Vector2(CELL_SIZE, CELL_SIZE)
	)

func cell_at(point: Vector2) -> Vector2i:
	for row in range(1, SpringMapTemplate.SIZE + 1):
		for col in range(1, SpringMapTemplate.SIZE + 1):
			if cell_rect(Vector2i(row, col)).has_point(point):
				return Vector2i(row, col)
	return Vector2i(-1, -1)

func _to_view(point: Vector2) -> Vector2:
	return (point - _offset) / _scale

func _compute_fit() -> void:
	_scale = minf(size.x / VIEW.x, size.y / VIEW.y)
	if _scale <= 0.0:
		_scale = 1.0
	_offset = (size - VIEW * _scale) * 0.5

func _draw() -> void:
	_compute_fit()
	draw_set_transform(_offset, 0.0, Vector2(_scale, _scale))
	_draw_background()
	if run == null:
		draw_string(ThemeDB.fallback_font, Vector2(435, 420), status_message, HORIZONTAL_ALIGNMENT_LEFT, 600, 20)
		_draw_button(RETURN_BTN, "返回大厅", true)
		return
	_draw_petals()
	_draw_top_bar()
	RouteOverlayScript.draw_mode_badge(self, run)
	_draw_grid()
	RouteOverlayScript.draw_route_on_grid(self, self, run, elapsed)
	if run.route_plan == null or not run.route_plan.hard_mode:
		_draw_selection()
	_draw_bottom_bar()
	if confirm_end:
		_draw_confirm()
	if run.exploration.finished:
		_draw_finished()
	if event_open:
		EventViewScript.draw(self, run, _event_id_for(event_place), event_result)
	elif shop_open:
		ShopViewScript.draw(self, run.shop, run, shop_tab, shop_sell_page, shop_message)
	elif not run.reward_choices.is_empty():
		_draw_reward_choices()
	elif collectible_open:
		_draw_collectibles()
	elif run.revive_prompt:
		_draw_revive_prompt()

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("#12171a"), true)
	# Soft spring light in the upper third; keeps the flat grid from reading cold.
	for index in range(6):
		var alpha: float = 0.020 - float(index) * 0.003
		var inset := float(index) * 46.0
		draw_rect(Rect2(Vector2(inset, inset * 0.4), VIEW - Vector2(inset * 2.0, inset * 0.8)), Color(0.85, 0.78, 0.62, maxf(alpha, 0.0)), true)

func _draw_petals() -> void:
	for petal in petals:
		var pos: Vector2 = petal["pos"]
		var radius: float = float(petal["size"])
		draw_circle(pos, radius, Color(0.95, 0.86, 0.90, float(petal["alpha"])))

func _draw_top_bar() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(VIEW.x, TOP_BAR_H)), Color(0.07, 0.09, 0.10, 0.92), true)
	draw_line(Vector2(0.0, TOP_BAR_H), Vector2(VIEW.x, TOP_BAR_H), P.GOLD * Color(1, 1, 1, 0.45), 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(36.0, 30.0), "春之境", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, P.GOLD_PALE)
	draw_string(font, Vector2(36.0, 56.0), "模板 %d · 未尽之春" % run.template_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TEXT_MUTED)

	var exploration := run.exploration
	var stamina_ratio: float = float(exploration.stamina) / float(ExplorationState.STAMINA_MAX)
	var stamina_color: Color = P.CYAN if stamina_ratio > 0.3 else Color("#d98f6a")
	draw_string(font, Vector2(300.0, 32.0), "探索体力", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_MUTED)
	draw_string(font, Vector2(300.0, 58.0), "%d / %d" % [exploration.stamina, ExplorationState.STAMINA_MAX], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, stamina_color)

	# Ten pips make the remaining distance legible without reading the number.
	for index in range(ExplorationState.STAMINA_MAX):
		var pip := Rect2(Vector2(392.0 + float(index) * 14.0, 44.0), Vector2(10.0, 10.0))
		var filled: bool = index < exploration.stamina
		draw_rect(pip, stamina_color if filled else Color(0.20, 0.23, 0.24), true)

	draw_string(font, Vector2(580.0, 32.0), "花钿", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_MUTED)
	draw_string(font, Vector2(580.0, 58.0), str(run.coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, P.GOLD_LIGHT)
	draw_string(font, Vector2(680.0, 32.0), "补给", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_MUTED)
	draw_string(font, Vector2(680.0, 58.0), str(run.supplies), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, P.TEXT_STRONG)
	draw_string(font, Vector2(780.0, 32.0), "四时花露", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_MUTED)
	draw_string(font, Vector2(780.0, 58.0), "%d / %d" % [run.dew_total(), run.effective_dew_cap()], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, P.TEXT_BODY)
	draw_string(font, Vector2(900.0, 32.0), "记忆残页", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_MUTED)
	draw_string(font, Vector2(900.0, 58.0), str(run.memory_pages), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, P.TEXT_BODY)
	draw_string(font, Vector2(1020.0, 32.0), "遗物", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_MUTED)
	draw_string(font, Vector2(1020.0, 58.0), str(run.relics.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, P.TEXT_BODY)
	draw_rect(COLLECTIBLES_BTN, P.BUTTON_BG, true)
	draw_rect(COLLECTIBLES_BTN, P.BUTTON_BORDER, false, 1.2)
	draw_string(font, COLLECTIBLES_BTN.position + Vector2(14.0, 32.0), "藏品", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.BUTTON_TEXT)

func _draw_grid() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(GRID_ORIGIN - Vector2(14.0, 14.0), Vector2(5.0 * CELL_SIZE + 4.0 * CELL_GAP + 28.0, 5.0 * CELL_SIZE + 4.0 * CELL_GAP + 28.0)), Color(0.09, 0.11, 0.12, 0.85), true)
	for row in range(1, SpringMapTemplate.SIZE + 1):
		for col in range(1, SpringMapTemplate.SIZE + 1):
			var cell := Vector2i(row, col)
			var rect := cell_rect(cell)
			var place := run.template.place_at(cell)
			var is_here: bool = cell == run.exploration.position
			draw_rect(rect, _cell_fill(place, is_here), true)
			draw_rect(rect, _cell_border(place, is_here), false, 1.4)
			if place == null:
				draw_string(font, rect.position + Vector2(rect.size.x * 0.5 - 6.0, rect.size.y * 0.5 + 6.0), "·", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.30, 0.33, 0.33))
				continue
			var done: bool = place.one_shot and run.exploration.completed.has(place.id)
			var glyph_color: Color = _glyph_color(place.kind)
			if done:
				glyph_color = P.TEXT_DISABLED
			draw_string(font, rect.position + Vector2(rect.size.x * 0.5 - 13.0, 40.0), place.glyph(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, glyph_color)
			var label: String = run.title_of(place)
			draw_string(font, rect.position + Vector2(8.0, 66.0), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16.0, 11, P.TEXT_DISABLED if done else P.TEXT_BODY)
			if done:
				draw_string(font, rect.position + Vector2(rect.size.x - 20.0, 20.0), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_MUTED)

func _draw_selection() -> void:
	if not run.template.is_inside(selected_cell):
		return
	var cost: int = run.exploration.cost_to(selected_cell)
	var affordable: bool = run.exploration.can_afford(selected_cell) and not run.exploration.finished
	var path := run.exploration.path_to(selected_cell)
	for cell in path:
		var rect := cell_rect(cell)
		draw_rect(rect.grow(-22.0), (P.GOLD if affordable else Color(0.55, 0.30, 0.26)) * Color(1, 1, 1, 0.22), true)
	var rect := cell_rect(selected_cell)
	draw_rect(rect.grow(2.0), P.GOLD if affordable else Color("#8a4b42"), false, 2.0)
	var font := ThemeDB.fallback_font
	var hint: String = "前往 · %d 体力" % cost if affordable else "体力不足 · 需要 %d 点" % cost
	draw_string(font, Vector2(rect.position.x, rect.position.y - 8.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.GOLD_PALE if affordable else Color("#c98a7a"))

func _draw_bottom_bar() -> void:
	draw_rect(Rect2(Vector2(0.0, BOTTOM_BAR_Y), Vector2(VIEW.x, VIEW.y - BOTTOM_BAR_Y)), Color(0.07, 0.09, 0.10, 0.94), true)
	draw_line(Vector2(0.0, BOTTOM_BAR_Y), Vector2(VIEW.x, BOTTOM_BAR_Y), P.GOLD * Color(1, 1, 1, 0.35), 1.0)
	var font := ThemeDB.fallback_font

	var here: String = _place_label(run.exploration.position)
	draw_string(font, Vector2(36.0, 664.0), "当前位置  %s" % here, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_BODY)
	draw_string(font, Vector2(36.0, 690.0), status_message, HORIZONTAL_ALIGNMENT_LEFT, 510.0, 12, P.TEXT_MUTED)
	if RouteOverlayScript.draw_bottom_controls(self, run):
		return
	if not run.exploration.finished:
		_draw_button(GO_BTN, "前往所选", run.template.is_inside(selected_cell) and run.exploration.can_move_to(selected_cell))
		_draw_button(END_BTN, "结束探索", true)

	if run.exploration.can_interact():
		var place := run.exploration.place_here()
		var label: String = "进入 · %s" % run.title_of(place)
		_draw_button(Rect2(612.0, 648.0, 196.0, 44.0), label, true)

func _draw_button(rect: Rect2, label: String, enabled: bool) -> void:
	var bg: Color = P.BUTTON_BG if enabled else P.PANEL_DISABLED
	var border: Color = P.BUTTON_BORDER if enabled else P.PANEL_BORDER_DISABLED
	var text: Color = P.BUTTON_TEXT if enabled else P.TEXT_DISABLED
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 1.4)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(20.0, 28.0), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 30.0, 15, text)

func _draw_confirm() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), P.OVERLAY_SCRIM, true)
	var panel := Rect2(440.0, 300.0, 400.0, 180.0)
	draw_rect(panel, P.OVERLAY_BG, true)
	draw_rect(panel, P.GOLD, false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(28.0, 46.0), "结束春之境探索？", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, P.GOLD_PALE)
	draw_string(font, panel.position + Vector2(28.0, 82.0), "剩余体力 %d 点将作废，不转移至下一区域。" % run.exploration.stamina, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 56.0, 13, P.TEXT_BODY)
	_draw_button(CONFIRM_YES, "确认结束", true)
	_draw_button(CONFIRM_NO, "取消", true)

func _draw_finished() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), P.OVERLAY_SCRIM, true)
	# 留白式结局：文案来自 SpringEnding（可测试），这里只负责绘制。平定一局有多行
	# 收束文字，其余结束较短；面板按行数伸缩，按钮用常量定位、始终贴在面板下方。
	var ending: Dictionary = EndingScript.ending_for(run.exploration.finish_reason, run.event_log)
	var lines: Array = ending.get("lines", [])
	var panel_h: float = 148.0 + 24.0 * float(lines.size())
	var panel := Rect2(390.0, 250.0, 500.0, panel_h)
	draw_rect(panel, P.OVERLAY_BG, true)
	draw_rect(panel, P.GOLD, false, 2.0)
	var font := ThemeDB.fallback_font
	var color: Color = P.WARN if run.exploration.finish_reason == "defeat" else P.GOLD_PALE
	draw_string(font, panel.position + Vector2(28.0, 40.0), str(ending.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
	for index in range(lines.size()):
		draw_string(font, panel.position + Vector2(28.0, 76.0 + 24.0 * float(index)), str(lines[index]), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 56.0, 13, P.TEXT_BODY)
	var footer: String = BridgeScript.last_transition_message if not BridgeScript.last_transition_message.is_empty() else str(ending.get("footer", ""))
	draw_string(font, panel.position + Vector2(28.0, panel_h - 30.0), footer, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 56.0, 12, P.TEXT_MUTED)
	_draw_button(RETURN_BTN, "返回大厅", true)

func _cell_fill(place: SpringPlace, is_here: bool) -> Color:
	if place == null:
		return Color(0.12, 0.14, 0.14, 0.9) if not is_here else Color(0.18, 0.19, 0.15, 0.95)
	match place.kind:
		SpringPlace.Kind.BOSS:
			return Color(0.26, 0.18, 0.16, 0.95)
		SpringPlace.Kind.ELITE:
			return Color(0.22, 0.17, 0.24, 0.95)
		SpringPlace.Kind.BATTLE:
			return Color(0.19, 0.16, 0.15, 0.95)
		SpringPlace.Kind.EVENT:
			return Color(0.15, 0.19, 0.20, 0.95)
		SpringPlace.Kind.SHOP:
			return Color(0.16, 0.19, 0.16, 0.95)
		_:
			return Color(0.17, 0.17, 0.17, 0.95)

func _cell_border(place: SpringPlace, is_here: bool) -> Color:
	if is_here:
		return P.GOLD
	if place == null:
		return Color(0.20, 0.22, 0.22)
	return _glyph_color(place.kind) * Color(1, 1, 1, 0.55)

func _glyph_color(kind: int) -> Color:
	match kind:
		SpringPlace.Kind.BOSS:
			return P.GOLD_LIGHT
		SpringPlace.Kind.ELITE:
			return Color("#c8a0d8")
		SpringPlace.Kind.BATTLE:
			return Color("#d8a08a")
		SpringPlace.Kind.EVENT:
			return P.CYAN
		SpringPlace.Kind.SHOP:
			return Color("#a8c89a")
		SpringPlace.Kind.HIDDEN:
			return P.TEXT_FAINT
	return P.TEXT_BODY

func _place_label(cell: Vector2i) -> String:
	var place := run.template.place_at(cell)
	if place == null:
		return "空地 (%d,%d)" % [cell.x, cell.y]
	return run.title_of(place)

func _gui_input(event: InputEvent) -> void:
	if RouteOverlayScript.handle_gui_event(self, run, event):
		queue_redraw()
		accept_event()
		return
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var point := _to_view(mouse.position)
	if run == null:
		if RETURN_BTN.has_point(point):
			SceneTravel.change(get_tree(), MENU_SCENE_PATH)
		return
	if collectible_open:
		_handle_collectible_tap(point)
		queue_redraw()
		accept_event()
		return
	if event_open:
		_handle_event_tap(point)
		queue_redraw()
		accept_event()
		return
	if shop_open:
		_handle_shop_tap(point)
		queue_redraw()
		accept_event()
		return
	if not run.reward_choices.is_empty():
		_handle_reward_tap(point)
		queue_redraw()
		accept_event()
		return
	if run.revive_prompt:
		_handle_revive_tap(point)
		queue_redraw()
		accept_event()
		return
	if confirm_end:
		if CONFIRM_YES.has_point(point):
			confirm_end = false
			run.exploration.end_exploration()
			status_message = "已结束探索。剩余体力作废。"
			_save()
		elif CONFIRM_NO.has_point(point):
			confirm_end = false
		queue_redraw()
		accept_event()
		return
	if run.exploration.finished:
		if RETURN_BTN.has_point(point):
			# The run is over, so the save has nothing left to resume (§5.3).
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
			var error := SceneTravel.change(get_tree(), MENU_SCENE_PATH)
			if error != OK:
				push_error("Unable to return to the main menu. Error: %s" % error)
		queue_redraw()
		accept_event()
		return

	if COLLECTIBLES_BTN.has_point(point):
		collectible_open = true
		queue_redraw()
		accept_event()
		return
	if END_BTN.has_point(point):
		confirm_end = true
		queue_redraw()
		accept_event()
		return
	if run.exploration.can_interact() and Rect2(612.0, 648.0, 196.0, 44.0).has_point(point):
		_enter_here()
		queue_redraw()
		accept_event()
		return
	if GO_BTN.has_point(point):
		_try_move()
		queue_redraw()
		accept_event()
		return

	var cell := cell_at(point)
	if cell != Vector2i(-1, -1):
		selected_cell = cell
		status_message = "选中 %s · 距离 %d 格" % [_place_label(cell), run.exploration.cost_to(cell)]
		if cell == run.exploration.position and run.exploration.can_interact():
			_enter_here()
	queue_redraw()
	accept_event()

func _try_move() -> void:
	if not run.template.is_inside(selected_cell):
		status_message = "先在地图上选择一个地点。"
		return
	if not run.exploration.can_afford(selected_cell):
		status_message = "体力不足：需要 %d 点，剩余 %d 点。" % [run.exploration.cost_to(selected_cell), run.exploration.stamina]
		return
	if not run.exploration.move_to(selected_cell):
		status_message = "无法移动。"
		return
	status_message = "抵达 %s · 剩余体力 %d" % [_place_label(run.exploration.position), run.exploration.stamina]
	_save()

func _save() -> bool:
	return flow.save(self)

func _enter_here() -> void:
	var place := run.exploration.place_here()
	if place == null:
		return
	if place.one_shot and run.exploration.completed.has(place.id):
		status_message = "该地点已完成。"
		return
	match place.kind:
		SpringPlace.Kind.BATTLE:
			_start_battle(place, BridgeScript.KIND_BATTLE)
		SpringPlace.Kind.ELITE:
			_start_battle(place, BridgeScript.KIND_ELITE)
		SpringPlace.Kind.BOSS:
			_start_battle(place, BridgeScript.KIND_BOSS)
		SpringPlace.Kind.EVENT:
			_open_event(place)
		SpringPlace.Kind.SHOP:
			_open_shop()
		SpringPlace.Kind.HIDDEN:
			_open_event(place)

func _start_battle(place: SpringPlace, kind: String) -> void:
	flow.start_battle(self, place, kind)

func _open_event(place: SpringPlace) -> void:
	var event_id := _event_id_for(place)
	if event_id == &"" or not EventCatalogScript.has_event(event_id):
		status_message = "「%s」的内容还没有接入。" % run.title_of(place)
		return
	event_place = place
	event_result = {}
	event_open = true

func _event_id_for(place: SpringPlace) -> StringName:
	if place == null:
		return &""
	# The random slot carries no identity of its own: the run drew one (§10.3).
	if place.id == &"event_random":
		return run.random_event_id
	# The hidden place resolves to a hoard, which is the one event that only
	# exists through a reveal.
	if place.kind == SpringPlace.Kind.HIDDEN:
		return &"hidden_hoard"
	return place.payload

func _open_shop() -> void:
	flow.open_shop(self)

func _apply_returned_battle() -> void:
	flow.apply_returned_battle(self)

func _reveal_hidden_place() -> void:
	for cell in FactoryScript.LAYOUT_ORDER:
		if run.reveal_hidden(cell):
			status_message += " 地图上多出一处「隐秘之地」。"
			return
	status_message += " 地图上已经没有能藏东西的地方了。"

func _draw_reward_choices() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, VIEW), P.OVERLAY_SCRIM, true)
	var panel := Rect2(180.0, 140.0, 920.0, 420.0)
	draw_rect(panel, P.OVERLAY_BG, true)
	draw_rect(panel, P.GOLD, false, 2.0)
	draw_string(font, Vector2(216.0, 196.0), "精英战利品 · 三选一", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.GOLD_PALE)
	draw_string(font, Vector2(216.0, 226.0), "只出现普通与稀有品质；已拥有的不会重复出现。", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_MUTED)
	for index in range(run.reward_choices.size()):
		var rect := reward_card_rect(index)
		var collectible_id: StringName = run.reward_choices[index]
		draw_rect(rect, P.PANEL, true)
		draw_rect(rect, P.BUTTON_BORDER, false, 1.4)
		draw_string(font, rect.position + Vector2(18.0, 30.0), CollectibleCatalogScript.name_of(collectible_id), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 18, P.GOLD_LIGHT)
		draw_string(font, rect.position + Vector2(18.0, 56.0), CollectibleCatalogScript.rarity_of(collectible_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.CYAN)
		draw_string(font, rect.position + Vector2(18.0, 84.0), CollectibleCatalogScript.desc_of(collectible_id), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 13, P.TEXT_BODY)

func reward_card_rect(index: int) -> Rect2:
	return Rect2(216.0 + float(index) * 300.0, 260.0, 280.0, 180.0)

func _draw_revive_prompt() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, VIEW), P.OVERLAY_SCRIM, true)
	var panel := Rect2(300.0, 240.0, 680.0, 240.0)
	draw_rect(panel, P.OVERLAY_BG, true)
	draw_rect(panel, P.WARN, false, 2.0)
	draw_string(font, Vector2(340.0, 296.0), "这一处失守了", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.WARN)
	draw_string(font, Vector2(340.0, 330.0), "每个区域可以续行一次：消耗 %d 份补给，回复至三成生命。" % BridgeScript.CONTINUE_SUPPLY_COST, HORIZONTAL_ALIGNMENT_LEFT, 600.0, 14, P.TEXT_BODY)
	draw_string(font, Vector2(340.0, 356.0), "现有补给 %d 份。" % run.supplies, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_MUTED)
	_draw_button(REVIVE_YES, "续行", BridgeScript.can_continue(run))
	_draw_button(REVIVE_NO, "结束本局", true)

func _handle_event_tap(point: Vector2) -> void:
	var event_id := _event_id_for(event_place)
	var hit: Dictionary = EventViewScript.hit(point, EventCatalogScript.option_count(event_id), not event_result.is_empty())
	match str(hit["action"]):
		EventViewScript.ACTION_OPTION:
			_choose_event_option(event_id, int(hit["index"]))
		EventViewScript.ACTION_CLOSE:
			_close_event()
		_:
			pass

func _choose_event_option(event_id: StringName, index: int) -> void:
	flow.choose_event_option(self, event_id, index)

func _close_event() -> void:
	flow.close_event(self)

func _handle_shop_tap(point: Vector2) -> void:
	var hit: Dictionary = ShopViewScript.hit(point, run.shop, run, shop_tab, shop_sell_page)
	match str(hit["action"]):
		ShopViewScript.ACTION_CLOSE:
			_close_shop()
		ShopViewScript.ACTION_TAB:
			shop_tab = int(hit["index"])
			shop_message = ""
		ShopViewScript.ACTION_BUY:
			var bought: Dictionary = run.shop.buy(int(hit["index"]), run)
			shop_message = str(bought.get("message", ""))
			_save()
		ShopViewScript.ACTION_SELL:
			var sold: Dictionary = run.shop.sell(run, int(hit["index"]))
			shop_message = str(sold.get("message", ""))
			_save()
		ShopViewScript.ACTION_REFRESH:
			var refreshed: Dictionary = run.shop.refresh(run)
			shop_message = str(refreshed.get("message", ""))
			_save()
		ShopViewScript.ACTION_SERVICE:
			var served: Dictionary = run.shop.use_service(SpringShop.SERVICE_REST, run)
			shop_message = str(served.get("message", ""))
			_save()
		ShopViewScript.ACTION_PAGE_PREV:
			shop_sell_page = maxi(0, shop_sell_page - 1)
		ShopViewScript.ACTION_PAGE_NEXT:
			shop_sell_page += 1
		_:
			pass

## §7.2: the shop keeps its stock between visits, so leaving only drops the
## pending price effect and the overlay.
func _close_shop() -> void:
	run.leave_shop()
	shop_open = false
	status_message = "离开了春日行商。"
	_save()

func _handle_reward_tap(point: Vector2) -> void:
	flow.handle_reward_tap(self, point)

func _handle_revive_tap(point: Vector2) -> void:
	flow.handle_revive_tap(self, point)

func _unhandled_key_input(event: InputEvent) -> void:
	if run == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.is_action_pressed("echo_cancel"):
		if event_open and not event_result.is_empty():
			_close_event()
			queue_redraw()
			accept_event()
			return
		if shop_open:
			_close_shop()
			queue_redraw()
			accept_event()
			return
		if confirm_end:
			confirm_end = false
		elif not run.exploration.finished:
			confirm_end = true
		queue_redraw()
		accept_event()
