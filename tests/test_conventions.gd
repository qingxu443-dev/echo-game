extends "res://tests/framework/test_case.gd"

## 约定守卫套件：把"数据声明的 id 必须有人接"变成每次 CI 都跑的红绿灯。
##
## 第十三轮之前，这类错只有玩家按下去才发现：目录里写了个拼错的 action_id，
## 规划器 push_error 然后敌人站着不动；技能目录加了新技能忘了登记执行器，
## 点击无声无息。这些都不是靠"下次更仔细"，是让 CI 在合并前就红。

const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const CharacterSkillRuntimeScript = preload("res://scripts/battle/character_skill_runtime.gd")
const EnemySkillCatalogScript = preload("res://scripts/battle/enemy_skill_catalog.gd")
const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")
const SpringShopScript = preload("res://scripts/spring/spring_shop.gd")
const DocChecks = preload("res://tests/framework/doc_checks.gd")


func _run() -> void:
	_test_every_skill_has_an_executor()
	_test_every_enemy_action_is_in_the_catalogue()
	_test_every_loot_kind_is_known()
	_test_every_shop_id_resolves()
	_test_count_copies_converge()
	_test_entry_points_isolate_the_user_profile()
	_report()


## 每个可施放的技能都必须有登记的执行器。角色目录加技能 = 加数据；忘了在
## CharacterSkillRuntime 登记执行器，就是按了没反应。
func _test_every_skill_has_an_executor() -> void:
	var executors: Dictionary = CharacterSkillRuntimeScript._executors
	_check(executors.size() > 0, "the executor table is built")
	for skill in SkillRegistryScript.all_skills():
		if skill.is_passive:
			continue
		_check(executors.has(skill.executor_id), "skill '%s' dispatches to a registered executor" % skill.skill_id)


## 敌人数据里写下的每个 action 都必须能在技能参数表里查到——这是规划器
## 报错前的最后一道闸，数据错字在这里就红，不用等实机。
func _test_every_enemy_action_is_in_the_catalogue() -> void:
	var dir := DirAccess.open("res://data/enemies")
	var checked: int = 0
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var definition = load("res://data/enemies/" + file_name)
		if definition == null:
			continue
		for action_id in definition.actions:
			checked += 1
			_check(EnemySkillCatalogScript.has(action_id), "%s uses a known action '%s'" % [file_name, action_id])
	_check(checked >= 10, "the enemy sheets declare actions to check (%d seen)" % checked)


## 战利品的 kind 决定它走交付/出售的哪条路；表外的 kind 会被所有分支静默跳过。
func _test_every_loot_kind_is_known() -> void:
	var known: Array[String] = [
		LootCatalogScript.KIND_WEAPON,
		LootCatalogScript.KIND_ARMOR,
		LootCatalogScript.KIND_CONSUMABLE,
		LootCatalogScript.KIND_SKILL_UPGRADE,
	]
	var definitions: Array = LootCatalogScript._definitions
	_check(definitions.size() >= 10, "the loot catalogue publishes its sheets (%d items)" % definitions.size())
	for definition in definitions:
		_check(known.has(str(definition.kind)), "loot '%s' carries a known kind" % str(definition.id))


## 商店手抄了目录的 id 清单（它不访问目录的私有表）。清单里任何 id 在目录里
## 查不到，就是货架上一件永远买不到的东西。
func _test_every_shop_id_resolves() -> void:
	for item_id in SpringShopScript._catalog_ids():
		_check(not LootCatalogScript.get_item(item_id).is_empty(), "the shop's '%s' resolves in the catalogue" % String(item_id))


## 文档计数的收敛性。PR #74 的七处冲突不是合并技术问题：守卫当年逼每个分支
## 把同一行改成"自己那个数"，两个分支改同一行必冲突。现在 --fix 把任何写法
## 归一成同一组占位符——只要归一化是纯函数且幂等，任何分支跑完都得到同一串字，
## git 自动合并。这条测试就是那个前提的证据。
func _test_count_copies_converge() -> void:
	var cases := [
		["共 2471 条断言", "共 <实际断言数> 条断言"],
		["33 个测试套件全部通过", "<实际套件数> 个测试套件全部通过"],
		["suites=42 assertions=2981 failures=0", "suites=<实际套件数> assertions=<实际断言数> failures=0"],
		["doc-numbers: ok (floor 2981)", "doc-numbers: ok (floor <下限>)"],
		["三十五个套件", "<实际套件数>个套件"],
	]
	for pair in cases:
		var source: String = pair[0]
		_check(DocChecks.converge_line(source) == String(pair[1]),
			"'%s' converges to the canonical pointer" % source)
		# 幂等：第二次归一化必须不再改动。否则 --fix 每跑一次都会产生新文本，
		# 分支之间就永远收敛不到同一串字。
		var once := DocChecks.converge_line(source)
		_check(DocChecks.converge_line(once) == once, "'%s' is a fixed point" % source)
	# 历史行与逐套件明细不是"当前计数副本"，必须原样保留，否则历史记录被改写。
	var historical := "历史记录：300 条断言 0 失败"
	_check(DocChecks.converge_line(historical) == historical, "historical lines keep their numbers")
	var per_suite := "`tests/test_hunter_summon.gd`，39 条断言"
	_check(DocChecks.converge_line(per_suite) == per_suite, "per-suite details keep their numbers")


## 两个入口都必须把 user:// 指到临时目录再启动引擎。套件假设配置是空的，而开发者
## 机器上的 user:// 里躺着自己的存档：装好的残片、编队、未完成的旅程。实测一份每
## 角色装 5–6 个残片的存档会让 49 条伤害与生命断言偏移，CI 却永远看不到——容器是
## 空的。删掉隔离就等于把"本地必红、CI 必绿"这个陷阱重新铺回去。
func _test_entry_points_isolate_the_user_profile() -> void:
	for path in ["res://tests/run_all.sh", "res://tests/run_all.ps1"]:
		var text := FileAccess.get_file_as_string(path)
		_check(not text.is_empty(), "%s is readable" % path)
		_check(text.contains("test-userdata"), "%s points user:// at a scratch directory" % path)
		_check(
			text.contains("APPDATA") or text.contains("XDG_DATA_HOME"),
			"%s sets the variable the engine reads for user://" % path
		)

