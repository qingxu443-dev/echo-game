class_name SpringEnding
extends RefCounted

## 春之境的收束文案（设计汇总 2026-11-26 §2 / §3）。
##
## 设计明确要求「暂不锁定结局」：曾讨论的三个方向——让时间重新流动、留下
## 守护、迎来新的春天——都还没有被选定，玩家陪伴樱而不是替她决定。因此这里
## 呈现的是**留白的收束**：承认这一程走到终点，把选择留在樱自己手里。
##
## 文案与表现分离：本脚本只持有可测试的数据，spring_map_view 仅负责绘制。
## 不新增场景、不引入素材、不改动任何结局规则或后续区域解锁状态。

const MemoryThreadScript = preload("res://scripts/spring/spring_memory_thread.gd")

## finish_reason → 收束文案。三种结束各有不同语气：平定是成就、失守是失败、
## 体力耗尽是软性止步；主动结束由调用方用通用文案。
const ENDINGS := {
	"cleared": {
		"title": "未尽之春 · 归乡",
		"lines": [
			"故园的信，终于送到了它该去的地方。",
			"旧日的回声在花下散去，你陪她走到花落之前。",
			"春天还停在这里，樱花没有谢。",
			"樱望着三条都没有走过的路，还没有决定要不要让时间重新开始。",
			"这一趟先陪她站到这里。剩下的选择，留给她自己。",
		],
		"footer": "春之境到此为止 · 夏之境及其后尚未解锁",
	},
	"defeat": {
		"title": "本局结束 · 失守",
		"lines": [
			"失守的节点留在了地图上，来路被落花掩住。",
			"这一趟走不下去了，但春天还会再来。",
		],
		"footer": "夏之境及其后尚未解锁",
	},
	"exhausted": {
		"title": "本局结束 · 体力耗尽",
		"lines": [
			"体力走完了，脚步停在花影里。",
			"路还在，只是这一程先到这里。",
		],
		"footer": "夏之境及其后尚未解锁",
	},
	"abandoned": {
		"title": "本局结束 · 主动结束",
		"lines": [
			"你收起脚步，把这一程留在了春天里。",
		],
		"footer": "夏之境及其后尚未解锁",
	},
}

const DEFAULT_REASON: String = "abandoned"


static func has_ending(reason: String) -> bool:
	return ENDINGS.has(reason)


## 未知 finish_reason 一律回落到通用文案，不让面板空白。
##
## `event_log` 可选：平定一局时，若玩家拼到过归乡记忆碎片（§10.4 记忆拼合），
## 追加一句留白回顾，让串起来的事件在收束处呼应。没有碎片就不加——「没遇到
## 后续事件不应受惩罚」；这句也不解锁任何内容、不指向任何候选结局。
static func ending_for(reason: String, event_log: Dictionary = {}) -> Dictionary:
	var key: String = reason if ENDINGS.has(reason) else DEFAULT_REASON
	var ending: Dictionary = ENDINGS[key].duplicate(true)
	if reason == "cleared":
		var echo: String = MemoryThreadScript.reflection_for(event_log)
		if not echo.is_empty():
			ending["lines"].append(echo)
	return ending


## 三个候选结局方向都没有被选定——这是「暂不锁定结局」最直接的可测断言。
static func leaves_choice_open(reason: String) -> bool:
	var ending: Dictionary = ending_for(reason)
	var joined: String = " ".join(PackedStringArray(ending.get("lines", [])))
	return joined.contains("还没有决定") or joined.contains("留给她自己")
