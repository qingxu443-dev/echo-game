extends Node2D

## Battle screen orchestrator.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const LevelCatalogScript = preload("res://scripts/battle/level_catalog.gd")
const Palette = preload("res://scripts/ui/theme_palette.gd")
const BoardViewScript = preload("res://scripts/ui/board_view.gd")
const BoardThreatViewScript = preload("res://scripts/ui/board_threat_view.gd")
const HudViewScript = preload("res://scripts/ui/hud_view.gd")
const SkillBarViewScript = preload("res://scripts/ui/skill_bar_view.gd")
const SkillInput = preload("res://scripts/ui/battle_skill_input.gd")
const SettlementViewScript = preload("res://scripts/ui/settlement_view.gd")
const InputRouterScript = preload("res://scripts/ui/input_router.gd")
const RunStateScript = preload("res://scripts/battle/run_state.gd")
const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")
const InventoryViewScript = preload("res://scripts/ui/inventory_view.gd")
const InventoryInput = preload("res://scripts/ui/battle_inventory_input.gd")
const SpringBattleBridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")
const SpringEncounterCatalogScript = preload("res://scripts/spring/spring_encounter_catalog.gd")
const SpringRunScript = preload("res://scripts/spring/spring_run.gd")
const SpringSettlementHandoffScript = preload("res://scripts/spring/spring_battle_settlement_handoff.gd")

## Prototype skill bar. Self-target skills resolve on press; actor-target skills wait for confirmation.
## Number keys 1–5 mirror the visible order, and nothing is selected by default.
## Rebuilt from the active character's sheet whenever the command switches.
var skill_bar: Array = []

var atelier_save_path := AtelierStash.SAVE_PATH
var controller: BattleController
var run_state: RunStateScript
var pending_rewards: Array[Dictionary] = []
var levels: Array[EncounterDefinition] = []
var current_level: int = 0
var status_message: String = "点击格子移动；点右侧技能后选择目标。"
var selected_skill: int = -1

## Procedural animation & visual feedback state (P1: owned by BattleFxState).
var fx: BattleFxState = BattleFxState.new()
var hover_cell: Vector2i = Vector2i(-1, -1)
var hovered_skill: int = -1
var inventory_open: bool = false
var inventory_page: int = 0
## True when this scene was opened by the 春之境 map for a single fight. The
## campaign path (three lessons in a row) is untouched and stays the default.
var spring_mode: bool = false
## Optional isolated authoring scene; the normal tutorial playlist stays fixed.
@export var encounter_override: EncounterDefinition

func _ready() -> void:
	var suspended := SessionSave.consume("battle")
	if not suspended.is_empty() and BattleSession.restore(self, suspended):
		SessionSave.clear()
		return
	var claim_requested := SpringBattleBridgeScript.consume_tutorial_loadout_request()
	if SpringBattleBridgeScript.has_pending():
		_begin_spring_fight()
		return
	levels = LevelCatalogScript.create_prototype_levels()
	if encounter_override != null: levels.assign([encounter_override])
	run_state = RunStateScript.new()
	controller = ControllerScript.new()
	controller.run_state = run_state
	add_child(controller)
	controller.battle_event.connect(_on_battle_event)
	controller.battle_finished.connect(_on_battle_finished)
	skill_bar = SkillBarViewScript.build_entries(controller)
	_begin_fresh_run()
	if claim_requested and controller.phase == controller.BattlePhase.PLAYER:
		var claim := AtelierStash.claim_loadout(atelier_save_path)
		if not claim["ok"]:
			status_message = "工坊补给未领取，原打包栏已保留。"
		for item in claim.get("items", []):
			run_state.add_to_backpack(item)

## One fight, injected from the map. Everything the run needs arrives in the
## bridge payload; nothing is read from the save here, so a fight is always
## against exactly the run the map handed over.
func _begin_spring_fight() -> void:
	spring_mode = true
	var payload: Dictionary = SpringBattleBridgeScript.pending
	var encounter_id := StringName(str(payload.get("encounter", "")))
	var party_ids: Array[String] = []
	for character_id in payload.get("character_ids", [SpringRunScript.HERO_CHARACTER_ID]):
		party_ids.append(str(character_id))
	var definition := SpringEncounterCatalogScript.build(encounter_id, party_ids)
	if definition == null:
		push_error("春之境：遭遇 %s 无法构建，直接返回地图。" % String(encounter_id))
		var fallback_result := {
			"result": "defeat",
			"kind": str(payload.get("kind", SpringBattleBridgeScript.KIND_BATTLE)),
			"place": str(payload.get("place", "")),
			"hero_health": int(payload.get("hero_health", 1)),
			"hero_max_health": int(payload.get("hero_max_health", 1)),
			"seed": int(payload.get("hero_health", 1)),
		}
		_open_spring_settlement(fallback_result)
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
	_restore_spring_party_vitals(payload)

## Hands the outcome back to the map scene. Called from the settlement button.
func _spring_run_lead():
	return SpringSettlementHandoffScript.run_lead(self)

func _restore_spring_party_vitals(payload: Dictionary) -> void:
	SpringBattleBridgeScript.restore_party_vitals(controller, payload)

func _return_to_map() -> void:
	var hero = _spring_run_lead()
	var payload: Dictionary = SpringBattleBridgeScript.pending
	var party_vitals: Dictionary = {}
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		if actor.team == "player":
			party_vitals[str(actor_id)] = {"health": actor.health, "max_health": actor.max_health}
	var result := {
		"result": controller.battle_result,
		"kind": str(payload.get("kind", SpringBattleBridgeScript.KIND_BATTLE)),
		"place": str(payload.get("place", "")),
		"hero_health": hero.health if hero != null else 1,
		"hero_max_health": hero.max_health if hero != null else 1,
		"party_vitals": party_vitals,
		"carry": SpringBattleBridgeScript.pack_carry(run_state),
		"chests_saved": pending_rewards.size(),
		"loot": pending_rewards.duplicate(true),
		"seed": run_state.loot_seed,
	}
	if spring_mode:
		_open_spring_settlement(result)
		return
	SpringBattleBridgeScript.last_result = result
	SpringBattleBridgeScript.clear_pending()
	var error := SceneTravel.change(get_tree(), SpringBattleBridgeScript.MAP_SCENE_PATH)
	if error != OK:
		push_error("无法返回春之境。Error: %s" % error)


func _open_spring_settlement(result: Dictionary) -> void:
	SpringSettlementHandoffScript.open(self, result)

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
	var law_error := EncounterLaws.describe_error(level.anomaly_overrides)
	if not law_error.is_empty():
		status_message = "关卡异象无效：" + law_error
		queue_redraw()
		return
	selected_skill = -1
	pending_rewards.clear()
	# A rejected setup leaves the previous encounter untouched, so say so instead
	# of showing a fresh-looking screen that will not accept any action.
	# §11.1 applies to the spring run: its fights start with a deployment phase.
	# The tutorial lessons keep the old direct start, because their opening beats
	# teach a turn action ("move one tile") rather than a placement.
	if not controller.start_encounter(level.player_cell, level.enemy_cells, level.obstacles, level.enemy_archetypes, level.character_ids, level.ally_cells, level.chest_items, level.ward_nodes, level.deploy_cells, spring_mode, level.enemy_stat_multiplier, level.anomaly_overrides):
		status_message = "关卡「%s」数据无效，未能开始。" % str(level.display_name_zh)
		queue_redraw()
		return
	current_level = index
	status_message = level.tactical_hint_zh
	skill_bar = SkillBarViewScript.build_entries(controller)
	_reset_fx_for_encounter()
	SceneTravel.reveal(self, str(level.display_name_zh))
	queue_redraw()

func _reset_fx_for_encounter() -> void:
	fx.reset_for_encounter(controller)

func _process(delta: float) -> void:
	fx.advance(delta, controller)

	# Stepped enemy turn playback so the player clearly sees each enemy attack
	if controller.phase == ControllerScript.BattlePhase.ENEMY:
		var msg: String = fx.step_enemy_phase(delta, controller)
		if not msg.is_empty():
			status_message = msg

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
	var fx_state := fx.snapshot(hover_cell)
	BoardViewScript.draw(self, controller, selected_skill, skill_bar, fx_state)
	HudViewScript.draw_status(self, controller, _effective_banner_message(), fx_state)
	HudViewScript.draw_party(self, controller)
	SkillBarViewScript.draw(self, controller, skill_bar, selected_skill, hovered_skill)
	if inventory_open:
		InventoryViewScript.draw(self, run_state, InventoryInput.lead_actor(self), inventory_page)
	elif controller.phase == ControllerScript.BattlePhase.FINISHED:
		SettlementViewScript.draw(self, controller, _current_level(), _has_next_level(), pending_rewards, spring_mode)

## The active character's display name, for prompts that name who is being
## placed. Read from the sheet so swapping the lead does not leave a stale name
## in the banner.
func _hero_name() -> String:
	return BattleBannerText.hero_name(controller)

func _effective_banner_message() -> String:
	return BattleBannerText.effective_message(controller, _current_level(), status_message)

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
	if SceneTravel.intercept(self, event): return
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
	fx.snap_actor_positions(controller)
	hover_cell = Vector2i(-1, -1)
	status_message = "已切换至 %s（按 Q / E 旋转四角镜头）。" % Palette.camera_label()
	queue_redraw()

func _end_player_turn() -> void:
	if controller.phase != ControllerScript.BattlePhase.PLAYER:
		return
	selected_skill = -1
	if controller.start_enemy_phase_stepped():
		fx.prepare_enemy_step()
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

## §11.1: no AP, no turn, no enemy action - the only two verbs here are "put the
## character somewhere in the zone" and "confirm".
func _handle_deploy_tap(position: Vector2) -> void:
	if Palette.END_TURN_RECT.has_point(position):
		if controller.request_begin_battle():
			fx.snap_actor_positions(controller)
			status_message = "部署完成，正式开战。"
		else:
			status_message = "还有角色没有就位，无法开战。"
		queue_redraw()
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
	if not controller.is_deploy_cell(cell):
		status_message = "只能部署在南侧高亮区，不能进入敌方区域。"
		queue_redraw()
		return
	if controller.request_deploy(cell):
		status_message = "已就位。确认前可继续点击其他高亮格调整位置，然后点右下角「确认部署」。"
	else:
		status_message = "该格无法部署（障碍或已被占据）。"
	queue_redraw()

func _handle_tap(position: Vector2) -> void:
	if inventory_open:
		_handle_inventory_tap(position)
		return
	if controller.phase == ControllerScript.BattlePhase.FINISHED:
		_handle_settlement_tap(position)
		return
	if controller.phase == ControllerScript.BattlePhase.DEPLOY:
		_handle_deploy_tap(position)
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

	if selected_skill >= 0 and str(skill_bar[selected_skill]["mode"]) == "cell":
		SkillInput.cast(self, skill_bar[selected_skill], "", cell)
		return

	if controller.beacons.has(cell) and int(controller.beacons[cell].get("health", 0)) > 0:
		var b: Dictionary = controller.beacons[cell]
		if str(b.get("kind", "")) == "ward_node":
			if selected_skill >= 0: _use_skill_on(str(b["id"]))
			else: status_message = "春之结界：为首领提供 +80 防御！请先选攻击技能再点击击破。"; queue_redraw()
			return
		status_message = "遗迹宝箱：保护至通关即可开启收进背包！若被怪拆毁，怪物会立刻获得增益。"; queue_redraw(); return

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

	if selected_skill >= 0:
		status_message = "当前技能需要目标；点击合法目标或右键取消，未消耗 AP。"
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
	InventoryInput.handle(self, position)

func _handle_settlement_tap(position: Vector2) -> void:
	if not BattleRewards.settle(controller, spring_mode, atelier_save_path):
		status_message = "战后残晶保存失败，当前战果已保留，请检查存档位置后重试。"
		queue_redraw()
		return
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
	SkillInput.select(self, index)

func _use_skill_on(actor_id: String) -> void:
	SkillInput.cast(self, skill_bar[selected_skill], actor_id)

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
	if event_type == "actor_moved": SceneTravel.sound(self, "move")
	elif event_type == "damage_applied": SceneTravel.sound(self, "hit")
	var out_status: Array = []
	var out_selected: Array = []
	fx.on_event(event_type, event, controller, out_status, out_selected)
	if not out_status.is_empty():
		status_message = str(out_status[0])
	if not out_selected.is_empty():
		selected_skill = int(out_selected[0])

	# 技能栏重建仍由 view 负责（需要 controller 的当前角色数据）
	if event_type == "player_turn_started":
		skill_bar = SkillBarViewScript.build_entries(controller)

	queue_redraw()

func _on_battle_finished(result: String) -> void:
	inventory_open = false
	var rewards_saved := BattleRewards.settle(controller, spring_mode, atelier_save_path)
	if result == "victory":
		pending_rewards = controller.collect_remaining_chests()
		var hero = _spring_run_lead() if spring_mode else controller.get_active_character()
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
	if not rewards_saved:
		status_message += " 残晶保存失败，离开前请重试结算。"
	queue_redraw()
