extends Control

## High-craft title screen for ECHO:
## - Clean 16:9 twilight illustration with subtle breathing zoom
## - Drifting golden & pale-cyan echo dust motes
## - Minimalist left-aligned typography & animated hover bars (no baked fake buttons)

const BATTLE_SCENE_PATH := "res://scenes/main/main.tscn"
const SPRING_SCENE_PATH := "res://scenes/spring/spring_map.tscn"
const BACKGROUND_PATH := "res://assets/ui/main_menu_background.png"

## §4 of the 2026-11-26 design summary: two play modes on one save. "开始探索"
## stays the tutorial mode it has always been; 未尽之春 is the season run, which
## keeps its own in-run resources.
const OPTION_START := 0
const OPTION_SPRING := 1
const OPTION_EXIT := 2
const OPTIONS: Array[Dictionary] = [
	{"label": "开始探索", "sub": "START EXPEDITION · TUTORIAL"},
	{"label": "未尽之春", "sub": "THE SPRING THAT NEVER FINISHED"},
	{"label": "退出游戏", "sub": "EXIT TO DESKTOP"},
]

var background: Texture2D
var selected_option: int = OPTION_START
var elapsed: float = 0.0
var hover_slide: Array[float] = [1.0, 0.0, 0.0]
var motes: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	background = _load_background()
	_init_motes()
	queue_redraw()


func _load_background() -> Texture2D:
	if ResourceLoader.exists(BACKGROUND_PATH, "Texture2D"):
		var res := ResourceLoader.load(BACKGROUND_PATH)
		if res is Texture2D:
			return res
	var abs_path := ProjectSettings.globalize_path(BACKGROUND_PATH)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _init_motes() -> void:
	motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261126
	for i in range(38):
		motes.append({
			"x": rng.randf_range(0.0, 1280.0),
			"y": rng.randf_range(0.0, 720.0),
			"vy": rng.randf_range(-18.0, -7.0),
			"vx": rng.randf_range(-6.0, 10.0),
			"r": rng.randf_range(1.2, 3.0),
			"phase": rng.randf_range(0.0, TAU),
			"cyan": rng.randf() < 0.28,
		})


func _process(delta: float) -> void:
	elapsed += delta
	for i in range(OPTIONS.size()):
		var target := 1.0 if i == selected_option else 0.0
		hover_slide[i] = lerpf(hover_slide[i], target, minf(1.0, delta * 12.0))
	for m in motes:
		m["x"] = fposmod(float(m["x"]) + float(m["vx"]) * delta + sin(elapsed * 0.8 + float(m["phase"])) * 4.0 * delta, maxf(1.0, size.x))
		m["y"] = float(m["y"]) + float(m["vy"]) * delta
		if float(m["y"]) < -10.0:
			m["y"] = size.y + 10.0
	queue_redraw()


func _draw() -> void:
	# 1. Background artwork (includes baked ECHO · THE LAST PROMISE logo; aspect-fill cleanly)
	if background != null:
		var tex_sz := background.get_size()
		var scale_f := maxf(size.x / maxf(1.0, tex_sz.x), size.y / maxf(1.0, tex_sz.y))
		var drawn := tex_sz * scale_f
		var offset := (size - drawn) * 0.5
		draw_texture_rect(background, Rect2(offset, drawn), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#141820"), true)

	# 2. Very light bottom-left scrim so menu buttons read crisply without dulling the logo
	var grad_w: float = size.x * 0.44
	var c_left := Color(0.05, 0.065, 0.095, 0.46)
	var c_clear := Color(0.05, 0.065, 0.095, 0.0)
	draw_polygon(
		PackedVector2Array([Vector2(0, size.y * 0.36), Vector2(grad_w, size.y * 0.36), Vector2(grad_w, size.y), Vector2(0, size.y)]),
		PackedColorArray([c_left, c_clear, c_clear, c_left])
	)

	# 3. Drifting warm dusk & echo dust motes
	for m in motes:
		var tw: float = 0.45 + 0.55 * sin(elapsed * 2.2 + float(m["phase"]))
		var col := Color(0.55, 0.86, 0.96, 0.55 * tw) if bool(m["cyan"]) else Color(0.98, 0.82, 0.46, 0.65 * tw)
		draw_circle(Vector2(float(m["x"]), float(m["y"])), float(m["r"]), col)

	# 4. Clean minimalist menu options directly beneath the baked ECHO logo
	var font := ThemeDB.fallback_font
	var sx: float = size.x / 1280.0
	var sy: float = size.y / 720.0
	var left_x: float = 112.0 * sx

	for i in range(OPTIONS.size()):
		var rect := _option_rect(i)
		var s: float = hover_slide[i]
		if s > 0.02:
			var bg_a: float = 0.42 * s
			var bar_c := Color(0.92, 0.76, 0.45, 0.95 * s)
			draw_polygon(
				PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
				PackedColorArray([Color(0.14, 0.13, 0.11, bg_a), Color(0.14, 0.13, 0.11, 0.0), Color(0.14, 0.13, 0.11, 0.0), Color(0.14, 0.13, 0.11, bg_a)])
			)
			draw_rect(Rect2(rect.position, Vector2(4.0, rect.size.y)), bar_c, true)

		var shift_x: float = 16.0 * sx + 12.0 * s * sx
		var text_col := Color(0.80, 0.81, 0.84, 0.82).lerp(Color(0.98, 0.92, 0.78, 1.0), s)
		var sub_col := Color(0.60, 0.63, 0.68, 0.62).lerp(Color(0.86, 0.74, 0.48, 0.90), s)
		draw_string(font, rect.position + Vector2(shift_x, rect.size.y * 0.52), str(OPTIONS[i]["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24.0 * sy), text_col)
		draw_string(font, rect.position + Vector2(shift_x, rect.size.y * 0.82), str(OPTIONS[i]["sub"]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.0 * sy), sub_col)

	# 5. Quiet footer tag
	draw_string(font, Vector2(left_x, size.y - 34.0 * sy), "黄昏纪元  ·  有些声音，从未真正消失   |   按 ↑↓ 选择，Enter 开始", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), Color(0.76, 0.78, 0.82, 0.62))


func _option_rect(index: int) -> Rect2:
	var sx: float = size.x / 1280.0
	var sy: float = size.y / 720.0
	var left_x: float = 112.0 * sx
	var first_y: float = 356.0 * sy
	var h: float = 64.0 * sy
	var gap: float = 18.0 * sy
	return Rect2(left_x, first_y + float(index) * (h + gap), 320.0 * sx, h)


func _move_selection(direction: int) -> void:
	if direction == 0:
		return
	selected_option = wrapi(selected_option + signi(direction), 0, OPTIONS.size())
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_UP, KEY_W:
			_move_selection(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN, KEY_S:
			_move_selection(1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_selected()
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in range(OPTIONS.size()):
			if _option_rect(i).has_point(event.position) and selected_option != i:
				selected_option = i
				queue_redraw()
				break
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for i in range(OPTIONS.size()):
			if _option_rect(i).has_point(event.position):
				selected_option = i
				queue_redraw()
				_activate_selected()
				accept_event()
				return


func _activate_selected() -> void:
	match selected_option:
		OPTION_START:
			var error := get_tree().change_scene_to_file(BATTLE_SCENE_PATH)
			if error != OK:
				push_error("Unable to open ECHO battle scene. Error: %s" % error)
		OPTION_SPRING:
			var spring_error := get_tree().change_scene_to_file(SPRING_SCENE_PATH)
			if spring_error != OK:
				push_error("Unable to open the 春之境 map. Error: %s" % spring_error)
		OPTION_EXIT:
			get_tree().quit()
