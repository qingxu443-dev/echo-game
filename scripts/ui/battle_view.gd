extends Node2D

## Battle screen orchestrator.
##
## Owns the encounter lifecycle, the skill bar and the player's intent; forwards
## rendering to the views and raw input to the router. It draws nothing itself
## beyond the backdrop: everything visible lives in board_view / hud_view /
## skill_bar_view / settlement_view, and every colour and coordinate lives in
## theme_palette.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const LevelCatalogScript = preload("res://scripts/battle/level_catalog.gd")
const Palette = preload("res://scripts/ui/theme_palette.gd")
const BoardViewScript = preload("res://scripts/ui/board_view.gd")
const HudViewScript = preload("res://scripts/ui/hud_view.gd")
const SkillBarViewScript = preload("res://scripts/ui/skill_bar_view.gd")
const SettlementViewScript = preload("res://scripts/ui/settlement_view.gd")
const InputRouterScript = preload("res://scripts/ui/input_router.gd")

## Prototype skill bar. Self-target skills resolve on press; actor-target skills wait for confirmation.
## Number keys 1–5 mirror the visible order, and nothing is selected by default.
## Rebuilt from the active character's sheet whenever the command switches.
var skill_bar: Array = []

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
	skill_bar = SkillBarViewScript.build_entries(controller)
	_start_level(0)


func _start_level(index: int) -> void:
	if index < 0 or index >= levels.size():
		return
	var level: EncounterDefinition = levels[index]
	selected_skill = -1
	# A rejected setup leaves the previous encounter untouched, so say so instead
	# of showing a fresh-looking screen that will not accept any action.
	if not controller.start_encounter(level.player_cell, level.enemy_cells, level.obstacles, level.enemy_archetypes, level.character_ids, level.ally_cells):
		status_message = "关卡「%s」数据无效，未能开始。" % str(level.display_name_zh)
		queue_redraw()
		return
	current_level = index
	status_message = level.tactical_hint_zh
	skill_bar = SkillBarViewScript.build_entries(controller)
	queue_redraw()


func _current_level() -> EncounterDefinition:
	if current_level < 0 or current_level >= levels.size():
		return null
	return levels[current_level]


func _has_next_level() -> bool:
	return current_level + 1 < levels.size()


# --- rendering ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Palette.VIEW_SIZE), Palette.BG, true)
	HudViewScript.draw_header(self, _current_level(), current_level, levels.size())
	BoardViewScript.draw(self, controller, selected_skill, skill_bar)
	HudViewScript.draw_status(self, controller, status_message)
	SkillBarViewScript.draw(self, controller, skill_bar, selected_skill)
	if controller.phase == ControllerScript.BattlePhase.FINISHED:
		SettlementViewScript.draw(self, controller, _current_level(), _has_next_level())


## Kept on the view because the integration suite asks it directly; the rule
## itself lives in BoardView so the ring and the cast share one predicate.
func _can_target_actor(skill_id: String, actor_id: String) -> bool:
	return BoardViewScript.can_target(controller, skill_bar, skill_id, actor_id)


## Layout delegators. The integration suite taps through the view's own geometry
## helpers rather than hard-coded coordinates, so these must stay reachable even
## though the geometry itself lives in SkillBarView and the palette.
func _skill_rect(index: int) -> Rect2:
	return SkillBarViewScript.skill_rect(index)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Palette.cell_rect(cell)


func _cell_center(cell: Vector2i) -> Vector2:
	return Palette.cell_center(cell)


# --- input -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var intent: Dictionary = InputRouterScript.translate(event)
	match intent.get("action", ""):
		InputRouterScript.ACTION_TAP:
			_handle_tap(intent["position"])
		InputRouterScript.ACTION_SKILL:
			_on_skill_pressed(int(intent["index"]))
		InputRouterScript.ACTION_CANCEL:
			_cancel_target_selection()
		InputRouterScript.ACTION_END_TURN:
			_end_player_turn()
		InputRouterScript.ACTION_SWITCH:
			_switch_character()


func _end_player_turn() -> void:
	if controller.phase != ControllerScript.BattlePhase.PLAYER:
		return
	controller.end_player_turn()
	status_message = "敌方已行动，新回合开始。"
	queue_redraw()


## Cycles command to the next living party member. Free: the AP pool is shared,
## so switching is a decision about who spends it, not a resource of its own.
func _switch_character() -> void:
	var roster: Array[String] = controller.get_switchable_characters()
	if roster.size() <= 1:
		status_message = "队伍中只有一名可行动角色。"
		queue_redraw()
		return
	var current_index: int = roster.find(controller.active_character_id)
	var next_id: String = roster[(current_index + 1) % roster.size()]
	if controller.set_active_character(next_id):
		selected_skill = -1
		skill_bar = SkillBarViewScript.build_entries(controller)
		# The rest of the screen is Chinese; the raw actor id ("sakura") is not
		# what the player sees on the token or in the HUD.
		var member = controller.get_actor(next_id)
		var label: String = next_id
		if member != null and not String(member.display_name_zh).is_empty():
			label = String(member.display_name_zh)
		status_message = "已切换到 %s。" % label
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

	for index in range(skill_bar.size()):
		if SkillBarViewScript.skill_rect(index).has_point(position):
			_on_skill_pressed(index)
			return

	if Palette.END_TURN_RECT.has_point(position):
		_end_player_turn()
		return

	var cell := Palette.cell_at(position)
	if not Palette.is_inside_board(cell, controller.grid_size):
		return

	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		if actor.team == "enemy" and actor.is_alive() and actor.cell == cell:
			if selected_skill >= 0:
				_use_skill_on(actor_id)
			else:
				# Tapping an enemy with no skill selected used to do nothing at
				# all, which reads as an unresponsive board rather than a missing
				# first step.
				status_message = "先点右侧技能，再点目标敌人。"
				queue_redraw()
			return

	var path := _path_to_cell(cell)
	if path.is_empty():
		status_message = "该位置无法到达，或超出两格移动范围。"
	elif controller.request_player_move(path):
		status_message = "移动完成，消耗 1 点行动点。"
	else:
		status_message = "无法移动，请检查行动点和路径。"
	queue_redraw()


func _handle_settlement_tap(position: Vector2) -> void:
	var won: bool = controller.battle_result == "victory"
	match SettlementViewScript.hit(position, won):
		SettlementViewScript.ACTION_RESTART:
			_start_level(current_level)
		SettlementViewScript.ACTION_NEXT:
			_start_level(current_level + 1 if _has_next_level() else 0)


# --- player actions ----------------------------------------------------------

func _on_skill_pressed(index: int) -> void:
	if index < 0 or index >= skill_bar.size():
		return
	var skill: Dictionary = skill_bar[index]
	if skill["mode"] == "self":
		selected_skill = -1
		# One entry point for every character: the runtime resolves the caster
		# from the active character and dispatches on the skill's effect id.
		var cast_ok: bool = controller.request_skill(StringName(str(skill["id"])))
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
	var skill: Dictionary = skill_bar[selected_skill]
	if controller.request_skill(StringName(str(skill["id"])), actor_id):
		status_message = "「%s」已生效。" % str(skill["name"])
	else:
		status_message = "「%s」未能施放：检查行动点、射程、视线与资源。" % str(skill["name"])
	queue_redraw()


## Candidate path only. The controller re-validates it through is_path_legal
## before committing the move, so this stays a hint rather than a decision.
func _path_to_cell(goal: Vector2i) -> Array[Vector2i]:
	var player = controller.get_active_character()
	if player == null:
		return []
	return GridRulesScript.find_path(
		player.cell,
		goal,
		controller.grid_size,
		controller.blocked_cells,
		controller.get_occupied_cells(controller.active_character_id),
		controller.PLAYER_MOVE_MAX_STEPS
	)


# --- controller signals ------------------------------------------------------

func _on_battle_event(event: Dictionary) -> void:
	# The bar belongs to the commanded character, and command can change without
	# the view asking - a downed commander hands over at the start of the turn.
	# Rebuild there, or the buttons would keep offering a dead character's kit.
	if str(event.get("type", "")) == "player_turn_started":
		selected_skill = -1
		skill_bar = SkillBarViewScript.build_entries(controller)
	queue_redraw()


func _on_battle_finished(result: String) -> void:
	status_message = "遭遇战结束：" + ("胜利" if result == "victory" else "失败")
	queue_redraw()
