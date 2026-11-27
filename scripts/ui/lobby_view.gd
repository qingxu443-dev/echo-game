extends Control

## Camp / Lobby hub for ECHO.
##
## Players arrive here from the title screen, see Sevrin stationed in the dusk
## camp with live expedition status, and click the prominent bottom-right
## "选择地图" button to open the region selector overlay (Tutorial / 未尽之春).

const MENU_SCENE_PATH := "res://scenes/menu/main_menu.tscn"
const BATTLE_SCENE_PATH := "res://scenes/main/main.tscn"
const SPRING_SCENE_PATH := "res://scenes/spring/spring_map.tscn"
const SPRING_SAVE_PATH := "user://spring_run.json"
const BACKGROUND_PATH := "res://assets/ui/main_menu_background.png"
const SEVRIN_SPRITE_PATH := "res://assets/actors/sevrin.png"

const MAP_ENTRIES: Array[Dictionary] = [
	{
		"id": "tutorial",
		"tag": "TUTORIAL · 3 关",
		"title": "序章 · 遗迹教学",
		"subtitle": "出战角色：瑟弗林（守誓者）",
		"desc_lines": [
			"2.5D 等距战棋基础演练（每回合 3 AP）。",
			"掌握击退破招、AP 联动敌方充能、",
			"遗迹宝箱抢宝与装备背包循环。",
		],
		"cta": "前往教学",
		"scene_path": BATTLE_SCENE_PATH,
		"accent": Color("#d4b77b"),
		"locked": false,
	},
	{
		"id": "spring",
		"tag": "SEASON MAP · 5×5",
		"title": "春之境 · 未尽之春",
		"subtitle": "出战角色：樱（折樱剑士）",
		"desc_lines": [
			"5×5 节点大地图探索，权衡体力与路线。",
			"触发十段奇遇、逛春日行商、收集藏品，",
			"直面四名精英专属技与 Boss 千枝神将。",
		],
		"cta": "进入春之境",
		"scene_path": SPRING_SCENE_PATH,
		"accent": Color("#e89ab0"),
		"locked": false,
	},
	{
		"id": "upcoming",
		"tag": "COMING SOON",
		"title": "更多区域 · 筹备中",
		"subtitle": "后续章节与多角色拓展",
		"desc_lines": [
			"底层多角色框架与队伍切换已预留接口。",
			"后续版本将在此陆续开放新的远征区域，",
			"以及更多可同行出战的同伴角色。",
		],
		"cta": "暂未开放",
		"scene_path": "",
		"accent": Color("#7c8796"),
		"locked": true,
	},
]

const CAMP_LINES: Array[String] = [
	"「在黄昏落尽之前，把要守的东西攥紧。随时可以从右下角挑选出征区域。」",
	"「遗迹里的宝箱别轻易让构造体抢走——它们会真的穿上里面的装备。」",
	"「听说永不落幕的春之境里，樱正在寻找一段未曾说完的旧回忆。」",
	"「点右下角的『选择地图』就能出发；如果想先热身，就去序章遗迹练练手吧。」",
]

var background: Texture2D
var sevrin_sprite: Texture2D
var elapsed: float = 0.0
var motes: Array[Dictionary] = []

var map_selector_open: bool = false
var selected_map_index: int = 0
var hovered_map_index: int = -1
var hover_expedition: bool = false
var hover_back: bool = false
var expedition_glow: float = 0.0
var selector_fade: float = 0.0

var camp_line_index: int = 0
var status_notice: String = ""
var spring_resume_info: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	background = _load_texture(BACKGROUND_PATH)
	sevrin_sprite = _load_texture(SEVRIN_SPRITE_PATH)
	_init_motes()
	refresh_save_summary()
	queue_redraw()


func refresh_save_summary() -> void:
	spring_resume_info.clear()
	var restored := SpringRun.load_from_file(SPRING_SAVE_PATH)
	if restored != null and not restored.exploration.finished:
		spring_resume_info = {
			"active": true,
			"template_id": restored.template_id,
			"stamina": restored.exploration.stamina,
			"stamina_max": ExplorationState.STAMINA_MAX,
		}


func _load_texture(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path, "Texture2D"):
		var res := ResourceLoader.load(res_path)
		if res is Texture2D:
			return res
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _init_motes() -> void:
	motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261127
	for _i in range(34):
		motes.append({
			"x": rng.randf_range(0.0, 1280.0),
			"y": rng.randf_range(0.0, 720.0),
			"vy": rng.randf_range(-16.0, -6.0),
			"vx": rng.randf_range(-5.0, 9.0),
			"r": rng.randf_range(1.2, 2.8),
			"phase": rng.randf_range(0.0, TAU),
			"cyan": rng.randf() < 0.35,
		})


func _process(delta: float) -> void:
	elapsed += delta
	var target_glow := 1.0 if hover_expedition else 0.0
	expedition_glow = lerpf(expedition_glow, target_glow, minf(1.0, delta * 10.0))
	var target_fade := 1.0 if map_selector_open else 0.0
	selector_fade = lerpf(selector_fade, target_fade, minf(1.0, delta * 14.0))
	for m in motes:
		m["x"] = fposmod(float(m["x"]) + float(m["vx"]) * delta + sin(elapsed * 0.7 + float(m["phase"])) * 3.5 * delta, maxf(1.0, size.x))
		m["y"] = float(m["y"]) + float(m["vy"]) * delta
		if float(m["y"]) < -10.0:
			m["y"] = size.y + 10.0
	queue_redraw()


# --- geometry (1280x720 scaled cleanly to viewport) --------------------------

func _sx() -> float:
	return maxf(1.0, size.x) / 1280.0


func _sy() -> float:
	return maxf(1.0, size.y) / 720.0


func back_button_rect() -> Rect2:
	return Rect2(32.0 * _sx(), 24.0 * _sy(), 132.0 * _sx(), 38.0 * _sy())


func expedition_button_rect() -> Rect2:
	return Rect2(920.0 * _sx(), 574.0 * _sy(), 320.0 * _sx(), 106.0 * _sy())


func character_hit_rect() -> Rect2:
	return Rect2(140.0 * _sx(), 140.0 * _sy(), 340.0 * _sx(), 440.0 * _sy())


func selector_panel_rect() -> Rect2:
	return Rect2(116.0 * _sx(), 92.0 * _sy(), 1048.0 * _sx(), 536.0 * _sy())


func close_selector_rect() -> Rect2:
	var panel := selector_panel_rect()
	return Rect2(panel.end.x - 54.0 * _sx(), panel.position.y + 16.0 * _sy(), 36.0 * _sx(), 36.0 * _sy())


func map_card_rect(index: int) -> Rect2:
	var panel := selector_panel_rect()
	var card_w: float = 308.0 * _sx()
	var card_h: float = 382.0 * _sy()
	var gap: float = 24.0 * _sx()
	var total_w: float = card_w * float(MAP_ENTRIES.size()) + gap * float(MAP_ENTRIES.size() - 1)
	var start_x: float = panel.position.x + (panel.size.x - total_w) * 0.5
	var top_y: float = panel.position.y + 92.0 * _sy()
	return Rect2(start_x + float(index) * (card_w + gap), top_y, card_w, card_h)


# --- public state helpers ----------------------------------------------------

func open_map_selector() -> void:
	refresh_save_summary()
	map_selector_open = true
	status_notice = ""
	queue_redraw()


func close_map_selector() -> void:
	map_selector_open = false
	hovered_map_index = -1
	queue_redraw()


func move_map_selection(direction: int) -> void:
	if direction == 0 or MAP_ENTRIES.is_empty():
		return
	selected_map_index = wrapi(selected_map_index + signi(direction), 0, MAP_ENTRIES.size())
	queue_redraw()


func activate_map(index: int) -> bool:
	if index < 0 or index >= MAP_ENTRIES.size():
		return false
	selected_map_index = index
	var entry: Dictionary = MAP_ENTRIES[index]
	if bool(entry.get("locked", false)):
		status_notice = "「%s」仍在筹备中，敬请期待。" % str(entry.get("title", "新区域"))
		queue_redraw()
		return false
	var target_path: String = str(entry.get("scene_path", ""))
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		status_notice = "目标地图场景不可用。"
		queue_redraw()
		return false
	var tree := get_tree()
	if tree == null:
		return true
	var error := tree.change_scene_to_file(target_path)
	if error != OK:
		push_error("Lobby: unable to open %s. Error: %s" % [target_path, error])
		return false
	return true


func return_to_title() -> bool:
	var tree := get_tree()
	if tree == null:
		return true
	var error := tree.change_scene_to_file(MENU_SCENE_PATH)
	if error != OK:
		push_error("Lobby: unable to return to title. Error: %s" % error)
		return false
	return true


# --- input -------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if map_selector_open:
		match event.keycode:
			KEY_ESCAPE:
				close_map_selector()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A:
				move_map_selection(-1)
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				move_map_selection(1)
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				activate_map(selected_map_index)
				get_viewport().set_input_as_handled()
		return

	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			open_map_selector()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			return_to_title()
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos: Vector2 = event.position
		if map_selector_open:
			var next_hover := -1
			for i in range(MAP_ENTRIES.size()):
				if map_card_rect(i).has_point(pos):
					next_hover = i
					selected_map_index = i
					break
			if next_hover != hovered_map_index:
				hovered_map_index = next_hover
				queue_redraw()
		else:
			var exp_h := expedition_button_rect().has_point(pos)
			var back_h := back_button_rect().has_point(pos)
			if exp_h != hover_expedition or back_h != hover_back:
				hover_expedition = exp_h
				hover_back = back_h
				queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(event.position)
		accept_event()


func _handle_click(pos: Vector2) -> void:
	if map_selector_open:
		if close_selector_rect().has_point(pos) or not selector_panel_rect().has_point(pos):
			close_map_selector()
			return
		for i in range(MAP_ENTRIES.size()):
			if map_card_rect(i).has_point(pos):
				activate_map(i)
				return
		return

	if expedition_button_rect().has_point(pos):
		open_map_selector()
		return
	if back_button_rect().has_point(pos):
		return_to_title()
		return
	if character_hit_rect().has_point(pos):
		camp_line_index = (camp_line_index + 1) % CAMP_LINES.size()
		queue_redraw()


# --- rendering ---------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var sx := _sx()
	var sy := _sy()

	_draw_backdrop(sx, sy)
	_draw_character_stage(font, sx, sy)
	_draw_top_bar(font, sx, sy)
	_draw_expedition_button(font, sx, sy)
	if map_selector_open or selector_fade > 0.02:
		_draw_map_selector(font, sx, sy, maxf(selector_fade, 1.0 if map_selector_open else 0.0))


func _draw_backdrop(sx: float, sy: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#12151b"), true)
	if background != null:
		var tex_sz := background.get_size()
		var scale_f := maxf(size.x / maxf(1.0, tex_sz.x), size.y / maxf(1.0, tex_sz.y))
		var drawn := tex_sz * scale_f
		var offset := (size - drawn) * 0.5
		draw_texture_rect(background, Rect2(offset, drawn), false, Color(0.55, 0.56, 0.62, 1.0))

	# Dusk sanctuary vignette & left/bottom readability gradient
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]),
		PackedColorArray([Color(0.06, 0.075, 0.11, 0.68), Color(0.07, 0.08, 0.11, 0.42), Color(0.04, 0.05, 0.08, 0.82), Color(0.05, 0.06, 0.09, 0.78)])
	)

	# Subtle rotating astrolabe echo rings behind the camp character
	var ring_center := Vector2(315.0 * sx, 385.0 * sy)
	draw_arc(ring_center, 185.0 * sy, elapsed * 0.18, elapsed * 0.18 + TAU * 0.72, 48, Color(0.84, 0.72, 0.48, 0.16), 1.5, true)
	draw_arc(ring_center, 226.0 * sy, -elapsed * 0.12, -elapsed * 0.12 + TAU * 0.55, 48, Color(0.56, 0.78, 0.86, 0.14), 1.2, true)

	for m in motes:
		var tw: float = 0.4 + 0.6 * sin(elapsed * 2.0 + float(m["phase"]))
		var col := Color(0.56, 0.86, 0.96, 0.48 * tw) if bool(m["cyan"]) else Color(0.96, 0.82, 0.48, 0.58 * tw)
		draw_circle(Vector2(float(m["x"]), float(m["y"])), float(m["r"]), col)


func _draw_character_stage(font: Font, sx: float, sy: float) -> void:
	# Glowing camp floor ellipse under Sevrin
	var foot := Vector2(310.0 * sx, 562.0 * sy)
	var bob: float = sin(elapsed * 1.9) * 4.5 * sy
	var pts := PackedVector2Array()
	for i in range(32):
		var a := float(i) / 32.0 * TAU
		pts.append(foot + Vector2(cos(a) * 116.0 * sx, sin(a) * 24.0 * sy))
	draw_colored_polygon(pts, Color(0.82, 0.70, 0.44, 0.14))

	if sevrin_sprite != null:
		var tex_sz := sevrin_sprite.get_size()
		var target_h: float = 445.0 * sy
		var target_w: float = target_h * (tex_sz.x / maxf(1.0, tex_sz.y))
		var dst := Rect2(foot.x - target_w * 0.5, foot.y - target_h + 26.0 * sy + bob, target_w, target_h)
		draw_texture_rect(sevrin_sprite, dst, false)

	# Bottom-left character nameplate & camp dialogue
	var card := Rect2(36.0 * sx, 560.0 * sy, 540.0 * sx, 120.0 * sy)
	draw_rect(card, Color(0.09, 0.11, 0.15, 0.82), true)
	draw_rect(Rect2(card.position, Vector2(4.0 * sx, card.size.y)), Color("#d4b77b"), true)
	draw_rect(card, Color(0.84, 0.72, 0.48, 0.32), false, 1.0)
	draw_string(font, card.position + Vector2(20.0 * sx, 30.0 * sy), "瑟弗林  ·  守誓者", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(19.0 * sy), Color("#f2e6cf"))
	draw_string(font, card.position + Vector2(205.0 * sx, 29.0 * sy), "点立绘切换营地对话", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.0 * sy), Color(0.65, 0.68, 0.74, 0.78))
	draw_string(font, card.position + Vector2(20.0 * sx, 68.0 * sy), CAMP_LINES[camp_line_index], HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 36.0 * sx, roundi(13.0 * sy), Color("#d6d2c7"))
	draw_string(font, card.position + Vector2(20.0 * sx, 102.0 * sy), "当前营地状态：整备就绪  ·  2 个可出征区域", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color("#8fc7dc"))


func _draw_top_bar(font: Font, sx: float, sy: float) -> void:
	draw_rect(Rect2(0.0, 0.0, size.x, 84.0 * sy), Color(0.06, 0.075, 0.105, 0.76), true)
	draw_line(Vector2(0.0, 84.0 * sy), Vector2(size.x, 84.0 * sy), Color(0.84, 0.72, 0.48, 0.25), 1.0)

	var back_r := back_button_rect()
	draw_rect(back_r, Color(0.18, 0.21, 0.26, 0.92) if hover_back else Color(0.12, 0.14, 0.18, 0.85), true)
	draw_rect(back_r, Color("#d4b77b") if hover_back else Color("#464b54"), false, 1.2)
	draw_string(font, back_r.position + Vector2(18.0 * sx, 24.0 * sy), "← 返回标题", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.0 * sy), Color("#e4dfd3"))

	draw_string(font, Vector2(188.0 * sx, 46.0 * sy), "ECHO  ·  黄昏营地大厅", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(22.0 * sy), Color("#f2e6cf"))
	draw_string(font, Vector2(188.0 * sx, 67.0 * sy), "EXPEDITION HUB  ·  选择出征地图开始探索", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.0 * sy), Color("#9b9a94"))

	# Top-right live status pill
	var pill := Rect2(920.0 * sx, 22.0 * sy, 320.0 * sx, 40.0 * sy)
	var has_resume := bool(spring_resume_info.get("active", false))
	draw_rect(pill, Color(0.11, 0.16, 0.20, 0.88) if has_resume else Color(0.12, 0.14, 0.18, 0.82), true)
	draw_rect(pill, Color("#8fc7dc") if has_resume else Color("#464b54"), false, 1.2)
	var pill_text := "未尽之春进行中 · 体力 %d/%d" % [int(spring_resume_info.get("stamina", 0)), int(spring_resume_info.get("stamina_max", 10))] if has_resume else "出征待命 · 可随时选择地图"
	draw_string(font, pill.position + Vector2(16.0 * sx, 25.0 * sy), pill_text, HORIZONTAL_ALIGNMENT_LEFT, pill.size.x - 24.0 * sx, roundi(13.0 * sy), Color("#d4eff8") if has_resume else Color("#c7c2b6"))


func _draw_expedition_button(font: Font, sx: float, sy: float) -> void:
	var btn := expedition_button_rect()
	var pulse: float = 0.5 + 0.5 * sin(elapsed * 2.8)
	var bg := Color("#3d3324").lerp(Color("#54452e"), expedition_glow)
	var border := Color("#c5a45c").lerp(Color("#f4dd9e"), maxf(expedition_glow, pulse * 0.35))

	# Soft golden outer halo
	draw_rect(btn.grow(4.0 * sx), Color(0.92, 0.76, 0.42, 0.12 + 0.14 * expedition_glow), true)
	draw_rect(btn, bg, true)
	# Accent left stripe
	draw_rect(Rect2(btn.position, Vector2(7.0 * sx, btn.size.y)), border, true)
	draw_rect(btn, border, false, 2.0)

	var shift_x: float = 6.0 * sx * expedition_glow
	draw_string(font, btn.position + Vector2(28.0 * sx + shift_x, 48.0 * sy), "选择地图", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(28.0 * sy), Color("#fbf2df"))
	draw_string(font, btn.position + Vector2(28.0 * sx + shift_x, 74.0 * sy), "EXPEDITION  ·  点击出征", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), Color("#e4d2aa"))
	draw_string(font, btn.position + Vector2(28.0 * sx + shift_x, 94.0 * sy), "教学遗迹 / 未尽之春  [Enter]", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.0 * sy), Color("#b9b7ad"))
	draw_string(font, btn.position + Vector2(btn.size.x - 42.0 * sx + shift_x * 0.5, 62.0 * sy), "▸", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(28.0 * sy), border)

	if bool(spring_resume_info.get("active", false)):
		var badge := Rect2(btn.end.x - 78.0 * sx, btn.position.y - 14.0 * sy, 74.0 * sx, 24.0 * sy)
		draw_rect(badge, Color("#244656"), true)
		draw_rect(badge, Color("#8fc7dc"), false, 1.2)
		draw_string(font, badge.position + Vector2(12.0 * sx, 16.0 * sy), "可续行", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color("#e4f9ff"))


func _draw_map_selector(font: Font, sx: float, sy: float, alpha: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.78 * alpha), true)
	var panel := selector_panel_rect()
	draw_rect(panel, Color(0.10, 0.12, 0.16, 0.96 * alpha), true)
	draw_rect(panel, Color(0.84, 0.72, 0.48, 0.65 * alpha), false, 1.8)

	draw_string(font, panel.position + Vector2(36.0 * sx, 44.0 * sy), "选择出征地图", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24.0 * sy), Color(0.96, 0.91, 0.80, alpha))
	draw_string(font, panel.position + Vector2(36.0 * sx, 68.0 * sy), "SELECT REGION  ·  点击卡片或按 Enter 出发，Esc 返回大厅", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), Color(0.66, 0.68, 0.73, alpha))

	var close_r := close_selector_rect()
	draw_rect(close_r, Color(0.18, 0.20, 0.25, 0.9 * alpha), true)
	draw_rect(close_r, Color(0.55, 0.56, 0.60, 0.7 * alpha), false, 1.2)
	draw_string(font, close_r.position + Vector2(11.0 * sx, 24.0 * sy), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20.0 * sy), Color(0.9, 0.88, 0.84, alpha))

	for i in range(MAP_ENTRIES.size()):
		_draw_map_card(font, i, sx, sy, alpha)

	var footer_text := status_notice if not status_notice.is_empty() else "提示：教学关与「未尽之春」各自独立记录，可随时切换体验。"
	var footer_col := Color("#e4b092") if not status_notice.is_empty() else Color("#9b9a94")
	draw_string(font, Vector2(panel.position.x + 36.0 * sx, panel.end.y - 22.0 * sy), footer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.5 * sy), Color(footer_col.r, footer_col.g, footer_col.b, alpha))


func _draw_map_card(font: Font, index: int, sx: float, sy: float, alpha: float) -> void:
	var entry: Dictionary = MAP_ENTRIES[index]
	var r := map_card_rect(index)
	var selected := (index == selected_map_index)
	var locked := bool(entry.get("locked", false))
	var accent: Color = entry.get("accent", Color("#d4b77b"))
	var bg := Color(0.14, 0.16, 0.21, 0.95 * alpha) if (selected and not locked) else Color(0.11, 0.13, 0.17, 0.90 * alpha)
	if locked:
		bg = Color(0.09, 0.10, 0.13, 0.85 * alpha)

	draw_rect(r, bg, true)
	# Top colour banner stripe
	draw_rect(Rect2(r.position, Vector2(r.size.x, 8.0 * sy)), Color(accent.r, accent.g, accent.b, (0.95 if selected else 0.55) * alpha), true)
	var border_col := Color(accent.r, accent.g, accent.b, (0.98 if selected else 0.38) * alpha)
	draw_rect(r, border_col, false, 2.2 if selected else 1.2)

	draw_string(font, r.position + Vector2(20.0 * sx, 38.0 * sy), str(entry["tag"]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color(accent.r, accent.g, accent.b, alpha))
	draw_string(font, r.position + Vector2(20.0 * sx, 74.0 * sy), str(entry["title"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36.0 * sx, roundi(22.0 * sy), Color(0.95, 0.92, 0.86, (0.55 if locked else 1.0) * alpha))
	draw_string(font, r.position + Vector2(20.0 * sx, 102.0 * sy), str(entry["subtitle"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36.0 * sx, roundi(13.0 * sy), Color(0.74, 0.76, 0.80, (0.55 if locked else 0.95) * alpha))
	draw_line(r.position + Vector2(20.0 * sx, 120.0 * sy), r.position + Vector2(r.size.x - 20.0 * sx, 120.0 * sy), Color(0.45, 0.47, 0.52, 0.35 * alpha), 1.0)

	var lines: Array = entry.get("desc_lines", [])
	for li in range(lines.size()):
		draw_string(font, r.position + Vector2(20.0 * sx, (152.0 + float(li) * 28.0) * sy), str(lines[li]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36.0 * sx, roundi(13.0 * sy), Color(0.80, 0.79, 0.76, (0.50 if locked else 0.92) * alpha))

	var is_spring_resume := (str(entry["id"]) == "spring" and bool(spring_resume_info.get("active", false)))
	if is_spring_resume:
		var tag_r := Rect2(r.position.x + 20.0 * sx, r.end.y - 108.0 * sy, r.size.x - 40.0 * sx, 28.0 * sy)
		draw_rect(tag_r, Color(0.13, 0.25, 0.32, 0.9 * alpha), true)
		draw_rect(tag_r, Color(0.56, 0.78, 0.86, 0.8 * alpha), false, 1.0)
		draw_string(font, tag_r.position + Vector2(12.0 * sx, 19.0 * sy), "检测到未完成探索 · 剩余体力 %d/%d" % [int(spring_resume_info.get("stamina", 0)), int(spring_resume_info.get("stamina_max", 10))], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color(0.88, 0.97, 1.0, alpha))

	# Bottom CTA button inside card
	var cta_r := Rect2(r.position.x + 20.0 * sx, r.end.y - 64.0 * sy, r.size.x - 40.0 * sx, 44.0 * sy)
	var cta_bg := Color(0.18, 0.19, 0.22, 0.75 * alpha) if locked else (Color(accent.r * 0.42, accent.g * 0.38, accent.b * 0.30, 0.95 * alpha) if selected else Color(0.18, 0.20, 0.24, 0.90 * alpha))
	draw_rect(cta_r, cta_bg, true)
	draw_rect(cta_r, border_col, false, 1.4)
	var cta_label := "继续探索" if is_spring_resume else str(entry["cta"])
	draw_string(font, cta_r.position + Vector2(0.0, 28.0 * sy), cta_label, HORIZONTAL_ALIGNMENT_CENTER, cta_r.size.x, roundi(15.0 * sy), Color(0.55, 0.56, 0.60, alpha) if locked else Color(0.98, 0.95, 0.88, alpha))
