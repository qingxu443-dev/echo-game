extends Control


const MENU_SCENE_PATH := "res://scenes/menu/main_menu.tscn"
const BATTLE_SCENE_PATH := "res://scenes/main/main.tscn"
const SPRING_SCENE_PATH := "res://scenes/spring/spring_map.tscn"
const BACKGROUND_PATH := "res://assets/ui/lobby_atelier_bg.png"
const AtelierStashScript = preload("res://scripts/meta/atelier_stash.gd")
const AtelierPrepOverlayScript = preload("res://scripts/ui/atelier_prep_overlay.gd")
const RosterOverlayScript = preload("res://scripts/ui/roster_manager_overlay.gd")

const MAP_ENTRIES: Array[Dictionary] = [
	{
		"id": "tutorial", "chapter": "CHAPTER 01", "chapter_zh": "章节 1", "tag": "序章 · 3 关教学", "title": "遗迹教学", "subtitle": "出战角色：瑟弗林（守誓者）",
		"desc_lines": ["2.5D 战棋基础演练（每回合 3 AP）", "击退破招 · AP 充能 · 遗迹宝箱"],
		"cta": "进入章节 1", "scene_path": BATTLE_SCENE_PATH, "accent": Color("#d4b77b"), "locked": false,
	},
	{
		"id": "spring", "chapter": "CHAPTER 02", "chapter_zh": "章节 2", "tag": "赛季大地图 · 5×5", "title": "春之境 · 未尽之春", "subtitle": "出战角色：樱（花之誓）",
		"desc_lines": ["5×5 探索 · 十段奇遇 · 春日行商", "精英专属技 · 首领千枝神将"],
		"cta": "进入章节 2", "scene_path": SPRING_SCENE_PATH, "accent": Color("#e89ab0"), "locked": false,
	},
	{
		"id": "upcoming", "chapter": "CHAPTER 03", "chapter_zh": "章节 3", "tag": "COMING SOON", "title": "未竟之域 · 筹备中", "subtitle": "后续章节与多角色拓展",
		"desc_lines": ["新区域与同行同伴开发中", "敬请期待后续版本开放"],
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
var chapter_portraits: Dictionary = {}
var elapsed: float = 0.0
var motes: Array[Dictionary] = []
var mouse_norm: Vector2 = Vector2.ZERO
var parallax_smooth: Vector2 = Vector2.ZERO

var map_selector_open: bool = false
var prep_open: bool = false
var atelier_state: Dictionary = {}
var prep_notice: String = ""
var mouse_pos: Vector2 = Vector2.ZERO
var selected_map_index: int = 0
var hovered_map_index: int = -1
var hovered_nav_btn: String = ""
var hover_expedition: bool = false
var hover_prep: bool = false
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
var roster_overlay: Control
var hover_roster: bool = false
var hover_squads: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	background = _load_texture(BACKGROUND_PATH)
	roster_overlay = RosterOverlayScript.new()
	add_child(roster_overlay)
	chapter_portraits["tutorial"] = _load_texture("res://assets/actors/portraits/sevrin.png")
	chapter_portraits["spring"] = _load_texture("res://assets/actors/portraits/sakura.png")
	_init_motes()
	refresh_save_summary()
	_show_dialogue("瑟弗林", SEVRIN_LINES[0], 6.0)
	queue_redraw()

func refresh_save_summary() -> void:
	spring_resume_info.clear()
	if not SpringSaveTransaction.recover(SpringRun.SAVE_PATH, AtelierStash.SAVE_PATH):
		status_notice = "出征存档尚未恢复，请检查存储后重试。"
		return
	atelier_state = AtelierStashScript.load_state()
	var restored := SpringRun.load_from_file(SpringRun.SAVE_PATH)
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

func _sx() -> float: return maxf(1.0, size.x) / 1280.0
func _sy() -> float: return maxf(1.0, size.y) / 720.0
func back_button_rect() -> Rect2: return Rect2(26.0 * _sx(), 22.0 * _sy(), 108.0 * _sx(), 34.0 * _sy())
func prep_button_rect() -> Rect2: return Rect2(744.0 * _sx(), 580.0 * _sy(), 168.0 * _sx(), 102.0 * _sy())
func expedition_button_rect() -> Rect2: return Rect2(928.0 * _sx(), 580.0 * _sy(), 316.0 * _sx(), 102.0 * _sy())
func roster_button_rect() -> Rect2: return Rect2(936.0 * _sx(), 68.0 * _sy(), 150.0 * _sx(), 38.0 * _sy())
func squads_button_rect() -> Rect2: return Rect2(1096.0 * _sx(), 68.0 * _sy(), 156.0 * _sx(), 38.0 * _sy())
func sevrin_hotspot_rect() -> Rect2: return Rect2(490.0 * _sx(), 230.0 * _sy(), 240.0 * _sx(), 440.0 * _sy())
func table_map_hotspot_rect() -> Rect2: return Rect2(240.0 * _sx(), 450.0 * _sy(), 260.0 * _sx(), 165.0 * _sy())
func gear_hotspot_rect() -> Rect2: return Rect2(760.0 * _sx(), 340.0 * _sy(), 170.0 * _sx(), 290.0 * _sy())
func selector_panel_rect() -> Rect2: return Rect2(Vector2.ZERO, size)
func close_selector_rect() -> Rect2: return Rect2(44.0 * _sx(), 36.0 * _sy(), 116.0 * _sx(), 50.0 * _sy())
func home_selector_rect() -> Rect2: return Rect2(160.0 * _sx(), 36.0 * _sy(), 116.0 * _sx(), 50.0 * _sy())

func map_card_rect(index: int) -> Rect2:
	var card_w: float = 346.0 * _sx()
	var gap: float = 76.0 * _sx()
	var total_w: float = card_w * float(MAP_ENTRIES.size()) + gap * float(MAP_ENTRIES.size() - 1)
	return Rect2((size.x - total_w) * 0.5 + float(index) * (card_w + gap), 216.0 * _sy(), card_w, 356.0 * _sy())

func spring_normal_button_rect() -> Rect2:
	var r := map_card_rect(1)
	var sx := _sx()
	return Rect2(r.position.x + 20.0 * sx, r.end.y - 64.0 * _sy(), (r.size.x - 50.0 * sx) * 0.5, 44.0 * _sy())

func spring_hard_button_rect() -> Rect2:
	var r := map_card_rect(1)
	var sx := _sx()
	var w := (r.size.x - 50.0 * sx) * 0.5
	return Rect2(r.position.x + 30.0 * sx + w, r.end.y - 64.0 * _sy(), w, 44.0 * _sy())


# --- public state helpers ----------------------------------------------------

func open_map_selector() -> void:
	status_notice = ""
	refresh_save_summary()
	map_selector_open = true
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
	if SpringSaveTransaction.is_pending(AtelierStash.SAVE_PATH):
		status_notice = "出征存档尚未恢复，请重新打开地图选择。"
		queue_redraw()
		return false
	var tree := get_tree()
	if tree == null:
		return true
	var error := SceneTravel.change(tree, target_path, str(entry.get("title", "踏入遗迹")))
	if error != OK:
		status_notice = "目标地图场景无法打开。"
		queue_redraw()
		return false
	# Godot adds the destination scene at the end of the frame.
	if str(entry.get("id", "")) == "spring":
		if hard_mode:
			SpringBattleBridge.requested_mode = "hard"
		elif not bool(spring_resume_info.get("active", false)):
			SpringBattleBridge.requested_mode = "normal"
		else:
			SpringBattleBridge.requested_mode = ""
	else:
		SpringBattleBridge.tutorial_loadout_requested = true
	return true


func return_to_title() -> bool:
	var tree := get_tree()
	if tree == null:
		return true
	var error := SceneTravel.change(tree, MENU_SCENE_PATH)
	if error != OK:
		push_error("Lobby: unable to return to title. Error: %s" % error)
		return false
	return true


# --- input -------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if roster_overlay != null and roster_overlay.visible:
		if event.keycode == KEY_ESCAPE:
			roster_overlay.hide()
			get_viewport().set_input_as_handled()
		return
	if prep_open:
		if event.keycode == KEY_ESCAPE:
			prep_open = false; queue_redraw(); get_viewport().set_input_as_handled()
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
		mouse_pos = pos
		mouse_norm = Vector2(clampf((pos.x / maxf(1.0, size.x) - 0.5) * 2.0, -1.0, 1.0), clampf((pos.y / maxf(1.0, size.y) - 0.5) * 2.0, -1.0, 1.0))
		if prep_open:
			queue_redraw()
		elif map_selector_open:
			var next_nav := "back" if close_selector_rect().has_point(pos) else ("home" if home_selector_rect().has_point(pos) else "")
			var next_hover := -1
			for i in range(MAP_ENTRIES.size()):
				if map_card_rect(i).has_point(pos):
					next_hover = i; selected_map_index = i; break
			if next_hover != hovered_map_index or next_nav != hovered_nav_btn:
				hovered_map_index = next_hover; hovered_nav_btn = next_nav; queue_redraw()
		else:
			hover_roster = roster_button_rect().has_point(pos)
			hover_squads = squads_button_rect().has_point(pos)
			hover_expedition = expedition_button_rect().has_point(pos)
			hover_prep = prep_button_rect().has_point(pos)
			hover_back = back_button_rect().has_point(pos)
			hovered_hotspot = ""
			if not hover_expedition and not hover_prep and not hover_back:
				hovered_hotspot = "map" if table_map_hotspot_rect().has_point(pos) else ("sevrin" if sevrin_hotspot_rect().has_point(pos) else ("gear" if gear_hotspot_rect().has_point(pos) else ""))
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(event.position)
		accept_event()

func _handle_click(pos: Vector2) -> void:
	if roster_overlay != null and roster_overlay.visible:
		return
	if roster_button_rect().has_point(pos):
		roster_overlay.open_characters(); return
	if squads_button_rect().has_point(pos):
		roster_overlay.open_squads(); return
	if prep_open:
		var res := AtelierPrepOverlayScript.handle_click(size, pos, atelier_state)
		if bool(res.get("close", false)): prep_open = false
		else: prep_notice = str(res.get("message", ""))
		queue_redraw(); return
	if map_selector_open:
		if close_selector_rect().has_point(pos) or home_selector_rect().has_point(pos):
			close_map_selector(); return
		for i in range(MAP_ENTRIES.size()):
			if map_card_rect(i).has_point(pos):
				activate_map(i, i == 1 and spring_hard_button_rect().has_point(pos)); return
		return
	if expedition_button_rect().has_point(pos) or table_map_hotspot_rect().has_point(pos):
		open_map_selector(); return
	if prep_button_rect().has_point(pos) or gear_hotspot_rect().has_point(pos):
		atelier_state = AtelierStashScript.load_state(); prep_notice = ""; prep_open = true; queue_redraw(); return
	if back_button_rect().has_point(pos):
		return_to_title(); return
	if sevrin_hotspot_rect().has_point(pos):
		camp_line_index = (camp_line_index + 1) % SEVRIN_LINES.size()
		_show_dialogue("瑟弗林", SEVRIN_LINES[camp_line_index], 6.0); queue_redraw(); return
	if dialogue_timer > 0.0:
		dialogue_timer = 0.0; queue_redraw()


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
	if prep_open:
		AtelierPrepOverlayScript.draw(self, font, size, atelier_state, prep_notice, mouse_pos)
	elif map_selector_open or selector_fade > 0.02:
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

	# Secondary character-management shortcuts sit below the status pill.
	var roster_r := roster_button_rect()
	var squad_r := squads_button_rect()
	var compact_labels := size.x < 700.0
	var entries := [
		{"rect": roster_r, "label": "角色" if compact_labels else "角色总览", "hover": hover_roster},
		{"rect": squad_r, "label": "编队" if compact_labels else "队伍编成", "hover": hover_squads},
	]
	for entry in entries:
		var rect: Rect2 = entry["rect"]
		var hovered: bool = bool(entry["hover"])
		var border := Color("#8fc7dc") if hovered else Color(0.72, 0.78, 0.82, 0.48)
		draw_rect(rect, Color(0.08, 0.12, 0.16, 0.88) if hovered else Color(0.07, 0.09, 0.12, 0.74), true)
		draw_rect(rect, border, false, 1.2)
		var label_width := font.get_string_size(str(entry["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy)).x
		draw_string(font, Vector2(rect.get_center().x - label_width * 0.5, rect.position.y + rect.size.y * 0.62), str(entry["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), Color("#e5f4fa") if hovered else Color("#d9d4ca"))


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
	# Atelier Prep button sitting cleanly to the left of Select Map
	var pr := prep_button_rect()
	var pb := Color(0.14, 0.17, 0.22, 0.94) if hover_prep else Color(0.10, 0.11, 0.15, 0.86)
	var pborder := Color("#74ebd5") if hover_prep else Color(0.56, 0.78, 0.86, 0.65)
	draw_rect(pr, pb, true); draw_rect(Rect2(pr.position, Vector2(5.0 * sx, pr.size.y)), pborder, true); draw_rect(pr, pborder, false, 1.6)
	var packed_n: int = (atelier_state.get("loadout", []) as Array).size()
	draw_string(font, pr.position + Vector2(18.0 * sx, 42.0 * sy), "补给商店", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(21.0 * sy), Color("#ecfaf7"))
	draw_string(font, pr.position + Vector2(18.0 * sx, 68.0 * sy), "随行 %d 件" % packed_n, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.5 * sy), Color("#9be3d5"))
	draw_string(font, pr.position + Vector2(18.0 * sx, 88.0 * sy), "残晶 %d" % int(atelier_state.get("shards", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color("#e6d19a"))

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
	# Full-screen chapter roadmap backdrop
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.09, 0.92 * alpha), true)
	for gx in range(1, 10):
		draw_line(Vector2(float(gx) * 128.0 * sx, 0.0), Vector2(float(gx) * 128.0 * sx, size.y), Color(0.75, 0.68, 0.52, 0.035 * alpha), 1.0)
	draw_line(Vector2(0.0, 394.0 * sy), Vector2(size.x, 394.0 * sy), Color(0.84, 0.72, 0.48, 0.08 * alpha), 1.0)

	# Top-left paired navigation bar: [ ← | ⌂ ]
	var back_r := close_selector_rect()
	var home_r := home_selector_rect()
	var nav_r := Rect2(back_r.position, Vector2(back_r.size.x + home_r.size.x, back_r.size.y))
	draw_rect(nav_r, Color(0.11, 0.12, 0.16, 0.95 * alpha), true)
	if hovered_nav_btn == "back":
		draw_rect(back_r, Color(0.24, 0.22, 0.18, 0.90 * alpha), true)
	elif hovered_nav_btn == "home":
		draw_rect(home_r, Color(0.24, 0.22, 0.18, 0.90 * alpha), true)
	draw_rect(nav_r, Color(0.86, 0.73, 0.48, 0.78 * alpha), false, 1.8)
	draw_line(Vector2(home_r.position.x, nav_r.position.y + 6.0 * sy), Vector2(home_r.position.x, nav_r.end.y - 6.0 * sy), Color(0.86, 0.73, 0.48, 0.55 * alpha), 1.5)
	var bc := Color(1.0, 0.94, 0.80, alpha) if hovered_nav_btn == "back" else Color(0.90, 0.86, 0.78, alpha)
	var hc := Color(1.0, 0.94, 0.80, alpha) if hovered_nav_btn == "home" else Color(0.90, 0.86, 0.78, alpha)
	var ba := back_r.get_center()
	draw_line(ba + Vector2(14.0 * sx, 0.0), ba + Vector2(-14.0 * sx, 0.0), bc, 2.2, true)
	draw_polyline(PackedVector2Array([ba + Vector2(-4.0 * sx, -9.0 * sy), ba + Vector2(-14.0 * sx, 0.0), ba + Vector2(-4.0 * sx, 9.0 * sy)]), bc, 2.2, true)
	var hm := home_r.get_center()
	draw_polyline(PackedVector2Array([hm + Vector2(-13.0 * sx, -1.0 * sy), hm + Vector2(0.0, -12.0 * sy), hm + Vector2(13.0 * sx, -1.0 * sy)]), hc, 2.2, true)
	draw_rect(Rect2(hm + Vector2(-9.0 * sx, -1.0 * sy), Vector2(18.0 * sx, 13.0 * sy)), hc, false, 2.0)
	draw_rect(Rect2(hm + Vector2(-3.0 * sx, 4.0 * sy), Vector2(6.0 * sx, 8.0 * sy)), hc, false, 1.6)

	draw_string(font, Vector2(nav_r.end.x + 28.0 * sx, 62.0 * sy), "章节选择", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24.0 * sy), Color(0.97, 0.93, 0.84, alpha))
	draw_string(font, Vector2(nav_r.end.x + 28.0 * sx, 83.0 * sy), "CHAPTER ROADMAP  ·  方向键或点击选择章节，Esc 返回大厅", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color(0.64, 0.66, 0.72, alpha))

	# Horizontal connectors linking Chapter 1 -- Chapter 2 -- Chapter 3
	for i in range(MAP_ENTRIES.size() - 1):
		var left_c := map_card_rect(i)
		var right_c := map_card_rect(i + 1)
		var y_mid: float = left_c.get_center().y
		var p0 := Vector2(left_c.end.x, y_mid)
		var p1 := Vector2(right_c.position.x, y_mid)
		var next_locked := bool(MAP_ENTRIES[i + 1].get("locked", false))
		var line_col := Color(0.42, 0.45, 0.52, 0.55 * alpha) if next_locked else Color(0.88, 0.75, 0.48, 0.85 * alpha)
		if next_locked:
			draw_dashed_line(p0 + Vector2(8.0 * sx, 0.0), p1 - Vector2(8.0 * sx, 0.0), line_col, 2.2, 7.0 * sx)
		else:
			draw_line(p0, p1, Color(line_col.r, line_col.g, line_col.b, 0.25 * alpha), 6.0, true)
			draw_line(p0, p1, line_col, 2.4, true)
			var t := fposmod(elapsed * 0.45, 1.0)
			draw_circle(p0.lerp(p1, t), 3.6 * sy, Color(1.0, 0.94, 0.76, 0.92 * alpha))
		for pt in [p0, p1]:
			var d := 5.0 * sy
			draw_colored_polygon(PackedVector2Array([pt + Vector2(0.0, -d), pt + Vector2(d, 0.0), pt + Vector2(0.0, d), pt + Vector2(-d, 0.0)]), line_col)

	for i in range(MAP_ENTRIES.size()):
		_draw_map_card(font, i, sx, sy, alpha)

	var footer_text := status_notice if not status_notice.is_empty() else "提示：章节 1 为瑟弗林教学遗迹，章节 2 为樱「春之境」大地图探索，各自独立记录。"
	var footer_col := Color("#e4b092") if not status_notice.is_empty() else Color("#9b9a94")
	draw_string(font, Vector2(44.0 * sx, size.y - 32.0 * sy), footer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.5 * sy), Color(footer_col.r, footer_col.g, footer_col.b, alpha))


func _draw_map_card(font: Font, index: int, sx: float, sy: float, alpha: float) -> void:
	var entry: Dictionary = MAP_ENTRIES[index]
	var r := map_card_rect(index)
	var selected := (index == selected_map_index)
	var locked := bool(entry.get("locked", false))
	var accent: Color = entry.get("accent", Color("#d4b77b"))
	var bg := Color(0.09, 0.10, 0.13, 0.88 * alpha) if locked else (Color(0.14, 0.16, 0.21, 0.96 * alpha) if selected else Color(0.11, 0.12, 0.17, 0.92 * alpha))
	var border_col := Color(accent.r, accent.g, accent.b, (0.98 if selected else 0.45) * alpha)
	if selected and not locked:
		draw_rect(r.grow(5.0 * sx), Color(accent.r, accent.g, accent.b, 0.12 * alpha), true)
	draw_rect(r, bg, true)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 7.0 * sy)), Color(accent.r, accent.g, accent.b, (0.96 if selected else 0.58) * alpha), true)
	draw_rect(r, border_col, false, 2.4 if selected else 1.4)

	# Chapter number header + optional hero portrait badge on top-right
	draw_string(font, r.position + Vector2(22.0 * sx, 34.0 * sy), str(entry["chapter"]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), Color(accent.r, accent.g, accent.b, alpha))
	draw_string(font, r.position + Vector2(22.0 * sx, 74.0 * sy), str(entry["chapter_zh"]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(30.0 * sy), Color(0.98, 0.95, 0.88, (0.48 if locked else 1.0) * alpha))
	draw_string(font, r.position + Vector2(22.0 * sx, 102.0 * sy), str(entry["title"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 110.0 * sx, roundi(17.0 * sy), Color(0.88, 0.85, 0.78, (0.48 if locked else 0.96) * alpha))
	var p_tex: Texture2D = chapter_portraits.get(str(entry["id"]), null)
	if p_tex != null:
		var pr := Rect2(r.end.x - 90.0 * sx, r.position.y + 22.0 * sy, 70.0 * sx, 70.0 * sy)
		draw_rect(pr, Color(0.08, 0.09, 0.12, 0.95 * alpha), true)
		draw_texture_rect(p_tex, pr, false, Color(1.0, 1.0, 1.0, alpha))
		draw_rect(pr, border_col, false, 1.4)

	draw_line(r.position + Vector2(22.0 * sx, 118.0 * sy), r.position + Vector2(r.size.x - 22.0 * sx, 118.0 * sy), Color(0.50, 0.52, 0.58, 0.35 * alpha), 1.0)
	draw_string(font, r.position + Vector2(22.0 * sx, 142.0 * sy), "%s  ·  %s" % [str(entry["tag"]), str(entry["subtitle"])], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40.0 * sx, roundi(12.0 * sy), Color(accent.r, accent.g, accent.b, (0.55 if locked else 0.92) * alpha))
	var lines: Array = entry.get("desc_lines", [])
	for li in range(lines.size()):
		draw_string(font, r.position + Vector2(22.0 * sx, (172.0 + float(li) * 26.0) * sy), str(lines[li]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40.0 * sx, roundi(13.0 * sy), Color(0.82, 0.80, 0.77, (0.48 if locked else 0.92) * alpha))

	var is_spring := (str(entry["id"]) == "spring")
	var is_spring_resume := (is_spring and bool(spring_resume_info.get("active", false)))
	if is_spring_resume:
		var tag_r := Rect2(r.position.x + 20.0 * sx, r.end.y - 106.0 * sy, r.size.x - 40.0 * sx, 28.0 * sy)
		draw_rect(tag_r, Color(0.13, 0.25, 0.32, 0.9 * alpha), true)
		draw_rect(tag_r, Color(0.56, 0.78, 0.86, 0.8 * alpha), false, 1.0)
		var mode_tag := "困难定轨" if bool(spring_resume_info.get("hard_mode", false)) else "普通"
		draw_string(font, tag_r.position + Vector2(12.0 * sx, 19.0 * sy), "进行中（%s）· 体力 %d/%d" % [mode_tag, int(spring_resume_info.get("stamina", 0)), int(spring_resume_info.get("stamina_max", 10))], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color(0.88, 0.97, 1.0, alpha))
	elif is_spring:
		draw_string(font, Vector2(r.position.x + 22.0 * sx, r.end.y - 82.0 * sy), "困难定轨：长按一笔画路线必达首领", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40.0 * sx, roundi(11.5 * sy), Color(0.95, 0.62, 0.56, alpha))

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
