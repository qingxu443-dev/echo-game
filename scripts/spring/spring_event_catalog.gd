class_name SpringEventCatalog
extends RefCounted

const MemoryThreadScript = preload("res://scripts/spring/spring_memory_thread.gd")

## The ten 春之境 events (设计汇总 2026-11-26 §10.2) and their resolution.
##
## The document fixes each event's options and the *direction* of their effects
## ("影响下一家商店价格", "可能触发陷阱战斗", "获得随机藏品但可能损失补给"). It does
## not fix the numbers, so every amount below is a draft held in one table -
## change a number here and every place it touches follows.
##
## Two rules from §10.1 shape the code:
##   - risk is announced, never fully spoiled: each event carries one of the four
##     risk labels and the option text says what could go wrong, not the odds;
##   - important progress is never permanently destroyed: no event can take a
##     relic, a collectible or the run itself, only resources and health.
##
## Rolls are seeded from (run seed, event id, option index), so resolving the same
## choice twice on the same run gives the same outcome. That is what lets a save
## record "resolved" without storing a roll history.

const RISK_SAFE: String = "安全"
const RISK_UNKNOWN: String = "未知"
const RISK_DANGER: String = "危险"
const RISK_HIGH: String = "高风险"

## Effect kinds. Anything that is not listed here is a data error and is skipped
## with a log line, so a typo cannot silently eat a player's resources.
const EFFECT_COINS: String = "coins"
const EFFECT_SUPPLIES: String = "supplies"
const EFFECT_PAGES: String = "pages"
const EFFECT_DEW: String = "dew"
const EFFECT_HEALTH: String = "health"
const EFFECT_SHOP_PRICE: String = "shop_price"
const EFFECT_COLLECTIBLE: String = "collectible"
const EFFECT_RELIC: String = "relic"
const EFFECT_BATTLE: String = "battle"
const EFFECT_REVEAL_HIDDEN: String = "reveal_hidden"
const EFFECT_RISK: String = "risk"
const EFFECT_NOTHING: String = "nothing"

const EVENTS := {
	"stranded_caravan": {
		"title": "受困的商队",
		"risk": RISK_UNKNOWN,
		"text": "车轮陷在软土里，货箱歪斜。领队看见你，先护住了箱子。",
		"options": [
			{
				"label": "帮着把车推出来",
				"hint": "会耽误时间，但他们记得这份人情",
				"effects": [
					{"kind": EFFECT_SUPPLIES, "amount": 2},
					{"kind": EFFECT_SHOP_PRICE, "multiplier": 0.85, "note": "商队替你说了话"},
				],
			},
			{
				"label": "婉拒，继续赶路",
				"hint": "什么也不会发生",
				"effects": [],
			},
			{
				"label": "趁乱翻检散落的货箱",
				"hint": "能拿到花钿；被撞见会很难看",
				"effects": [
					{"kind": EFFECT_COINS, "amount": 30},
					{"kind": EFFECT_SHOP_PRICE, "multiplier": 1.15, "note": "商队记住了你的手"},
					{"kind": EFFECT_RISK, "chance": 0.35, "label": "被护卫扭住", "effects": [
						{"kind": EFFECT_SUPPLIES, "amount": -2},
					]},
				],
			},
		],
	},
	"unworshipped_shrine": {
		"title": "无人祭拜的神龛",
		"risk": RISK_DANGER,
		"text": "石龛里积着去年的落花，供台上还摆着没人收走的东西。",
		"options": [
			{
				"label": "献上一份花钿",
				"hint": "花钿 -20，换一页记不全的旧事",
				"requires": {EFFECT_COINS: 20},
				"effects": [
					{"kind": EFFECT_COINS, "amount": -20},
					{"kind": EFFECT_PAGES, "amount": 1},
				],
			},
			{
				"label": "献上一份补给",
				"hint": "补给 -1，换两滴春露",
				"requires": {EFFECT_SUPPLIES: 1},
				"effects": [
					{"kind": EFFECT_SUPPLIES, "amount": -1},
					{"kind": EFFECT_DEW, "dew_kind": "spring", "amount": 2},
				],
			},
			{
				"label": "取走供品",
				"hint": "拿到花钿；神龛不一定愿意",
				"effects": [
					{"kind": EFFECT_COINS, "amount": 25},
					{"kind": EFFECT_RISK, "chance": 0.45, "label": "有什么东西抓住了你的手腕", "effects": [
						{"kind": EFFECT_HEALTH, "amount": -300},
					]},
				],
			},
		],
	},
	"sealed_chest": {
		"title": "被封存的箱子",
		"risk": RISK_HIGH,
		"text": "箱盖被蜡封死，缝隙里透出一点不属于这里的气味。",
		"options": [
			{
				"label": "按规矩开封",
				"hint": "花钿 -30，箱里的东西归你",
				"requires": {EFFECT_COINS: 30},
				"effects": [
					{"kind": EFFECT_COINS, "amount": -30},
					{"kind": EFFECT_COLLECTIBLE, "count": 1},
				],
			},
			{
				"label": "用补给换一把撬棍硬开",
				"hint": "补给 -2；动静可能招来东西",
				"requires": {EFFECT_SUPPLIES: 2},
				"effects": [
					{"kind": EFFECT_SUPPLIES, "amount": -2},
					{"kind": EFFECT_COLLECTIBLE, "count": 1},
					{"kind": EFFECT_RISK, "chance": 0.30, "label": "箱子底下是空的，下面是巢", "effects": [
						{"kind": EFFECT_BATTLE, "encounter": "B005"},
					]},
				],
			},
			{
				"label": "砸开",
				"hint": "不花任何东西；代价写在箱子的封蜡上",
				"effects": [
					{"kind": EFFECT_RISK, "chance": 0.60, "label": "封蜡是封印", "effects": [
						{"kind": EFFECT_BATTLE, "encounter": "B005"},
					]},
					{"kind": EFFECT_RISK, "chance": 0.20, "label": "碎片划伤了手", "effects": [
						{"kind": EFFECT_HEALTH, "amount": -250},
					]},
				],
			},
		],
	},
	"empty_camp": {
		"title": "无人的营地",
		"risk": RISK_UNKNOWN,
		"text": "火堆还有余温，铺盖上落了一层花瓣，主人像是刚刚走开。",
		"options": [
			{
				"label": "借火堆歇一会儿",
				"hint": "补给 -2，回复四成生命",
				"requires": {EFFECT_SUPPLIES: 2},
				"effects": [
					{"kind": EFFECT_SUPPLIES, "amount": -2},
					{"kind": EFFECT_HEALTH, "fraction": 0.40},
				],
			},
			{
				"label": "翻找留下的物资",
				"hint": "能补上补给和花钿；营地也许不是无人的",
				"effects": [
					{"kind": EFFECT_SUPPLIES, "amount": 2},
					{"kind": EFFECT_COINS, "amount": 15},
					{"kind": EFFECT_RISK, "chance": 0.40, "label": "铺盖底下有人醒着", "effects": [
						{"kind": EFFECT_BATTLE, "encounter": "B002"},
					]},
				],
			},
			{
				"label": "不打扰，离开",
				"hint": "什么也不会发生",
				"effects": [],
			},
		],
	},
	"forest_noise": {
		"title": "林间的异响",
		"risk": RISK_DANGER,
		"text": "枝叶在没有人走过的地方分开，又慢慢合上。",
		"options": [
			{
				"label": "走过去看清楚",
				"hint": "会打起来",
				"effects": [
					{"kind": EFFECT_BATTLE, "encounter": "B007"},
				],
			},
			{
				"label": "先布下陷阱（补给 -2）",
				"hint": "仍是同一批东西，但你能挑战场",
				"requires": {EFFECT_SUPPLIES: 2},
				"effects": [
					{"kind": EFFECT_SUPPLIES, "amount": -2},
					{"kind": EFFECT_BATTLE, "encounter": "B001"},
				],
			},
			{
				"label": "绕开",
				"hint": "什么也不会发生",
				"effects": [],
			},
		],
	},
	"beyond_stone_door": {
		"title": "石门之后",
		"risk": RISK_UNKNOWN,
		"text": "门板上没有锁，只有一圈被摸得发亮的旧纹。",
		"options": [
			{
				"label": "顺着旧纹找机关",
				"hint": "也许能让门自己开",
				"effects": [
					{"kind": EFFECT_REVEAL_HIDDEN, "chance": 0.50, "label": "机关轻轻一响"},
				],
			},
			{
				"label": "用补给换一根撬杠（补给 -1）",
				"hint": "门一定会开；开门的方式会疼",
				"requires": {EFFECT_SUPPLIES: 1},
				"effects": [
					{"kind": EFFECT_SUPPLIES, "amount": -1},
					{"kind": EFFECT_REVEAL_HIDDEN},
					{"kind": EFFECT_RISK, "chance": 0.30, "label": "门后的东西先动了", "effects": [
						{"kind": EFFECT_HEALTH, "amount": -350},
					]},
				],
			},
			{
				"label": "放弃",
				"hint": "什么也不会发生",
				"effects": [],
			},
		],
	},
	"lost_traveler": {
		"title": "失落的旅人",
		"risk": RISK_SAFE,
		"text": "她坐在路边，说自己的行囊丢在了来时的方向。",
		"options": [
			{
				"label": "替她找回来",
				"hint": "她会把记得的事写下来给你",
				"effects": [
					{"kind": EFFECT_PAGES, "amount": 1},
				],
			},
			{
				"label": "索要报酬",
				"hint": "拿到花钿，故事就到这里",
				"effects": [
					{"kind": EFFECT_COINS, "amount": 25},
				],
			},
			{
				"label": "趁她不注意拿走行囊",
				"hint": "能拿到藏品；补给会少一些",
				"effects": [
					{"kind": EFFECT_COLLECTIBLE, "count": 1},
					{"kind": EFFECT_SUPPLIES, "amount": -2},
				],
			},
		],
	},
	"old_contract": {
		"title": "旧时代的商契",
		"risk": RISK_SAFE,
		"text": "契书摊在石上，墨迹还是湿的，落款却写着很多年前。",
		"options": [
			{
				"label": "签下名字",
				"hint": "下一家店会给你面子",
				"effects": [
					{"kind": EFFECT_SHOP_PRICE, "multiplier": 0.80, "note": "旧契仍然有效"},
				],
			},
			{
				"label": "不签",
				"hint": "什么也不会发生",
				"effects": [],
			},
			{
				"label": "撕了换钱",
				"hint": "拿到花钿；有人会记得",
				"effects": [
					{"kind": EFFECT_COINS, "amount": 35},
					{"kind": EFFECT_SHOP_PRICE, "multiplier": 1.20, "note": "毁契的名声走得比人快"},
				],
			},
		],
	},
	"mysterious_collector": {
		"title": "神秘收藏家",
		"risk": RISK_SAFE,
		"text": "他摊开一块绒布，上面空着，像是专门留给你的东西。",
		"options": [
			{
				"label": "付他花钿",
				"hint": "花钿 -40，换一件藏品",
				"requires": {EFFECT_COINS: 40},
				"effects": [
					{"kind": EFFECT_COINS, "amount": -40},
					{"kind": EFFECT_COLLECTIBLE, "count": 1},
				],
			},
			{
				"label": "拿一件自己的藏品交换",
				"hint": "他会给你两件更好的",
				"requires": {"collectible": 1},
				"effects": [
					{"kind": EFFECT_COLLECTIBLE, "count": 2, "consume_one": true},
				],
			},
			{
				"label": "拒绝",
				"hint": "什么也不会发生",
				"effects": [],
			},
		],
	},
	"hidden_hoard": {
		"title": "隐秘之地",
		"risk": RISK_SAFE,
		"text": "地图上本来没有这一格。土里埋着一只没有被写进任何记录的匣子。",
		"options": [
			{
				"label": "打开它",
				"hint": "这里的东西只有你看见过",
				"effects": [
					{"kind": EFFECT_COINS, "amount": 40},
					{"kind": EFFECT_COLLECTIBLE, "count": 1},
					{"kind": EFFECT_RELIC, "random": true},
				],
			},
			{
				"label": "不动它，记住位置",
				"hint": "什么也不会发生",
				"effects": [],
			},
		],
	},
	"unsent_letter": {
		"title": "没有寄出的信",
		"risk": RISK_SAFE,
		"text": "信纸压在石下，收信人一栏写着你的名字，笔迹是很多年前的。",
		"options": [
			{
				"label": "读下去",
				"hint": "记住它写下的东西",
				"effects": [
					{"kind": EFFECT_PAGES, "amount": 2},
					{"kind": EFFECT_NOTHING, "note": "这段记忆被记下了"},
				],
			},
			{
				"label": "收进衣襟，暂时不看",
				"hint": "什么也不会发生",
				"effects": [],
			},
			{
				"label": "烧掉",
				"hint": "只剩一页能记住的",
				"effects": [
					{"kind": EFFECT_PAGES, "amount": 1},
				],
			},
		],
	},
}

const RANDOM_POOL: Array[String] = [
	"sealed_chest",
	"forest_noise",
	"mysterious_collector",
	"unworshipped_shrine",
	"stranded_caravan",
	"lost_traveler",
]


static func has_event(event_id: StringName) -> bool:
	return EVENTS.has(String(event_id))


static func title_of(event_id: StringName) -> String:
	var entry: Dictionary = EVENTS.get(String(event_id), {})
	return str(entry.get("title", String(event_id)))


static func risk_of(event_id: StringName) -> String:
	var entry: Dictionary = EVENTS.get(String(event_id), {})
	return str(entry.get("risk", RISK_UNKNOWN))


static func body_of(event_id: StringName) -> String:
	var entry: Dictionary = EVENTS.get(String(event_id), {})
	return str(entry.get("text", ""))


static func option_count(event_id: StringName) -> int:
	var entry: Dictionary = EVENTS.get(String(event_id), {})
	return (entry.get("options", []) as Array).size()


static func option_label(event_id: StringName, index: int) -> String:
	var option: Dictionary = _option(event_id, index)
	return str(option.get("label", ""))


static func option_hint(event_id: StringName, index: int) -> String:
	var option: Dictionary = _option(event_id, index)
	return str(option.get("hint", ""))


static func _option(event_id: StringName, index: int) -> Dictionary:
	var entry: Dictionary = EVENTS.get(String(event_id), {})
	var options: Array = entry.get("options", [])
	if index < 0 or index >= options.size():
		return {}
	return options[index]


## Can the player pick this option right now? §10.1 forbids offering a choice the
## player cannot pay for, because a greyed-out "pay 20 花钿" with 12 花钿 in hand
## reads as a bug rather than a rule.
static func can_afford(run, event_id: StringName, index: int) -> bool:
	var option: Dictionary = _option(event_id, index)
	if option.is_empty():
		return false
	var requires: Dictionary = option.get("requires", {})
	for key in requires:
		var need: int = int(requires[key])
		match String(key):
			EFFECT_COINS:
				if run.coins < need:
					return false
			EFFECT_SUPPLIES:
				if run.supplies < need:
					return false
			"collectible":
				var owned_count: int = run.collectibles.size()
				for stack_count in run.collectible_consumables.values():
					owned_count += int(stack_count)
				if owned_count < need:
					return false
	return true


## Resolves one option and mutates the run. Returns a log the UI can show and,
## when the choice starts a fight, the encounter id in "battle".
##
## `event_id` is the *event* id, not the place id - template slots keep their own
## identity so the same event can sit in a fixed slot on one board and in the
## random slot on another.
static func resolve(run, event_id: StringName, index: int) -> Dictionary:
	var result := {"ok": false, "log": [], "battle": &"", "reveal_hidden": false}
	var option: Dictionary = _option(event_id, index)
	if option.is_empty():
		result["log"].append("这个选项不存在。")
		return result
	if not can_afford(run, event_id, index):
		result["log"].append("条件不足，无法选择。")
		return result

	var rng := RandomNumberGenerator.new()
	# Seeded so a replayed choice on the same run rolls the same way.
	rng.seed = hash("%d|%s|%d" % [run.seed_value, String(event_id), index])

	var ctx := {
		"battle": &"",
		"reveal_hidden": false,
	}
	var log: Array = []
	for effect in option.get("effects", []):
		_apply(run, effect, rng, log, ctx)

	# "Do nothing" is still an answer: an empty panel reads as a broken event.
	if log.is_empty():
		log.append("你什么也没做。")
	# 归乡记忆线（§10.4 记忆拼合 / 三级剧情延续但不阻断主线）：本次选择若拼上
	# 一片记忆、且此前已有别的可呼应，追加一句留白回响。回响只读 event_log，
	# 此前的选择还没写进去（由地图层在 resolve 之后写入），所以 echo_for 看到的
	# 正是「本次之前」的记忆。回响不写进任何存档字段，纯展示。
	var echo: String = MemoryThreadScript.echo_for(event_id, index, run.event_log)
	if not echo.is_empty():
		log.append(echo)
	result["ok"] = true
	result["log"] = log
	result["battle"] = ctx["battle"]
	result["reveal_hidden"] = ctx["reveal_hidden"]
	return result


static func _apply(run, effect: Dictionary, rng: RandomNumberGenerator, log: Array, ctx: Dictionary) -> void:
	var kind: String = str(effect.get("kind", ""))
	match kind:
		EFFECT_COINS:
			var coin_delta: int = int(effect.get("amount", 0))
			run.add_coins(coin_delta)
			log.append("花钿 %s%d。" % ["+" if coin_delta >= 0 else "", coin_delta])
		EFFECT_SUPPLIES:
			var supply_delta: int = int(effect.get("amount", 0))
			if supply_delta >= 0:
				run.add_supplies(supply_delta)
			else:
				run.spend_supplies(-supply_delta)
			log.append("补给 %s%d。" % ["+" if supply_delta >= 0 else "", supply_delta])
		EFFECT_PAGES:
			var page_delta: int = int(effect.get("amount", 0))
			run.add_memory_pages(page_delta)
			log.append("记忆残页 %s%d。" % ["+" if page_delta >= 0 else "", page_delta])
		EFFECT_DEW:
			var dew_kind: String = str(effect.get("dew_kind", "spring"))
			var dew_amount: int = int(effect.get("amount", 0))
			if run.add_dew(dew_kind, dew_amount):
				log.append("春露 +%d。" % dew_amount)
			else:
				# §5.4: full storage must be announced, never silently dropped.
				log.append("四时花露已满，这一份没能收下。")
		EFFECT_HEALTH:
			if effect.has("fraction"):
				var healed: int = run.heal_fraction(float(effect["fraction"]))
				log.append("回复 %d 点生命。" % healed)
			else:
				var hp_delta: int = int(effect.get("amount", 0))
				if hp_delta >= 0:
					run.heal_hero(hp_delta)
					log.append("回复 %d 点生命。" % hp_delta)
				else:
					run.damage_hero(-hp_delta)
					log.append("失去 %d 点生命。" % -hp_delta)
		EFFECT_SHOP_PRICE:
			var multiplier: float = float(effect.get("multiplier", 1.0))
			run.apply_shop_price_modifier(multiplier, str(effect.get("note", "")))
			if multiplier < 1.0:
				log.append("下一家商店会便宜一些。")
			elif multiplier > 1.0:
				log.append("下一家商店会贵一些。")
		EFFECT_COLLECTIBLE:
			var wanted: int = int(effect.get("count", 1))
			if bool(effect.get("consume_one", false)):
				run.consume_collectible()
			for _i in range(wanted):
				var gained: StringName = run.grant_random_collectible(rng)
				if gained != &"":
					var effect_note: String = "已收纳，可在藏品栏中选择使用。"
					if not SpringCollectibleCatalog.is_consumable(gained):
						var applied: Dictionary = run.apply_collectible_effect(gained)
						effect_note = str(applied.get("message", "效果已结算。"))
					log.append("获得藏品「%s」：%s" % [run.collectible_name(gained), effect_note])
				else:
					var fallback_coins: int = 20
					run.add_coins(fallback_coins)
					log.append("藏品已收集齐全，换得 %d 花钿。" % fallback_coins)
		EFFECT_RELIC:
			var relic_id: StringName = StringName(str(effect.get("relic_id", "")))
			if bool(effect.get("random", false)):
				relic_id = run.grant_random_relic(rng)
			elif relic_id != &"":
				run.add_relic(relic_id)
			if relic_id != &"":
				log.append("获得遗物「%s」。" % run.relic_name(relic_id))
			else:
				run.add_coins(40)
				log.append("遗物已收集齐全，换得 40 花钿。")
		EFFECT_BATTLE:
			var encounter: StringName = StringName(str(effect.get("encounter", "")))
			if encounter != &"":
				ctx["battle"] = encounter
				log.append("有什么挡在了路上。")
		EFFECT_REVEAL_HIDDEN:
			if effect.has("chance") and rng.randf() >= float(effect["chance"]):
				log.append("旧纹没有回应。")
			else:
				ctx["reveal_hidden"] = true
				log.append("地图上多出一处从前没看到的地方。")
		EFFECT_RISK:
			if rng.randf() < float(effect.get("chance", 0.0)):
				var label: String = str(effect.get("label", "意外发生了"))
				log.append("%s。" % label)
				for nested in effect.get("effects", []):
					_apply(run, nested, rng, log, ctx)
		EFFECT_NOTHING:
			var note: String = str(effect.get("note", ""))
			if not note.is_empty():
				log.append("%s。" % note)
		_:
			log.append("（未知效果 %s，已跳过）" % kind)
