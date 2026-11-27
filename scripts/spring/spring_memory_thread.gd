class_name SpringMemoryThread
extends RefCounted

## 归乡记忆线：把十个孤立事件里带「旧事 / 记忆 / 来时 / 旧纹」母题的几个串成
## 一条弱主线（设计汇总 2026-11-26 §10.4「三级剧情延续，关键选择影响整局剧情
## 但不阻断主线」，§6.3「记忆残页用于记忆拼合」）。
##
## 严守边界：
##   - 只读 event_log 与 memory_pages，不改任何事件选项、数值、规则、区域解锁。
##   - 所有回响文案都是留白，绝不倒向三个候选结局方向中的任何一个——樱的归乡
##     选择仍由她自己决定，玩家只是陪她想起一些事。
##   - 「若玩家没有遇到后续事件，不应受到惩罚」（§10.4）：碎片只是回忆，没有
##     任何数值收益或门控，没凑齐也不影响通关。

## 每片记忆：事件 id → 贡献碎片的选择下标、碎片短句、回响句。
## 选的三个事件在三套地图里都能遇到（lost_traveler 模板1固定 / unworshipped_shrine
## 模板2固定 / unsent_letter 三模板固定），所以任何一局都能至少拼到一片。
const THREAD := {
	"lost_traveler": {
		"option": 0,
		"fragment": "旅人说起的、来时的方向。",
		"echo": "你想起那个旅人——她弄丢的方向，原来一直朝着这里。",
	},
	"unworshipped_shrine": {
		"option": 0,
		"fragment": "神龛里一页记不全的旧事。",
		"echo": "供台上那页旧事，和信里的笔迹像是同一个人的。",
	},
	"unsent_letter": {
		"option": 0,
		"fragment": "一封很多年前、写给你的信。",
		"echo": "那封信你记着。落款的日子，正是春天第一次不谢的时候。",
	},
}

## 拼合度分档文案：按已收集碎片数取一档，都是留白，不解锁、不指向任何结局。
const REFLECTIONS := {
	1: "你替她收着一片碎掉的记忆。剩下的，还散在这一程里。",
	2: "两片记忆对上了缝。它们指向的，你还没有看清。",
	3: "三片记忆连成一条细线，尽头是她一直没说出口的那句话——你决定先不问。",
}


## 这个选择是否贡献一片归乡记忆。
static func is_memory_choice(event_id: StringName, option: int) -> bool:
	var entry: Dictionary = THREAD.get(String(event_id), {})
	return not entry.is_empty() and int(entry.get("option", -1)) == option


## 从存档里的 event_log 只读地拼出玩家已收集的碎片短句（按 THREAD 固定顺序，
## 去重，稳定）。event_log 的键是事件 id 字符串，值是 {"option": int, ...}。
static func collected(event_log: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for event_id in THREAD:
		var record: Dictionary = event_log.get(String(event_id), {})
		if record.is_empty():
			continue
		if int(record.get("option", -1)) != int(THREAD[event_id]["option"]):
			continue
		result.append(str(THREAD[event_id]["fragment"]))
	return result


static func count(event_log: Dictionary) -> int:
	return collected(event_log).size()


## 事件结算时的回响：当玩家刚拼上一片、且此前已有别的记忆时，给一句呼应。
## 第一片不回响（还没有东西可呼应）；非记忆选择不回响。这样回响的是「事件之间
## 的联系」，把孤立的事件串起来。
static func echo_for(event_id: StringName, option: int, event_log_before: Dictionary) -> String:
	if not is_memory_choice(event_id, option):
		return ""
	# event_log_before 是本次选择写入之前的记录，数的是「此前已拼到的片数」。
	if count(event_log_before) < 1:
		return ""
	return str(THREAD[String(event_id)]["echo"])


## 结局回顾：仅按拼合度给留白文案，没有任何数值或解锁效果。
static func reflection_for(event_log: Dictionary) -> String:
	var n: int = count(event_log)
	if n <= 0:
		return ""
	return str(REFLECTIONS.get(mini(n, 3), ""))


## 三片都拼到才算「串成一条线」——给测试与文档一个明确的达成判据。
static func thread_complete(event_log: Dictionary) -> bool:
	return count(event_log) >= THREAD.size()
