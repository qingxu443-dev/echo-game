extends "res://tests/framework/test_case.gd"

const MainScene = preload("res://scenes/main/main.tscn")
const MapView = preload("res://scripts/spring/spring_map_view.gd")
const P = preload("res://scripts/ui/theme_palette.gd")


func _run() -> void:
	_test_equipment_health_is_reversible()
	_test_unaffordable_continue_is_inert()
	await _test_empty_tile_cast()
	await _test_selected_attack_does_not_move()
	await _test_sakura_ap_costs()
	await _test_kill_refunds_are_visible()
	await _test_deployment_visibility()
	await _test_camera_stress()
	await _test_highlight_composition()
	_test_compact_threat_labels()
	_test_compact_reactive_warnings()
	await _test_area_cast_rejections()
	var shell = root.get_node_or_null("GameShell")
	if shell != null:
		for voice in shell.audio.voices:
			voice.stop()
			voice.stream = null
		await create_timer(0.12, true).timeout


func _test_compact_threat_labels() -> void:
	var battle := BattleController.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(3, 5), [Vector2i(3, 3), Vector2i(5, 3)], [], ["vanguard", "area_controller"]), "label fixture starts through normal encounter setup")
	battle.beacons.clear()
	var hero = battle.get_active_character()
	var before: int = hero.health
	var area: Array[Vector2i] = [hero.cell, Vector2i(4, 5)]
	var red := BattleIntent.new("red", "vanguard_00", "charged_strike", BattleIntent.TargetMode.AREA_LOCKED, "", hero.cell, area, 150)
	var purple := BattleIntent.new("purple", "area_controller_01", "ground_pulse", BattleIntent.TargetMode.AREA_LOCKED, "", hero.cell, area, 100, 1, "magical")
	battle.intents.assign([red, purple])
	var labels := BoardThreatView.label_entries(battle, {})
	_check(labels.size() == 1 and labels.has(hero.cell), "default board numbers are limited to the active character's tile")
	_check(labels[hero.cell].size() == 2, "the current tile retains every announced hit")
	labels = BoardThreatView.label_entries(battle, {"hover_cell": Vector2i(4, 5)})
	_check(labels.size() == 2 and labels[Vector2i(4, 5)].size() == 2, "hovering an outer area tile shows its real damage despite not being the original aim cell")
	labels = BoardThreatView.label_entries(battle, {"hover_cell": Vector2i(3, 3)})
	_check(labels[hero.cell].size() == 2, "focusing one enemy never hides other incoming hits from the character label")
	_check(BoardThreatView.label_entries(battle, {"hover_cell": hero.cell}).size() == 1, "hover on the character does not duplicate the label")
	_check(BoardThreatView.label_entries(battle, {"hover_cell": Vector2i(20, 20)}).size() == 1, "off-board hover never creates a chip")
	purple.cancel("fixture_cancel")
	labels = BoardThreatView.label_entries(battle, {})
	_check(labels[hero.cell].size() == 1, "cancelled attacks immediately leave the compact labels")
	_check(hero.health == before and battle.ap.current == 3, "compact projection does not spend AP or health")
	battle.queue_free()


func _test_compact_reactive_warnings() -> void:
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(3, 4), [Vector2i(3, 3)])
	battle.beacons.clear()
	var intent := BattleIntent.new("reactive", "vanguard_00", "basic_melee", BattleIntent.TargetMode.TILE_LOCKED, "", Vector2i(2, 3), [], 100)
	battle.intents.assign([intent])
	var once := BoardThreatView.caution_tiles(battle, {})
	_check(once.has(Vector2i(3, 4)), "conditional warning still covers the actual eligible target")
	battle.intents.append(intent)
	_check(BoardThreatView.caution_tiles(battle, {}) == once, "duplicate warnings do not add fill, outlines or opacity")
	_check(is_equal_approx(float(once.get(Vector2i(3, 4), 0.0)), 0.9), "current character warning retains its emphasis")
	intent.cancel("fixture_cancel")
	_check(BoardThreatView.caution_tiles(battle, {}).is_empty(), "cancelled conditional attacks leave no warning tiles")
	battle.queue_free()


func _test_equipment_health_is_reversible() -> void:
	for with_actor in [false, true]:
		var state := RunState.new()
		state.reset(1800, 520, 180, 111)
		state.hero_health = 600
		var actor = BattleActor.new("sakura", "player", Vector2i.ONE, 1800)
		actor.health = 600
		state.add_to_backpack({"id": "hp_armor", "kind": "armor", "max_health": 400})
		for cycle in range(5):
			state.equip_from_backpack(0, actor if with_actor else null)
			_check(state.hero_health == 1000 and state.hero_max_health == 2200, "equip adds health once, cycle %d actor=%s" % [cycle, with_actor])
			state.unequip_slot("armor", actor if with_actor else null)
			_check(state.hero_health == 600 and state.hero_max_health == 1800, "unequip reclaims health, cycle %d actor=%s" % [cycle, with_actor])
		state.add_to_backpack({"id": "hp_weapon", "kind": "weapon", "max_health": 200})
		state.equip_from_backpack(0, actor if with_actor else null)
		state.equip_from_backpack(0, actor if with_actor else null)
		_check(state.hero_health == 1200 and state.hero_max_health == 2400, "weapon and armor health stack symmetrically")
		state.add_to_backpack({"id": "smaller_armor", "kind": "armor", "max_health": 100})
		state.equip_from_backpack(0, actor if with_actor else null)
		_check(state.hero_health == 900 and state.hero_max_health == 2100, "swapping to smaller armor also reclaims current health")
		if with_actor:
			actor.health = 0
			state.unequip_slot("armor", actor)
			_check(actor.health == 0, "equipment changes never revive a downed actor")


func _test_unaffordable_continue_is_inert() -> void:
	var map = MapView.new()
	map.run = SpringRun.begin(91)
	map.run.supplies = 0
	map.run.revive_prompt = true
	map.save_path = "user://playtest-continue.json"
	map._handle_revive_tap(map.REVIVE_YES.get_center())
	_check(not map.run.exploration.finished, "disabled continue does not end the run")
	_check(map.run.revive_prompt and not map.run.revive_used, "disabled continue preserves the choice")
	_check(map.run.supplies == 0, "disabled continue keeps supplies")
	_check(not FileAccess.file_exists(map.save_path), "disabled continue never writes a failed-run save")
	map.run.supplies = SpringBattleBridge.CONTINUE_SUPPLY_COST
	map.run.revive_used = true
	map._handle_revive_tap(map.REVIVE_YES.get_center())
	_check(map.run.revive_prompt and not map.run.exploration.finished, "already-used continue also ignores clicks")
	map.run.revive_used = false
	map._handle_revive_tap(map.REVIVE_YES.get_center())
	_check(not map.run.revive_prompt and map.run.revive_used and map.run.supplies == 0, "affordable continue pays once and closes prompt")
	map._handle_revive_tap(map.REVIVE_YES.get_center())
	_check(not map.run.exploration.finished and map.run.supplies == 0, "repeated continue cannot end or charge the run")
	map.run.revive_prompt = true
	map._handle_revive_tap(map.REVIVE_NO.get_center())
	_check(map.run.exploration.finished, "explicit finish still ends the failed run")
	DirAccess.remove_absolute(map.save_path)
	map.free()


func _sakura_view():
	var view = MainScene.instantiate()
	root.add_child(view)
	view.run_state.reset(1800, 520, 180, 111)
	var battle: BattleController = view.controller
	battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3), Vector2i(7, 0)], [], [], ["sakura"])
	for actor in view.controller.actors.values():
		if actor.team == "enemy":
			actor.max_health = 100000
			actor.health = 100000
			actor.armor_layers = 0
	view.controller.beacons.clear()
	view.skill_bar = SkillBarView.build_entries(view.controller)
	view._reset_fx_for_encounter()
	return view


func _tap(view, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	view._input(event)


func _select(view, skill_id: String) -> void:
	for index in range(view.skill_bar.size()):
		if view.skill_bar[index]["id"] == skill_id:
			_tap(view, SkillBarView.skill_rect(index).get_center())
			return
	_check(false, "skill exists in UI: " + skill_id)


func _test_empty_tile_cast() -> void:
	var view = _sakura_view()
	var enemy = view.controller.get_actor("vanguard_00")
	var before: int = enemy.health
	_select(view, "sakura_falling_petals")
	_tap(view, P.cell_center(Vector2i(5, 3)))
	_check(enemy.health < before, "Falling Petals aimed at empty tile hits its area")
	_check(view.controller.ap.current == 1, "empty tile area cast costs exactly two AP")
	_check(view.controller.get_active_character().cell == Vector2i(3, 3), "area cast never falls through to movement")
	_check(view.selected_skill == -1, "successful cast returns to movement hints")
	view.queue_free()
	await process_frame


func _test_selected_attack_does_not_move() -> void:
	var view = _sakura_view()
	_select(view, "sakura_pierce_blossom")
	_tap(view, P.cell_center(Vector2i(3, 4)))
	_check(view.controller.ap.current == 3, "invalid attack target spends no AP")
	_check(view.controller.get_active_character().cell == Vector2i(3, 3), "selected attack on empty tile cannot silently move")
	view.queue_free()
	await process_frame


func _test_sakura_ap_costs() -> void:
	for skill_id in ["sakura_pierce_blossom", "sakura_flowing_wind", "sakura_falling_petals", "sakura_endless_fragrance"]:
		var view = _sakura_view()
		var battle: BattleController = view.controller
		var skill := SkillRegistry.get_skill(StringName(skill_id))
		var caster = battle.get_active_character()
		battle.ap.maximum = 5
		battle.ap.reset()
		for cast_index in range(2):
			caster.ultimate_energy = caster.ultimate_energy_max
			_select(view, skill_id)
			if skill.target_mode != SkillDefinition.TARGET_SELF:
				_check(battle.ap.current == 5 - cast_index * skill.ap_cost, "selection is free: %s #%d" % [skill_id, cast_index + 1])
				_tap(view, P.cell_center(battle.get_actor("vanguard_00").cell))
			_check(battle.ap.current == 5 - (cast_index + 1) * skill.ap_cost, "each confirmed skill pays its own cost: %s #%d" % [skill_id, cast_index + 1])
			_check(view.selected_skill == -1, "each completed cast clears aim: " + skill_id)
			_check(String(view.status_message).contains("消耗 %d AP" % skill.ap_cost), "cast feedback names the actual cost: " + skill_id)
		battle.ap.current = 0
		var health_before: int = battle.get_actor("vanguard_00").health
		caster.ultimate_energy = caster.ultimate_energy_max
		_select(view, skill_id)
		_tap(view, P.cell_center(battle.get_actor("vanguard_00").cell))
		_check(battle.ap.current == 0 and battle.get_actor("vanguard_00").health == health_before, "unaffordable skill is inert: " + skill_id)
		view.queue_free()
		await process_frame


func _test_kill_refunds_are_visible() -> void:
	var view = _sakura_view()
	var battle: BattleController = view.controller
	for index in range(3):
		var target := BattleActor.new("refund_%d" % index, "enemy", Vector2i(4, 3), 1)
		battle.get_actor("vanguard_00").cell = Vector2i(6, 6)
		battle.actors[target.actor_id] = target
		_select(view, "sakura_pierce_blossom")
		_tap(view, P.cell_center(target.cell))
		_check(target.is_defeated(), "refund scenario executes a real kill")
		_check(battle.ap.current == (3 if index < 2 else 2), "kill refunds stop at the existing two-per-turn cap")
		_check(String(view.status_message).contains("击杀返还 1 AP") == (index < 2), "AP message distinguishes spend from refund")
	view.queue_free()
	await process_frame


func _test_deployment_visibility() -> void:
	var view = _sakura_view()
	var battle: BattleController = view.controller
	battle.start_encounter(Vector2i(3, 6), [Vector2i(3, 1)], [], [], ["sakura"], [], [], 0, [], true)
	view._reset_fx_for_encounter()
	var hero = battle.get_actor("sakura")
	_check(not BoardObjectsView.is_actor_visible(battle, hero), "Sakura's placeholder is hidden during deployment")
	_check(BoardObjectsView.is_actor_visible(battle, battle.get_actor("vanguard_00")), "enemies remain visible for deployment planning")
	_check(not battle.request_begin_battle(), "hidden placeholder does not count as deployed")
	_tap(view, P.cell_center(Vector2i(4, 6)))
	_check(battle.deploy_index == 1 and not BoardObjectsView.is_actor_visible(battle, hero), "deployment marks a cell without showing the actor")
	_tap(view, P.END_TURN_RECT.get_center())
	_check(battle.phase == battle.BattlePhase.PLAYER and hero.cell == Vector2i(4, 6), "confirmation starts on the chosen cell")
	_check(BoardObjectsView.is_actor_visible(battle, hero), "Sakura becomes visible after confirmation")
	_check(view.fx.actor_visual_pos["sakura"] == P.cell_center(hero.cell), "confirmation snaps the first visible frame to the chosen tile")
	battle.start_encounter(Vector2i(3, 6), [Vector2i(3, 1)], [], [], ["sevrin", "sakura"], [Vector2i(4, 6)], [], 0, [], true)
	_check(battle.request_deploy(Vector2i(4, 6)), "an undeployed hidden placeholder does not occupy a deploy tile")
	_check(not battle.request_deploy(Vector2i(4, 6)), "a confirmed party deployment still occupies its tile")
	_check(battle.request_deploy(Vector2i(5, 6)) and battle.request_begin_battle(), "both party members deploy without overlap")
	view.queue_free()
	await process_frame


func _test_camera_stress() -> void:
	var view = _sakura_view()
	var battle: BattleController = view.controller
	var initial_quadrant: int = P.camera_quadrant
	view.set_process(false)
	var draws := {"count": 0}
	view.draw.connect(func(): draws["count"] += 1)
	var projects_correctly := true
	var positions_match := true
	for index in range(128):
		view.fx.actor_lunge["sakura"] = Vector2(10, 0)
		view.hover_cell = Vector2i(3, 3)
		_tap(view, (P.CAM_LEFT_BTN if index % 3 == 0 else P.CAM_RIGHT_BTN).get_center())
		for y in range(battle.grid_size.y):
			for x in range(battle.grid_size.x):
				var cell := Vector2i(x, y)
				projects_correctly = projects_correctly and P.cell_at(P.cell_center(cell)) == cell
		positions_match = positions_match and view.fx.actor_visual_pos["sakura"] == P.cell_center(battle.get_actor("sakura").cell)
		await process_frame
	_check(draws["count"] >= 120, "128 repeated camera clicks keep the draw loop running")
	_check(projects_correctly and positions_match, "all rotations preserve grid picking and actor projection")
	_check(view.hover_cell == Vector2i(-1, -1) and view.fx.actor_lunge.is_empty(), "rotation discards old projection hover and lunge")
	_check(battle.turn_number == 1 and battle.ap.current == 3, "rotation never spends AP or advances the turn")
	battle.start_enemy_phase_stepped()
	view.fx.prepare_enemy_step()
	for index in range(24):
		view._rotate_camera(1)
		view._process(0.6)
	_check(battle.phase == battle.BattlePhase.PLAYER and battle.turn_number == 2, "rotating during enemy playback does not stall phase completion")
	P.camera_quadrant = initial_quadrant
	view.queue_free()
	await process_frame


func _intent(source: String, action: String, cell: Vector2i, mode: BattleIntent.TargetMode = BattleIntent.TargetMode.TILE_LOCKED) -> BattleIntent:
	return BattleIntent.new("test_" + action, source, action, mode, "", cell, [cell])


func _test_highlight_composition() -> void:
	var view = _sakura_view()
	var battle: BattleController = view.controller
	var cell := Vector2i(4, 4)
	var red := _intent("vanguard_00", "charged_strike", cell, BattleIntent.TargetMode.AREA_LOCKED)
	var purple := _intent("vanguard_01", "ground_pulse", cell, BattleIntent.TargetMode.AREA_LOCKED)
	battle.intents = [red, purple]
	var tiles := BoardThreatTiles.build(battle)
	_check(tiles[cell] == ["charge", "pulse"], "overlap preserves red and purple in a fixed priority")
	battle.intents.reverse()
	_check(BoardThreatTiles.build(battle) == tiles, "enemy iteration order cannot alter highlight priority")
	_check(BoardThreatView.is_cell_in_danger(battle, cell), "composed attack tile remains dangerous")
	var locked := _intent("vanguard_00", "shadow_raid", Vector2i(1, 1), BattleIntent.TargetMode.ACTOR_LOCKED)
	locked.target_actor_id = "sakura"
	battle.intents = [locked]
	_check(BoardThreatTiles.build(battle).has(Vector2i(3, 3)), "actor-locked red tiles follow Sakura's current position")
	_check(not BoardThreatTiles.build(battle).has(Vector2i(1, 1)), "actor lock does not paint a stale target cell")
	_check(BoardThreatView.is_cell_in_danger(battle, Vector2i(3, 3)), "green safety check agrees with the actor-locked highlight")
	locked.cancel("test")
	_check(BoardThreatTiles.build(battle).is_empty(), "cancelled intent leaves no tile highlight")
	view.queue_free()
	await process_frame


func _test_area_cast_rejections() -> void:
	var view = _sakura_view()
	var battle: BattleController = view.controller
	var skill := SkillRegistry.get_skill(&"sakura_falling_petals")
	var hero = battle.get_active_character()
	for cell in [Vector2i(-1, -1), Vector2i(7, 7), hero.cell]:
		_check(not battle.request_skill(skill.skill_id, "", cell) and battle.ap.current == 3, "illegal area aim spends no AP: " + str(cell))
	battle.blocked_cells[Vector2i(4, 3)] = true
	_check(not battle.request_skill(skill.skill_id, "", Vector2i(5, 3)) and battle.ap.current == 3, "wall blocks area cast before AP spend")
	battle.blocked_cells.clear()
	battle.get_actor("vanguard_00").cell = Vector2i(7, 6)
	_check(battle.request_skill(skill.skill_id, "", Vector2i(5, 3)) and battle.ap.current == 1, "entirely empty area is a valid two-AP cast")
	_check(not battle.request_skill(skill.skill_id, "", Vector2i(5, 3)) and battle.ap.current == 1, "second two-AP cast at one AP is rejected without clearing the pool")
	battle.ap.reset()
	battle.beacons[Vector2i(4, 3)] = {"id": "ward_test", "kind": "ward_node", "health": 700, "max_health": 700, "cell": Vector2i(4, 3)}
	_check(battle.request_skill(skill.skill_id, "", Vector2i(5, 3)), "area cast can aim past a ward node")
	_check(int(battle.beacons[Vector2i(4, 3)]["health"]) == 232, "area cast preserves the existing 90-percent attack damage against a ward")
	_check(battle.ap.current == 1, "ward splash never adds a second AP charge")
	view.queue_free()
	await process_frame
