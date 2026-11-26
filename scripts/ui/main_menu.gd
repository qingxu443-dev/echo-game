extends Control

## ECHO title screen. The supplied artwork contains the menu lettering and frame
## decoration; this script adds only the two functional hit targets and focus
## feedback, leaving the artwork itself untouched.

const DESIGN_SIZE := Vector2(1260.0, 700.0)
const BACKGROUND_PATH := "res://assets/ui/main_menu_background.png"
const BATTLE_SCENE_PATH := "res://scenes/main/main.tscn"

# Only these two entries are actionable. Save and Settings remain decorative
# artwork for a later phase and are intentionally not focusable.
const OPTION_START := 0
const OPTION_EXIT := 1
const OPTION_COUNT := 2

# Hit areas follow the baked button frames in the supplied 1260 x 700 artwork.
const OPTION_RECTS := [
	Rect2(214.0, 315.0, 322.0, 58.0),
	Rect2(214.0, 505.0, 322.0, 58.0),
]

var selected_option: int = OPTION_START
var background: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	if ResourceLoader.exists(BACKGROUND_PATH):
		background = load(BACKGROUND_PATH) as Texture2D
	else:
		push_warning("ECHO main menu background is not installed yet: " + BACKGROUND_PATH)
	queue_redraw()


func _draw() -> void:
	if background != null:
		var scale_factor := _background_scale()
		var drawn_size := DESIGN_SIZE * scale_factor
		var offset := (size - drawn_size) * 0.5
		draw_texture_rect(background, Rect2(offset, drawn_size), false)
	else:
		_draw_fallback_background()

	# The source artwork already contains the selected gold frame. This subtle
	# outline follows keyboard/mouse focus without repainting the supplied art.
	var focus_rect := _scaled_option_rect(selected_option)
	draw_rect(focus_rect, Color(1.0, 0.84, 0.62, 0.78), false, 2.0, true)


func _draw_fallback_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.075, 0.10), true)
	var title_font := ThemeDB.fallback_font
	var scale_factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var title_size := maxi(24, roundi(68.0 * scale_factor))
	var body_size := maxi(14, roundi(25.0 * scale_factor))
	draw_string(title_font, Vector2(size.x * 0.16, size.y * 0.28), "ECHO", HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.88, 0.88, 0.87))
	draw_string(title_font, Vector2(size.x * 0.17, size.y * 0.355), "THE LAST PROMISE", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, roundi(15.0 * scale_factor)), Color(0.72, 0.72, 0.72))
	draw_string(title_font, Vector2(size.x * 0.22, size.y * 0.49), "▶  开始游戏", HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, Color(0.94, 0.88, 0.78))
	draw_string(title_font, Vector2(size.x * 0.22, size.y * 0.77), "□  退出游戏", HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, Color(0.78, 0.79, 0.80))


func _background_scale() -> float:
	# Fill the viewport without distorting the 1260 x 700 artwork.
	# Any overflow is cropped evenly from the opposing edges.
	return maxf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)


func _background_offset() -> Vector2:
	return (size - DESIGN_SIZE * _background_scale()) * 0.5


func _scaled_option_rect(index: int) -> Rect2:
	var source_rect: Rect2 = OPTION_RECTS[index]
	var scale_factor := _background_scale()
	return Rect2(
		_background_offset() + source_rect.position * scale_factor,
		source_rect.size * scale_factor
	)


func _move_selection(direction: int) -> void:
	if direction == 0:
		return
	selected_option = wrapi(selected_option + signi(direction), 0, OPTION_COUNT)
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
		for index in range(OPTION_COUNT):
			if _scaled_option_rect(index).has_point(event.position) and selected_option != index:
				selected_option = index
				queue_redraw()
				break
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for index in range(OPTION_COUNT):
			if _scaled_option_rect(index).has_point(event.position):
				selected_option = index
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
		OPTION_EXIT:
			get_tree().quit()
