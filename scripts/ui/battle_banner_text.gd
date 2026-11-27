class_name BattleBannerText
extends RefCounted

## 战斗状态栏文案的单一来源（P1 拆分第二刀：从 battle_view.gd 抽出）。
##
## 只读 controller / level / status_message，产出展示文案，不修改任何状态。
## 教学关的分步引导文案集中在此，避免编排器里塞满教学脚本。

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const SpringRunScript = preload("res://scripts/spring/spring_run.gd")
const BoardThreatViewScript = preload("res://scripts/ui/board_threat_view.gd")


## 当前角色的展示名。角色数据缺失时回落到主角或中文占位。
static func hero_name(controller) -> String:
	var hero = controller.get_active_character() if controller != null else null
	if hero != null and not hero.display_name_zh.is_empty():
		return hero.display_name_zh
	var sheet = CharacterCatalogScript.get_definition(String(SpringRunScript.HERO_CHARACTER_ID))
	return sheet.display_name_zh if sheet != null else "主角"


## 状态栏最终文案：部署阶段固定提示、教学关分步引导、其余回落到 status_message。
static func effective_message(controller, level, status_message: String) -> String:
	if controller.phase == ControllerScript.BattlePhase.DEPLOY:
		return "【部署阶段】点击南侧高亮格放置%s，确认后开战。部署不消耗行动点，也不计入回合。" % hero_name(controller)
	if level == null or controller.phase != ControllerScript.BattlePhase.PLAYER:
		return status_message
	var hero = controller.get_active_character()
	if hero == null or not hero.is_alive():
		return status_message

	# Interactive step-by-step guidance for the opening turns of Lesson 1 & 2
	if level.level_id == &"lesson_charge" and controller.turn_number == 1:
		var in_danger: bool = BoardThreatViewScript.is_cell_in_danger(controller, hero.cell)
		if in_danger:
			return "【引导 1/3】先锋正锁定你脚下红框蓄力！点击高亮绿色格子移动 1 格即可无伤闪避。"
		if controller.damage_dealt <= 0:
			return "【引导 2/3】漂亮！现在点击下方 [2] 裁决印记（或 [1] 誓刃），再点击先锋展开反击！"
		return "【引导 3/3】点击右下角「结束回合」[空格]，观察敌方蓄力落空！"

	if level.level_id == &"lesson_lane" and controller.turn_number == 1:
		var in_danger: bool = BoardThreatViewScript.is_cell_in_danger(controller, hero.cell)
		if in_danger:
			return "【引导 1/2】神射手沿直线锁定了你！斜向移出蓝框，或贴近至 2 格内使其狙击哑火。"
		return "【引导 2/2】已避开狙击锁格！趁机用技能反击，或点击「结束回合」推进。"

	return status_message
