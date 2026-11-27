extends "res://tests/framework/test_case.gd"

## 四名精英的专属技能：从「借招」变成真正的机制。
##
## Why this suite exists: 樱华蓄斩 / 百花锁命 / 逐影突袭 / 腐樱诅咒 were the last
## four lines of §14 still borrowing another enemy's move. Each one needs a
## mechanic the battle layer did not have - an interruptible telegraph, a mark
## that resolves a phase later, a telegraphed path, and a defence debuff - so the
## sheets could not express them by data alone. These assertions drive real turns
## and check what a player would see: the telegraph, the cancel, the hit number
## and the stat that comes back when the debuff lapses.
##
## Everything runs the controller, not the .tres: reading `actions` back would
## stay green even if the planner ignored the new branches.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const PlannerScript = preload("res://scripts/battle/intent_planner.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const DamageTypesScript = preload("res://scripts/battle/damage_types.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")

const HERO := "sakura"
var _events: Array = []


func _run() -> void:
	_test_crimson_charge_is_interruptible()
	_test_uninterrupted_charge_still_lands()
	_test_interrupt_does_not_touch_ordinary_charges()
	_test_lock_on_then_shot_next_phase()
	_test_lock_breaks_when_target_leaves_reach()
	_test_shadow_raid_paths_and_strikes()
	_test_shadow_raid_stays_home_beyond_four_cells()
	_test_rot_curse_strips_defense_once()
	_test_rot_curse_expires_after_next_enemy_phase()
	_test_sheets_carry_the_new_actions()


## Builds a one-on-one fight with Sakura as the commanded hero. Beacons are
## removed so the elites look at the hero instead of a relic objective.
func _spawn(archetype: String, hero_cell: Vector2i, enemy_cell: Vector2i):
	_events.clear()
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.battle_event.connect(_on_event)
	var cells: Array[Vector2i] = [enemy_cell]
	var archetypes: Array[String] = [archetype]
	var roster: Array[String] = [HERO]
	battle.start_encounter(hero_cell, cells, [], archetypes, roster)
	battle.beacons.clear()
	battle.intents = PlannerScript.plan(battle)
	return battle


func _on_event(event: Dictionary) -> void:
	_events.append(event)


func _event_seen(event_type: String) -> bool:
	for event in _events:
		if String(event.get("type", "")) == event_type:
			return true
	return false


## The resolver records the action it executed in the event detail, so this is
## how a test tells "the signature fired" from "the enemy fell back to a basic
## shot that happens to deal damage too".
func _resolved_action(action_id: String) -> bool:
	for event in _events:
		if String(event.get("type", "")) == "enemy_action_resolved" and String(event.get("detail", "")) == action_id:
			return true
	return false


func _active_intent(battle, actor_id: String):
	for intent in battle.intents:
		if intent.source_actor_id == actor_id and intent.state == IntentScript.IntentState.ACTIVE:
			return intent
	return null


func _test_crimson_charge_is_interruptible() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var enemy = battle.actors["crimson_sword_guard_00"]
	var hero = battle.actors[HERO]
	var intent = _active_intent(battle, enemy.actor_id)
	_check(intent != null and intent.action_id == "charged_strike", "绯樱剑卫满充能时预告樱华蓄斩（锁定 3×2 范围）")
	_check(intent != null and intent.interruptible, "樱华蓄斩被标记为可打断，别的蓄力技不能")
	var hero_health_before: int = hero.health
	_check(battle.request_skill(&"sakura_flowing_wind", enemy.actor_id), "樱的流风可以命中蓄势中的剑卫")
	_check(intent != null and intent.state == IntentScript.IntentState.CANCELED, "流风命中后蓄斩预告被取消")
	_check(enemy.skill_charge == 0, "打断同时清空充能条，需要重新积累")
	_check(_event_seen("enemy_skill_interrupted"), "事件流记录下这次打断")
	battle.end_player_turn()
	_check(hero.health == hero_health_before, "被打断的蓄斩不再结算伤害")
	_check(not battle.actors.has(enemy.actor_id) or enemy.skill_charge == 0, "打断后没有偷偷恢复充能")


func _test_uninterrupted_charge_still_lands() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var hero = battle.actors[HERO]
	var health_before: int = hero.health
	battle.end_player_turn()
	_check(hero.health < health_before, "不打断时樱华蓄斩照常落下（对照，防止打断逻辑吞掉伤害）")


## The interrupt is keyed on the intent's flag, not on the action id: a vanguard
## wind-up is the same `charged_strike` and must survive the dash. Without this
## test, marking every charge interruptible would still pass the suite above.
func _test_interrupt_does_not_touch_ordinary_charges() -> void:
	var battle = _spawn("vanguard", Vector2i(2, 2), Vector2i(3, 2))
	var enemy = battle.actors["vanguard_00"]
	var intent = _active_intent(battle, enemy.actor_id)
	_check(intent != null and intent.action_id == "charged_strike", "先锋同样预告蓄力横扫")
	_check(intent != null and not intent.interruptible, "普通先锋的蓄力没有可打断标记")
	battle.request_skill(&"sakura_flowing_wind", enemy.actor_id)
	_check(intent != null and intent.state == IntentScript.IntentState.ACTIVE, "流风打不断未标记的普通蓄力")


func _test_lock_on_then_shot_next_phase() -> void:
	var battle = _spawn("hundred_bloom_sniper", Vector2i(5, 2), Vector2i(2, 2))
	var enemy = battle.actors["hundred_bloom_sniper_00"]
	var hero = battle.actors[HERO]
	var first = _active_intent(battle, enemy.actor_id)
	_check(first != null and first.action_id == "lock_on", "百花狙击手先预告锁命标记")
	_check(first != null and first.damage == 0, "锁命本身不造成伤害")
	battle.end_player_turn()
	_check(enemy.lock_target_id == hero.actor_id, "敌方阶段把标记落在樱身上")
	_check(hero.health == hero.max_health, "标记当回合不结算伤害，玩家有一整个回合应对")
	var second = _active_intent(battle, enemy.actor_id)
	_check(second != null and second.action_id == "locked_shot", "下一回合才预告锁命箭")
	_check(second != null and second.damage == 1380, "锁命箭伤害取档案钉死的 1380")
	battle.end_player_turn()
	_check(hero.health < hero.max_health, "锁命箭在下一敌方阶段结算")
	_check(_resolved_action("locked_shot"), "结算的动作是锁命箭，不是退化成普通点射")
	_check(enemy.lock_target_id.is_empty(), "射出后清掉标记，不会连续两箭")


func _test_lock_breaks_when_target_leaves_reach() -> void:
	var battle = _spawn("hundred_bloom_sniper", Vector2i(5, 2), Vector2i(2, 2))
	var enemy = battle.actors["hundred_bloom_sniper_00"]
	var hero = battle.actors[HERO]
	battle.end_player_turn()
	_check(enemy.lock_target_id == hero.actor_id, "先形成锁定")
	hero.cell = Vector2i(7, 7)
	var planned = PlannerScript.plan(battle)
	var still_telegraphed := false
	for intent in planned:
		if intent.action_id == "locked_shot":
			still_telegraphed = true
	_check(not still_telegraphed, "目标脱离 6 格后不再预告锁命箭")
	battle.finish_enemy_phase_stepped()
	_check(enemy.lock_target_id.is_empty(), "脱离射程的锁定被清理")
	_check(_event_seen("enemy_lock_broken"), "事件流记录破锁原因")


func _test_shadow_raid_paths_and_strikes() -> void:
	var battle = _spawn("gale_blade", Vector2i(2, 2), Vector2i(5, 2))
	var enemy = battle.actors["gale_blade_00"]
	var hero = battle.actors[HERO]
	var intent = _active_intent(battle, enemy.actor_id)
	_check(intent != null and intent.action_id == "shadow_raid", "4 格内逐风刃客预告逐影突袭")
	_check(intent != null and intent.move_path.size() == 2, "路径只有 2 格时不会多走")
	_check(intent != null and intent.damage == 1260, "突袭伤害按档案钉死 1260")
	battle.end_player_turn()
	_check(GridRulesScript.manhattan_distance(enemy.cell, hero.cell) == 1, "按路径移动到目标相邻格")
	_check(hero.health < hero.max_health, "突袭落地后造成伤害")


func _test_shadow_raid_stays_home_beyond_four_cells() -> void:
	var battle = _spawn("gale_blade", Vector2i(1, 1), Vector2i(6, 1))
	var enemy = battle.actors["gale_blade_00"]
	var intent = _active_intent(battle, enemy.actor_id)
	_check(intent == null or intent.action_id != "shadow_raid", "5 格外不发动突袭，改为逼近")


func _test_rot_curse_strips_defense_once() -> void:
	var battle = _spawn("rotten_blossom_witch", Vector2i(2, 2), Vector2i(5, 2))
	var enemy = battle.actors["rotten_blossom_witch_00"]
	var hero = battle.actors[HERO]
	var intent = _active_intent(battle, enemy.actor_id)
	_check(intent != null and intent.action_id == "rot_curse", "4 格内腐樱巫灵预告腐樱诅咒")
	_check(intent != null and intent.damage == 100, "诅咒载荷是 100 点防御，不是伤害")
	_check(DamageTypesScript.resistance_for(hero, "physical") == 180, "施法前樱的物理防御是 180")
	battle.end_player_turn()
	_check(hero.defense_penalty == 100, "诅咒剥掉 100 防御")
	_check(DamageTypesScript.resistance_for(hero, "physical") == 80, "有效防御降到 80")
	_check(battle.statuses.has_status(hero.actor_id, &"rot_curse"), "诅咒作为状态挂在目标身上")
	# 不叠加：再来一次仍是 100，而不是 200。
	enemy.skill_charge = enemy.skill_charge_max
	battle.intents = PlannerScript.plan(battle)
	var again = _active_intent(battle, enemy.actor_id)
	_check(again != null and again.action_id == "rot_curse", "冷却结束后可以再次诅咒")
	battle.end_player_turn()
	_check(hero.defense_penalty == 100, "重复诅咒只刷新时长，不叠加到 200")


func _test_rot_curse_expires_after_next_enemy_phase() -> void:
	var battle = _spawn("rotten_blossom_witch", Vector2i(2, 2), Vector2i(5, 2))
	var hero = battle.actors[HERO]
	battle.end_player_turn()
	_check(hero.defense_penalty == 100, "先挂上诅咒")
	_check(hero.defense_penalty_expiry_turn == battle.turn_number, "到期回合是施放后的下一回合")
	battle.turn_number = hero.defense_penalty_expiry_turn
	battle.finish_enemy_phase_stepped()
	_check(hero.defense_penalty == 0, "下一敌方阶段结束后防御恢复")
	_check(DamageTypesScript.resistance_for(hero, "physical") == 180, "恢复后的有效防御回到 180")
	_check(_event_seen("enemy_curse_expired"), "事件流记录诅咒到期")


func _test_sheets_carry_the_new_actions() -> void:
	var crimson = EnemyCatalogScript.get_definition("crimson_sword_guard")
	_check(crimson != null and crimson.interruptible_skill, "绯樱剑卫档案标记蓄斩可打断")
	var sniper = EnemyCatalogScript.get_definition("hundred_bloom_sniper")
	_check(sniper != null and String(sniper.actions[0]) == "lock_on", "百花狙击手首选锁命")
	_check(sniper != null and not sniper.actions.has(&"aimed_shot"), "锁命取代通用贯通狙，不再借招")
	var blade = EnemyCatalogScript.get_definition("gale_blade")
	_check(blade != null and String(blade.actions[0]) == "shadow_raid", "逐风刃客首选逐影突袭")
	_check(blade != null and blade.skill_damage == 1260, "逐影突袭伤害与基础攻击解耦")
	var witch = EnemyCatalogScript.get_definition("rotten_blossom_witch")
	_check(witch != null and String(witch.actions[0]) == "rot_curse", "腐樱巫灵首选腐樱诅咒")
	_check(witch != null and witch.curse_defense_down == 100, "诅咒数值写在档案里，不在代码里")
