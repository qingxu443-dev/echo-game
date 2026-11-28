extends SceneTree

## Native Compatibility visual regression. Run with a graphics-capable Godot,
## not --headless. Writes only under ignored build/overlay-preview.
const P = preload("res://scripts/ui/theme_palette.gd")
const OUTPUT := "res://build/overlay-preview/"
var view
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var shell = root.get_node_or_null("GameShell")
	if shell != null: shell.animations_enabled = false
	var run := SpringRun.begin(3)
	run.party_character_ids.assign(["sakura", "sevrin", "dest_lee"])
	SpringBattleBridge.prepare(run, &"B001", &"battle_1")
	view = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(view)
	current_scene = view
	var battle: BattleController = view.controller
	battle.start_encounter(Vector2i(3, 5), [Vector2i(3, 2), Vector2i(5, 2), Vector2i(7, 3), Vector2i(1, 1)], [], ["vanguard", "area_controller", "marksman", "vanguard"], ["sakura", "sevrin", "dest_lee"], [Vector2i(2, 6), Vector2i(3, 6)])
	battle.beacons.clear()
	var row_a: Array[Vector2i] = [Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4)]
	var row_b: Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]
	var row_c: Array[Vector2i] = [Vector2i(6, 4), Vector2i(7, 4)]
	var a := BattleIntent.new("red", "vanguard_00", "charged_strike", BattleIntent.TargetMode.AREA_LOCKED, "", row_a[0], row_a, 300)
	var b := BattleIntent.new("purple", "area_controller_01", "ground_pulse", BattleIntent.TargetMode.AREA_LOCKED, "", row_b[0], row_b, 200)
	var c := BattleIntent.new("blue", "marksman_02", "aimed_shot", BattleIntent.TargetMode.AREA_LOCKED, "", row_c[0], row_c, 150)
	var move := BattleIntent.new("move", "vanguard_03", "pursuit", BattleIntent.TargetMode.NONE)
	move.move_path.assign([Vector2i(1, 2), Vector2i(1, 3)])
	battle.intents.assign([a, b, c, move, a])
	view.fx.snap_actor_positions(battle)
	view.set_process(false)
	view.hover_cell = Vector2i(-1, -1)
	var attack: Image = await _capture("attacks.png")
	var reference := _pixel(attack, row_a[0])
	var flat := true
	for cell in [Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4)]: flat = flat and _pixel(attack, cell).is_equal_approx(reference)
	_check(flat and reference.is_equal_approx(BoardOverlayRegion.ATTACK_FILL), "single, mixed and duplicate attacks have identical flat red pixels")
	view._handle_tap(BattleOverlayInput.TOGGLE_RECT.get_center())
	var hidden: Image = await _capture("hidden.png")
	_check(not _pixel(hidden, row_a[0]).is_equal_approx(reference), "hiding attacks restores the underlying slab")
	_check(_pixel(attack, Vector2i(1, 2)).is_equal_approx(_pixel(hidden, Vector2i(1, 2))), "enemy movement pixels are unchanged by the attack toggle")
	view._handle_tap(PartyPortraitView.card_rect(0).get_center())
	var movement: Image = await _capture("movement.png")
	_check(_pixel(movement, Vector2i(4, 5)).is_equal_approx(_pixel(movement, Vector2i(5, 5))) and _pixel(movement, Vector2i(4, 5)).is_equal_approx(BoardOverlayRegion.MOVE_FILL), "selected movement uses the same green on alternating slabs")
	view._on_skill_pressed(2)
	view.hover_cell = Vector2i(4, 5)
	var skill: Image = await _capture("skill.png")
	var area := SkillEffects.area_cells(battle, SkillRegistry.get_skill(&"sakura_falling_petals"), view.hover_cell)
	var matches := 0
	for cell in area:
		if _pixel(skill, cell).is_equal_approx(BoardOverlayRegion.SKILL_FILL): matches += 1
	_check(matches >= 4, "actual skill preview contains uniformly pale-yellow tile interiors")
	view._handle_tap(BattleOverlayInput.TOGGLE_RECT.get_center())
	var combined: Image = await _capture("combined.png")
	var unchanged := true
	for cell in area:
		if _pixel(skill, cell).is_equal_approx(BoardOverlayRegion.SKILL_FILL): unchanged = unchanged and _pixel(combined, cell).is_equal_approx(BoardOverlayRegion.SKILL_FILL)
	_check(unchanged, "visible attacks never recolour the selected skill interior")
	view.queue_free()
	await process_frame
	if shell != null:
		for voice in shell.audio.voices:
			voice.stop()
			voice.stream = null
	await create_timer(0.12, true).timeout
	print("OVERLAY_RENDER_RESULT failures=", 1 if failed else 0)
	quit(1 if failed else 0)


func _capture(filename: String) -> Image:
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var captured := root.get_texture().get_image()
	captured.save_png(OUTPUT + filename)
	return captured


func _pixel(captured: Image, cell: Vector2i) -> Color:
	var position := P.cell_center(cell) + Vector2(-8, 0)
	return captured.get_pixel(int(position.x), int(position.y))


func _check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	failed = failed or not ok
