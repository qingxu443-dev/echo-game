extends CanvasLayer

signal quit_requested(saved: bool)
const PauseScript = preload("res://scripts/ui/pause_menu.gd")
const TransitionScript = preload("res://scripts/ui/scene_transition.gd")
const AudioScript = preload("res://scripts/ui/game_audio.gd")
var audio: GameAudio
var menu: PauseMenu
var transition: SceneTransition
var pause_button: Button
var animations_enabled: bool = true
var allow_quit: bool = true
var is_paused: bool = false
var stage: String = ""
var phase_time: float = 0.0
var destination: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	animations_enabled = DisplayServer.get_name() != "headless"
	audio = AudioScript.new()
	add_child(audio)
	pause_button = Button.new()
	pause_button.text = "Ⅱ  暂停"
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.position = Vector2(1154, 14)
	pause_button.size = Vector2(102, 38)
	pause_button.add_theme_font_size_override("font_size", 15)
	pause_button.pressed.connect(open_pause)
	add_child(pause_button)
	menu = PauseScript.new()
	add_child(menu)
	menu._skin(pause_button)
	menu.action_requested.connect(_on_action)
	transition = TransitionScript.new()
	add_child(transition)
	transition.hide()
	get_tree().scene_changed.connect(_scene_changed)
	pause_button.hide()


func _is_gameplay() -> bool:
	var scene := get_tree().current_scene
	return scene != null and (scene.has_method("_current_level") or scene.has_method("_start_battle"))


func _input(event: InputEvent) -> void:
	intercept(event)
	if not is_paused and stage.is_empty() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _is_gameplay():
		audio.play_cue("ui")


func intercept(event: InputEvent) -> bool:
	if not stage.is_empty():
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("echo_pause") and _is_gameplay():
		if is_paused:
			if not menu.dismiss_detail(): resume()
		else: open_pause()
		get_viewport().set_input_as_handled()
		return true
	return is_paused


func open_pause() -> void:
	if not _is_gameplay() or not stage.is_empty() or is_paused: return
	is_paused = true
	get_tree().paused = true
	pause_button.hide()
	var scene := get_tree().current_scene
	var context := "春之境 · 地图探索"
	if scene.has_method("_current_level"):
		var level: EncounterDefinition = scene._current_level()
		context = "%s · 第 %d 回合" % [str(level.display_name_zh) if level != null else "遗迹战场", scene.controller.turn_number]
	menu.open(context, audio.music_enabled, audio.effects_enabled)
	audio.play_cue("pause")


func resume() -> void:
	menu.hide()
	is_paused = false
	get_tree().paused = false
	pause_button.visible = _is_gameplay()
	_position_pause_button()
	audio.play_cue("pause")


func _on_action(action: String) -> void:
	match action:
		"resume": resume()
		"about": menu.show_about()
		"exit": menu.ask_exit()
		"confirm_exit": _exit(false)
		"save_exit":
			if PlaySession.save(get_tree().current_scene): _exit(true)
			else: menu.note.text = "保存失败，当前旅程已保留在游戏中。请检查磁盘后重试。"
		"music", "effects":
			var enabled := not audio.music_enabled if action == "music" else not audio.effects_enabled
			if not audio.set_enabled(action, enabled): menu.note.text = "声音设置保存失败，原设置已保留。"
			menu.refresh_audio(audio.music_enabled, audio.effects_enabled)
			audio.play_cue("ui")


func _exit(saved: bool) -> void:
	quit_requested.emit(saved)
	if allow_quit: get_tree().quit()


func travel(path: String, title: String) -> Error:
	if not stage.is_empty(): return ERR_BUSY
	if not ResourceLoader.exists(path): return ERR_FILE_NOT_FOUND
	if is_paused: resume()
	destination = path
	transition.title = title
	transition.coverage = 0.0
	transition.show()
	stage = "closing"
	phase_time = 0.0
	get_tree().paused = true
	pause_button.hide()
	return OK


func reveal(title: String) -> void:
	if not animations_enabled or not stage.is_empty(): return
	transition.title = title
	transition.coverage = 1.0
	transition.show()
	stage = "opening"
	phase_time = 0.0
	get_tree().paused = true
	pause_button.hide()


func _scene_changed() -> void:
	if stage == "waiting":
		stage = "opening"
		phase_time = 0.0
		transition.coverage = 1.0
	elif stage.is_empty():
		reveal("有些声音，从未真正消失。")
	pause_button.visible = _is_gameplay() and stage.is_empty() and not is_paused
	_position_pause_button()


func _position_pause_button() -> void:
	var scene := get_tree().current_scene
	# The battle's top-right corner belongs to the enemy-order/formation card.
	pause_button.position = Vector2(846, 84) if scene != null and scene.has_method("_current_level") else Vector2(1154, 18)


func _process(delta: float) -> void:
	if stage.is_empty(): return
	phase_time += delta
	if stage == "closing":
		transition.coverage = smoothstep(0.0, 1.0, minf(phase_time / 0.30, 1.0))
		if phase_time >= 0.30:
			stage = "waiting"
			var error := get_tree().change_scene_to_file(destination)
			if error != OK:
				transition.title = "未能抵达目的地，请稍后重试。"
				stage = "opening"
				phase_time = 0.0
	elif stage == "opening":
		transition.coverage = 1.0 - smoothstep(0.0, 1.0, minf(phase_time / 0.60, 1.0))
		if phase_time >= 0.60:
			stage = ""
			transition.hide()
			get_tree().paused = false
			pause_button.visible = _is_gameplay()
			_position_pause_button()
