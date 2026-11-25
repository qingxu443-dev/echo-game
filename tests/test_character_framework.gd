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


func _run() -> void:
	_test_characters_come_from_data()
	_test_sevrin_normal_attack()
	_test_party_spawns_from_the_level_sheet()
	_test_switching_is_free_and_party_wide()
	_test_movement_follows_the_active_character()
	_test_a_character_cannot_borrow_another_kit()
	_test_pierce_blossom_applies_the_mark_without_follow_up()
	_test_second_hit_triggers_echo_return()
	_test_blade_intent_accumulates_and_caps()
	_test_petal_mark_lasts_three_enemy_turns()
	_test_endless_fragrance_scales_with_intent()
	_test_falling_petals_covers_the_rectangle_in_front()
	_test_flowing_wind_respects_its_range()
	_test_a_dead_target_is_not_marked()
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
	_check(sakura.max_health == 1800 and sakura.attack == 520, "Sakura's sheet carries the planned panel")
	_check(sakura.has_resource() and String(sakura.resource_id) == "blade_intent", "Sakura's sheet declares blade intent")

	var skills := SkillRegistryScript.skills_for_character("sakura")
	_check(skills.size() == 5, "Sakura brings five slots")
	var active := SkillRegistryScript.active_skills_for_character("sakura")
	_check(active.size() == 4, "the passive is not a button")


## §15: every character has a normal attack. Sevrin's takes the shared executor.
func _test_sevrin_normal_attack() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var ids: Array[String] = ["sevrin"]
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], [], [], ids, [])
	var enemy = battle.get_actor("vanguard_00")
	var health_before: int = enemy.health
	var ap_before: int = battle.ap.current

	_check(battle.request_skill(&"oathblade", "vanguard_00"), "the Oathblade resolves on an adjacent enemy")
	# 2000 ATK x 1.0 against 700 defense: floor(2000 * 1000 / 1700) = 1176
	_check(health_before - enemy.health == 1176, "the normal attack deals full attack through defense")
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
	# 520 ATK x 1.0 against 700 defense: floor(520 * 1000 / 1700) = 305
	_check(dealt == 305, "the first hit deals its own damage only")
	_check(battle.statuses.has_status("vanguard_00", &"sakura_petal_mark"), "the hit applies the petal mark")
	battle.queue_free()


func _test_second_hit_triggers_echo_return() -> void:
	var battle = _sakura_battle()
	var enemy = battle.get_actor("vanguard_00")
	battle.request_skill(&"sakura_pierce_blossom", "vanguard_00")
	var health_before: int = enemy.health

	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_00"), "the second Pierce Blossom resolves")
	var dealt: int = health_before - enemy.health
	# 305 from the hit plus floor(260 * 1000 / 1700) = 152 from the follow-up
	_check(dealt == 457, "an already-marked target also takes the echo return")
	battle.queue_free()


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
	# floor(104*1000/1700)=61 x3 plus floor(416*1000/1700)=244
	var dealt: int = health_before - enemy.health
	_check(dealt == 427, "the cross hits four times with the intent-scaled finisher")
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

	# Three segments of 30%: floor(156 * 1000 / 1700) = 91 each, so 273.
	_check(near_before - near.health == 273, "the aimed target takes all three segments")
	_check(side_before - side.health == 273, "a target beside the axis is inside the block and also takes three")
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
	var inside_sakura = inside.get_actor("sakura")
	var enemy = inside.get_actor("vanguard_00")
	var health_before: int = enemy.health
	_check(inside.request_skill(&"sakura_flowing_wind", "vanguard_00"), "a target three cells away is inside the dash range")
	_check(inside_sakura.cell == Vector2i(3, 1), "the dash lands two cells closer")
	# floor(416 * 1000 / 1700) = 244
	_check(health_before - enemy.health == 244, "the dash strikes once it arrives")
	inside.queue_free()


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
	_check(enemy.is_defeated, "the target is down")
	_check(not battle.statuses.has_status("vanguard_00", &"sakura_petal_mark"), "a dead target carries no mark")

	var survivor = battle.get_actor("vanguard_01")
	survivor.cell = Vector2i(1, 2)
	battle.get_actor("sakura").cell = Vector2i(1, 1)
	_check(battle.request_skill(&"sakura_pierce_blossom", "vanguard_01"), "a second Pierce Blossom resolves")
	_check(battle.statuses.has_status("vanguard_01", &"sakura_petal_mark"), "a surviving target is still marked")
	battle.queue_free()
