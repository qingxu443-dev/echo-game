extends "res://tests/framework/test_case.gd"

## P1 拆分的契约钉子：battle_view 的全部瞬态 FX 状态由 BattleFxState 持有。
##
## 锁定四件事：
##   1. snapshot 的键集合与下游 board/hud 视图的旧字典契约一致（零改动迁移）
##   2. reset_for_encounter / snap_actor_positions 把视觉位置对齐到当前格
##   3. advance 推进时间并老化飘字 / 冲击环 / 受击闪烁
##   4. on_event 把 actor_moved / damage_applied / loot_picked_up 等事件
##      转成正确的 FX，且通过 out_status/out_selected 传出 view 层副作用

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const LevelCatalogScript = preload("res://scripts/battle/level_catalog.gd")
const Palette = preload("res://scripts/ui/theme_palette.gd")


func _run() -> void:
	_test_snapshot_contract()
	_test_reset_aligns_actor_positions()
	_test_advance_ages_transient_fx()
	_test_move_event_sets_hop()
	_test_damage_event_sets_flash_and_popup()
	_test_loot_event_reports_status()
	_test_snap_after_camera_rotation()
	_test_rectangular_board_projection()
	_test_enemy_step_prep()
	_test_banner_text_delegation()


func _fresh_controller() -> BattleController:
	var controller = ControllerScript.new()
	root.add_child(controller)
	var level: EncounterDefinition = LevelCatalogScript.create_prototype_levels()[0]
	controller.start_encounter(level.player_cell, level.enemy_cells, level.obstacles, level.enemy_archetypes, level.character_ids, [], level.chest_items)
	return controller


func _test_snapshot_contract() -> void:
	var fx := BattleFxState.new()
	var snap: Dictionary = fx.snapshot(Vector2i(2, 3))
	var required: Array[String] = ["time", "hover_cell", "actor_pos", "hit_flash", "lunge", "popups", "impacts"]
	for key in required:
		_check(snap.has(key), "snapshot keeps downstream key: %s" % key)
	_check(snap["hover_cell"] == Vector2i(2, 3), "snapshot carries the hover cell")
	_check(snap["time"] == 0.0, "snapshot starts at time zero")


func _test_reset_aligns_actor_positions() -> void:
	var controller := _fresh_controller()
	var fx := BattleFxState.new()
	fx.reset_for_encounter(controller)
	_check(fx.actor_visual_pos.size() == controller.actors.size(), "reset seeds a visual position for every actor")
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		_check(fx.actor_visual_pos.has(String(actor_id)), "reset covers actor %s" % String(actor_id))
		_check(fx.actor_visual_pos[String(actor_id)] == Palette.cell_center(actor.cell), "actor %s aligned to its cell" % String(actor_id))
	_check(fx.floating_popups.is_empty() and fx.impact_flashes.is_empty(), "reset clears transient FX")


func _test_advance_ages_transient_fx() -> void:
	var controller := _fresh_controller()
	var fx := BattleFxState.new()
	fx.reset_for_encounter(controller)
	fx.floating_popups.append({"age": 0.0, "duration": 0.2, "pos": Vector2.ZERO, "text": "x", "color": Color.WHITE})
	fx.impact_flashes.append({"age": 0.0, "duration": 0.2, "cell": Vector2i.ZERO, "color": Color.WHITE})
	fx.actor_hit_flash["hero"] = 0.5
	fx.advance(0.1, controller)
	_check(fx.time > 0.0, "advance moves the FX clock")
	_check(fx.floating_popups.size() == 1, "popup alive before its duration elapses")
	fx.advance(0.2, controller)
	_check(fx.floating_popups.is_empty(), "popup removed after its duration")
	_check(fx.impact_flashes.is_empty(), "impact flash removed after its duration")
	_check(not fx.actor_hit_flash.has("hero"), "hit flash decays away")


func _test_move_event_sets_hop() -> void:
	var controller := _fresh_controller()
	var fx := BattleFxState.new()
	fx.reset_for_encounter(controller)
	var actor_id: String = ""
	for key in controller.actors:
		actor_id = String(key)
		break
	var status: Array = []
	var selected: Array = []
	var handled: bool = fx.on_event("actor_moved", {"actor_id": actor_id}, controller, status, selected)
	_check(handled, "actor_moved is consumed by the FX component")
	_check(fx.actor_hop_state.has(actor_id), "actor_moved creates a hop for the mover")
	var hop: Dictionary = fx.actor_hop_state[actor_id]
	_check(float(hop["duration"]) > 0.0, "hop has a positive duration")
	_check(status.is_empty() and selected.is_empty(), "movement has no view-layer side effect")


func _test_damage_event_sets_flash_and_popup() -> void:
	var controller := _fresh_controller()
	var fx := BattleFxState.new()
	fx.reset_for_encounter(controller)
	var target_id: String = ""
	for key in controller.actors:
		target_id = String(key)
		break
	var status: Array = []
	var selected: Array = []
	var handled: bool = fx.on_event("damage_applied", {
		"actor_id": target_id,
		"target_id": target_id,
		"detail": "applied=120 absorbed=0",
	}, controller, status, selected)
	_check(handled, "damage_applied is consumed by the FX component")
	_check(fx.actor_hit_flash.has(target_id), "damage flags a hit flash on the target")
	_check(fx.floating_popups.size() >= 1, "damage spawns a popup")
	_check(str(fx.floating_popups[0]["text"]) == "-120", "popup shows the applied damage")


func _test_loot_event_reports_status() -> void:
	var controller := _fresh_controller()
	var fx := BattleFxState.new()
	fx.reset_for_encounter(controller)
	var status: Array = []
	var selected: Array = []
	fx.on_event("loot_picked_up", {"detail": "遗迹铁壁甲"}, controller, status, selected)
	_check(status.size() == 1, "loot pickup emits one status line")
	_check(str(status[0]).contains("遗迹铁壁甲"), "status names the picked-up item")
	_check(fx.floating_popups.size() == 1, "loot pickup spawns a popup")


func _test_snap_after_camera_rotation() -> void:
	var controller := _fresh_controller()
	var fx := BattleFxState.new()
	fx.reset_for_encounter(controller)
	var actor_id: String = ""
	for key in controller.actors:
		actor_id = String(key)
		break
	fx.actor_hop_state[actor_id] = {"from": Vector2.ZERO, "age": 0.0, "duration": 0.18}
	fx.snap_actor_positions(controller)
	_check(fx.actor_hop_state.is_empty(), "camera snap interrupts in-flight hops")
	var actor = controller.get_actor(actor_id)
	_check(fx.actor_visual_pos[actor_id] == Palette.cell_center(actor.cell), "camera snap aligns to the new projection")


func _test_enemy_step_prep() -> void:
	var fx := BattleFxState.new()
	fx.enemy_phase_finishing = true
	fx.enemy_step_timer = 9.0
	fx.prepare_enemy_step()
	_check(not fx.enemy_phase_finishing, "enemy step prep clears the finishing flag")
	_check(fx.enemy_step_timer > 0.0, "enemy step prep schedules the first step")


func _test_banner_text_delegation() -> void:
	var controller := _fresh_controller()
	var level: EncounterDefinition = LevelCatalogScript.create_prototype_levels()[0]
	# 部署阶段提示应包含主角名字，且明确说明部署不耗 AP
	controller.phase = controller.BattlePhase.DEPLOY
	var deploy_msg: String = BattleBannerText.effective_message(controller, level, "fallback")
	_check(deploy_msg.contains("部署阶段"), "banner shows the deploy-phase hint")
	_check(deploy_msg.contains("不消耗行动点"), "deploy hint states the no-AP rule")
	# 非教学关卡回落原状态
	controller.phase = controller.BattlePhase.FINISHED
	var fallback: String = BattleBannerText.effective_message(controller, null, "原样消息")
	_check(fallback == "原样消息", "banner falls back to the caller status outside lessons")
	# hero_name 有非空中文回落
	_check(not BattleBannerText.hero_name(controller).is_empty(), "hero name never empty")


func _test_rectangular_board_projection() -> void:
	var old_size := Palette.board_grid_size
	var old_camera := Palette.camera_quadrant
	Palette.board_grid_size = Vector2i(6, 9)
	for quadrant in range(4):
		Palette.camera_quadrant = quadrant
		var expected := Vector2i(6, 9) if quadrant % 2 == 0 else Vector2i(9, 6)
		var view_size := Palette.view_grid_size()
		_check(view_size == expected, "rectangular board view bounds match camera quadrant %d" % quadrant)
		var tiles := {}
		for x in range(view_size.x):
			for y in range(view_size.y):
				var logical := Palette.from_view_cell(Vector2i(x, y))
				if Rect2i(Vector2i.ZERO, Palette.board_grid_size).has_point(logical):
					tiles[logical] = true
		_check(tiles.size() == 54, "the renderer can visit every logical tile in quadrant %d" % quadrant)
	Palette.board_grid_size = old_size
	Palette.camera_quadrant = old_camera
