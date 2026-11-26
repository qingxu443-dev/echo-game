class_name LootCatalog
extends RefCounted

## Data-only catalog for random Relic Chest loot across 4 categories:
##   "weapon"        -> equippable in weapon slot (swap/unequip freely)
##   "armor"         -> equippable in armor slot (swap/unequip freely)
##   "consumable"    -> kept in backpack, single-use during battle
##   "skill_upgrade" -> permanent skill mod for the current run

const KIND_WEAPON: String = "weapon"
const KIND_ARMOR: String = "armor"
const KIND_CONSUMABLE: String = "consumable"
const KIND_SKILL_UPGRADE: String = "skill_upgrade"

const ITEMS: Array[Dictionary] = [
	# --- Weapons ---
	{
		"id": &"weapon_oath_greatsword",
		"kind": KIND_WEAPON,
		"kind_zh": "武器",
		"name": "誓约重剑",
		"desc": "攻击 +260。",
		"attack": 260,
		"defense": 0,
		"magic_resistance": 0,
		"max_health": 0,
		"enemy_buff_zh": "夺得重剑 · 攻+260",
		"enemy_attack": 260,
		"enemy_shield": 0,
		"enemy_heal": 0,
		"enemy_charge": false,
	},
	{
		"id": &"weapon_echo_halberd",
		"kind": KIND_WEAPON,
		"kind_zh": "武器",
		"name": "回声战戟",
		"desc": "攻击 +180，撞击真实伤害 +200。",
		"attack": 180,
		"defense": 0,
		"magic_resistance": 0,
		"max_health": 0,
		"collision_bonus": 200,
		"enemy_buff_zh": "夺得战戟 · 攻+200 & 满充能",
		"enemy_attack": 200,
		"enemy_shield": 0,
		"enemy_heal": 0,
		"enemy_charge": true,
	},
	{
		"id": &"weapon_dusk_blade",
		"kind": KIND_WEAPON,
		"kind_zh": "武器",
		"name": "黄昏破甲刃",
		"desc": "攻击 +340，但防御 -60。",
		"attack": 340,
		"defense": -60,
		"magic_resistance": 0,
		"max_health": 0,
		"enemy_buff_zh": "夺得破甲刃 · 攻+320",
		"enemy_attack": 320,
		"enemy_shield": 0,
		"enemy_heal": 0,
		"enemy_charge": false,
	},
	# --- Armors ---
	{
		"id": &"armor_iron_bulwark",
		"kind": KIND_ARMOR,
		"kind_zh": "护甲",
		"name": "遗迹铁壁甲",
		"desc": "防御 +180，最大生命 +400。",
		"attack": 0,
		"defense": 180,
		"magic_resistance": 0,
		"max_health": 400,
		"enemy_buff_zh": "夺得铁壁 · 护盾+650",
		"enemy_attack": 0,
		"enemy_shield": 650,
		"enemy_heal": 0,
		"enemy_charge": false,
	},
	{
		"id": &"armor_echo_mantle",
		"kind": KIND_ARMOR,
		"kind_zh": "护甲",
		"name": "回声抗魔披风",
		"desc": "魔抗 +220，防御 +90。",
		"attack": 0,
		"defense": 90,
		"magic_resistance": 220,
		"max_health": 0,
		"enemy_buff_zh": "夺得披风 · 护盾+500 & 抗+150",
		"enemy_attack": 0,
		"enemy_shield": 500,
		"enemy_heal": 0,
		"enemy_charge": false,
	},
	{
		"id": &"armor_warden_plate",
		"kind": KIND_ARMOR,
		"kind_zh": "护甲",
		"name": "守望者胸铠",
		"desc": "最大生命 +700，防御 +100。",
		"attack": 0,
		"defense": 100,
		"magic_resistance": 0,
		"max_health": 700,
		"enemy_buff_zh": "夺得胸铠 · 回复+650 血",
		"enemy_attack": 0,
		"enemy_shield": 0,
		"enemy_heal": 650,
		"enemy_charge": false,
	},
	# --- Consumables ---
	{
		"id": &"item_dusk_potion",
		"kind": KIND_CONSUMABLE,
		"kind_zh": "道具",
		"name": "黄昏疗伤药",
		"desc": "使用：立刻回复 1000 生命。",
		"heal": 1000,
		"enemy_buff_zh": "吞食药剂 · 回复+800 血",
		"enemy_attack": 0,
		"enemy_shield": 0,
		"enemy_heal": 800,
		"enemy_charge": false,
	},
	{
		"id": &"item_echo_hourglass",
		"kind": KIND_CONSUMABLE,
		"kind_zh": "道具",
		"name": "回声沙漏",
		"desc": "使用：本回合立刻获得 +1 行动点（不给敌方充能）。",
		"ap_gain": 1,
		"enemy_buff_zh": "吞噬沙漏 · 技能立刻满充能",
		"enemy_attack": 120,
		"enemy_shield": 0,
		"enemy_heal": 0,
		"enemy_charge": true,
	},
	{
		"id": &"item_vow_talisman",
		"kind": KIND_CONSUMABLE,
		"kind_zh": "道具",
		"name": "誓约护符",
		"desc": "使用：立刻获得 700 护盾与 +1 终极能量。",
		"shield_gain": 700,
		"energy_gain": 1,
		"enemy_buff_zh": "夺得护符 · 护盾+600",
		"enemy_attack": 0,
		"enemy_shield": 600,
		"enemy_heal": 0,
		"enemy_charge": false,
	},
	# --- Skill Upgrades ---
	{
		"id": &"upg_heavy_push",
		"kind": KIND_SKILL_UPGRADE,
		"kind_zh": "技能升级",
		"name": "铭文·重盾冲击",
		"desc": "使用：「誓刃」击退距离提升至 2 格。",
		"mod_id": &"heavy_push",
		"enemy_buff_zh": "吸收铭文 · 攻+220 & 满充能",
		"enemy_attack": 220,
		"enemy_shield": 0,
		"enemy_heal": 0,
		"enemy_charge": true,
	},
	{
		"id": &"upg_shatter_slam",
		"kind": KIND_SKILL_UPGRADE,
		"kind_zh": "技能升级",
		"name": "铭文·碎石震荡",
		"desc": "使用：撞墙 / 撞怪真实伤害翻倍（450 → 900）。",
		"mod_id": &"shatter_slam",
		"enemy_buff_zh": "吸收铭文 · 攻+260",
		"enemy_attack": 260,
		"enemy_shield": 0,
		"enemy_heal": 0,
		"enemy_charge": false,
	},
	{
		"id": &"upg_shock_shield",
		"kind": KIND_SKILL_UPGRADE,
		"kind_zh": "技能升级",
		"name": "铭文·震荡誓盾",
		"desc": "使用：「誓盾庇护」+350 护盾，且开盾震退周围敌人。",
		"mod_id": &"shock_shield",
		"enemy_buff_zh": "吸收铭文 · 护盾+700",
		"enemy_attack": 0,
		"enemy_shield": 700,
		"enemy_heal": 0,
		"enemy_charge": false,
	},
	{
		"id": &"upg_wide_verdict",
		"kind": KIND_SKILL_UPGRADE,
		"kind_zh": "技能升级",
		"name": "铭文·大裁决域",
		"desc": "使用：「绝对裁决」范围扩大至自身周围 2 格。",
		"mod_id": &"wide_verdict",
		"enemy_buff_zh": "吸收铭文 · 满充能 & 攻+200",
		"enemy_attack": 200,
		"enemy_shield": 0,
		"enemy_heal": 0,
		"enemy_charge": true,
	},
]


static func roll_random_item() -> Dictionary:
	if ITEMS.is_empty():
		return {}
	return ITEMS[randi() % ITEMS.size()].duplicate(true)


static func get_item(item_id: StringName) -> Dictionary:
	for item in ITEMS:
		if item["id"] == item_id:
			return item.duplicate(true)
	return {}
