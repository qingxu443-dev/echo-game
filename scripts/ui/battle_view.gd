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
const BoardThreatViewScript = preload("res://scripts/ui/board_threat_view.gd")
const HudViewScript = preload("res://scripts/ui/hud_view.gd")
const SkillBarViewScript = preload("res://scripts/ui/skill_bar_view.gd")
const SettlementViewScript = preload("res://scripts/ui/settlement_view.gd")
const InputRouterScript = preload("res://scripts/ui/input_router.gd")
const RunStateScript = preload("res://scripts/battle/run_state.gd")
const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")
const InventoryViewScript = preload("res://scripts/ui/inventory_view.gd")
const SpringBattleBridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")
const SpringEncounterCatalogScript = preload("res://scripts/spring/spring_encounter_catalog.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")

## Prototype skill bar. Self-target skills resolve on press; actor-target skills wait for confirmation.
## Number keys 1–5 mirror the visible order, and nothing is selected by default.
## Rebuilt from the active character's sheet whenever the command switches.
var skill_bar: Array = []

var controller: BattleController
var run_state: RunStateScript
var pending_rewards: Array[Dictionary] = []
var levels: Array[EncounterDefinition] = []
var current_level: int = 0
var status_message: String = "点击格子移动；点右侧技能后选择目标。"
var selected_skill: int = -1

## Procedural animation & visual feedback state passed into BoardView.draw().
var fx_time: float = 0.0
var hover_cell: Vector2i = Vector2i(-1, -1)
var hovered_skill: int = -1
var inventory_open: bool = false
var inventory_page: int = 0
var actor_visual_pos: Dictionary = {}
var actor_hop_state: Dictionary = {}
var actor_hit_flash: Dictionary = {}
var actor_lunge: Dictionary = {}
var floating_popups: Array = []
var impact_flashes: Array = []
var enemy_step_timer: float = 0.0
var enemy_phase_finishing: bool = false
## True when this scene was opened by the 春之境 map for a single fight. The
## campaign path (three lessons in a row) is untouched and stays the default.
var spring_mode: bool = false


func _ready() -> void:
	if SpringBattleBridgeScript.has_pending():
		_begin_spring_fight()
		return
	levels = LevelCatalogScript.create_prototype_levels()
	run_state = RunStateScript.new()
	controller = ControllerScript.new()
	controller.run_state = run_state
	add_child(controller)
	controller.battle_event.connect(_on_battle_event)
	controller.battle_finished.connect(_on_battle_finished)
	skill_bar = SkillBarViewScript.build_entries(controller)
	_begin_fresh_run()


## A fresh run gets a fresh drop sequence: reseed the loot RNG and remember the
## seed on the run state so a drop complaint can be reproduced from it later.
## Seeding lives here in the UI layer on purpose - headless tests never start a
## run through this path, so their rolls stay on the fixed default seed.
## One fight, injected from the map. Everything the run needs arrives in the
## bridge payload; nothing is read from the save here, so a fight is always
## against exactly the run the map handed over.
func _begin_spring_fight() -> void:
	spring_mode = true
	var payload: Dictionary = SpringBattleBridgeScript.pending
	var encounter_id := StringName(str(payload.get("encounter", "")))
	var definition := SpringEncounterCatalogScript.build(encounter_id, [CharacterCatalogScript.default_id()])
	if definition == null:
		push_error("春之境：遭遇 %s 无法构建，直接返回地图。" % String(encounter_id))
		SpringBattleBridgeScript.last_result = {
			"result": "defeat",
			"kind": str(payload.get("kind", SpringBattleBridgeScript.KIND_BATTLE)),
			"place": str(payload.get("place", "")),
			"hero_health": int(payload.get("hero_health", 1)),
			"hero_max_health": int(payload.get("hero_max_health", 1)),
		}
		SpringBattleBridgeScript.clear_pending()
		var error := get_tree().change_scene_to_file(SpringBattleBridgeScript.MAP_SCENE_PATH)
		if error != OK:
			push_error("无法返回春之境。Error: %s" % error)
		return
	levels = [definition]
	run_state = RunStateScript.new()
	SpringBattleBridgeScript.apply_payload(run_state, payload)
	controller = ControllerScript.new()
	controller.run_state = run_state
	add_child(controller)
	controller.battle_event.connect(_on_battle_event)
	controller.battle_finished.connect(_on_battle_finished)
	var loot_seed: int = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	LootCatalogScript.seed_rng(loot_seed)
	run_state.loot_seed = loot_seed
	_start_level(0)


## Hands the outcome back to the map scene. Called from the settlement button.
func _return_to_map() -> void:
	var hero = controller.get_active_character()
	var payload: Dictionary = SpringBattleBridgeScript.pending
	var result := {
		"result": controller.battle_result,
		"kind": str(payload.get("kind", SpringBattleBridgeScript.KIND_BATTLE)),
		"place": str(payload.get("place", "")),
		"hero_health": hero.health if hero != null else 1,
		"hero_max_health": hero.max_health if hero != null else 1,
		"carry": SpringBattleBridgeScript.pack_carry(run_state),
		"chests_saved": pending_rewards.size(),
		"loot": pending_rewards.duplicate(true),
		"seed": run_state.loot_seed,
	}
	SpringBattleBridgeScript.last_result = result
	SpringBattleBridgeScript.clear_pending()
	var error := get_tree().change_scene_to_file(SpringBattleBridgeScript.MAP_SCENE_PATH)
	if error != OK:
		push_error("无法返回春之境。Error: %s" % error)


func _begin_fresh_run() -> void:
	run_state.reset()
	var loot_seed: int = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	LootCatalogScript.seed_rng(loot_seed)
	run_state.loot_seed = loot_seed
	_start_level(0)


func _start_level(index: int) -> void:
	if index < 0 or index >= levels.size():
		return
	var level: EncounterDefinition = levels[index]
	selected_skill = -1
	pending_rewards.clear()
	# A rejected setup leaves the previous encounter untouched, so say so instead
	# of showing a fresh-looking screen that will not accept any action.
	if not controller.start_encounter(level.player_cell, level.enemy_cells, level.obstacles, level.enemy_archetypes, level.character_ids, level.ally_cells, level.chest_items, level.ward_nodes):
		status_message = "关卡「%s」数据无效，未能开始。" % str(level.display_name_zh)
		queue_redraw()
		return
	current_level = index
	status_message = level.tactical_hint_zh
	skill_bar = SkillBarViewScript.build_entries(controller)
	_reset_fx_for_encounter()
	queue_redraw()


func _reset_fx_for_encounter() -> void:
	actor_visual_pos.clear()
	actor_hop_state.clear()
	actor_hit_flash.clear()
	actor_lunge.clear()
	floating_popups.clear()
	impact_flashes.clear()
	enemy_step_timer = 0.0
	enemy_phase_finishing = false
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		actor_visual_pos[String(actor_id)] = Palette.cell_center(actor.cell)


func _process(delta: float) -> void:
	fx_time += delta

	# Smooth hop-interpolated movement for every living/downed actor
	for actor_id in controller.actors:
		var key := String(actor_id)
		var actor = controller.actors[actor_id]
		var target_pos: Vector2 = Palette.cell_center(actor.cell)
		if not actor_visual_pos.has(key):
			actor_visual_pos[key] = target_pos
		if actor_hop_state.has(key):
			var hop: Dictionary = actor_hop_state[key]
			hop["age"] = float(hop["age"]) + delta
			var u: float = clampf(float(hop["age"]) / maxf(0.05, float(hop["duration"])), 0.0, 1.0)
			var ease_u: float = 1.0 - pow(1.0 - u, 3.0)
			var base: Vector2 = Vector2(hop["from"]).lerp(target_pos, ease_u)
			var arc_y: float = -sin(u * PI) * 14.0
			actor_visual_pos[key] = base + Vector2(0.0, arc_y)
			if u >= 1.0:
				actor_visual_pos[key] = target_pos
				actor_hop_state.erase(key)
		else:
			var cur: Vector2 = actor_visual_pos[key]
			if cur.distance_to(target_pos) > 1.0:
				actor_visual_pos[key] = cur.lerp(target_pos, minf(1.0, delta * 18.0))
			else:
				actor_visual_pos[key] = target_pos

	# Decay hit flashes
	for key in actor_hit_flash.keys():
		var left: float = float(actor_hit_flash[key]) - delta * 3.8
		if left <= 0.0:
			actor_hit_flash.erase(key)
		else:
			actor_hit_flash[key] = left

	# Decay attack lunges
	for key in actor_lunge.keys():
		var vec: Vector2 = actor_lunge[key]
		vec = vec.lerp(Vector2.ZERO, minf(1.0, delta * 14.0))
		if vec.length() < 0.4:
			actor_lunge.erase(key)
		else:
			actor_lunge[key] = vec

	# Advance floating damage/shield popups
	var alive_popups: Array = []
	for item in floating_popups:
		item["age"] = float(item["age"]) + delta
		if float(item["age"]) < float(item["duration"]):
			alive_popups.append(item)
	floating_popups = alive_popups

	# Advance impact flash rings
	var alive_impacts: Array = []
	for item in impact_flashes:
		item["age"] = float(item["age"]) + delta
		if float(item["age"]) < float(item["duration"]):
			alive_impacts.append(item)
	impact_flashes = alive_impacts

	# Stepped enemy turn playback so the player clearly sees each enemy attack
	if controller.phase == ControllerScript.BattlePhase.ENEMY:
		enemy_step_timer -= delta
		if enemy_step_timer <= 0.0:
			if enemy_phase_finishing:
				enemy_phase_finishing = false
				controller.finish_enemy_phase_stepped()
				if controller.phase == ControllerScript.BattlePhase.PLAYER:
					status_message = "敌方攻势结束，轮到你的回合！"
			else:
				var ran: bool = controller.resolve_next_enemy_intent()
				if ran:
					enemy_step_timer = 0.42
				else:
					enemy_phase_finishing = true
					enemy_step_timer = 0.28

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
	var fx_state := {
		"time": fx_time,
		"hover_cell": hover_cell,
		"actor_pos": actor_visual_pos,
		"hit_flash": actor_hit_flash,
		"lunge": actor_lunge,
		"popups": floating_popups,
		"impacts": impact_flashes,
	}
	BoardViewScript.draw(self, controller, selected_skill, skill_bar, fx_state)
	HudViewScript.draw_status(self, controller, _effective_banner_message(), fx_state)
	HudViewScript.draw_party(self, controller)
	SkillBarViewScript.draw(self, controller, skill_bar, selected_skill, hovered_skill)
	if inventory_open:
		InventoryViewScript.draw(self, run_state, controller.get_active_character(), inventory_page)
	elif controller.phase == ControllerScript.BattlePhase.FINISHED:
		SettlementViewScript.draw(self, controller, _current_level(), _has_next_level(), pending_rewards, spring_mode)


func _effective_banner_message() -> String:
	var level := _current_level()
	if level == null or controller.phase != ControllerScript.BattlePhase.PLAYER:
		return status_message
	var hero = controller.get_active_character()
	if hero == null or not hero.is_alive():
		return status_message

	# Interactive step-by-step guidance for the opening turns of Lesson 1 & 2
	if level.level_id == &"lesson_charge" and controller.turn_number == 1:
		var in_danger: bool = _is_cell_in_active_telegraph(hero.cell)
		if in_danger:
			return "【引导 1/3】先锋正锁定你脚下红框蓄力！点击高亮青色格子移动 1 格即可无伤闪避。"
		if controller.damage_dealt <= 0:
			return "【引导 2/3】漂亮！现在点击下方 [2] 裁决印记（或 [1] 誓刃），再点击先锋展开反击！"
		return "【引导 3/3】点击右下角「结束回合」[空格]，观察敌方蓄力落空！"

	if level.level_id == &"lesson_lane" and controller.turn_number == 1:
		var in_danger: bool = _is_cell_in_active_telegraph(hero.cell)
		if in_danger:
			return "【引导 1/2】神射手沿直线锁定了你！斜向移出青框，或贴近至 2 格内使其狙击哑火。"
		return "【引导 2/2】已避开狙击锁格！趁机用技能反击，或点击「结束回合」推进。"

	return status_message


func _is_cell_in_active_telegraph(cell: Vector2i) -> bool:
	# Delegate to the threat layer's predicate instead of re-listing the action
	# ids here: the two lists drifted once already (this copy missed light_shot,
	# echo_bolt and basic_melee), so the teaching prompt could call a red cell
	# "safe". One source of truth keeps the hint and the red outline agreeing.
	return BoardThreatViewScript.is_cell_in_danger(controller, cell)


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
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		hovered_skill = -1
		for idx in range(skill_bar.size()):
			if SkillBarViewScript.skill_rect(idx).has_point(motion.position):
				hovered_skill = idx
				break
		var cell := Palette.cell_at(motion.position)
		if Palette.is_inside_board(cell, controller.grid_size):
			hover_cell = cell
		else:
			hover_cell = Vector2i(-1, -1)
		return
	var intent: Dictionary = InputRouterScript.translate(event)
	match intent.get("action", ""):
		InputRouterScript.ACTION_TAP:
			_handle_tap(intent["position"])
		InputRouterScript.ACTION_SKILL:
			_on_skill_pressed(int(intent["index"]))
		InputRouterScript.ACTION_CANCEL:
			if inventory_open:
				inventory_open = false
				queue_redraw()
			else:
				_cancel_target_selection()
		InputRouterScript.ACTION_END_TURN:
			if not inventory_open:
				_end_player_turn()
		InputRouterScript.ACTION_SWITCH:
			if not inventory_open:
				_switch_character()
		InputRouterScript.ACTION_ROTATE_CAM:
			if not inventory_open:
				_rotate_camera(int(intent["step"]))
		InputRouterScript.ACTION_TOGGLE_BAG:
			if controller.phase == ControllerScript.BattlePhase.PLAYER or (controller.phase == ControllerScript.BattlePhase.FINISHED and controller.battle_result == "victory"):
				inventory_open = not inventory_open
				if inventory_open:
					inventory_page = 0
				queue_redraw()


func _rotate_camera(step: int) -> void:
	Palette.board_grid_size = controller.grid_size
	Palette.rotate_camera(step)
	actor_hop_state.clear()
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		actor_visual_pos[String(actor_id)] = Palette.cell_center(actor.cell)
	status_message = "已切换至 %s（按 Q / E 旋转四角镜头）。" % Palette.camera_label()
	queue_redraw()


func _end_player_turn() -> void:
	if controller.phase != ControllerScript.BattlePhase.PLAYER:
		return
	selected_skill = -1
	if controller.start_enemy_phase_stepped():
		enemy_phase_finishing = false
		enemy_step_timer = 0.25
		status_message = "【敌方回合】敌方正在结算攻势…"
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
	if inventory_open:
		_handle_inventory_tap(position)
		return
	if controller.phase == ControllerScript.BattlePhase.FINISHED:
		_handle_settlement_tap(position)
		return
	if controller.phase != ControllerScript.BattlePhase.PLAYER:
		return

	if Palette.BAG_BTN.has_point(position):
		inventory_open = true
		queue_redraw()
		return

	for index in range(skill_bar.size()):
		if SkillBarViewScript.skill_rect(index).has_point(position):
			_on_skill_pressed(index)
			return

	if Palette.END_TURN_RECT.has_point(position):
		_end_player_turn()
		return

	if Palette.CAM_LEFT_BTN.has_point(position):
		_rotate_camera(-1)
		return

	if Palette.CAM_RIGHT_BTN.has_point(position):
		_rotate_camera(1)
		return

	var cell := Palette.cell_at(position)
	if not Palette.is_inside_board(cell, controller.grid_size):
		return

	# Clicking an intact Relic Chest explains the win-to-claim / enemy-steal rule
	if controller.beacons.has(cell) and int(controller.beacons[cell].get("health", 0)) > 0:
		status_message = "遗迹宝箱：保护至通关即可开启收进背包！若被怪拆毁，怪物会立刻获得增益。"
		queue_redraw()
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

	# A party member shares the board but is not a destination, so tapping one
	# used to fall through to the path finder and answer "cannot reach". With an
	# ally skill selected it is a target instead - including a downed member,
	# which is how Oath Shield's revival reach gets a tap surface.
	for actor_id in controller.actors:
		var member = controller.actors[actor_id]
		if member.team == "player" and (member.is_alive() or member.is_downed()) and member.cell == cell:
			if selected_skill >= 0:
				var chosen: Dictionary = skill_bar[selected_skill]
				if str(chosen["mode"]) == "ally":
					_use_skill_on(actor_id)
				else:
					status_message = "「%s」只能对敌人使用。" % str(chosen["name"])
					queue_redraw()
			else:
				status_message = "这是队伍成员所在的格子，不能移动过去。"
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


func _handle_inventory_tap(position: Vector2) -> void:
	var action: String = InventoryViewScript.hit(position, run_state.backpack.size(), inventory_page)
	var hero = controller.get_active_character()
	if action == InventoryViewScript.ACTION_CLOSE:
		inventory_open = false
		queue_redraw()
		return
	if action == InventoryViewScript.ACTION_PAGE_PREV:
		inventory_page = maxi(0, inventory_page - 1)
		queue_redraw()
		return
	if action == InventoryViewScript.ACTION_PAGE_NEXT:
		var pages: int = maxi(1, int(ceil(float(run_state.backpack.size()) / float(InventoryViewScript.PAGE_SIZE))))
		inventory_page = mini(pages - 1, inventory_page + 1)
		queue_redraw()
		return
	if action == InventoryViewScript.ACTION_UNEQUIP_WEAPON:
		var msg: String = run_state.unequip_slot("weapon", hero)
		if not msg.is_empty():
			status_message = msg
		queue_redraw()
		return
	if action == InventoryViewScript.ACTION_UNEQUIP_ARMOR:
		var msg: String = run_state.unequip_slot("armor", hero)
		if not msg.is_empty():
			status_message = msg
		queue_redraw()
		return
	if action.begins_with(InventoryViewScript.ACTION_BAG_PREFIX):
		var idx: int = int(action.substr(InventoryViewScript.ACTION_BAG_PREFIX.length()))
		var msg: String = run_state.use_backpack_item(idx, controller, hero)
		if not msg.is_empty():
			status_message = msg
		# Using/equipping an item shrinks the bag, which can leave the page past
		# the last one. Clamp so the panel never shows an empty page.
		var pages: int = maxi(1, int(ceil(float(run_state.backpack.size()) / float(InventoryViewScript.PAGE_SIZE))))
		inventory_page = clampi(inventory_page, 0, pages - 1)
		queue_redraw()


func _handle_settlement_tap(position: Vector2) -> void:
	var won: bool = controller.battle_result == "victory"
	var action: String = SettlementViewScript.hit(position, won, _has_next_level(), spring_mode)
	match action:
		SettlementViewScript.ACTION_RETURN_MAP:
			_return_to_map()
		SettlementViewScript.ACTION_OPEN_BAG:
			inventory_open = true
			queue_redraw()
		SettlementViewScript.ACTION_RESTART:
			_begin_fresh_run()
		SettlementViewScript.ACTION_NEXT:
			if _has_next_level():
				_start_level(current_level + 1)
			else:
				_begin_fresh_run()


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
	if str(skill["mode"]) == "ally":
		status_message = "已选择「%s」，点击自己或 %d 格内友军施放。" % [str(skill["name"]), int(skill["max_range"])]
	else:
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
	var event_type: String = str(event.get("type", ""))
	if event_type == "player_turn_started":
		selected_skill = -1
		skill_bar = SkillBarViewScript.build_entries(controller)
	elif event_type == "actor_moved":
		var mover_id: String = str(event.get("actor_id", ""))
		var mover = controller.get_actor(mover_id)
		if not mover_id.is_empty() and mover != null:
			var from_pos: Vector2 = actor_visual_pos.get(mover_id, Palette.cell_center(mover.cell))
			actor_hop_state[mover_id] = {"from": from_pos, "age": 0.0, "duration": 0.18}
	elif event_type == "damage_applied":
		_trigger_damage_fx(event)
	elif event_type == "beacon_damaged":
		_trigger_beacon_fx(event)
	elif event_type == "enemy_action_missed":
		_trigger_miss_fx(event)
	elif event_type == "chest_stolen_by_enemy":
		var thief_id: String = str(event.get("actor_id", ""))
		var thief = controller.get_actor(thief_id)
		if thief != null:
			floating_popups.append({
				"pos": Palette.cell_center(thief.cell) + Vector2(-46.0, -78.0),
				"text": str(event.get("detail", "夺宝强化!")),
				"color": Palette.GOLD_LIGHT,
				"age": 0.0,
				"duration": 1.35,
			})
	elif event_type == "loot_dropped":
		var dead_id: String = str(event.get("actor_id", ""))
		var dead = controller.get_actor(dead_id)
		if dead != null:
			floating_popups.append({
				"pos": Palette.cell_center(dead.cell) + Vector2(-36.0, -56.0),
				"text": str(event.get("detail", "掉落装备!")),
				"color": Palette.GOLD_PALE,
				"age": 0.0,
				"duration": 1.35,
			})
	elif event_type == "loot_picked_up":
		var hero = controller.get_active_character()
		if hero != null:
			var nm: String = str(event.get("detail", "装备"))
			status_message = "拾取了掉落装备「%s」（按 [B] 穿戴）！" % nm
			floating_popups.append({
				"pos": Palette.cell_center(hero.cell) + Vector2(-36.0, -78.0),
				"text": "拾取 " + nm,
				"color": Palette.GOLD_PALE,
				"age": 0.0,
				"duration": 1.25,
			})
	queue_redraw()


func _trigger_beacon_fx(event: Dictionary) -> void:
	var source_id: String = str(event.get("actor_id", ""))
	var detail: String = str(event.get("detail", ""))
	var applied: int = _extract_int_field(detail, "applied=")
	var source = controller.get_actor(source_id)
	for b_cell in controller.beacons:
		if str(controller.beacons[b_cell]["id"]) == str(event.get("target_id", "")):
			impact_flashes.append({"cell": b_cell, "color": Palette.TELEGRAPH_CHARGE_LINE, "age": 0.0, "duration": 0.38})
			floating_popups.append({
				"pos": Palette.cell_center(b_cell) + Vector2(-24.0, -54.0),
				"text": "宝箱 -%d" % applied,
				"color": Palette.WARN,
				"age": 0.0,
				"duration": 0.95,
			})
			if source != null:
				var dir: Vector2 = (Palette.cell_center(b_cell) - Palette.cell_center(source.cell)).normalized()
				actor_lunge[source_id] = dir * 18.0
			break


func _trigger_miss_fx(event: Dictionary) -> void:
	var source_id: String = str(event.get("actor_id", ""))
	var source = controller.get_actor(source_id)
	if source != null:
		for intent in controller.intents:
			if intent.source_actor_id == source_id:
				impact_flashes.append({"cell": intent.target_cell, "color": Palette.GOLD_LIGHT, "age": 0.0, "duration": 0.30})
				floating_popups.append({
					"pos": Palette.cell_center(intent.target_cell) + Vector2(-14.0, -24.0),
					"text": "落空",
					"color": Palette.TEXT_DIM,
					"age": 0.0,
					"duration": 0.75,
				})
				var dir: Vector2 = (Palette.cell_center(intent.target_cell) - Palette.cell_center(source.cell)).normalized()
				actor_lunge[source_id] = dir * 16.0
				break


func _trigger_damage_fx(event: Dictionary) -> void:
	var source_id: String = str(event.get("actor_id", ""))
	var target_id: String = str(event.get("target_id", ""))
	var detail: String = str(event.get("detail", ""))
	var applied: int = _extract_int_field(detail, "applied=")
	var absorbed: int = _extract_int_field(detail, "absorbed=")

	var target = controller.get_actor(target_id)
	var source = controller.get_actor(source_id)
	if target != null:
		actor_hit_flash[target_id] = 1.0
		var pos: Vector2 = actor_visual_pos.get(target_id, Palette.cell_center(target.cell)) + Vector2(-14.0, -56.0)
		if applied > 0:
			floating_popups.append({
				"pos": pos,
				"text": "-%d" % applied,
				"color": Palette.WARN if target.team == "player" else Palette.GOLD_PALE,
				"age": 0.0,
				"duration": 0.85,
			})
		elif absorbed > 0:
			floating_popups.append({
				"pos": pos,
				"text": "格挡 %d" % absorbed,
				"color": Palette.CYAN,
				"age": 0.0,
				"duration": 0.85,
			})
	if source != null and target != null and source_id != target_id:
		var src_pos: Vector2 = Palette.cell_center(source.cell)
		var dst_pos: Vector2 = Palette.cell_center(target.cell)
		var dir: Vector2 = (dst_pos - src_pos).normalized()
		actor_lunge[source_id] = dir * 16.0


static func _extract_int_field(detail: String, prefix: String) -> int:
	var idx: int = detail.find(prefix)
	if idx < 0:
		return 0
	var start: int = idx + prefix.length()
	var end: int = detail.find(" ", start)
	var raw: String = detail.substr(start) if end < 0 else detail.substr(start, end - start)
	return int(raw) if raw.is_valid_int() else 0


func _on_battle_finished(result: String) -> void:
	inventory_open = false
	if result == "victory":
		pending_rewards = controller.collect_remaining_chests()
		var hero = controller.get_active_character()
		if hero != null and run_state != null:
			run_state.sync_from_actor(hero)
		if spring_mode:
			status_message = "战斗胜利！保住 %d 个遗迹宝箱，战利品已收入背包。按 B 查看，或点「返回春之境」继续探索。" % pending_rewards.size()
		else:
			status_message = "遭遇战胜利！保住 %d 个遗迹宝箱，战利品已收入背包。按 B 打开背包穿戴装备 / 激活铭文后再进下一关。" % pending_rewards.size()
	else:
		pending_rewards.clear()
		if spring_mode:
			status_message = "战斗失败。返回春之境后可消耗补给续行一次。"
		else:
			status_message = "遭遇战失败，点击重开将清空本局装备与背包重新开始。"
	queue_redraw()
