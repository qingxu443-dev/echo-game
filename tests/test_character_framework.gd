extends "res://tests/framework/test_case.gd"

## The character framework and Sakura's kit.
##
## Two things are being pinned here. First, that a character exists because of
## data - its sheet, its slots and its skills - rather than because the
## controller knows its name. Second, that Sakura's mechanics behave as design
## plan §19-24 describe.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const BoardViewScript = preload("res://scripts/ui/board_view.gd")
const SkillBarViewScript = preload("res://scripts/ui/skill_bar_view.gd")
const SkillExecutorScript = preload("res://scripts/battle/skill_executor.gd")
const CharacterSkillRuntimeScript = preload("res://scripts/battle/character_skill_runtime.gd")
const SkillEffectsScript = preload("res://scripts/battle/skill_effects.gd")
const CombatGeometryScript = preload("res://scripts/battle/combat_geometry.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const IntentPlannerScript = preload("res://scripts/battle/intent_planner.gd")


func _run() -> void:
	_test_characters_come_from_data()
	_test_every_active_skill_has_an_executor()
	_test_sevrin_normal_attack()
	_test_party_spawns_from_the_level_sheet()
	_test_switching_is_free_and_party_wide()
	_test_movement_follows_the_active_character()
	_test_a_character_cannot_borrow_another_kit()
	_test_pierce_blossom_applies_the_mark_without_follow_up()
	_test_second_hit_triggers_echo_return()
	_test_echo_kill_pays_a_kill_stack()
	_test_blade_intent_accumulates_and_caps()
	_test_petal_mark_lasts_three_enemy_turns()
	_test_endless_fragrance_scales_with_intent()
	_test_falling_petals_covers_the_rectangle_in_front()
	_test_flowing_wind_respects_its_range()
	_test_flowing_wind_kill_pays_the_kill_stack()
	_test_every_reachable_dash_can_strike()
	_test_a_wall_stops_the_lane()
	_test_oath_shield_reaches_a_party_member()
	_test_a_dead_target_is_not_marked()
	_test_active_skills_grant_ultimate_energy()
	_test_every_sakura_action_grants_the_same_energy()
	_test_extreme_strengthens_the_next_active_skill()
	_test_kills_pay_intent_inside_the_budget()
	_test_cast_uses_the_commanded_character()
	_test_movement_uses_the_commanded_character()
	_test_oath_vow_follows_the_passive_not_the_character()
	_test_absolute_guard_follows_the_status()
	_report()


func _sakura_battle() -> Node:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sakura"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], ids, [])
	return battle


func _test_characters_come_from_data() -> void:
	_check(CharacterCatalogScript.has_definition("sevrin"), "Sevrin is defined by a sheet")
	_check(CharacterCatalogScript.has_definition("sakura"), "Sakura is defined by a sheet")
	var sakura = CharacterCatalogScript.get_definition("sakura")
	_check(sakura.max_health == 2100 and sakura.attack == 600, "Sakura's sheet carries the planned panel")
	_check(sakura.has_resource() and String(sakura.resource_id) == "blade_intent", "Sakura's sheet declares blade intent")

	var skills := SkillRegistryScript.skills_for_character("sakura")
	_check(skills.size() == 5, "Sakura brings five slots")
	var active := SkillRegistryScript.active_skills_for_character("sakura")
	_check(active.size() == 4, "the passive is not a button")


## §15: every character has a normal attack. Sevrin's takes the shared executor.
## §18-24: a skill can live in data, appear on the bar and do nothing when
## pressed. The press returns false, which is indistinguishable from a failed
## condition, so the only place to catch a missing executor is here: walk the
## registry and ask the runtime which ids it can actually run.
func _test_every_active_skill_has_an_executor() -> void:
	var active := 0
	var missing: Array[String] = []
	for skill in SkillRegistryScript.all_skills():
		if skill.is_passive:
			continue
		active += 1
		if not CharacterSkillRuntimeScript.supports(skill.executor_id):
			missing.append("%s(%s)" % [String(skill.skill_id), String(skill.executor_id)])
	# Guards the test itself: an empty registry would pass the check below while
	# proving nothing.
	_check(active > 0, "the registry exposes active skills to check", str(active))
	_check(missing.is_empty(), "every active skill has a registered executor", ", ".join(missing))
	_check(not CharacterSkillRuntimeScript.supports(&"no_such_executor"), "an unregistered executor is not claimed")


func _test_sevrin_normal_attack() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], ids, [])
	battle.beacons.clear()
	var enemy = battle.get_actor("vanguard_00")
	var health_before: int = enemy.health
	var ap_before: int = battle.ap.current

	_check(battle.request_skill(&"oathblade", "vanguard_00"), "the Oathblade resolves on an adjacent enemy")
	# 650 ATK x 1.0 against 450 defense: floor(650 * 1000 / 1450) = 448
	_check(health_before - enemy.health == 448, "the normal attack deals full attack through defense")
	_check(enemy.cell == Vector2i(3, 1), "Oathblade knocks the adjacent enemy back one tile")
	_check(battle.ap.current == ap_before - 1, "the normal attack costs one AP")
	battle.queue_free()

	var far = ControllerScript.new()
	root.add_child(far)
	far.start_encounter(Vector2i(1, 1), [Vector2i(3, 1)])
	_check(not far.request_skill(&"oathblade", "vanguard_00"), "the normal attack refuses a non-adjacent target")
	_check(far.ap.current == far.ap.maximum, "a refused normal attack spends nothing")
	far.queue_free()


func _test_party_spawns_from_the_level_sheet() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	var ally_cells: Array[Vector2i] = [Vector2i(1, 2)]
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)], [], [], ids, ally_cells), "a two-member party deploys")
	_check(battle.actors.has("sevrin") and battle.actors.has("sakura"), "both members are on the field")
	_check(battle.get_actor("sakura").cell == Vector2i(1, 2), "the ally spawns on its declared cell")
	_check(battle.get_actor("sakura").glyph == "樱", "the board glyph comes from the sheet")
	_check(battle.active_character_id == "sevrin", "the first listed character starts active")

	var mismatched: Array[String] = ["sevrin", "sakura"]
	_check(not battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)], [], [], mismatched, []), "a roster without matching cells is rejected")
	battle.queue_free()


func _test_switching_is_free_and_party_wide() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	var ally_cells: Array[Vector2i] = [Vector2i(1, 2)]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)], [], [], ids, ally_cells)

	var ap_before: int = battle.ap.current
	_check(battle.set_active_character("sakura"), "command can switch to Sakura")
	_check(battle.ap.current == ap_before, "switching costs no AP")
	_check(battle.get_active_character().actor_id == "sakura", "the active character is Sakura")
	_check(battle.get_switchable_characters().size() == 2, "both members are offered by the switch control")
	_check(not battle.set_active_character("vanguard_00"), "enemies cannot be commanded")
	_check(not battle.set_active_character("nobody"), "an unknown id is rejected")
	battle.queue_free()


## The active character is the one that acts. Movement used to validate the path
## from Sevrin's cell, so every move Sakura attempted failed the adjacency check.
func _test_movement_follows_the_active_character() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	var ally_cells: Array[Vector2i] = [Vector2i(1, 2)]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5)], [], [], ids, ally_cells)
	var sevrin = battle.get_actor("sevrin")
	var sakura = battle.get_actor("sakura")
	var sevrin_cell: Vector2i = sevrin.cell
	battle.set_active_character("sakura")

	var step: Array[Vector2i] = [sakura.cell + Vector2i(0, 1)]
	_check(battle.request_player_move(step), "the active character can move")
	_check(sakura.cell == step[0], "the active character is the one that moves")
	_check(sevrin.cell == sevrin_cell, "the other party member stays put")
	_check(battle.ap.current == battle.ap.maximum - 1, "one move spends one shared AP")
	battle.queue_free()


## Ownership comes from the sheet, so a caller cannot resolve Sevrin's numbers
## against Sakura's stats by naming his skill id.
func _test_a_character_cannot_borrow_another_kit() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	var ally_cells: Array[Vector2i] = [Vector2i(1, 2)]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 2)], [], [], ids, ally_cells)
	battle.set_active_character("sakura")
	var enemy = battle.get_actor("vanguard_00")
	var health_before: int = enemy.health
	var ap_before: int = battle.ap.current

	_check(not battle.request_skill(&"oathblade", "vanguard_00"), "Sakura cannot cast Sevrin's normal attack")
	_check(not battle.request_skill(&"oath_shield", "sevrin"), "Sakura cannot cast Sevrin's support skill")
	_check(enemy.health == health_before and battle.ap.current == ap_before, "a borrowed skill spends and deals nothing")
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "Sakura can still cast her own kit")
	battle.queue_free()


func _test_pierce_blossom_applies_the_mark_without_follow_up() -> void:
	var battle = _sakura_battle()
	var sakura = battle.get_actor("sakura")
	var enemy = battle.get_actor("vanguard_00")
	var health_before: int = enemy.health

	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "Pierce Blossom resolves")
	var dealt: int = health_before - enemy.health
	# 600 ATK x 1.0 against 450 defense: floor(600 * 1000 / 1450) = 413
	_check(dealt == 413, "the first hit deals its own damage only")
	_check(battle.statuses.has_status("vanguard_00", &"sakura_petal_mark"), "the hit applies the petal mark")
	battle.queue_free()


func _test_second_hit_triggers_echo_return() -> void:
	var battle = _sakura_battle()
	var enemy = battle.get_actor("vanguard_00")
	battle.request_skill(&"sakura_pierce_blossom", "vanguard_00")
	var health_before: int = enemy.health

	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "the second Pierce Blossom resolves")
	var dealt: int = health_before - enemy.health
	# 413 from the hit plus floor(300 * 1000 / 1450) = 206 from the follow-up
	_check(dealt == 619, "an already-marked target also takes the echo return")
	battle.queue_free()


## §19 / §30: an echo return that kills is still a defeat, so it pays a stack -
## after the action's own stack, before the first-echo stack.
func _test_echo_kill_pays_a_kill_stack() -> void:
	var battle = _sakura_battle()
	var sakura = battle.get_actor("sakura")
	var enemy = battle.get_actor("vanguard_00")
	sakura.resource_current = 0
	# 305 from the strike leaves 95 of 400; the 152 follow-up is lethal.
	enemy.health = 400
	SkillEffectsScript.apply_petal_mark(battle, sakura, enemy)
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "the strike resolves")
	_check(not enemy.is_alive(), "the echo return lands the killing blow")
	_check(sakura.resource_current == 3, "action 1 + kill 1 + first echo 1 reaches the budget cap")
	battle.queue_free()

	# Control: the same strike without a lethal follow-up pays no kill stack.
	var open = _sakura_battle()
	var sakura_open = open.get_actor("sakura")
	var enemy_open = open.get_actor("vanguard_00")
	sakura_open.resource_current = 0
	SkillEffectsScript.apply_petal_mark(open, sakura_open, enemy_open)
	open.request_skill(&"sakura_pierce_blossom", "vanguard_00")
	_check(enemy_open.is_alive(), "the control target survives the follow-up")
	_check(sakura_open.resource_current == 2, "action 1 + first echo 1, with no kill stack")
	open.queue_free()


func _test_blade_intent_accumulates_and_caps() -> void:
	var battle = _sakura_battle()
	var sakura = battle.get_actor("sakura")
	_check(sakura.resource_current == 1, "one stack arrives at turn start")

	battle.request_skill(&"sakura_pierce_blossom", "vanguard_00")
	_check(sakura.resource_current == 2, "an attack action grants a stack")

	# The action budget is three per turn, so further actions stop adding stacks.
	battle.request_skill(&"sakura_pierce_blossom", "vanguard_00")
	_check(sakura.resource_current == 4, "the second attack plus its follow-up fill the track")
	_check(sakura.is_resource_full(), "four stacks is the full state")
	battle.queue_free()


func _test_petal_mark_lasts_three_enemy_turns() -> void:
	var battle = _sakura_battle()
	battle.request_skill(&"sakura_pierce_blossom", "vanguard_00")
	var mark = battle.statuses.get_status("vanguard_00", &"sakura_petal_mark")
	_check(mark != null, "the mark exists")
	_check(mark.enemy_turns_remaining == 3, "the mark starts at three enemy turns")

	battle.end_player_turn()
	mark = battle.statuses.get_status("vanguard_00", &"sakura_petal_mark")
	_check(mark != null and mark.enemy_turns_remaining == 2, "one enemy phase leaves two")
	battle.queue_free()


func _test_endless_fragrance_scales_with_intent() -> void:
	var battle = _sakura_battle()
	var sakura = battle.get_actor("sakura")
	var enemy = battle.get_actor("vanguard_00")
	sakura.resource_current = 4
	sakura.ultimate_energy = 5
	var health_before: int = enemy.health

	_check(battle.request_skill(&"sakura_endless_fragrance"), "the ultimate resolves")
	_check(sakura.ultimate_energy == 0, "the ultimate spends five energy")
	# Three 20% segments and a finisher of 40% + 4x5% + 20% = 80%.
	# floor(120*1000/1450)=82 x3 plus floor(480*1000/1450)=331
	var dealt: int = health_before - enemy.health
	_check(dealt == 577, "the cross hits four times with the intent-scaled finisher")
	_check(not battle.statuses.has_status("vanguard_00", &"sakura_petal_mark"), "the ultimate does not apply the mark")
	battle.queue_free()


func _test_falling_petals_covers_the_rectangle_in_front() -> void:
	# Owner decision 2026-11-25: the fan became a rectangle in front of Sakura,
	# three cells across and two deep. Aiming right from (1,1) covers x=2..3
	# across y=0..2.
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sakura"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1), Vector2i(3, 2), Vector2i(1, 6), Vector2i(4, 1)], [], [], ids, [])

	var near = battle.get_actor("vanguard_00")
	var side = battle.get_actor("vanguard_01")
	var outside = battle.get_actor("vanguard_02")
	var beyond_depth = battle.get_actor("vanguard_03")
	var near_before: int = near.health
	var side_before: int = side.health
	var outside_before: int = outside.health
	var beyond_before: int = beyond_depth.health

	var skill = SkillRegistryScript.get_skill(&"sakura_falling_petals")
	_check(skill.shape_width == 3 and skill.shape_depth == 2, "the footprint is three across and two deep")
	_check(battle.request_skill(&"sakura_falling_petals", "vanguard_00"), "Falling Petals resolves")

	# Three segments of 30%: floor(156 * 1000 / 1450) = 107 each, so 321.
	_check(near_before - near.health == 321, "the aimed target takes all three segments")
	_check(side_before - side.health == 321, "a target beside the axis is inside the block and also takes three")
	_check(outside.health == outside_before, "an enemy outside the block is untouched")
	_check(beyond_depth.health == beyond_before, "an enemy four cells ahead is beyond the two-cell depth")
	_check(battle.statuses.has_status("vanguard_00", &"sakura_petal_mark"), "the block applies the mark")
	_check(battle.statuses.has_status("vanguard_01", &"sakura_petal_mark"), "the mark lands on every enemy in the block")
	battle.queue_free()


## §22 prices the dash at a three-cell pick. The gate used to be written as
## "not aligned and too far", and the line-of-sight check right after it already
## requires a shared row or column, so it never fired: any target in the same row
## at any distance was accepted, the AP was spent, and the dash landed short of
## everything with no damage and no explanation.
func _test_flowing_wind_respects_its_range() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sakura"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)], [], [], ids, [])
	var sakura = battle.get_actor("sakura")
	var cell_before: Vector2i = sakura.cell
	var ap_before: int = battle.ap.current

	_check(not battle.request_skill(&"sakura_flowing_wind", "vanguard_00"), "the dash refuses a target beyond its three-cell range")
	_check(battle.ap.current == ap_before, "an out-of-range dash spends no AP")
	_check(sakura.cell == cell_before, "an out-of-range dash does not move the caster")
	battle.queue_free()

	# Control: three cells away is inside the range, so the dash closes in and hits.
	var inside = ControllerScript.new()
	root.add_child(inside)
	var inside_ids: Array[String] = ["sakura"]
	inside.start_encounter(Vector2i(1, 1), [Vector2i(4, 1)], [], [], inside_ids, [])
	inside.beacons.clear()
	var inside_sakura = inside.get_actor("sakura")
	var enemy = inside.get_actor("vanguard_00")
	var health_before: int = enemy.health
	_check(inside.request_skill(&"sakura_flowing_wind", "vanguard_00"), "a target three cells away is inside the dash range")
	_check(inside_sakura.cell == Vector2i(3, 1), "the dash lands two cells closer")
	# floor(480 * 1000 / 1450) = 331
	_check(health_before - enemy.health == 331, "the dash strikes once it arrives")
	inside.queue_free()


## §19 / §30: a dash that kills still pays its stacks in the documented order,
## and a corpse keeps no mark. The echo return cannot fire here - the target is
## already dead when the echo step would run - so two is the whole ceiling, and
## asserting two is what separates "kill paid" from "kill silently dropped".
func _test_flowing_wind_kill_pays_the_kill_stack() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sakura"]
	# A second enemy keeps the battle running. With one enemy the kill ends the
	# fight, finish_battle clears every status, and "no mark on the corpse" would
	# pass for the wrong reason - measured, not assumed.
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1), Vector2i(7, 7)], [], [], ids, [])
	var sakura = battle.get_actor("sakura")
	var enemy = battle.get_actor("vanguard_00")
	sakura.resource_current = 0
	# 244 damage against 200 health: the strike itself is lethal, so the mark is
	# applied to a target that is already down.
	enemy.health = 200
	SkillEffectsScript.apply_petal_mark(battle, sakura, enemy)
	_check(battle.request_skill(&"sakura_flowing_wind", "vanguard_00"), "a lethal dash resolves")
	_check(not enemy.is_alive(), "the dash kills a 200-health target")
	_check(sakura.resource_current == 2, "action 1 + kill 1, with no living target for the echo step")
	_check(not battle.statuses.has_status(enemy.actor_id, SkillEffectsScript.PETAL_MARK), "a corpse keeps no petal mark")
	battle.queue_free()

	# 极意 first, kill second: the bar is spent before the action earns anything,
	# so the same kill that pays 2 from zero pays 2 from four as well.
	var extreme = ControllerScript.new()
	root.add_child(extreme)
	var extreme_ids: Array[String] = ["sakura"]
	extreme.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], extreme_ids, [])
	var extreme_sakura = extreme.get_actor("sakura")
	var extreme_enemy = extreme.get_actor("vanguard_00")
	extreme_sakura.resource_current = 4
	extreme_enemy.health = 200
	_check(extreme.request_skill(&"sakura_flowing_wind", "vanguard_00"), "an extreme lethal dash resolves")
	_check(extreme_sakura.resource_current == 2, "the full bar is spent first, then action 1 + kill 1")
	extreme.queue_free()


## The target ring promises "you can dash here". Pinned as a property over every
## cell in range rather than as one example, because the promise is what the
## player reads and the two rules that back it - the aim check and the walk -
## live in different files now. If either loosens alone, one of these goes red.
##
## Every cell in range contributes an assertion, reachable or not, so the count
## depends on the board rather than on the implementation.
func _test_every_reachable_dash_can_strike() -> void:
	var skill = SkillRegistryScript.get_skill(&"sakura_flowing_wind")
	var origin := Vector2i(3, 3)
	var reachable: int = 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var cell := origin + Vector2i(dx, dy)
			if cell == origin or absi(dx) + absi(dy) > 3:
				continue
			var battle = ControllerScript.new()
			root.add_child(battle)
			var ids: Array[String] = ["sakura"]
			battle.start_encounter(origin, [cell], [], [], ids, [])
			battle.beacons.clear()
			var caster = battle.get_actor("sakura")
			var target = battle.get_actor("vanguard_00")
			var aimed: bool = CharacterSkillRuntimeScript.can_aim(battle, skill, target)
			var landing: Vector2i = CombatGeometryScript.dash_landing(battle, caster, target, 2)
			var strikes: bool = GridRulesScript.manhattan_distance(landing, cell) == 1
			if aimed:
				reachable += 1
			_check(not aimed or strikes, "a dash the ring offers at %s can actually strike" % str(cell))
			battle.queue_free()
	# A guard on the guard: an empty walk would make every line above vacuous.
	# A guard on the guard: an empty walk would make every line above vacuous.
	# Twelve is the shape of the rule, not a coincidence: four adjacent, four
	# orthogonal at two cells, four at three. Diagonals are offered by neither,
	# because the walk only steps along one axis.
	_check(reachable == 12, "the ring offers twelve of the twenty-four cells in range")


## A wall in the lane must stop the cast. Two different holes, one rule:
##
##  - Flowing Wind checked its own lane but the target ring did not, so a wall
##    between Sakura and the enemy left the ring lit and the cast refused.
##  - 落英 checked nothing but bounds. The rectangle walked straight through the
##    wall and struck the enemy behind it for 273 damage.
##
## can_aim() now answers for both, so neither can drift again.
func _test_a_wall_stops_the_lane() -> void:
	# Sakura (1,1), wall (1,2), enemy (1,3): distance two is inside both ranges.
	var dash = ControllerScript.new()
	root.add_child(dash)
	var dash_ids: Array[String] = ["sakura"]
	dash.start_encounter(Vector2i(1, 1), [Vector2i(1, 3)], [Vector2i(1, 2)], [], dash_ids, [])
	var dash_ap: int = dash.ap.current
	_check(not dash.request_skill(&"sakura_flowing_wind", "vanguard_00"), "a wall stops the dash")
	_check(dash.ap.current == dash_ap, "a blocked dash spends no AP")
	dash.queue_free()

	var petals = ControllerScript.new()
	root.add_child(petals)
	var petal_ids: Array[String] = ["sakura"]
	petals.start_encounter(Vector2i(1, 1), [Vector2i(1, 3)], [Vector2i(1, 2)], [], petal_ids, [])
	var enemy = petals.get_actor("vanguard_00")
	var petal_ap: int = petals.ap.current
	var health_before: int = enemy.health
	_check(not petals.request_skill(&"sakura_falling_petals", "vanguard_00"), "a wall stops the rectangle")
	_check(petals.ap.current == petal_ap, "a blocked rectangle spends no AP")
	_check(enemy.health == health_before, "a blocked rectangle deals no damage, not even through the wall")
	petals.queue_free()

	# Control: the same rectangle against the same enemy, wall removed.
	var open = ControllerScript.new()
	root.add_child(open)
	var open_ids: Array[String] = ["sakura"]
	open.start_encounter(Vector2i(1, 1), [Vector2i(1, 3)], [], [], open_ids, [])
	_check(open.request_skill(&"sakura_falling_petals", "vanguard_00"), "the same cast resolves once the lane is open")
	open.queue_free()

	# The ring reads the same predicate, so it agrees without being told twice.
	var ring = ControllerScript.new()
	root.add_child(ring)
	var ring_ids: Array[String] = ["sakura"]
	ring.start_encounter(Vector2i(1, 1), [Vector2i(1, 3)], [Vector2i(1, 2)], [], ring_ids, [])
	var bar: Array = SkillBarViewScript.build_entries(ring)
	_check(not BoardViewScript.can_target(ring, bar, "sakura_flowing_wind", "vanguard_00"), "the dash ring stays off behind a wall")
	_check(not BoardViewScript.can_target(ring, bar, "sakura_falling_petals", "vanguard_00"), "the rectangle ring stays off behind a wall")
	ring.queue_free()


## Oath Shield promises Sevrin and one nearby ally. The bar used to flatten
## SELF_AND_ALLY into a press-once button and the runtime filled the missing
## target with the caster, so the second shield was only reachable by calling the
## API by hand. Sevrin and Sakura now stand next to each other.
func _test_oath_shield_reaches_a_party_member() -> void:
	var definition = SkillRegistryScript.get_skill(&"oath_shield")
	_check(definition.max_range == 0, "the catalogue declares instant self-cast for solo play")

	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(6, 6)], [], [], ids, [Vector2i(1, 2)])
	var sevrin = battle.get_actor("sevrin")
	var sakura = battle.get_actor("sakura")
	var bar: Array = SkillBarViewScript.build_entries(battle)

	_check(sakura.shield == 0, "no shield before the cast")
	_check(not BoardViewScript.can_target(battle, bar, "oath_shield", "vanguard_00"), "a support skill is not offered against an enemy")

	_check(battle.request_skill(&"oath_shield", "sakura"), "Oath Shield can name the ally as its target")
	_check(sakura.shield > 0, "the named ally is shielded")
	_check(sevrin.shield > 0, "the caster is shielded as well")
	battle.queue_free()

	# Out of reach: an ally three cells away is still refused.
	var far = ControllerScript.new()
	root.add_child(far)
	var far_ids: Array[String] = ["sevrin", "sakura"]
	far.start_encounter(Vector2i(1, 1), [Vector2i(6, 6)], [], [], far_ids, [Vector2i(1, 4)])
	_check(not far.request_skill(&"oath_shield", "sakura"), "an ally three cells away cannot be named")
	far.queue_free()


## 残香 belongs to a living target. Damage already cleared the corpse's statuses,
## so marking afterwards left one behind for the mark's full three enemy phases -
## and the other multi-target skill guards against exactly that.
func _test_a_dead_target_is_not_marked() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sakura"]
	# A second enemy keeps the battle alive, so nothing else clears the statuses.
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1), Vector2i(1, 6)], [], [], ids, [])
	var enemy = battle.get_actor("vanguard_00")
	enemy.health = 1
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "the killing blow resolves")
	_check(enemy.is_defeated(), "the target is down")
	_check(not battle.statuses.has_status("vanguard_00", &"sakura_petal_mark"), "a dead target carries no mark")

	var survivor = battle.get_actor("vanguard_01")
	survivor.cell = Vector2i(1, 2)
	battle.get_actor("sakura").cell = Vector2i(1, 1)
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_01"), "a second Pierce Blossom resolves")
	_check(battle.statuses.has_status("vanguard_01", &"sakura_petal_mark"), "a surviving target is still marked")


## The framework claim being tested: the caster is whoever is commanded, not the
## character the prototype started with. Damage numbers make this observable -
## Sakura's 600 attack and Sevrin's 650 produce different results from the same
## distance against the same defense.
func _test_cast_uses_the_commanded_character() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	# Sakura at (2,2) so the enemy at (2,1) is adjacent to both: the normal attack
	# needs adjacency and the comparison is about who casts, not about reach.
	var allies: Array[Vector2i] = [Vector2i(3, 2)]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], ids, allies)
	battle.beacons.clear()
	_check(battle.active_character_id == "sevrin", "the first deployed character starts in command")

	var adjacent = battle.get_actor("vanguard_00")
	# Sevrin's 650 attack against 450 defense: floor(650 * 1000 / 1450) = 448 (and knocks vanguard to (3, 1))
	var before_sevrin: int = adjacent.health
	_check(battle.request_skill(&"oathblade", "vanguard_00"), "Sevrin's normal attack resolves")
	_check(before_sevrin - adjacent.health == 448, "Sevrin's attack uses Sevrin's attack stat")

	_check(battle.set_active_character("sakura"), "command switches to Sakura")
	# Sakura at (3, 2) is now adjacent to the knocked-back vanguard at (3, 1).
	# Sakura's 600 attack against 450 defense: floor(600 * 1000 / 1450) = 413
	var before_sakura: int = adjacent.health
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "Sakura's attack resolves after switching")
	_check(before_sakura - adjacent.health == 413, "the same enemy takes Sakura's number, so the caster really changed")
	battle.queue_free()


## Movement was the other hardcoded path: it walked a fixed actor regardless of
## who was being commanded, so a switched character could not move at all.
func _test_movement_uses_the_commanded_character() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	var allies: Array[Vector2i] = [Vector2i(1, 5)]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(6, 6)], [], [], ids, allies)
	_check(battle.set_active_character("sakura"), "command switches to Sakura")

	var ap_before: int = battle.ap.current
	var move_path: Array[Vector2i] = [Vector2i(1, 4)]
	_check(battle.request_player_move(move_path), "the commanded character can move")
	_check(battle.get_actor("sakura").cell == Vector2i(1, 4), "Sakura moved, not the prototype character")
	_check(battle.get_actor("sevrin").cell == Vector2i(1, 1), "Sevrin stayed where he was")
	_check(battle.ap.current == ap_before - 1, "the move drew from the shared pool")
	battle.queue_free()


## Oath Vow is a passive, so it belongs to the unit carrying it. Sakura does not
## have it; without this check the hook would silently feed her a resource she
## has no business owning.
func _test_oath_vow_follows_the_passive_not_the_character() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sakura"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], ids, [])
	battle.beacons.clear()
	battle.intents = IntentPlannerScript.plan(battle)
	_check(not battle.has_passive("sakura", &"oath_vow"), "Sakura does not carry Oath Vow")
	_check(battle.end_player_turn(), "the enemy attack resolves against Sakura")
	_check(battle.get_oath_vow_stacks("sakura") == 0, "being hit grants Oath Vow only to a unit that has the passive")

	var sevrin_battle = ControllerScript.new()
	root.add_child(sevrin_battle)
	sevrin_battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)])
	sevrin_battle.beacons.clear()
	sevrin_battle.intents = IntentPlannerScript.plan(sevrin_battle)
	_check(sevrin_battle.has_passive("sevrin", &"oath_vow"), "Sevrin carries Oath Vow")
	_check(sevrin_battle.end_player_turn(), "the enemy attack resolves against Sevrin")
	_check(sevrin_battle.get_oath_vow_stacks() == 1, "the passive holder does accumulate a stack")
	battle.queue_free()
	sevrin_battle.queue_free()


## The taunt used to look for a character by id. It now looks for the status, so
## the guardian is whoever holds it - including a character the prototype never
## had.
func _test_absolute_guard_follows_the_status() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin", "sakura"]
	var allies: Array[Vector2i] = [Vector2i(1, 4)]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], ids, allies)

	_check(battle.get_absolute_guardian().is_empty(), "nobody guards before the stance is up")
	_check(battle.statuses.apply_status(&"absolute_guard", "sakura", "sakura", 1, 1, -1, &"player_phase_start", &"replace"), "the stance can be placed on any party member")
	_check(battle.get_absolute_guardian() == "sakura", "the guardian is the status holder, not a fixed character")
	battle.queue_free()


## §13: a successful active action grants one ultimate energy per turn, for
## every character. The two active skills honour it; the normal-attack slot
## stays out pending the design adjudication, and the ultimate never grants
## its own energy.
func _test_active_skills_grant_ultimate_energy() -> void:
	var battle = _sakura_battle()
	var sakura = battle.get_actor("sakura")
	# Keep Sakura alive across the enemy's melee tolerance counter + charged cleave
	# so this test stays focused on per-turn ultimate energy bookkeeping.
	sakura.max_health = 5000
	sakura.health = 5000
	_check(sakura.ultimate_energy == 1, "Sakura starts with the turn-start energy")

	_check(battle.request_skill(&"sakura_flowing_wind", "vanguard_00"), "Flowing Wind resolves")
	_check(sakura.ultimate_energy == 2, "the first active action of a turn grants one energy")
	_check(battle.request_skill(&"sakura_falling_petals", "vanguard_00"), "Falling Petals resolves")
	_check(sakura.ultimate_energy == 2, "a second action the same turn stays capped at one grant")

	battle.end_player_turn()
	_check(sakura.ultimate_energy == 3, "the next turn start adds one energy")
	_check(battle.request_skill(&"sakura_falling_petals", "vanguard_00"), "Falling Petals resolves on the new turn")
	_check(sakura.ultimate_energy == 4, "the first active action of the new turn grants one energy")
	battle.queue_free()


## §13 grants one ultimate energy per character per turn for a successful active
## action. Pierce Blossom was the one branch that skipped it, so which button the
## player pressed decided whether they got energy. Written as a loop over the two
## single-target skills plus the rectangle rather than as one call, because the
## whole point is that the rule does not depend on which skill it was.
func _test_every_sakura_action_grants_the_same_energy() -> void:
	var cases := [
		{"skill": &"sakura_pierce_blossom", "enemy": Vector2i(2, 1), "label": "Pierce Blossom"},
		{"skill": &"sakura_flowing_wind", "enemy": Vector2i(2, 1), "label": "Flowing Wind"},
	]
	for entry in cases:
		var battle = ControllerScript.new()
		root.add_child(battle)
		var ids: Array[String] = ["sakura"]
		battle.start_encounter(Vector2i(1, 1), [entry["enemy"]], [], [], ids, [])
		var sakura = battle.get_actor("sakura")
		var before: int = sakura.ultimate_energy
		_check(battle.request_skill(entry["skill"], "vanguard_00"), "%s resolves" % entry["label"])
		_check(sakura.ultimate_energy == before + 1, "%s grants one ultimate energy" % entry["label"])
		battle.queue_free()

	# The once-per-turn cap applies across skills, not per skill: a second action
	# in the same turn must not pay again.
	var capped = ControllerScript.new()
	root.add_child(capped)
	var capped_ids: Array[String] = ["sakura"]
	capped.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], capped_ids, [])
	var capped_sakura = capped.get_actor("sakura")
	_check(capped.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "first action resolves")
	var after_first: int = capped_sakura.ultimate_energy
	_check(capped.request_skill(&"sakura_flowing_wind", "vanguard_00"), "second action resolves")
	_check(capped_sakura.ultimate_energy == after_first, "the second action in the same turn grants no further energy")
	capped.queue_free()


## §19-23 极意: full intent strengthens the next active skill and is then spent.
## The numbers here are the plan's - 40% follow-up, 65% echo return - so a change
## to either constant shows up as a failure rather than a quiet rebalance.
func _test_extreme_strengthens_the_next_active_skill() -> void:
	# Flowing Wind at 极意: 80% dash strike plus the 40% second strike.
	# floor(480*1000/1450) = 331, floor(240*1000/1450) = 165.
	var dash = ControllerScript.new()
	root.add_child(dash)
	var dash_ids: Array[String] = ["sakura"]
	dash.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], dash_ids, [])
	var dash_sakura = dash.get_actor("sakura")
	var dash_enemy = dash.get_actor("vanguard_00")
	dash_sakura.resource_current = 4
	_check(dash_sakura.is_resource_full(), "four stacks is the 极意 state")
	var before: int = dash_enemy.health
	_check(dash.request_skill(&"sakura_flowing_wind", "vanguard_00"), "an extreme Flowing Wind resolves")
	_check(before - dash_enemy.health == 496, "the dash strikes for 80% then follows up for 40%")
	# Spent first, then the action's own gain applies (§19).
	_check(dash_sakura.resource_current == 1, "using an enhanced skill spends the bar, then the action earns one")
	dash.queue_free()

	# The same skill without 极意 must not gain the follow-up - otherwise the
	# assertion above would pass for the wrong reason.
	var plain = ControllerScript.new()
	root.add_child(plain)
	var plain_ids: Array[String] = ["sakura"]
	plain.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], plain_ids, [])
	var plain_sakura = plain.get_actor("sakura")
	var plain_enemy = plain.get_actor("vanguard_00")
	plain_sakura.resource_current = 3
	var plain_before: int = plain_enemy.health
	_check(plain.request_skill(&"sakura_flowing_wind", "vanguard_00"), "a non-extreme Flowing Wind resolves")
	_check(plain_before - plain_enemy.health == 331, "without 极意 the dash strikes once")
	plain.queue_free()

	# 落英 at 极意: the rectangle grows and the echo return rises to 65%.
	var petals = ControllerScript.new()
	root.add_child(petals)
	var petal_ids: Array[String] = ["sakura"]
	# (2,1) adjacent and pre-marked; (2,3) sits one row outside the base block.
	petals.start_encounter(Vector2i(1, 1), [Vector2i(2, 1), Vector2i(2, 3)], [], [], petal_ids, [])
	var petal_sakura = petals.get_actor("sakura")
	var near = petals.get_actor("vanguard_00")
	var outside = petals.get_actor("vanguard_01")
	petals.statuses.apply_status(&"sakura_petal_mark", "sakura", "vanguard_00", 1, 1, -1, &"")
	petal_sakura.resource_current = 4
	var near_before: int = near.health
	var outside_before: int = outside.health
	_check(petals.request_skill(&"sakura_falling_petals", "vanguard_00"), "an extreme Falling Petals resolves")
	# 321 from three segments, plus 65% echo: floor(338*1000/1450) = 233.
	_check(near_before - near.health == 554, "the marked target takes the segments and a 65% echo return")
	_check(outside_before - outside.health == 321, "the expanded block reaches one extra row")
	petals.queue_free()

	# 极意 is not spent by the other actions.
	var plain_attack = ControllerScript.new()
	root.add_child(plain_attack)
	var attack_ids: Array[String] = ["sakura"]
	plain_attack.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], attack_ids, [])
	var attack_sakura = plain_attack.get_actor("sakura")
	attack_sakura.resource_current = 4
	_check(plain_attack.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "Pierce Blossom resolves at full intent")
	_check(attack_sakura.resource_current >= 4, "a normal attack neither spends nor clears 极意")
	plain_attack.queue_free()


## §19 lists five ways to earn intent: turn start, movement, attacks, kills and
## the first echo return of a turn. The kill clause was missing from the code
## while the decision sheet claimed the whole item was unaddressed - the first
## echo return had been there since the kit landed. Both are pinned here.
func _test_kills_pay_intent_inside_the_budget() -> void:
	# One kill on top of the action's own stack.
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sakura"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], ids, [])
	var sakura = battle.get_actor("sakura")
	var enemy = battle.get_actor("vanguard_00")
	sakura.resource_current = 1
	enemy.health = 1
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "the killing blow resolves")
	_check(enemy.is_defeated(), "the target is defeated")
	_check(sakura.resource_current == 3, "a kill pays one extra stack on top of the action's own")
	battle.queue_free()

	# §19/§30 order: the action's stack lands before the kill's, which is only
	# observable in the event log when the per-turn budget is nearly spent. The
	# sheet requires this order to be pinned by a test rather than assumed.
	var order = ControllerScript.new()
	root.add_child(order)
	var order_ids: Array[String] = ["sakura"]
	order.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], order_ids, [])
	var order_sakura = order.get_actor("sakura")
	var order_enemy = order.get_actor("vanguard_00")
	order_sakura.resource_current = 1
	order_enemy.health = 1
	var gains: Array = []
	order.battle_event.connect(func(event):
		if event["type"] == "resource_gained":
			gains.append(String(event["detail"]))
	)
	_check(order.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "the ordered action resolves")
	_check(gains.size() == 2, "the action and the kill each report a stack")
	_check(gains[0].contains("reason=action"), "the action's stack is credited first")
	_check(gains[1].contains("reason=kill"), "the kill's stack follows the action")
	order.queue_free()

	# With the budget nearly spent, the action takes the last stack and the kill
	# gets nothing - and must not report a gain it did not receive.
	var capped = ControllerScript.new()
	root.add_child(capped)
	var capped_ids: Array[String] = ["sakura"]
	capped.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], capped_ids, [])
	var capped_sakura = capped.get_actor("sakura")
	var capped_enemy = capped.get_actor("vanguard_00")
	capped_sakura.resource_current = 1
	capped_enemy.health = 1
	capped.ledger.resource_gain_turn["sakura"] = capped.turn_number
	capped.ledger.resource_gain_count["sakura"] = 2
	var capped_gains: Array = []
	capped.battle_event.connect(func(event):
		if event["type"] == "resource_gained":
			capped_gains.append(String(event["detail"]))
	)
	_check(capped.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "the capped action resolves")
	_check(capped_sakura.resource_current == 2, "the action takes the last stack")
	_check(capped_gains.size() == 1 and capped_gains[0].contains("reason=action"), "the kill reports nothing when the budget is spent")
	capped.queue_free()

	# Two kills in one action still respect the three-stack action budget, so the
	# total is capped rather than doubled.
	var wide = ControllerScript.new()
	root.add_child(wide)
	var wide_ids: Array[String] = ["sakura"]
	# A third enemy far away keeps the battle from ending on the double kill.
	wide.start_encounter(Vector2i(1, 1), [Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 6)], [], [], wide_ids, [])
	var wide_sakura = wide.get_actor("sakura")
	wide_sakura.resource_current = 0
	wide.get_actor("vanguard_00").health = 1
	wide.get_actor("vanguard_01").health = 1
	_check(wide.request_skill(&"sakura_falling_petals", "vanguard_00"), "the double kill resolves")
	_check(wide_sakura.resource_current == 3, "two kills and the action are capped at three stacks")
	wide.queue_free()

	# A character without a resource must not be affected by the kill credit.
	var sevrin = ControllerScript.new()
	root.add_child(sevrin)
	var sevrin_ids: Array[String] = ["sevrin"]
	sevrin.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], sevrin_ids, [])
	sevrin.get_actor("vanguard_00").health = 1
	_check(sevrin.request_skill(&"oathblade", "vanguard_00"), "Sevrin's killing blow resolves")
	_check(sevrin.get_actor("vanguard_00").is_defeated(), "the enemy dies to a character with no intent track")
	sevrin.queue_free()

	# The first echo return of a turn pays a stack; the second in the same turn
	# does not. This is the clause the decision sheet wrongly called unimplemented.
	var echo = ControllerScript.new()
	root.add_child(echo)
	var echo_ids: Array[String] = ["sakura"]
	echo.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], echo_ids, [])
	var echo_sakura = echo.get_actor("sakura")
	echo.statuses.apply_status(&"sakura_petal_mark", "sakura", "vanguard_00", 1, 1, -1, &"")
	echo_sakura.resource_current = 1
	_check(echo.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "the marked target is struck")
	_check(echo_sakura.resource_current == 3, "the first echo return pays a stack as well as the action")
	echo.queue_free()
