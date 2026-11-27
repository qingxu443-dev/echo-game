class_name PauseMenu
extends Control

signal action_requested(action: String)
var buttons: Dictionary = {}
var heading: Label
var note: Label
var detail: PanelContainer
var detail_text: Label
var confirm_exit: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	heading = _label("旅 途 暂 歇", Vector2(408, 123), Vector2(464, 48), 32, UiPalette.GOLD_PALE)
	_label("E C H O   /   I N T E R M I S S I O N", Vector2(408, 103), Vector2(464, 22), 11, UiPalette.GOLD)
	_label("让回声停留片刻，再向未尽之处前行。", Vector2(408, 177), Vector2(464, 26), 14, UiPalette.TEXT_DIM)
	_add_button("resume", "继  续", "RETURN TO THE JOURNEY", Rect2(408, 224, 464, 62), true)
	_add_button("save_exit", "保存并退出", "SAVE & EXIT", Rect2(408, 300, 226, 58))
	_add_button("exit", "退出", "EXIT GAME", Rect2(646, 300, 226, 58))
	_add_button("music", "音乐 · 开", "MUSIC", Rect2(408, 372, 226, 58))
	_add_button("effects", "音效 · 开", "SOUND EFFECTS", Rect2(646, 372, 226, 58))
	_add_button("about", "关于", "ABOUT ECHO", Rect2(408, 444, 464, 54))
	note = _label("Esc 继续  ·  方向键选择  ·  Enter 确认", Vector2(408, 532), Vector2(464, 56), 13, UiPalette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail = PanelContainer.new()
	detail.position = Vector2(368, 176)
	detail.size = Vector2(544, 370)
	detail.add_theme_stylebox_override("panel", _style(Color("#171d26"), UiPalette.GOLD, 22))
	add_child(detail)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	detail.add_child(box)
	detail_text = Label.new()
	detail_text.add_theme_color_override("font_color", UiPalette.TEXT)
	detail_text.add_theme_font_size_override("font_size", 17)
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_text.custom_minimum_size = Vector2(480, 230)
	box.add_child(detail_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	for id in ["back", "confirm"]:
		var button := Button.new()
		button.text = "返回" if id == "back" else "确认退出"
		button.custom_minimum_size = Vector2(176, 44)
		_skin(button)
		button.pressed.connect(_detail_action.bind(id))
		row.add_child(button)
		buttons[id] = button
	detail.hide()
	hide()


func _style(fill: Color, border: Color, margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(margin)
	style.corner_radius_top_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _skin(button: Button, primary: bool = false) -> void:
	button.add_theme_stylebox_override("normal", _style(Color("#2b2c2b") if primary else Color("#1e242b"), Color("#8e794c") if primary else Color("#48505a")))
	button.add_theme_stylebox_override("hover", _style(Color("#323b42"), UiPalette.GOLD_LIGHT))
	button.add_theme_stylebox_override("pressed", _style(Color("#384347"), UiPalette.CYAN))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), UiPalette.CYAN))
	button.add_theme_color_override("font_color", UiPalette.GOLD_PALE if primary else UiPalette.TEXT)
	button.add_theme_color_override("font_hover_color", UiPalette.GOLD_PALE)
	button.add_theme_font_size_override("font_size", 18)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _add_button(id: String, label: String, sub: String, rect: Rect2, primary: bool = false) -> void:
	var button := Button.new()
	button.text = label + "\n" + sub
	button.position = rect.position
	button.size = rect.size
	_skin(button, primary)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(func(): action_requested.emit(id))
	add_child(button)
	buttons[id] = button


func _label(text: String, pos: Vector2, bounds: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = bounds
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func open(context: String, music_on: bool, effects_on: bool) -> void:
	show()
	detail.hide()
	confirm_exit = false
	_enable_main(true)
	note.text = context + "\nEsc 继续  ·  方向键选择  ·  Enter 确认"
	refresh_audio(music_on, effects_on)
	buttons.resume.grab_focus()


func refresh_audio(music_on: bool, effects_on: bool) -> void:
	buttons.music.text = "音乐 · %s\nMUSIC" % ("开" if music_on else "关")
	buttons.effects.text = "音效 · %s\nSOUND EFFECTS" % ("开" if effects_on else "关")


func show_about() -> void:
	confirm_exit = false
	_enable_main(false)
	detail_text.text = "ECHO · 回声\n\n2.5D 回合制战术 Roguelite\n开发：ECHO 项目贡献者\n引擎：Godot 4.7.2 Standard\n音乐与音效：本项目原创合成音频\n\n有些声音，从未真正消失。"
	buttons.confirm.hide()
	detail.show()
	buttons.back.grab_focus()


func ask_exit() -> void:
	confirm_exit = true
	_enable_main(false)
	detail_text.text = "离开这段旅途？\n\n退出不会保存当前暂停位置。\n已有的自动存档与此前保存的旅程会保留。\n\n若希望下次从这里继续，请返回并选择「保存并退出」。"
	buttons.confirm.show()
	detail.show()
	buttons.back.grab_focus()


func dismiss_detail() -> bool:
	if not detail.visible: return false
	detail.hide()
	confirm_exit = false
	_enable_main(true)
	buttons.resume.grab_focus()
	return true


func _enable_main(enabled: bool) -> void:
	for id in ["resume", "save_exit", "exit", "music", "effects", "about"]:
		buttons[id].disabled = not enabled


func _detail_action(id: String) -> void:
	if id == "confirm" and confirm_exit: action_requested.emit("confirm_exit")
	else: dismiss_detail()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.032, 0.045, 0.82))
	var panel := Rect2(368, 76, 544, 552)
	draw_rect(panel.grow(8), Color(0.02, 0.025, 0.035, 0.35))
	draw_rect(panel, Color("#171d25"))
	draw_rect(panel, Color(UiPalette.GOLD, 0.55), false, 1.0)
	for point in [panel.position, panel.position + Vector2(panel.size.x, 0), panel.end, panel.position + Vector2(0, panel.size.y)]:
		draw_circle(point, 3.0, UiPalette.GOLD_LIGHT)
	draw_line(Vector2(408, 210), Vector2(872, 210), Color(UiPalette.GOLD, 0.25), 1.0)
	draw_line(Vector2(408, 516), Vector2(872, 516), Color(UiPalette.GOLD, 0.25), 1.0)
