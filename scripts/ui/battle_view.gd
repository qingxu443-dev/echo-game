extends Node2D

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const LevelCatalogScript = preload("res://scripts/battle/level_catalog.gd")
const CELL_SIZE: float = 64.0
const BOARD_ORIGIN := Vector2(384.0, 72.0)
const BOARD_SIZE := 8
const END_TURN_RECT := Rect2(940.0, 620.0, 300.0, 60.0)
const SKILL_PANEL_X: float = 940.0
const SKILL_PANEL_W: float = 300.0
const SKILL_FIRST_Y: float = 112.0
const SKILL_BTN_H: float = 50.0
const SKILL_BTN_STEP: float = 54.0

const SETTLEMENT_RECT := Rect2(330.0, 210.0, 620.0, 330.0)
const RESTART_BTN := Rect2(390.0, 464.0, 220.0, 52.0)
const NEXT_BTN := Rect2(640.0, 464.0, 220.0, 52.0)

## Prototype skill bar. Self-target skills resolve on press; actor-target skills wait for confirmation.
## Number keys 1–4 mirror the visible order; no default attack is selected.
const SKILL_BAR := [
	{"id": "oathkeeper_judgment_mark", "name": "裁决印记", "hint": "1–4 格 · DEF×0.8 · 施加标记", "cost": 1, "mode": "actor"},
	{"id": "oath_shield", "name": "誓盾庇护", "hint": "自身 + 两格内友军 · 护盾", "cost": 1, "mode": "self"},
	{"id": "absolute_guard", "name": "绝对守护", "hint": "2 AP + 5 能量 · 嘲讽反击", "cost": 2, "mode": "self"},
	{"id": "hunter_summon", "name": "猎人通灵", "hint": "任意敌人 · 现身一击 · 冷却 2 回合", "cost": 0, "mode": "actor"},
]

## Presentation-only summon roster. Future summons can be added here without changing
## the existing hunter_summon execution path. Selection currently affects the displayed icon/name only.
const SUMMON_OPTIONS := [
	{"id": "yu_bubble", "name": "余泡泡", "icon": preload("res://assets/ui/summons/yu_bubble.webp")},
]
var selected_summon_option: int = 0

var controller: BattleController
var levels: Array[EncounterDefinition] = []
var current_level: int = 0
var status_message: String = "点击格子移动；点右侧技能后选择目标。"
var selected_skill: int = -1


func _ready() -> void:
	levels = LevelCatalogScript.create_prototype_levels()
	controller = ControllerScript.new()
	add_child(controller)
	controller.battle_event.connect(_on_battle_event)
	controller.battle_finished.connect(_on_battle_finished)
	_start_level(0)


func _start_level(index: int) -> void:
	if index < 0 or index >= levels.size():
		return
	current_level = index
	var level: EncounterDefinition = levels[index]
	selected_skill = -1
	controller.start_encounter(level.player_cell, level.enemy_cells, level.obstacles, level.enemy_archetypes)
	status_message = level.tactical_hint_zh
	queue_redraw()


func _current_level() -> EncounterDefinition:
	if current_level < 0 or current_level >= levels.size():
		return null
	return levels[current_level]


func _has_next_level() -> bool:
	return current_level + 1 < levels.size()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)), Color("#17191d"), true)
	_draw_header()
	_draw_board()
	_draw_area_effects()
	_draw_telegraphs()
	_draw_target_hints()
	_draw_actors()
	_draw_hud()
	_draw_skill_panel()
	if controller.phase == ControllerScript.BattlePhase.FINISHED:
		_draw_settlement()


func _draw_header() -> void:
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(48, 52), "回声计划  /  原型 0.1", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#e4dfd3"))
	draw_string(font, Vector2(48, 82), "初次守望", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#9b9a94"))
	var level := _current_level()
	if level != null:
		draw_string(font, Vector2(48, 112), "%s　（%d / %d）" % [level.display_name_zh, current_level + 1, levels.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c5a45c"))


func _draw_board() -> void:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(cell)
			var fill := Color("#292c31") if (x + y) % 2 == 0 else Color("#24272c")
			draw_rect(rect, fill, true)
			draw_rect(rect, Color("#45484c"), false, 1.0)
			if controller.blocked_cells.has(cell):
				draw_rect(rect.grow(-5.0), Color("#101114"), true)
				draw_rect(rect.grow(-5.0), Color("#55504a"), false, 2.0)


func _draw_area_effects() -> void:
	# Legacy Watchwall effects remain supported by the controller but are not part of the V2 skill UI.
	pass


func _draw_actors() -> void:
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		if not actor.is_alive():
			continue
		var center := _cell_center(actor.cell)
		var body_color := Color("#a8a08b") if actor.team == "player" else Color("#873f3b")
		var outline := Color("#e7d7ae") if actor.team == "player" else Color("#d58b78")
		draw_circle(center, 22.0, body_color)
		draw_arc(center, 22.0, 0.0, TAU, 48, outline, 3.0)
		var glyph := "守" if actor.team == "player" else ("射" if actor.archetype == "marksman" else ("术" if actor.archetype == "area_controller" else "锋"))
		draw_string(ThemeDB.fallback_font, center + Vector2(-7.0, 7.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#17191d"))
		_draw_actor_badges(actor_id, actor, center)


## V2 status markers: shield/guard on Sevrin and the isolated mark on enemies.
func _draw_actor_badges(actor_id: String, actor, center: Vector2) -> void:
	if actor.team == "player":
		if actor.shield > 0:
			draw_arc(center, 27.0, 0.0, TAU, 48, Color("#7fb8d8"), 3.0)
		if actor_id == "sevrin" and controller.statuses.has_status(actor_id, &"absolute_guard"):
			draw_arc(center, 32.0, 0.0, TAU, 48, Color("#e0b25c"), 3.0)
		return
	if controller.statuses.has_status(actor_id, &"oathkeeper_mark"):
		draw_arc(center, 27.0, 0.0, TAU, 48, Color("#c98be0"), 3.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(-7.0, -28.0), "印", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e6c9f2"))


func _draw_telegraphs() -> void:
	for intent in controller.intents:
		if intent.state != IntentScript.IntentState.ACTIVE:
			continue
		match intent.action_id:
			"ground_pulse":
				for area_cell in intent.affected_cells:
					var area_rect := _cell_rect(area_cell).grow(-5.0)
					draw_rect(area_rect, Color(0.48, 0.35, 0.72, 0.24), true)
					draw_rect(area_rect, Color("#b49adf"), false, 3.0)
				var center_rect := _cell_rect(intent.target_cell).grow(-9.0)
				draw_string(ThemeDB.fallback_font, center_rect.position + Vector2(13.0, 35.0), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#eee4ff"))

			"aimed_shot":
				var shot_rect := _cell_rect(intent.target_cell).grow(-4.0)
				draw_rect(shot_rect, Color(0.20, 0.55, 0.72, 0.22), true)
				draw_rect(shot_rect, Color("#78c7df"), false, 4.0)
				draw_string(ThemeDB.fallback_font, shot_rect.position + Vector2(8.0, 20.0), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#d7f5ff"))
			"charged_strike":
				var rect := _cell_rect(intent.target_cell).grow(-4.0)
				draw_rect(rect, Color(0.65, 0.12, 0.10, 0.24), true)
				draw_rect(rect, Color("#e36a5e"), false, 4.0)
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(8.0, 20.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#ffd7cb"))
			"basic_melee":
				var target = controller.get_actor(intent.target_actor_id)
				if target != null and target.is_alive():
					draw_arc(_cell_center(target.cell), 29.0, 0.0, TAU, 48, Color("#e3a35d"), 4.0)
			"pursuit":
				for path_cell in intent.affected_cells:
					draw_rect(_cell_rect(path_cell).grow(-10.0), Color(0.75, 0.61, 0.31, 0.22), true)
					draw_rect(_cell_rect(path_cell).grow(-10.0), Color("#c5a45c"), false, 2.0)
			"wait":
				var wait_center := _cell_center(controller.get_actor(intent.source_actor_id).cell)
				draw_arc(wait_center, 27.0, 0.0, TAU, 48, Color("#8c8b84"), 2.0)


## Highlights the enemies the selected skill could legally hit right now.
## Whether the selected skill may legally target this enemy right now.
##
## Kept separate from _draw_target_hints so the highlight and the cast cannot
## drift apart. hunter_summon needs a free cell beside the target as well as a
## ready cooldown, so a ring drawn from distance alone used to promise a cast
## that the controller would then refuse.
func _can_target_actor(skill_id: String, actor_id: String) -> bool:
	var player = controller.get_actor("sevrin")
	if player == null:
		return false
	var actor = controller.get_actor(actor_id)
	if actor == null or actor.team != "enemy" or not actor.is_alive():
		return false
	match skill_id:
		"oathkeeper_judgment_mark":
			var distance: int = absi(actor.cell.x - player.cell.x) + absi(actor.cell.y - player.cell.y)
			if distance < 1 or distance > 4:
				return false
			return GridRulesScript.has_clear_line_of_sight(player.cell, actor.cell, controller.blocked_cells, controller.get_occupied_cells())
		"hunter_summon":
			return controller.can_summon(actor_id)
	return false


func _draw_target_hints() -> void:
	if controller.phase != ControllerScript.BattlePhase.PLAYER:
		return
	if selected_skill < 0 or selected_skill >= SKILL_BAR.size():
		return
	var skill: Dictionary = SKILL_BAR[selected_skill]
	if skill["mode"] != "actor":
		return
	for actor_id in controller.actors:
		if not _can_target_actor(str(skill["id"]), str(actor_id)):
			continue
		draw_arc(_cell_center(controller.actors[actor_id].cell), 31.0, 0.0, TAU, 48, Color(0.95, 0.85, 0.55, 0.55), 2.0)


func _draw_hud() -> void:
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(48, 145), "回合  %02d" % controller.turn_number, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#d9d4c8"))
	draw_string(font, Vector2(48, 180), "行动点  %d / %d" % [controller.ap.current, controller.ap.maximum], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#d4b77b"))
	draw_string(font, Vector2(48, 235), "瑟弗林", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#e4dfd3"))
	var sevrin = controller.get_actor("sevrin")
	if sevrin != null:
		draw_string(font, Vector2(48, 263), "生命  %d / %d" % [sevrin.health, sevrin.max_health], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#b9b7ad"))
		draw_string(font, Vector2(48, 290), "攻击 %d  防御 %d" % [sevrin.attack, sevrin.defense], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#b9b7ad"))
		draw_string(font, Vector2(48, 336), "护盾 %d  终极能量 %d / 5" % [sevrin.shield, sevrin.ultimate_energy], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#8fc7dc"))
		draw_string(font, Vector2(48, 313), "魔抗 %d" % sevrin.magic_resistance, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#b9b7ad"))
		draw_string(font, Vector2(48, 359), "被动：不屈誓约 · 守誓 %d / 3" % controller.get_oath_vow_stacks(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#d4b77b"))
	_draw_wrapped(font, status_message, Vector2(48, 382), 320.0, 15, Color("#aaa79e"), 2)
	draw_string(font, Vector2(48, 425), "敌方行动顺序", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c5a45c"))
	var order_y := 455.0
	for index in range(controller.intents.size()):
		var intent = controller.intents[index]
		var action_label: String = _action_name(intent.action_id)
		var state_label: String = "  [待执行]" if intent.state == IntentScript.IntentState.ACTIVE else ("  [已执行]" if intent.state == IntentScript.IntentState.RESOLVED else "  [已取消]")
		draw_string(font, Vector2(48, order_y), "%d. %s — %s%s" % [index + 1, _actor_name(intent.source_actor_id), action_label, state_label], HORIZONTAL_ALIGNMENT_LEFT, 315, 13, Color("#c7c2b6"))
		order_y += 24.0


func _draw_skill_panel() -> void:
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(SKILL_PANEL_X, 96), "技能", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#e4dfd3"))

	for index in range(SKILL_BAR.size()):
		var skill: Dictionary = SKILL_BAR[index]
		var rect := _skill_rect(index)
		var affordable: bool = controller.ap != null and controller.ap.can_spend(int(skill["cost"]))
		if skill["id"] == "absolute_guard":
			var sevrin = controller.get_actor("sevrin")
			affordable = affordable and sevrin != null and sevrin.ultimate_energy >= 5
		var cost_label := "%d AP" % int(skill["cost"])
		var cost_offset: float = 52.0
		var cost_y: float = 30.0
		if skill["id"] == "hunter_summon":
			var summon_remaining: int = controller.summon_cooldown_remaining()
			affordable = controller.phase == ControllerScript.BattlePhase.PLAYER and summon_remaining <= 0
			cost_label = "就绪" if summon_remaining <= 0 else "冷却 %d" % summon_remaining
			cost_offset = 76.0
			# The icon pushes the text block 36 px to the right, so the status label
			# shares the name baseline instead of sitting between the two text rows.
			cost_y = 21.0
		var is_selected: bool = (index == selected_skill and skill["mode"] == "actor")
		var bg := Color("#3a3f46") if is_selected else Color("#262a2f")
		var border := Color("#d4b77b") if is_selected else Color("#45484c")
		if not affordable:
			bg = Color("#1e2124")
			border = Color("#33363a")
		draw_rect(rect, bg, true)
		draw_rect(rect, border, false, 2.0 if is_selected else 1.0)
		var text_color := Color("#f0e5d0") if affordable else Color("#6b6a66")
		var skill_name: String = str(skill["name"])
		var text_x: float = 14.0
		if skill["id"] == "hunter_summon":
			var summon_option: Dictionary = SUMMON_OPTIONS[selected_summon_option]
			var icon_modulate: Color = Color(1.0, 1.0, 1.0) if affordable else Color(1.0, 1.0, 1.0, 0.45)
			draw_texture_rect(summon_option["icon"], Rect2(rect.position + Vector2(8.0, 8.0), Vector2(34.0, 34.0)), false, icon_modulate)
			skill_name += " · " + str(summon_option["name"])
			text_x = 50.0
		draw_string(font, rect.position + Vector2(text_x, 21.0), skill_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, text_color)
		draw_string(font, rect.position + Vector2(text_x, 39.0), str(skill["hint"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_color)
		draw_string(font, rect.position + Vector2(rect.size.x - cost_offset, cost_y), cost_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#d4b77b") if affordable else Color("#6b6a66"))

	var end_color := Color("#4b4030") if controller.phase == ControllerScript.BattlePhase.PLAYER else Color("#2a2d31")
	draw_rect(END_TURN_RECT, end_color, true)
	draw_rect(END_TURN_RECT, Color("#c4a66c"), false, 2.0)
	draw_string(font, END_TURN_RECT.position + Vector2(100.0, 38.0), "结束回合", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#f0e5d0"))

	var hint_y := 496.0
	draw_string(font, Vector2(SKILL_PANEL_X, hint_y), "操作", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#9b9a94"))
	draw_string(font, Vector2(SKILL_PANEL_X, hint_y + 22.0), "点格子移动，最多两格直线", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8c8b84"))
	draw_string(font, Vector2(SKILL_PANEL_X, hint_y + 40.0), "自身技能点一下即生效", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8c8b84"))
	draw_string(font, Vector2(SKILL_PANEL_X, hint_y + 58.0), "选中技能后，黄圈标出可打目标", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8c8b84"))
	draw_string(font, Vector2(SKILL_PANEL_X, hint_y + 76.0), "数字键 1–4 施放/选择技能", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8c8b84"))
	draw_string(font, Vector2(SKILL_PANEL_X, hint_y + 94.0), "Esc / 右键取消目标选择", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8c8b84"))


func _draw_settlement() -> void:
	var font = ThemeDB.fallback_font
	var won := controller.battle_result == "victory"
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)), Color(0.03, 0.04, 0.05, 0.72), true)
	draw_rect(SETTLEMENT_RECT, Color("#1b1e22"), true)
	draw_rect(SETTLEMENT_RECT, Color("#c4a66c"), false, 2.0)

	var title := "战斗结束 · 胜利" if won else "战斗结束 · 失败"
	draw_string(font, Vector2(370.0, 262.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#e4d2aa") if won else Color("#d58b78"))

	var level := _current_level()
	var level_name := "—" if level == null else level.display_name_zh
	_draw_settlement_row(font, 296.0, "关卡", level_name)
	_draw_settlement_row(font, 324.0, "回合数", "%d" % controller.turn_number)
	_draw_settlement_row(font, 352.0, "造成伤害", "%d" % controller.damage_dealt)
	_draw_settlement_row(font, 380.0, "承受伤害", "%d" % controller.damage_taken)
	_draw_settlement_row(font, 408.0, "击败敌人", "%d" % controller.enemies_defeated)

	var sevrin = controller.get_actor("sevrin")
	var health_label := "—"
	if sevrin != null:
		health_label = "%d / %d" % [sevrin.health, sevrin.max_health]
	_draw_settlement_row(font, 436.0, "剩余生命", health_label)

	_draw_settlement_button(font, RESTART_BTN, "重开本关")
	if won:
		_draw_settlement_button(font, NEXT_BTN, "下一关" if _has_next_level() else "从头开始")


func _draw_settlement_row(font: Font, y: float, label: String, value: String) -> void:
	draw_string(font, Vector2(390.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#9b9a94"))
	# draw_string ignores alignment when width is -1, so right-align by measuring.
	var value_width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(font, Vector2(910.0 - value_width, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#e4dfd3"))


func _draw_settlement_button(font: Font, rect: Rect2, label: String) -> void:
	draw_rect(rect, Color("#4b4030"), true)
	draw_rect(rect, Color("#c4a66c"), false, 2.0)
	var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, rect.position + Vector2((rect.size.x - text_width) * 0.5, 34.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#f0e5d0"))


func _handle_settlement_tap(position: Vector2) -> void:
	if RESTART_BTN.has_point(position):
		_start_level(current_level)
		return
	if controller.battle_result != "victory" or not NEXT_BTN.has_point(position):
		return
	_start_level(current_level + 1 if _has_next_level() else 0)


func _skill_rect(index: int) -> Rect2:
	return Rect2(SKILL_PANEL_X, SKILL_FIRST_Y + float(index) * SKILL_BTN_STEP, SKILL_PANEL_W, SKILL_BTN_H)


## Character-level wrapping so CJK status text breaks cleanly instead of clipping.
func _draw_wrapped(font: Font, text: String, pos: Vector2, max_width: float, size: int, color: Color, max_lines: int) -> void:
	var lines: Array[String] = []
	var current := ""
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		var trial := current + ch
		if current != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
			lines.append(current)
			current = ch
		else:
			current = trial
	if current != "":
		lines.append(current)
	var y := pos.y
	for i in range(mini(lines.size(), max_lines)):
		var line_text: String = lines[i]
		if i == max_lines - 1 and lines.size() > max_lines:
			line_text += "…"
		draw_string(font, Vector2(pos.x, y), line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		y += float(size) + 6.0


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(BOARD_ORIGIN + Vector2(cell) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))


func _cell_center(cell: Vector2i) -> Vector2:
	return _cell_rect(cell).position + Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_tap(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_target_selection()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_on_skill_pressed(0)
			KEY_2:
				_on_skill_pressed(1)
			KEY_3:
				_on_skill_pressed(2)
			KEY_4:
				_on_skill_pressed(3)
			KEY_ESCAPE:
				_cancel_target_selection()
			KEY_ENTER, KEY_SPACE:
				if controller.phase == ControllerScript.BattlePhase.PLAYER:
					controller.end_player_turn()
					status_message = "敌方已行动，新回合开始。"
					queue_redraw()


func _cancel_target_selection() -> void:
	if selected_skill < 0:
		return
	selected_skill = -1
	status_message = "已取消目标选择。"
	queue_redraw()


func _handle_tap(position: Vector2) -> void:
	if controller.phase == ControllerScript.BattlePhase.FINISHED:
		_handle_settlement_tap(position)
		return
	if controller.phase != ControllerScript.BattlePhase.PLAYER:
		return

	for index in range(SKILL_BAR.size()):
		if _skill_rect(index).has_point(position):
			_on_skill_pressed(index)
			return

	if END_TURN_RECT.has_point(position):
		controller.end_player_turn()
		status_message = "敌方已行动，新回合开始。"
		queue_redraw()
		return

	var grid_position := (position - BOARD_ORIGIN) / CELL_SIZE
	var cell := Vector2i(floori(grid_position.x), floori(grid_position.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= BOARD_SIZE or cell.y >= BOARD_SIZE:
		return

	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		if actor.team == "enemy" and actor.is_alive() and actor.cell == cell:
			if selected_skill >= 0:
				_use_skill_on(actor_id)
			return

	var path := _path_to_cell(controller.get_actor("sevrin").cell, cell)
	if path.is_empty():
		status_message = "该位置无法到达，或超出两格移动范围。"
	elif controller.request_player_move(path):
		status_message = "移动完成，消耗 1 点行动点。"
	else:
		status_message = "无法移动，请检查行动点和路径。"
	queue_redraw()


func _on_skill_pressed(index: int) -> void:
	if index < 0 or index >= SKILL_BAR.size():
		return
	var skill: Dictionary = SKILL_BAR[index]
	if skill["mode"] == "self":
		selected_skill = -1
		var cast_ok := false
		match skill["id"]:
			"oath_shield":
				cast_ok = controller.request_oath_shield("sevrin")
			"absolute_guard":
				cast_ok = controller.request_absolute_guard()
		if cast_ok:
			status_message = "「%s」已生效。" % str(skill["name"])
		else:
			status_message = "无法施放「%s」：检查行动点、终极能量与当前阶段。" % str(skill["name"])
		queue_redraw()
		return
	selected_skill = index
	status_message = "已选择「%s」，点击目标敌人施放。" % str(skill["name"])
	queue_redraw()


func _use_skill_on(actor_id: String) -> void:
	var skill: Dictionary = SKILL_BAR[selected_skill]
	var cast_ok := false
	match skill["id"]:
		"oathkeeper_judgment_mark":
			cast_ok = controller.request_oathkeeper_judgment_mark(actor_id)
		"hunter_summon":
			cast_ok = controller.request_hunter_summon(actor_id)
		_:
			status_message = "该技能需要点击自身，不需要选择目标。"
			queue_redraw()
			return

	if cast_ok:
		match skill["id"]:
			"oathkeeper_judgment_mark":
				status_message = "裁决印记已施加，造成伤害并标记目标。"
			"hunter_summon":
				status_message = "猎人现身一击命中，未消耗行动点。"
	else:
		match skill["id"]:
			"oathkeeper_judgment_mark":
				status_message = "裁决印记失败：目标需在 1–4 格内且视线无遮挡。"
			"hunter_summon":
				status_message = "猎人通灵失败：冷却未结束，或目标四周没有空位。"
	queue_redraw()


func _path_to_cell(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var came_from := {start: start}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var occupied: Dictionary = controller.get_occupied_cells("sevrin")
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == goal:
			break
		for direction in directions:
			var next: Vector2i = current + direction
			if next.x < 0 or next.y < 0 or next.x >= BOARD_SIZE or next.y >= BOARD_SIZE:
				continue
			if controller.blocked_cells.has(next) or occupied.has(next) or came_from.has(next):
				continue
			came_from[next] = current
			queue.append(next)
	if not came_from.has(goal) or goal == start:
		return []
	var reversed_path: Array[Vector2i] = []
	var cursor: Vector2i = goal
	while cursor != start:
		reversed_path.push_front(cursor)
		cursor = came_from[cursor]
	if reversed_path.size() > 2:
		return []
	return reversed_path


func _on_battle_event(_event: Dictionary) -> void:
	queue_redraw()


func _on_battle_finished(result: String) -> void:
	status_message = "遭遇战结束：" + ("胜利" if result == "victory" else "失败")
	queue_redraw()


func _actor_name(actor_id: String) -> String:
	if actor_id == "sevrin":
		return "瑟弗林"
	if actor_id.begins_with("vanguard"):
		return "先锋"
	if actor_id.begins_with("marksman"):
		return "神射手"
	if actor_id.begins_with("area_controller"):
		return "区域术士"
	return "未知单位"


func _action_name(action_id: String) -> String:
	var names := {
		"charged_strike": "蓄力重击",
		"basic_melee": "近战攻击",
		"pursuit": "追击",
		"aimed_shot": "瞄准射击",
		"ground_pulse": "地脉脉冲",
		"wait": "待机"
	}
	return names.get(action_id, "未知行动")
