extends "res://tests/framework/test_case.gd"

## 敌人技能数据表（EnemySkillCatalog）的自检。
##
## Why this suite exists: the 24 numbers that used to sit at the top of
## intent_planner.gd now live in a table, and a table can be wrong in ways code
## cannot. Three failures matter and none of them raise on their own:
##   1. a sheet names an action nobody registered → the enemy would fall through
##      to `wait` and look frozen;
##   2. a number drifts during a refactor → every enemy quietly changes strength;
##   3. a spec is malformed (range inverted, unknown damage type) → that action
##      silently never fires.
## The numbers below are the pre-refactor constants, written down so the move to
## data is provably behaviour-preserving.

const EnemySkillCatalogScript = preload("res://scripts/battle/enemy_skill_catalog.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")
const DefinitionScript = preload("res://scripts/battle/enemy_skill_definition.gd")
const EliteSkillsScript = preload("res://scripts/battle/elite_skills.gd")


func _run() -> void:
	_test_every_sheet_action_is_registered()
	_test_every_registered_spec_is_valid()
	_test_multipliers_match_the_pre_refactor_constants()
	_test_ranges_match_the_pre_refactor_constants()
	_test_hazard_payloads_carry_kind_and_duration()
	_test_unknown_action_is_rejected_loudly()
	_test_elite_executors_cover_the_catalog()


## 档案里写了什么，表里就必须有什么。这条防止「新敌人用了未注册的招式」。
func _test_every_sheet_action_is_registered() -> void:
	var missing: Array[String] = []
	var checked := 0
	for definition in EnemyCatalogScript.definitions():
		for action_id in definition.actions:
			checked += 1
			if not EnemySkillCatalogScript.has(action_id):
				missing.append("%s->%s" % [String(definition.archetype_id), String(action_id)])
	_check(checked > 0, "至少扫到一条档案动作（防止空跑）")
	_check(missing.is_empty(), "所有档案的 actions 都在数据表里", ", ".join(missing))


func _test_every_registered_spec_is_valid() -> void:
	var bad: Array[String] = []
	for action_id in EnemySkillCatalogScript.all_ids():
		var spec = EnemySkillCatalogScript.get_skill(StringName(action_id))
		if spec == null or not spec.is_valid():
			bad.append(String(action_id))
	_check(bad.is_empty(), "没有非法 spec（射程倒置 / 未知伤害类型）", ", ".join(bad))
	_check(EnemySkillCatalogScript.all_ids().size() >= 16, "16 条招式全部注册，少一条就是漏了")


func _test_multipliers_match_the_pre_refactor_constants() -> void:
	# 左：重构前 intent_planner.gd 顶部的常量。右：数据表。
	var expected := {
		"charged_strike": 1.5,
		"basic_melee": 0.8,
		"aimed_shot": 1.35,
		"light_shot": 0.75,
		"ground_pulse": 1.15,
		"echo_bolt": 0.7,
		"blight_field": 1.0,
		"spring_bloom": 0.75,
		"sakura_shock": 0.75,
		"locked_shot": 1.15,
		"shadow_raid": 1.05,
	}
	for action_id in expected:
		var spec = EnemySkillCatalogScript.get_skill(StringName(action_id))
		_check(spec != null and absf(spec.damage_multiplier - expected[action_id]) < 0.0001,
			"%s 倍率仍是 %.2f" % [action_id, expected[action_id]])


func _test_ranges_match_the_pre_refactor_constants() -> void:
	var expected := {
		"charged_strike": [1, 2],
		"basic_melee": [1, 1],
		"aimed_shot": [2, 6],
		"light_shot": [2, 6],
		"ground_pulse": [2, 4],
		"echo_bolt": [2, 4],
		"blight_field": [1, 2],
		"spring_bloom": [2, 5],
		"sakura_shock": [1, 2],
		"lock_on": [2, 6],
		"locked_shot": [1, 6],
		"shadow_raid": [2, 4],
		"rot_curse": [1, 4],
		"ward_ally": [0, 2],
	}
	for action_id in expected:
		var spec = EnemySkillCatalogScript.get_skill(StringName(action_id))
		var want: Array = expected[action_id]
		_check(spec != null and spec.min_range == want[0] and spec.max_range == want[1],
			"%s 射程仍是 %d-%d" % [action_id, want[0], want[1]])
	# 狙击手的风筝距离是可打击距离 +1，两件事分开记。
	var shot = EnemySkillCatalogScript.get_skill(&"aimed_shot")
	_check(shot.reposition_min_range == 3, "贯通狙击退到 3 格外开火（原 AIMED_SHOT_MIN_RANGE）")


func _test_hazard_payloads_carry_kind_and_duration() -> void:
	var blight = EnemySkillCatalogScript.get_skill(&"blight_field")
	_check(blight.hazard_kind == "blight" and absf(blight.hazard_multiplier - 0.25) < 0.0001, "凋零仍按 0.25 每跳")
	_check(blight.hazard_duration_turns == 2, "樱落领域的地格持续 2 个完整回合")
	var bloom = EnemySkillCatalogScript.get_skill(&"spring_bloom")
	_check(bloom.hazard_kind == "lingering_spring" and absf(bloom.hazard_multiplier - 0.2) < 0.0001, "残春仍是草案 0.2")
	_check(bloom.damage_type == "magical", "春痕绽放走魔抗")
	# 逐影突袭的三格路径也是数据，不是代码里写死的 3。
	_check(EnemySkillCatalogScript.get_skill(&"shadow_raid").move_steps == 3, "逐影突袭最多走 3 格")


func _test_unknown_action_is_rejected_loudly() -> void:
	_check(not EnemySkillCatalogScript.has(&"sakura_shok"), "错字招式不在表里")
	# get_skill 会 push_error，测试里用 has() 判定即可；返回 null 是契约。
	_check(EnemySkillCatalogScript.get_skill(&"sakura_shok") == null, "未注册招式返回 null 而不是默认近战")


## 专属技的执行表必须与数据表对齐：有数值没执行 = 敌人站着不动，
## 有执行没数值 = 一条永远不会被调用的死代码。
func _test_elite_executors_cover_the_catalog() -> void:
	var table: Dictionary = EliteSkillsScript.executors()
	_check(table.size() == 9, "九条专属技都登记了，多一条少一条都会让分派漏掉")
	var orphan: Array[String] = []
	for action_id in table:
		if not EnemySkillCatalogScript.has(action_id):
			orphan.append(String(action_id))
		var cb: Callable = table[action_id]
		if not cb.is_valid():
			orphan.append(String(action_id) + "(invalid)")
	_check(orphan.is_empty(), "执行表的每条都有数值定义且 Callable 有效", ", ".join(orphan))
	# 通用招式不该混进专属表，否则规划器自己的 match 就成了死分支。
	_check(not table.has(&"charged_strike"), "蓄力斩是通用招，不进专属表")
	_check(not table.has(&"basic_melee"), "近战是通用招，不进专属表")
