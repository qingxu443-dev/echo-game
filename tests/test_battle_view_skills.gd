extends "res://tests/framework/test_case.gd"

const MainScene = preload("res://scenes/main/main.tscn")
const InputRouterScript = preload("res://scripts/ui/input_router.gd")
const SkillBarViewScript = preload("res://scripts/ui/skill_bar_view.gd")


func _run() -> void:
	await _test_no_default_selection()
	await _test_self_skill_controls()
	await _test_target_skill_flow()
	await _test_target_hint_matches_cast()
	await _test_normal_attack_ring()
	await _test_hotkeys_cover_the_bar()
	await _test_ultimate_needs_a_full_bar()
	await _test_switch_announces_the_display_name()
	_report()


func _test_no_default_selection() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var controller: Variant = view.get("controller")
	_check(int(view.get("selected_skill")) == -1, "battle view starts with no selected player skill")
	var skill_bar: Array = view.get("skill_bar")
	_check(skill_bar.size() == 5, "player skill bar exposes the normal attack, three V2 skills and Hunter Summon")
	_check(skill_bar[0]["id"] == "oathblade" and skill_bar[1]["id"] == "oathkeeper_judgment_mark" and skill_bar[2]["id"] == "oath_shield" and skill_bar[3]["id"] == "absolute_guard" and skill_bar[4]["id"] == "summon:yu_bubble", "skill bar follows the sheet's slot order and ends with the summon")
	var enemy = controller.get_actor("vanguard_00")
	var starting_ap: int = controller.ap.current
	_tap_cell(view, enemy.cell)
	_check(controller.ap.current == starting_ap, "clicking an enemy without selecting a skill does not spend AP")
	_check(enemy.health == enemy.max_health, "clicking an enemy without selecting a skill does not attack")
	_check(String(view.get("status_message")).find("先点右侧技能") != -1, "tapping an enemy with nothing selected explains the missing step instead of doing nothing")
	view.queue_free()
	await process_frame


func _test_self_skill_controls() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var controller: Variant = view.get("controller")

	# Oath Shield is a SELF_AND_ALLY skill, so the button now waits for a target
	# instead of silently shielding Sevrin. Tapping him is the one-target case.
	_tap_skill_by_id(view, "oath_shield")
	_check(int(view.get("selected_skill")) >= 0, "Oath Shield waits for a target instead of firing at Sevrin on its own")
	_tap_cell(view, controller.get_actor("sevrin").cell)
	_check(controller.get_actor("sevrin").shield > 0, "V2 Oath Shield activates from the skill bar once Sevrin is tapped")
	_check(controller.ap.current == controller.ap.maximum - 1, "V2 Oath Shield spends one AP through the battle view")

	var sevrin = controller.get_actor("sevrin")
	sevrin.ultimate_energy = 5
	_tap_skill_by_id(view, "absolute_guard")
	_check(controller.statuses.has_status("sevrin", &"absolute_guard"), "Absolute Guard activates from the skill bar")
	_check(sevrin.ultimate_energy == 0 and controller.ap.current == controller.ap.maximum - 3, "Absolute Guard spends five energy without exceeding the once-per-turn active-action gain cap")

	view.queue_free()
	await process_frame


func _test_target_skill_flow() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	# Target skills need the mixed roster; level 1 only teaches a single vanguard.
	view.call("_start_level", 2)
	var controller: Variant = view.get("controller")
	var marksman = controller.get_actor("marksman_02")
	_check(marksman != null, "main encounter exposes the expected Marksman target")

	_tap_skill_by_id(view, "oathkeeper_judgment_mark")
	var cancel_event := InputEventMouseButton.new()
	cancel_event.pressed = true
	cancel_event.button_index = MOUSE_BUTTON_RIGHT
	view.call("_input", cancel_event)
	_check(int(view.get("selected_skill")) == -1, "right mouse cancels target selection without selecting a default attack")
	_tap_skill_by_id(view, "oathkeeper_judgment_mark")
	_tap_cell(view, marksman.cell)
	_check(controller.statuses.has_status("marksman_02", &"oathkeeper_mark"), "V2 Judgment Mark can be selected and confirmed on the battlefield")
	_check(controller.ap.current == controller.ap.maximum - 1, "V2 Judgment Mark spends one AP through the battle view")
	_check(marksman.health < marksman.max_health, "V2 Judgment Mark deals damage when confirmed")

	_tap_skill_by_id(view, "summon:yu_bubble")
	_tap_cell(view, marksman.cell)
	_check(controller.summon_cooldown_remaining() > 0, "Hunter Summon enters its two-turn cooldown after use")

	view.queue_free()
	await process_frame


func _test_target_hint_matches_cast() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var controller: Variant = view.get("controller")

	var enemy = controller.get_actor("vanguard_00")
	_check(view.call("_can_target_actor", "summon:yu_bubble", enemy.actor_id), "a summonable enemy is highlighted")
	_check(view.call("_can_target_actor", "oathkeeper_judgment_mark", enemy.actor_id), "an enemy on a clear line is highlighted for Judgment Mark")

	# Surround the enemy. The cast would now fail, so the ring must not appear.
	for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		controller.blocked_cells[enemy.cell + offset] = true
	_check(not controller.can_summon(enemy.actor_id), "the controller refuses a summon when every neighbour is blocked")
	_check(not view.call("_can_target_actor", "summon:yu_bubble", enemy.actor_id), "the summon hint drops the ring when the cast would fail")
	# The enemy's left neighbour is also the cell Sevrin's sight line crosses,
	# so blocking the ring legitimately blocks the mark as well.
	_check(not view.call("_can_target_actor", "oathkeeper_judgment_mark", enemy.actor_id), "blocking the neighbour on the sight line also drops the mark hint")

	view.queue_free()
	await process_frame


## The normal attack is the primary way a player deals damage, so its ring must
## track the one-cell range instead of silently never appearing.
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


## Every button needs a key. The bar grew to five when the normal attack came
## back, and the summon silently fell off the end of the key map.
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

	# End to end: the last key must select the last button, not be swallowed.
	var last_key := InputEventKey.new()
	last_key.pressed = true
	last_key.keycode = KEY_1 + bar.size() - 1
	view.call("_input", last_key)
	_check(int(view.get("selected_skill")) == bar.size() - 1, "the last hotkey selects the last skill bar entry")

	view.queue_free()
	await process_frame


## An ultimate costs a full energy bar, and the button should say so. The check
## used to be special-cased on "absolute_guard" by id, so Sakura's ultimate
## looked ready at zero energy and only failed after the tap.
func _test_ultimate_needs_a_full_bar() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	var controller: Variant = view.get("controller")

	var guard: Dictionary = _entry_for(view, "absolute_guard")
	_check(not guard.is_empty(), "the bar carries Absolute Guard")
	var sevrin = controller.get_actor("sevrin")
	sevrin.ultimate_energy = 0
	_check(not SkillBarViewScript.is_affordable(controller, guard), "Absolute Guard is dim at zero energy")
	sevrin.ultimate_energy = 5
	_check(SkillBarViewScript.is_affordable(controller, guard), "Absolute Guard lights up at a full bar")

	_check(controller.set_active_character("sakura"), "command switches to Sakura")
	# The view rebuilds its bar from the turn event; asking the builder directly
	# is the same call the view makes, without waiting for a turn boundary.
	var sakura_bar: Array = SkillBarViewScript.build_entries(controller)
	var ultimate: Dictionary = {}
	for entry in sakura_bar:
		if str(entry["slot"]) == "ultimate":
			ultimate = entry
	_check(not ultimate.is_empty(), "Sakura's bar exposes her ultimate slot")
	_check(str(ultimate["id"]) == "sakura_endless_fragrance", "the ultimate slot is her own skill, not Sevrin's")
	var sakura = controller.get_actor("sakura")
	sakura.ultimate_energy = 0
	_check(not SkillBarViewScript.is_affordable(controller, ultimate), "Sakura's ultimate is dim at zero energy")
	sakura.ultimate_energy = 5
	_check(SkillBarViewScript.is_affordable(controller, ultimate), "Sakura's ultimate lights up at a full bar")

	# A plain skill is judged by AP alone.
	var basic: Dictionary = {}
	for entry in sakura_bar:
		if str(entry["id"]) == "sakura_pierce_blossom":
			basic = entry
	_check(not basic.is_empty(), "the bar carries her normal attack")
	_check(SkillBarViewScript.is_affordable(controller, basic), "a 1 AP skill is affordable on a fresh turn")
	controller.ap.clear()
	_check(not SkillBarViewScript.is_affordable(controller, basic), "a 1 AP skill is dim with an empty pool")

	view.queue_free()
	await process_frame


## The status line is the only feedback the switch gives, and it used to print
## the actor id - "已切换到 sakura。" - in an otherwise Chinese screen.
func _test_switch_announces_the_display_name() -> void:
	var view: Node = MainScene.instantiate()
	root.add_child(view)
	await process_frame
	view.call("_switch_character")
	var message := str(view.get("status_message"))
	_check("樱" in message, "the switch message names the character")
	_check(not ("sakura" in message), "the switch message does not leak the actor id")
	_check(int(view.get("selected_skill")) == -1, "switching clears the pending target selection")
	view.queue_free()
	await process_frame


func _entry_for(view: Node, skill_id: String) -> Dictionary:
	for entry in view.get("skill_bar"):
		if str(entry["id"]) == skill_id:
			return entry
	return {}


## Tap helpers resolve positions from the view's own layout methods so a
## layout change can never silently desync the synthetic clicks.
## Taps a skill by id rather than by position, so adding a slot to a character's
## sheet does not silently retarget the test at a different button.
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

