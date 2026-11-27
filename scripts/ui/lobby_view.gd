extends Control

## Atelier-style twilight sanctuary idle hub for ECHO.
##
## Features a dedicated full-bleed warm sunset atelier illustration with gentle
## breathing parallax, streaming window light, interactive room hotspots
## (Sevrin, workbench map, leaned sword & shield), a quiet auto-fading dialogue
## ribbon, and the prominent bottom-right "选择地图" expedition trigger.

const MENU_SCENE_PATH := "res://scenes/menu/main_menu.tscn"
const BATTLE_SCENE_PATH := "res://scenes/main/main.tscn"
const SPRING_SCENE_PATH := "res://scenes/spring/spring_map.tscn"
const SPRING_SAVE_PATH := "user://spring_run.json"
const BACKGROUND_PATH := "res://assets/ui/lobby_atelier_bg.png"

const MAP_ENTRIES: Array[Dictionary] = [
	{
		"id": "tutorial", "tag": "TUTORIAL · 3 关", "title": "序章 · 遗迹教学", "subtitle": "出战角色：瑟弗林（守誓者）",
		"desc_lines": ["2.5D 等距战棋基础演练（每回合 3 AP）。", "掌握击退破招、AP 联动敌方充能、", "遗迹宝箱抢宝与装备背包循环。"],
		"cta": "前往教学", "scene_path": BATTLE_SCENE_PATH, "accent": Color("#d4b77b"), "locked": false,
	},
	{
		"id": "spring", "tag": "SEASON MAP · 5×5", "title": "春之境 · 未尽之春", "subtitle": "出战角色：樱（折樱剑士）",
		"desc_lines": ["5×5 节点大地图探索，权衡体力与路线。", "触发十段奇遇、逛春日行商、收集藏品，", "直面四名精英专属技与 Boss 千枝神将。"],
		"cta": "进入春之境", "scene_path": SPRING_SCENE_PATH, "accent": Color("#e89ab0"), "locked": false,
	},
	{
		"id": "upcoming", "tag": "COMING SOON", "title": "更多区域 · 筹备中", "subtitle": "后续章节与多角色拓展",
		"desc_lines": ["底层多角色框架与队伍切换已预留接口。", "后续版本将在此陆续开放新的远征区域，", "以及更多可同行出战的同伴角色。"],
		"cta": "暂未开放", "scene_path": "", "accent": Color("#7c8796"), "locked": true,
	},
]

const SEVRIN_LINES: Array[String] = [
	"「黄昏前的这段安静时间真难得……路线想好了吗？点桌上的地图或右下角就能出发。」",
	"「遗迹里的宝箱经不起两下敲打，别让那些构造体抢先砸开了。」",
	"「听说永不落幕的春之境里，樱还在沿着旧花径收集散落的记忆。」",
	"「盾和剑都擦好了。休息够的话，我们随时可以动身。」",
]

const GEAR_LINES: Array[String] = [
	"【战备检查】誓刃与守誓战盾正静静倚在石柱旁，回声纹路仍在微弱脉动。",
	"【工坊手记】桌上的青色与琥珀药剂在夕阳下泛着微光，出发前记得规划好路线。",
]

var background: Texture2D
var elapsed: float = 0.0
var motes: Array[Dictionary] = []
var mouse_norm: Vector2 = Vector2.ZERO
var parallax_smooth: Vector2 = Vector2.ZERO

var map_selector_open: bool = false
var selected_map_index: int = 0
var hovered_map_index: int = -1
var hover_expedition: bool = false
var hover_back: bool = false
var hovered_hotspot: String = ""
var expedition_glow: float = 0.0
var selector_fade: float = 0.0

var camp_line_index: int = 0
var gear_line_index: int = 0
var active_dialogue: String = ""
var dialogue_speaker: String = "瑟弗林"
var dialogue_timer: float = 0.0
var status_notice: String = ""
var spring_resume_info: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	background = _load_texture(BACKGROUND_PATH)
	_init_motes()
	refresh_save_summary()
	_show_dialogue("瑟弗林", SEVRIN_LINES[0], 6.0)
	queue_redraw()


func refresh_save_summary() -> void:
	spring_resume_info.clear()
	var restored := SpringRun.load_from_file(SPRING_SAVE_PATH)
	if restored != null and not restored.exploration.finished:
		spring_resume_info = {
			"active": true,
			"hard_mode": restored.route_plan != null and restored.route_plan.hard_mode,
			"template_id": restored.template_id,
			"stamina": restored.exploration.stamina,
			"stamina_max": ExplorationState.STAMINA_MAX,
		}


func _show_dialogue(speaker: String, text: String, duration: float = 5.5) -> void:
	dialogue_speaker = speaker
	active_dialogue = text
	dialogue_timer = duration


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
	for _i in range(36):
		motes.append({"x": rng.randf_range(120.0, 980.0), "y": rng.randf_range(40.0, 660.0), "vy": rng.randf_range(-12.0, -4.0), "vx": rng.randf_range(4.0, 12.0), "r": rng.randf_range(1.1, 2.6), "phase": rng.randf_range(0.0, TAU), "cyan": rng.randf() < 0.22})


func _process(delta: float) -> void:
	elapsed += delta
	var target_glow := 1.0 if hover_expedition else 0.0
	expedition_glow = lerpf(expedition_glow, target_glow, minf(1.0, delta * 10.0))
	var target_fade := 1.0 if map_selector_open else 0.0
	selector_fade = lerpf(selector_fade, target_fade, minf(1.0, delta * 14.0))
	parallax_smooth = parallax_smooth.lerp(mouse_norm, minf(1.0, delta * 3.5))
	if dialogue_timer > 0.0:
		dialogue_timer = maxf(0.0, dialogue_timer - delta)
	for m in motes:
		m["x"] = fposmod(float(m["x"]) + float(m["vx"]) * delta + sin(elapsed * 0.6 + float(m["phase"])) * 3.0 * delta, maxf(1.0, size.x))
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
	return Rect2(26.0 * _sx(), 22.0 * _sy(), 108.0 * _sx(), 34.0 * _sy())


func expedition_button_rect() -> Rect2:
	return Rect2(928.0 * _sx(), 580.0 * _sy(), 316.0 * _sx(), 102.0 * _sy())


## Interactive Atelier hotspots aligned with lobby_atelier_bg.png.
func sevrin_hotspot_rect() -> Rect2:
	return Rect2(490.0 * _sx(), 230.0 * _sy(), 240.0 * _sx(), 440.0 * _sy())


func table_map_hotspot_rect() -> Rect2:
	return Rect2(240.0 * _sx(), 450.0 * _sy(), 260.0 * _sx(), 165.0 * _sy())


func gear_hotspot_rect() -> Rect2:
	return Rect2(760.0 * _sx(), 340.0 * _sy(), 170.0 * _sx(), 290.0 * _sy())


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


func spring_normal_button_rect() -> Rect2:
	var r := map_card_rect(1)
	var sx := _sx()
	var sy := _sy()
	var w := (r.size.x - 50.0 * sx) * 0.5
	return Rect2(r.position.x + 20.0 * sx, r.end.y - 64.0 * sy, w, 44.0 * sy)


func spring_hard_button_rect() -> Rect2:
	var r := map_card_rect(1)
	var sx := _sx()
	var sy := _sy()
	var w := (r.size.x - 50.0 * sx) * 0.5
	return Rect2(r.position.x + 30.0 * sx + w, r.end.y - 64.0 * sy, w, 44.0 * sy)


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


func activate_map(index: int, hard_mode: bool = false) -> bool:
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
	if str(entry.get("id", "")) == "spring":
		if hard_mode:
			SpringBattleBridge.requested_mode = "hard"
		elif not bool(spring_resume_info.get("active", false)):
			SpringBattleBridge.requested_mode = "normal"
		else:
			SpringBattleBridge.requested_mode = ""
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
		mouse_norm = Vector2(
			clampf((pos.x / maxf(1.0, size.x) - 0.5) * 2.0, -1.0, 1.0),
			clampf((pos.y / maxf(1.0, size.y) - 0.5) * 2.0, -1.0, 1.0)
		)
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
			hover_expedition = expedition_button_rect().has_point(pos)
			hover_back = back_button_rect().has_point(pos)
			hovered_hotspot = ""
			if not hover_expedition and not hover_back:
				if table_map_hotspot_rect().has_point(pos):
					hovered_hotspot = "map"
				elif sevrin_hotspot_rect().has_point(pos):
					hovered_hotspot = "sevrin"
				elif gear_hotspot_rect().has_point(pos):
					hovered_hotspot = "gear"
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
				if i == 1 and spring_hard_button_rect().has_point(pos):
					activate_map(1, true)
				else:
					activate_map(i, false)
				return
		return

	if expedition_button_rect().has_point(pos):
		open_map_selector()
		return
	if back_button_rect().has_point(pos):
		return_to_title()
		return
	if table_map_hotspot_rect().has_point(pos):
		open_map_selector()
		return
	if sevrin_hotspot_rect().has_point(pos):
		camp_line_index = (camp_line_index + 1) % SEVRIN_LINES.size()
		_show_dialogue("瑟弗林", SEVRIN_LINES[camp_line_index], 6.0)
		queue_redraw()
		return
	if gear_hotspot_rect().has_point(pos):
		gear_line_index = (gear_line_index + 1) % GEAR_LINES.size()
		_show_dialogue("工坊见闻", GEAR_LINES[gear_line_index], 5.0)
		queue_redraw()
		return
	if dialogue_timer > 0.0:
		dialogue_timer = 0.0
		queue_redraw()


# --- rendering ---------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var sx := _sx()
	var sy := _sy()

	_draw_atelier_scene(sx, sy)
	_draw_hotspots(font, sx, sy)
	_draw_minimal_hud(font, sx, sy)
	_draw_dialogue_ribbon(font, sx, sy)
	_draw_expedition_button(font, sx, sy)
	if map_selector_open or selector_fade > 0.02:
		_draw_map_selector(font, sx, sy, maxf(selector_fade, 1.0 if map_selector_open else 0.0))


func _draw_atelier_scene(sx: float, sy: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#141218"), true)
	if background != null:
		var tex_sz := background.get_size()
		var breath: float = 1.03 + 0.008 * sin(elapsed * 0.55)
		var scale_f := maxf(size.x / maxf(1.0, tex_sz.x), size.y / maxf(1.0, tex_sz.y)) * breath
		var drawn := tex_sz * scale_f
		var pan := Vector2(-parallax_smooth.x * 10.0 * sx, -parallax_smooth.y * 6.0 * sy)
		var offset := (size - drawn) * 0.5 + pan
		draw_texture_rect(background, Rect2(offset, drawn), false)

	# Soft breathing sunset god-rays streaming from the arched stone windows
	var ray_a: float = 0.045 + 0.025 * sin(elapsed * 1.1)
	var ray_col := Color(1.0, 0.84, 0.54, ray_a)
	var ray_end := Color(1.0, 0.84, 0.54, 0.0)
	draw_polygon(
		PackedVector2Array([Vector2(260.0 * sx, 90.0 * sy), Vector2(460.0 * sx, 60.0 * sy), Vector2(880.0 * sx, 560.0 * sy), Vector2(540.0 * sx, 640.0 * sy)]),
		PackedColorArray([ray_col, ray_col, ray_end, ray_end])
	)

	# Warm lantern & potion subtle breathing glow
	var lamp_p: float = 0.5 + 0.5 * sin(elapsed * 2.4)
	draw_circle(Vector2(445.0 * sx, 442.0 * sy), (28.0 + lamp_p * 6.0) * sy, Color(1.0, 0.80, 0.36, 0.09 + 0.05 * lamp_p))
	draw_circle(Vector2(150.0 * sx, 515.0 * sy), (22.0 + lamp_p * 4.0) * sy, Color(0.32, 0.90, 0.96, 0.08 + 0.04 * lamp_p))

	# Gentle drifting sunlit dust motes
	for m in motes:
		var tw: float = 0.35 + 0.65 * sin(elapsed * 1.9 + float(m["phase"]))
		var col := Color(0.58, 0.90, 0.98, 0.42 * tw) if bool(m["cyan"]) else Color(1.0, 0.86, 0.52, 0.55 * tw)
		draw_circle(Vector2(float(m["x"]), float(m["y"])), float(m["r"]), col)

	# Very subtle corner edge framing (keeps the sunlit atelier warm & unobstructed)
	draw_polygon(
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(size.x, 0.0), Vector2(size.x, 96.0 * sy), Vector2(0.0, 96.0 * sy)]),
		PackedColorArray([Color(0.04, 0.04, 0.06, 0.46), Color(0.04, 0.04, 0.06, 0.46), Color(0.04, 0.04, 0.06, 0.0), Color(0.04, 0.04, 0.06, 0.0)])
	)


func _draw_hotspots(font: Font, sx: float, sy: float) -> void:
	if map_selector_open:
		return
	var pulse: float = 0.5 + 0.5 * sin(elapsed * 3.0)
	var spots := [
		{"id": "map", "pos": Vector2(368.0 * sx, 520.0 * sy), "label": "查看地图"},
		{"id": "sevrin", "pos": Vector2(605.0 * sx, 258.0 * sy), "label": "与瑟弗林交谈"},
		{"id": "gear", "pos": Vector2(842.0 * sx, 430.0 * sy), "label": "检视战备"},
	]
	for spot in spots:
		var is_h: bool = (hovered_hotspot == str(spot["id"]))
		var p: Vector2 = spot["pos"]
		var r: float = (8.0 if is_h else 5.5 + pulse * 1.5) * sy
		var col := Color(1.0, 0.92, 0.70, 0.95) if is_h else Color(0.95, 0.80, 0.48, 0.55 + 0.25 * pulse)
		var diamond := PackedVector2Array([p + Vector2(0.0, -r), p + Vector2(r, 0.0), p + Vector2(0.0, r), p + Vector2(-r, 0.0)])
		draw_colored_polygon(diamond, Color(col.r, col.g, col.b, 0.28 if not is_h else 0.60))
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), col, 1.6, true)
		if is_h:
			var lbl: String = str(spot["label"])
			var sz := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.5 * sy))
			var box := Rect2(p.x - sz.x * 0.5 - 12.0 * sx, p.y - 38.0 * sy, sz.x + 24.0 * sx, 24.0 * sy)
			draw_rect(box, Color(0.09, 0.08, 0.10, 0.86), true)
			draw_rect(box, col, false, 1.2)
			draw_string(font, box.position + Vector2(12.0 * sx, 16.5 * sy), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.5 * sy), Color("#fbf2df"))


func _draw_minimal_hud(font: Font, sx: float, sy: float) -> void:
	var back_r := back_button_rect()
	draw_rect(back_r, Color(0.16, 0.14, 0.16, 0.82) if hover_back else Color(0.09, 0.09, 0.12, 0.65), true)
	draw_rect(back_r, Color("#e4c583") if hover_back else Color(0.84, 0.72, 0.48, 0.40), false, 1.2)
	draw_string(font, back_r.position + Vector2(14.0 * sx, 22.0 * sy), "← 返回标题", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(13.0 * sy), Color("#efe6d6"))

	# Atelier-style light title crest (no heavy dark bar)
	draw_string(font, Vector2(152.0 * sx, 40.0 * sy), "黄昏工坊  ·  ECHO ATELIER", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20.0 * sy), Color("#f8ebd2"))
	draw_line(Vector2(152.0 * sx, 48.0 * sy), Vector2(408.0 * sx, 48.0 * sy), Color(0.90, 0.76, 0.48, 0.50), 1.2)
	draw_string(font, Vector2(152.0 * sx, 65.0 * sy), "点击工坊内物品或右下角「选择地图」启程", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.0 * sy), Color(0.86, 0.83, 0.78, 0.82))

	# Top-right subtle translucent status pill
	var pill := Rect2(936.0 * sx, 22.0 * sy, 316.0 * sx, 36.0 * sy)
	var has_resume := bool(spring_resume_info.get("active", false))
	draw_rect(pill, Color(0.10, 0.16, 0.20, 0.78) if has_resume else Color(0.09, 0.09, 0.12, 0.64), true)
	draw_rect(pill, Color("#8fc7dc") if has_resume else Color(0.84, 0.72, 0.48, 0.35), false, 1.2)
	var mode_tag := "困难定轨" if bool(spring_resume_info.get("hard_mode", false)) else "普通"
	var pill_text := "未尽之春（%s）· 体力 %d/%d" % [mode_tag, int(spring_resume_info.get("stamina", 0)), int(spring_resume_info.get("stamina_max", 10))] if has_resume else "黄昏时分  ·  营地待机中"
	draw_string(font, pill.position + Vector2(16.0 * sx, 23.0 * sy), pill_text, HORIZONTAL_ALIGNMENT_LEFT, pill.size.x - 24.0 * sx, roundi(12.5 * sy), Color("#dcf4fc") if has_resume else Color("#dfd6c6"))


func _draw_dialogue_ribbon(font: Font, sx: float, sy: float) -> void:
	if map_selector_open or dialogue_timer <= 0.0 or active_dialogue.is_empty():
		return
	var fade: float = minf(1.0, dialogue_timer * 1.4)
	var box := Rect2(32.0 * sx, 608.0 * sy, 680.0 * sx, 74.0 * sy)
	draw_rect(box, Color(0.07, 0.07, 0.10, 0.76 * fade), true)
	draw_rect(Rect2(box.position, Vector2(4.0 * sx, box.size.y)), Color(0.90, 0.76, 0.48, 0.92 * fade), true)
	draw_rect(box, Color(0.88, 0.76, 0.50, 0.30 * fade), false, 1.0)
	draw_string(font, box.position + Vector2(18.0 * sx, 24.0 * sy), dialogue_speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.0 * sy), Color(0.95, 0.84, 0.58, fade))
	draw_string(font, box.position + Vector2(18.0 * sx, 52.0 * sy), active_dialogue, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 32.0 * sx, roundi(13.0 * sy), Color(0.92, 0.90, 0.86, fade))


func _draw_expedition_button(font: Font, sx: float, sy: float) -> void:
	var btn := expedition_button_rect()
	var pulse: float = 0.5 + 0.5 * sin(elapsed * 2.6)
	var bg := Color(0.18, 0.14, 0.11, 0.88).lerp(Color(0.30, 0.23, 0.15, 0.96), expedition_glow)
	var border := Color("#c9a55b").lerp(Color("#f8e2a6"), maxf(expedition_glow, pulse * 0.38))

	draw_rect(btn.grow(4.0 * sx), Color(0.95, 0.78, 0.42, 0.10 + 0.14 * expedition_glow), true)
	draw_rect(btn, bg, true)
	draw_rect(Rect2(btn.position, Vector2(6.0 * sx, btn.size.y)), border, true)
	draw_rect(btn, border, false, 1.8)

	var shift_x: float = 6.0 * sx * expedition_glow
	draw_string(font, btn.position + Vector2(26.0 * sx + shift_x, 45.0 * sy), "选择地图", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(27.0 * sy), Color("#fff5e2"))
	draw_string(font, btn.position + Vector2(26.0 * sx + shift_x, 70.0 * sy), "DEPART  ·  开启远征探索", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), Color("#e8d4a8"))
	draw_string(font, btn.position + Vector2(26.0 * sx + shift_x, 90.0 * sy), "教学遗迹 / 未尽之春  [Enter]", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.0 * sy), Color("#c2bcb0"))
	draw_string(font, btn.position + Vector2(btn.size.x - 40.0 * sx + shift_x * 0.5, 60.0 * sy), "▸", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(26.0 * sy), border)

	if bool(spring_resume_info.get("active", false)):
		var badge := Rect2(btn.end.x - 78.0 * sx, btn.position.y - 14.0 * sy, 74.0 * sx, 24.0 * sy)
		draw_rect(badge, Color("#244656"), true)
		draw_rect(badge, Color("#8fc7dc"), false, 1.2)
		draw_string(font, badge.position + Vector2(12.0 * sx, 16.0 * sy), "可续行", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color("#e4f9ff"))


func _draw_map_selector(font: Font, sx: float, sy: float, alpha: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.78 * alpha), true)
	var panel := selector_panel_rect()
	draw_rect(panel, Color(0.10, 0.11, 0.15, 0.96 * alpha), true)
	draw_rect(panel, Color(0.86, 0.73, 0.48, 0.68 * alpha), false, 1.8)

	draw_string(font, panel.position + Vector2(36.0 * sx, 44.0 * sy), "选择出征地图", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24.0 * sy), Color(0.96, 0.91, 0.80, alpha))
	draw_string(font, panel.position + Vector2(36.0 * sx, 68.0 * sy), "SELECT REGION  ·  点击卡片或按 Enter 出发，Esc 返回工坊", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), Color(0.66, 0.68, 0.73, alpha))

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

	var is_spring := (str(entry["id"]) == "spring")
	var is_spring_resume := (is_spring and bool(spring_resume_info.get("active", false)))
	if is_spring_resume:
		var tag_r := Rect2(r.position.x + 20.0 * sx, r.end.y - 108.0 * sy, r.size.x - 40.0 * sx, 28.0 * sy)
		draw_rect(tag_r, Color(0.13, 0.25, 0.32, 0.9 * alpha), true)
		draw_rect(tag_r, Color(0.56, 0.78, 0.86, 0.8 * alpha), false, 1.0)
		var mode_tag := "困难定轨" if bool(spring_resume_info.get("hard_mode", false)) else "普通"
		draw_string(font, tag_r.position + Vector2(12.0 * sx, 19.0 * sy), "进行中（%s）· 体力 %d/%d" % [mode_tag, int(spring_resume_info.get("stamina", 0)), int(spring_resume_info.get("stamina_max", 10))], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color(0.88, 0.97, 1.0, alpha))
	elif is_spring:
		draw_string(font, Vector2(r.position.x + 20.0 * sx, r.end.y - 84.0 * sy), "困难定轨：长按一笔画路线必达首领", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36.0 * sx, roundi(11.5 * sy), Color(0.95, 0.62, 0.56, alpha))

	if is_spring:
		var left_r := spring_normal_button_rect()
		var right_r := spring_hard_button_rect()
		draw_rect(left_r, Color(0.24, 0.22, 0.24, 0.92 * alpha), true)
		draw_rect(left_r, border_col, false, 1.4)
		draw_string(font, left_r.position + Vector2(0.0, 28.0 * sy), "继续探索" if is_spring_resume else "普通探索", HORIZONTAL_ALIGNMENT_CENTER, left_r.size.x, roundi(14.0 * sy), Color(0.98, 0.95, 0.88, alpha))
		draw_rect(right_r, Color(0.38, 0.14, 0.15, 0.96 * alpha), true)
		draw_rect(right_r, Color(0.90, 0.44, 0.42, 0.95 * alpha), false, 1.6)
		draw_string(font, right_r.position + Vector2(0.0, 28.0 * sy), "困难 · 定轨", HORIZONTAL_ALIGNMENT_CENTER, right_r.size.x, roundi(14.0 * sy), Color(1.0, 0.90, 0.86, alpha))
		return

	var cta_r := Rect2(r.position.x + 20.0 * sx, r.end.y - 64.0 * sy, r.size.x - 40.0 * sx, 44.0 * sy)
	var cta_bg := Color(0.18, 0.19, 0.22, 0.75 * alpha) if locked else (Color(accent.r * 0.42, accent.g * 0.38, accent.b * 0.30, 0.95 * alpha) if selected else Color(0.18, 0.20, 0.24, 0.90 * alpha))
	draw_rect(cta_r, cta_bg, true)
	draw_rect(cta_r, border_col, false, 1.4)
	draw_string(font, cta_r.position + Vector2(0.0, 28.0 * sy), str(entry["cta"]), HORIZONTAL_ALIGNMENT_CENTER, cta_r.size.x, roundi(15.0 * sy), Color(0.55, 0.56, 0.60, alpha) if locked else Color(0.98, 0.95, 0.88, alpha))
