extends "res://tests/framework/test_case.gd"

## 预告与结算必须同源（§15 预告可信度）。
##
## Why this suite exists: the board badge and the order list both printed
## `intent.damage`, which is the number BEFORE defence. A 1688 樱华蓄斩 read as
## 1688 on screen but removed 1430 from a defence-180 樱, and no test failed
## when those two drifted apart - they only agreed because nobody had changed
## the formula yet. These assertions pin the promise to the bill: whatever the
## telegraph quotes, ending the turn must remove exactly that much.
##
## The fix is structural rather than cosmetic. BattleActor.mitigated_damage is
## the single mitigation expression; apply_damage_with_result and
## preview_damage both call it, so a future tweak to shields, resistance or
## percentage reductions moves the quote and the charge together.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const PlannerScript = preload("res://scripts/battle/intent_planner.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const HudViewScript = preload("res://scripts/ui/hud_view.gd")

const HERO := "sakura"
## 绯樱剑卫的樱华蓄斩钉死 1688；樱防御 180，1688 * 1000 / 1180 = 1430.5 → 1430.
const CHARGE_RAW := 1688
const CHARGE_AFTER_DEFENCE := 1430


func _run() -> void:
	_test_charge_quote_equals_health_lost()
	_test_shield_is_deducted_from_the_quote()
	_test_magical_quote_uses_magic_resistance()
	_test_quote_tracks_defence_penalty()
	_test_preview_leaves_state_untouched()
	_test_shield_and_curse_payloads_are_not_health_damage()
	_test_ordered_threat_totals()
	_test_curse_applies_in_preview_order()


func _spawn(archetype: String, hero_cell: Vector2i, enemy_cell: Vector2i):
	var battle = ControllerScript.new()
	root.add_child(battle)
	var cells: Array[Vector2i] = [enemy_cell]
	var archetypes: Array[String] = [archetype]
	var roster: Array[String] = [HERO]
	battle.start_encounter(hero_cell, cells, [], archetypes, roster)
	battle.beacons.clear()
	battle.intents = PlannerScript.plan(battle)
	return battle


func _active_intent(battle, actor_id: String):
	for intent in battle.intents:
		if intent.source_actor_id == actor_id and intent.state == IntentScript.IntentState.ACTIVE:
			return intent
	return null


## 核心断言：预告多少，就掉多少。
func _test_charge_quote_equals_health_lost() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var hero = battle.actors[HERO]
	var enemy = battle.actors["crimson_sword_guard_00"]
	var intent = _active_intent(battle, enemy.actor_id)
	_check(intent != null, "绯樱剑卫预告樱华蓄斩")
	if intent == null:
		return
	var quoted: int = intent.preview_health_damage(battle)
	_check(quoted == CHARGE_AFTER_DEFENCE, "1688 原始伤害对防御 180 的樱预告成 1430")
	_check(quoted < intent.damage, "预告值必须已扣防御，不能直接等于原始伤害")
	var before: int = hero.health
	battle.end_player_turn()
	_check(before - hero.health == quoted, "实际掉血与预告逐点相等（不是差不多，是相等）")


## 护盾是资源，先于 HP 被吃，预告必须跟着减。
func _test_shield_is_deducted_from_the_quote() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var hero = battle.actors[HERO]
	hero.shield = 400
	var intent = _active_intent(battle, "crimson_sword_guard_00")
	_check(intent != null, "有护盾时蓄斩照常预告")
	if intent == null:
		return
	var quoted: int = intent.preview_health_damage(battle)
	_check(quoted == CHARGE_AFTER_DEFENCE - 400, "护盾先吃掉 400，预告只剩 1030")
	var before: int = hero.health
	battle.end_player_turn()
	_check(before - hero.health == quoted, "结算同样只扣 1030，护盾与预告同步")


## 法术走魔抗而不是防御：同一条 preview 必须认 damage_type。
func _test_magical_quote_uses_magic_resistance() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var hero = battle.actors[HERO]
	var physical: int = hero.preview_damage(1000, "physical")
	var magical: int = hero.preview_damage(1000, "magical")
	# 1000 * 1000 / 1180 = 847；1000 * 1000 / 1111 = 900
	_check(physical == 847, "物理预告按防御 180 减免到 847")
	_check(magical == 900, "法术预告按魔抗 111 减免到 900")
	_check(physical != magical, "两种类型的预告不能是同一个数，否则说明类型没进公式")


## 腐樱诅咒降防 100，预告必须立刻反映，否则玩家会低估后续挨打。
func _test_quote_tracks_defence_penalty() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var hero = battle.actors[HERO]
	var clean: int = hero.preview_damage(CHARGE_RAW, "physical")
	hero.defense_penalty = 100
	var cursed: int = hero.preview_damage(CHARGE_RAW, "physical")
	_check(cursed > clean, "降防 100 后同一发蓄斩的预告必须变大")
	_check(cursed == hero.mitigated_damage(CHARGE_RAW, "physical"), "预告与减伤公式在降防下仍逐点一致")
	# 180 - 100 = 80 → 1688 * 1000 / 1080 = 1562。若降防被扣两次（旧参数通道），
	# 这里会变成 1688 全额，玩家会以为诅咒没效果。
	_check(cursed == 1562, "降防 100 只扣一次：1688 变成 1562，不是 1688 全额")


## 预告是只读的：算一遍不许动血、盾或任何状态。
func _test_preview_leaves_state_untouched() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var hero = battle.actors[HERO]
	hero.shield = 250
	var health_before: int = hero.health
	var shield_before: int = hero.shield
	for i in range(3):
		hero.preview_damage(5000, "physical")
	_check(hero.health == health_before, "预览多次不掉血")
	_check(hero.shield == shield_before, "预览多次不磨盾")


## 护盾/降防载荷不是 HP 伤害，界面靠这两个判断绕开 preview。
## 若将来有人把 ward_stance 也从 preview 走，这条会红。
func _test_shield_and_curse_payloads_are_not_health_damage() -> void:
	_check(HudViewScript._is_shield_action("ward_ally"), "古木壁垒的载荷是护盾")
	_check(HudViewScript._is_shield_action("ward_stance"), "结界守护的载荷是护盾")
	_check(not HudViewScript._is_shield_action("rot_curse"), "腐樱诅咒不算护盾（走降防分支）")
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var hero = battle.actors[HERO]
	# 护盾载荷若误走 preview，会被防御减掉，显示成 500 → 423 这种假伤害。
	_check(hero.preview_damage(500, "true") == 500, "真伤不被防御削减，可作为对照")
	_check(hero.preview_damage(500, "physical") < 500, "同一发物理会被防御削减，两者必须不同")


func _fixture_intent(battle, action: String, amount: int, damage_type: String = "physical") -> BattleIntent:
	var mode := BattleIntent.TargetMode.ACTOR_LOCKED if action == "rot_curse" else BattleIntent.TargetMode.TILE_LOCKED
	var actor_id := HERO if action == "rot_curse" else ""
	return BattleIntent.new("preview_%d" % battle.intents.size(), "crimson_sword_guard_00",
		action, mode, actor_id, battle.actors[HERO].cell, [], amount, battle.intents.size(), damage_type)


func _test_ordered_threat_totals() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var hero = battle.actors[HERO]
	hero.defense = 0
	hero.shield = 400
	battle.intents.clear()
	for i in range(2):
		battle.intents.append(_fixture_intent(battle, "echo_bolt", 1000))
	var summary := BoardThreatView.incoming_threats_at(battle, hero.cell)
	_check(summary["total_dmg"] == 1600, "two hits share the same 400 shield")
	_check(summary["entries"][0]["dmg"] == 600 and summary["entries"][1]["dmg"] == 1000,
		"damage breakdown consumes the shield on the first hit")
	_check(hero.health == 1800 and hero.shield == 400, "the detailed preview leaves the live actor unchanged")
	battle.end_player_turn()
	_check(1800 - hero.health == summary["total_dmg"], "the displayed total matches normal phase resolution")

	hero.health = 200
	hero.shield = 350
	hero.magic_resistance = 1000
	battle.intents.clear()
	battle.intents.append(_fixture_intent(battle, "echo_bolt", 600, "magical"))
	battle.intents.append(_fixture_intent(battle, "echo_bolt", 600, "true"))
	battle.intents.append(_fixture_intent(battle, "echo_bolt", 600))
	summary = BoardThreatView.incoming_threats_at(battle, hero.cell)
	_check(summary["entries"][0]["dmg"] == 0, "a magical hit can be fully absorbed")
	_check(summary["entries"][1]["dmg"] == 200 and summary["total_dmg"] == 200, "the lethal hit is capped at remaining HP")
	_check(summary["entries"][2]["dmg"] == 0, "later hits add no damage after predicted defeat")


func _test_curse_applies_in_preview_order() -> void:
	var battle = _spawn("crimson_sword_guard", Vector2i(2, 2), Vector2i(3, 2))
	var hero = battle.actors[HERO]
	hero.defense = 1000
	hero.health = 1800
	battle.intents.clear()
	battle.intents.append(_fixture_intent(battle, "echo_bolt", 1000))
	battle.intents.append(_fixture_intent(battle, "rot_curse", 500))
	battle.intents.append(_fixture_intent(battle, "echo_bolt", 1000))
	var summary := BoardThreatView.incoming_threats_at(battle, hero.cell)
	_check(summary["entries"][0]["dmg"] == 500, "the first hit uses the original defence")
	_check(summary["entries"][1]["dmg"] == 0 and summary["entries"][2]["dmg"] == 666,
		"the curse changes only following physical hits")
	_check(hero.defense_penalty == 0, "curse preview does not apply a live status")
	battle.end_player_turn()
	_check(1800 - hero.health == summary["total_dmg"], "curse and hits resolve in preview order")
