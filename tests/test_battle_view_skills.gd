extends "res://tests/framework/test_case.gd"

const MainScene = preload("res://scenes/main/main.tscn")
const InputRouterScript = preload("res://scripts/ui/input_router.gd")
const SkillBarViewScript = preload("res://scripts/ui/skill_bar_view.gd")
const BoardViewScript = preload("res://scripts/ui/board_view.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const RunStateScript = preload("res://scripts/battle/run_state.gd")


func _run() -> void:
	await _test_no_default_selection()
	await _test_self_skill_controls()
	await _test_target_skill_flow()
	await _test_normal_attack_ring()
	await _test_hotkeys_cover_the_bar()
	await _test_ultimate_needs_a_full_bar()
	await _test_chest_loot_and_inventory()
	_test_skill_bar_copies_track_the_catalogue()
	_report()


func _test_no_default_selection() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var controller: Variant = view.get("controller")
	_check(int(view.get("selected_skill")) == -1, "battle view starts with no selected player skill")
	var skill_bar: Array = view.get("skill_bar")
	_check(skill_bar.size() == 4, "solo Sevrin skill bar exposes 4 core skills")
	_check(skill_bar[0]["id"] == "oathblade" and skill_bar[1]["id"] == "oathkeeper_judgment_mark" and skill_bar[2]["id"] == "oath_shield" and skill_bar[3]["id"] == "absolute_guard", "skill bar follows Sevrin slot order")
	var enemy = controller.get_actor("vanguard_00")
	var starting_ap: int = controller.ap.current
	_tap_cell(view, enemy.cell)
	_check(controller.ap.current == starting_ap, "clicking an enemy without selecting a skill does not spend AP")
	_check(enemy.health == enemy.max_health, "clicking an enemy without selecting a skill does not attack")
	_check(String(view.get("status_message")).find("先点右侧技能") != -1, "tapping an enemy explains selecting a skill first")
	view.queue_free()
	await process_frame


func _test_self_skill_controls() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var controller: Variant = view.get("controller")

	# Oath Shield is instant self-cast in solo Sevrin mode
	_tap_skill_by_id(view, "oath_shield")
	_check(int(view.get("selected_skill")) == -1, "Oath Shield fires immediately on tap")
	_check(controller.get_actor("sevrin").shield >= 650, "Oath Shield grants 650+ shield")
	_check(controller.ap.current == controller.ap.maximum - 1, "Oath Shield spends one AP through the battle view")

	# Absolute Verdict (ultimate) requires full 4 energy and 2 AP
	var sevrin = controller.get_actor("sevrin")
	sevrin.ultimate_energy = sevrin.ultimate_energy_max
	_tap_skill_by_id(view, "absolute_guard")
	_check(sevrin.ultimate_energy == 0 and controller.ap.current == 0, "Absolute Verdict spends full energy and 2 AP")

	view.queue_free()
	await process_frame


func _test_target_skill_flow() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	view.call("_start_level", 2)
	var controller: Variant = view.get("controller")
	var marksman = controller.get_actor("marksman_02")
	_check(marksman != null, "level 3 exposes the expected Marksman target")

	_tap_skill_by_id(view, "oathkeeper_judgment_mark")
	var cancel_event := InputEventMouseButton.new()
	cancel_event.pressed = true
	cancel_event.button_index = MOUSE_BUTTON_RIGHT
	view.call("_input", cancel_event)
	_check(int(view.get("selected_skill")) == -1, "right mouse cancels target selection")

	_tap_skill_by_id(view, "oathkeeper_judgment_mark")
	_tap_cell(view, marksman.cell)
	_check(controller.statuses.has_status("marksman_02", &"oathkeeper_mark"), "Judgment Mark applies vulnerability mark")
	_check(controller.ap.current == controller.ap.maximum - 1, "Judgment Mark spends one AP")
	_check(marksman.health < marksman.max_health, "Judgment Mark deals damage when confirmed")

	view.queue_free()
	await process_frame


func _test_normal_attack_ring() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var controller: Variant = view.get("controller")
	var sevrin = controller.get_actor("sevrin")
	var enemy = controller.get_actor("vanguard_00")

	enemy.cell = Vector2i(controller.grid_size.x - 1, controller.grid_size.y - 1)
	_check(not view.call("_can_target_actor", "oathblade", "vanguard_00"), "the normal attack ring stays off beyond one cell")

	for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var cell: Vector2i = sevrin.cell + offset
		if controller.get_occupied_cells().has(cell) or controller.blocked_cells.has(cell):
			continue
		enemy.cell = cell
		_check(view.call("_can_target_actor", "oathblade", "vanguard_00"), "an adjacent enemy is highlighted for the normal attack")
		break

	view.queue_free()
	await process_frame


func _test_hotkeys_cover_the_bar() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var bar: Array = view.get("skill_bar")
	for index in range(bar.size()):
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = KEY_1 + index
		var intent: Dictionary = InputRouterScript.translate(event)
		_check(int(intent.get("index", -1)) == index, "key %d maps to skill bar slot %d" % [index + 1, index + 1])

	# Rotate camera & toggle bag keys
	var q_evt := InputEventKey.new()
	q_evt.pressed = true
	q_evt.keycode = KEY_Q
	_check(str(InputRouterScript.translate(q_evt).get("action", "")) == InputRouterScript.ACTION_ROTATE_CAM, "Q key rotates camera")
	var b_evt := InputEventKey.new()
	b_evt.pressed = true
	b_evt.keycode = KEY_B
	_check(str(InputRouterScript.translate(b_evt).get("action", "")) == InputRouterScript.ACTION_TOGGLE_BAG, "B key toggles inventory")

	view.queue_free()
	await process_frame


func _test_ultimate_needs_a_full_bar() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var controller: Variant = view.get("controller")

	var guard: Dictionary = _entry_for(view, "absolute_guard")
	_check(not guard.is_empty(), "the bar carries Absolute Verdict")
	var sevrin = controller.get_actor("sevrin")
	sevrin.ultimate_energy = 0
	_check(not SkillBarViewScript.is_affordable(controller, guard), "ultimate is dim at zero energy")
	sevrin.ultimate_energy = sevrin.ultimate_energy_max
	_check(SkillBarViewScript.is_affordable(controller, guard), "ultimate lights up at full energy")
	controller.ap.clear()
	_check(not SkillBarViewScript.is_affordable(controller, guard), "ultimate is dim with empty AP")

	view.queue_free()
	await process_frame


func _test_chest_loot_and_inventory() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var controller: Variant = view.get("controller")
	var rs: Variant = view.get("run_state")
	_check(controller.alive_beacons().size() == 2, "2 Relic Chests spawn on the battlefield")
	var b_evt := InputEventKey.new()
	b_evt.pressed = true
	b_evt.keycode = KEY_B
	view.call("_input", b_evt)
	_check(bool(view.get("inventory_open")), "pressing B opens the equipment & backpack overlay")
	view.call("_input", b_evt)
	_check(not bool(view.get("inventory_open")), "pressing B again closes the overlay")
	_check(rs != null, "battle view maintains a RunState")
	view.queue_free()
	await process_frame


func _entry_for(view: Node, skill_id: String) -> Dictionary:
	for entry in view.get("skill_bar"):
		if str(entry["id"]) == skill_id:
			return entry
	return {}


func _tap_skill_by_id(view: Node, skill_id: String) -> void:
	var bar: Array = view.get("skill_bar")
	for index in range(bar.size()):
		if str(bar[index]["id"]) == skill_id:
			_tap_skill(view, index)
			return
	push_error("no skill bar entry with id %s" % skill_id)


func _tap_skill(view: Node, index: int) -> void:
	var rect: Rect2 = view.call("_skill_rect", index)
	view.call("_handle_tap", rect.position + rect.size * 0.5)


func _tap_cell(view: Node, cell: Vector2i) -> void:
	var rect: Rect2 = view.call("_cell_rect", cell)
	view.call("_handle_tap", rect.position + rect.size * 0.5)


## The skill bar reads the catalogue directly; keep the displayed costs and
## combat semantics checked against the same definitions and run modifiers.
func _test_skill_bar_copies_track_the_catalogue() -> void:
	var bar = SkillBarViewScript
	var blade_desc: String = str(bar.full_description(&"oathblade"))
	var blade = SkillRegistryScript.get_skill(&"oathblade")
	_check(blade_desc.contains("%d AP" % blade.ap_cost), "the blade copy states the catalogue's AP cost")
	_check(blade_desc.contains("%d%%" % roundi(blade.damage_multiplier * 100.0)), "the blade copy states the catalogue's multiplier")
	var run_state = RunStateScript.new()
	_check(blade_desc.contains("%d 真实伤害" % run_state.collision_damage()), "the blade copy states the run's collision damage")

	var guard_desc: String = str(bar.full_description(&"absolute_guard"))
	var guard = SkillRegistryScript.get_skill(&"absolute_guard")
	_check(guard_desc.contains("%d AP" % guard.ap_cost), "the verdict copy states the catalogue's AP cost")
	_check(guard_desc.contains("%d%%" % roundi(guard.damage_multiplier * 100.0)), "the verdict copy states the catalogue's multiplier")

	var mark_desc: String = str(bar.full_description(&"oathkeeper_judgment_mark"))
	var mark = SkillRegistryScript.get_skill(&"oathkeeper_judgment_mark")
	_check(mark_desc.contains("%d%%" % roundi(mark.damage_multiplier * 100.0)), "the mark copy states the catalogue's multiplier")
	_check(mark_desc.contains("+%d%%" % roundi((run_state.mark_vulnerability_multiplier() - 1.0) * 100.0)), "the mark copy states the run's vulnerability")
