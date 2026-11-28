extends "res://tests/framework/test_case.gd"

const Scene = preload("res://scenes/main/main.tscn")
const P = preload("res://scripts/ui/theme_palette.gd")


func _run() -> void:
	var shell = root.get_node_or_null("GameShell")
	if shell != null: shell.animations_enabled = false
	SessionSave.path_override = "user://overlay_session_%d.json" % OS.get_process_id()
	SessionSave.clear()
	_test_region_boundaries_and_colours()
	_test_movement_matches_controller()
	await _test_selection_and_visibility()
	SessionSave.clear()
	SessionSave.path_override = ""
	SpringBattleBridge.clear_pending()
	if shell != null:
		for voice in shell.audio.voices: voice.stop()
	await create_timer(0.05, true).timeout


func _test_region_boundaries_and_colours() -> void:
	var previous: int = P.camera_quadrant
	P.board_grid_size = Vector2i(8, 8)
	var square := {Vector2i(2, 2): true, Vector2i(3, 2): true, Vector2i(2, 3): true, Vector2i(3, 3): true}
	for quadrant in range(4):
		P.camera_quadrant = quadrant
		var edges := BoardOverlayRegion.boundary_edges(square)
		_check(edges.size() == 8, "a four-tile square has only eight exterior edges in camera %d" % quadrant)
		var endpoints := {}
		for edge in edges:
			for point in edge: endpoints[point] = int(endpoints.get(point, 0)) + 1
		var continuous := true
		for count in endpoints.values(): continuous = continuous and count == 2
		_check(continuous, "region outline is continuous without internal crosses in camera %d" % quadrant)
		_check(BoardOverlayRegion.boundary_edges({Vector2i(0, 0): true}).size() == 4, "board edge tiles keep every outer boundary")
	P.camera_quadrant = previous
	for fill in [BoardOverlayRegion.ATTACK_FILL, BoardOverlayRegion.MOVE_FILL, BoardOverlayRegion.SKILL_FILL]:
		_check(is_equal_approx(fill.a, 1.0), "flat fill does not inherit a light/dark or underlying attack colour")
	var battle := _battle()
	var cell := Vector2i(4, 3)
	var a := BattleIntent.new("a", "vanguard_00", "charged_strike", BattleIntent.TargetMode.AREA_LOCKED, "", cell, [cell], 100)
	var b := BattleIntent.new("b", "vanguard_00", "ground_pulse", BattleIntent.TargetMode.AREA_LOCKED, "", cell, [cell], 100)
	battle.intents.assign([a, b, a])
	_check(BoardThreatTiles.build(battle).size() == 1, "different and duplicate attacks compose into exactly one painted tile")
	var before := BoardThreatTiles.build(battle)
	battle.intents.reverse()
	_check(BoardThreatTiles.build(battle) == before, "attack ordering cannot change the overlay")
	battle.queue_free()


func _battle() -> BattleController:
	var battle := BattleController.new()
	battle.single_active_party = true
	battle.run_state = RunState.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(3, 3), [Vector2i(5, 3)], [Vector2i(3, 2)], [], ["sevrin", "sakura"], [Vector2i(2, 3)])
	battle.beacons.clear()
	return battle


func _test_movement_matches_controller() -> void:
	var battle := _battle()
	var hero = battle.get_active_character()
	var origin: Vector2i = hero.cell
	for mode in ["paid", "zero_ap", "free_stride", "free_spent"]:
		battle.run_state.mods.clear()
		var available_ap := 0 if mode != "paid" else 3
		if mode.begins_with("free"): battle.run_state.mods.append(&"echo_stride")
		var used_turn: int = battle.turn_number if mode == "free_spent" else -1
		battle.ap.current = available_ap
		battle.ledger.free_move_used_turn = used_turn
		var shown := BoardMoveRange.cells(battle)
		for y in range(8):
			for x in range(8):
				hero.cell = origin
				battle.ap.current = available_ap
				battle.ledger.free_move_used_turn = used_turn
				var goal := Vector2i(x, y)
				var path := GridRules.find_path(origin, goal, battle.grid_size, battle.blocked_cells, battle.get_occupied_cells(hero.actor_id), battle.PLAYER_MOVE_MAX_STEPS)
				var accepted := battle.request_player_move(path)
				_check(accepted == shown.has(goal), "%s: displayed reach matches the authoritative movement request at %s" % [mode, goal])
		_check(not shown.has(Vector2i(3, 2)) and not shown.has(Vector2i(5, 3)), "obstacles and live enemies never appear reachable")
		if mode in ["paid", "free_stride"]: _check(shown.has(Vector2i(2, 3)), "the reserve's former cell remains walkable")
		hero.cell = origin
	battle.phase = battle.BattlePhase.ENEMY
	_check(BoardMoveRange.cells(battle).is_empty(), "enemy phase never exposes player movement")
	battle.queue_free()


func _scene():
	var run := SpringRun.begin(3)
	run.party_character_ids.assign(["sakura", "sevrin"])
	SpringBattleBridge.prepare(run, &"B001", &"battle_1")
	var view = Scene.instantiate()
	root.add_child(view)
	view.controller.beacons.clear()
	view.controller.blocked_cells.clear()
	view.controller.request_deploy(Vector2i(3, 5))
	view.controller.request_begin_battle()
	view.fx.snap_actor_positions(view.controller)
	return view


func _test_selection_and_visibility() -> void:
	var view = _scene()
	var battle: BattleController = view.controller
	_check(view.fx.attack_tiles_visible and view.fx.move_actor_id.is_empty(), "new encounter shows attack warnings and hides movement by default")
	_check(BoardMoveRange.visible_cells(battle, -1, view.fx.snapshot(Vector2i(-1, -1))).is_empty(), "unselected movement range is actually empty")
	view._handle_tap(P.cell_center(battle.get_active_character().cell))
	_check(view.fx.move_actor_id == "sakura" and battle.ap.current == 3, "clicking the current actor selects movement without spending AP")
	_check(not BoardMoveRange.visible_cells(battle, -1, view.fx.snapshot(Vector2i(-1, -1))).is_empty(), "selected movement range is visible")
	view._cancel_target_selection()
	_check(view.fx.move_actor_id.is_empty(), "right-click cancel also hides the movement selection")
	view._handle_tap(PartyPortraitView.card_rect(0).get_center())
	_check(view.fx.move_actor_id == "sakura" and battle.ap.current == 3, "the active portrait is a free selection control, not a paid switch")
	view._on_skill_pressed(2)
	_check(view.fx.move_actor_id.is_empty() and view.selected_skill == 2, "selecting an area skill replaces the movement selection")
	view.hover_cell = battle.get_active_character().cell + Vector2i.RIGHT
	var area := SkillEffects.area_cells(battle, SkillRegistry.get_skill(&"sakura_falling_petals"), view.hover_cell)
	_check(not area.is_empty(), "hovered empty tile produces an actual area preview")
	var intents := JSON.stringify(SessionCodec.encode(battle.intents.map(func(i): return SessionCodec.fields(i))))
	view._handle_tap(BattleOverlayInput.TOGGLE_RECT.get_center())
	_check(not view.fx.attack_tiles_visible and battle.ap.current == 3 and view.selected_skill == 2, "hide button changes only attack display, keeping the selected skill and AP")
	_check(JSON.stringify(SessionCodec.encode(battle.intents.map(func(i): return SessionCodec.fields(i)))) == intents, "hiding attacks never modifies intent paths, targets, damage or state")
	view._handle_tap(BattleOverlayInput.TOGGLE_RECT.get_center())
	_check(view.fx.attack_tiles_visible, "same button restores attack display")
	view._handle_tap(BattleOverlayInput.TOGGLE_RECT.get_center())
	var data := BattleSession.capture(view)
	_check(SessionSave.valid(data), "hidden attack preference is valid checkpoint data")
	data.fx.attack_tiles_visible = "false"
	_check(not SessionSave.valid(data), "wrong display flag types fail before restore")
	data.fx.attack_tiles_visible = false
	view.queue_free()
	await process_frame
	SessionSave.pending = data
	var restored = Scene.instantiate()
	root.add_child(restored)
	_check(not restored.fx.attack_tiles_visible, "pause restore preserves the user's attack display choice")
	restored._handle_tap(PartyPortraitView.card_rect(0).get_center())
	_check(restored.fx.move_actor_id == "sakura", "restored active portrait still selects movement")
	_check(restored.controller.request_switch_character("sevrin"), "fixture switches to its reserve")
	_check(restored.fx.move_actor_id.is_empty(), "switching roles clears the previous movement selection")
	restored._handle_tap(PartyPortraitView.card_rect(1).get_center())
	_check(restored.fx.move_actor_id == "sevrin", "the newly active role can select its own movement range")
	restored._end_player_turn()
	_check(restored.fx.move_actor_id.is_empty(), "ending the player turn does not leave a stale movement range")
	restored._handle_tap(BattleOverlayInput.TOGGLE_RECT.get_center())
	_check(restored.fx.attack_tiles_visible and restored.controller.phase == BattleController.BattlePhase.ENEMY, "attack display can toggle during enemy playback without advancing its phase")
	restored.queue_free()
	await process_frame
