class_name CustomLevelData
extends RefCounted

const VERSION := 1
const LIMITS := {"health": [1, 999999], "attack": [0, 99999], "defense": [0, 99999], "magic_resistance": [0, 99999], "shield": [0, 99999], "ultimate_energy": [0, 30], "resource_current": [0, 30], "move_steps": [1, 8], "skill_charge": [0, 10], "skill_charge_max": [1, 10], "skill_damage": [0, 99999], "armor_layers": [0, 8]}
var data: Dictionary = {"version": VERSION, "name": "回声试炼", "width": 8, "height": 8, "ap": 3, "heroes": [], "enemies": [], "walls": [], "chests": []}


static func demo() -> CustomLevelData:
	var level := CustomLevelData.new()
	level.place_unit("hero", "sevrin", Vector2i(2, 6))
	level.place_unit("enemy", "vanguard", Vector2i(2, 3))
	level.place_unit("enemy", "marksman", Vector2i(5, 1))
	level.data.walls = [[4, 3], [4, 4]]
	level.data.chests = [[0, 4]]
	return level


static func from_dict(values: Dictionary) -> CustomLevelData:
	var level := CustomLevelData.new()
	for key in level.data:
		if not values.has(key): return null
		level.data[key] = values[key].duplicate(true) if values[key] is Array or values[key] is Dictionary else values[key]
	if not level.error().is_empty(): return null
	for key in ["width", "height", "ap", "version"]: level.data[key] = int(level.data[key])
	for key in ["heroes", "enemies"]:
		for unit in level.data[key]:
			unit.cell = [int(unit.cell[0]), int(unit.cell[1])]
			for stat in LIMITS:
				if unit.has(stat): unit[stat] = int(unit[stat])
	for group in ["walls", "chests"]:
		for index in range(level.data[group].size()):
			var cell: Array = level.data[group][index]
			level.data[group][index] = [int(cell[0]), int(cell[1])]
	return level


func to_dict() -> Dictionary:
	return data.duplicate(true)


func size() -> Vector2i:
	return Vector2i(int(data.width), int(data.height))


func inside(cell: Vector2i) -> bool:
	return GridRules.is_inside_bounds(cell, size())


static func point(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


func unit_at(cell: Vector2i) -> Dictionary:
	for group in ["heroes", "enemies"]:
		for unit in data[group]:
			if point(unit.cell) == cell: return unit
	return {}


func occupied(cell: Vector2i) -> bool:
	return not unit_at(cell).is_empty() or data.walls.has([cell.x, cell.y]) or data.chests.has([cell.x, cell.y])


func place_unit(kind: String, id: String, cell: Vector2i) -> String:
	if not inside(cell): return "该格不在地图内。"
	if kind not in ["hero", "enemy"]: return "未知单位类型。"
	var sheet = CharacterCatalog.get_definition(id) if kind == "hero" else EnemyCatalog.get_definition(id)
	if sheet == null: return "找不到该单位档案。"
	if kind == "hero":
		for unit in data.heroes:
			if unit.id == id: return move_unit(point(unit.cell), cell)
	if occupied(cell): return "该格已被占用，请先移动或擦除。"
	if data.enemies.size() >= 48 and kind == "enemy": return "当前最多放置 48 名敌人。"
	var unit := {"kind": kind, "id": id, "cell": [cell.x, cell.y], "health": sheet.max_health if kind == "hero" else sheet.health, "attack": sheet.attack, "defense": sheet.defense, "magic_resistance": sheet.magic_resistance, "shield": 0}
	if kind == "hero":
		unit.merge({"ultimate_energy": 0, "resource_current": 0})
	else:
		unit.merge({"move_steps": sheet.move_steps, "skill_charge": 3, "skill_charge_max": 3, "skill_damage": sheet.skill_damage, "armor_layers": 2 if sheet.tier == 2 else 0})
	data["heroes" if kind == "hero" else "enemies"].append(unit)
	return ""


func move_unit(from: Vector2i, to: Vector2i) -> String:
	var unit := unit_at(from)
	if unit.is_empty(): return "先选择一个角色或怪物。"
	if from == to: return ""
	if not inside(to) or occupied(to): return "目标格被占用或不在地图内。"
	unit.cell = [to.x, to.y]
	return ""


func paint(cell: Vector2i, tool: String) -> String:
	if not inside(cell): return "该格不在地图内。"
	var pair := [cell.x, cell.y]
	if tool == "erase":
		for group in ["heroes", "enemies"]:
			for unit in data[group].duplicate():
				if point(unit.cell) == cell: data[group].erase(unit)
		data.walls.erase(pair)
		data.chests.erase(pair)
	elif tool == "floor":
		data.walls.erase(pair)
	elif tool in ["wall", "chest"]:
		var group := "walls" if tool == "wall" else "chests"
		if data[group].has(pair): return ""
		if occupied(cell): return "该格已被占用，请先移动或擦除。"
		data[group].append(pair)
	return ""


func resize_board(width: int, height: int) -> bool:
	if width < 4 or height < 4 or width > 8 or height > 8: return false
	for cell in used_cells():
		if cell.x >= width or cell.y >= height: return false
	data.width = width
	data.height = height
	return true


func used_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for group in ["heroes", "enemies"]:
		for unit in data[group]: cells.append(point(unit.cell))
	for group in ["walls", "chests"]:
		for value in data[group]: cells.append(point(value))
	return cells


func error(playable: bool = false) -> String:
	if data.get("version") != VERSION: return "关卡版本不受支持。"
	if not data.get("name") is String or data.name.strip_edges().is_empty() or data.name.length() > 40: return "名称需为 1–40 个字符。"
	for key in ["width", "height", "ap"]:
		if not _integer(data.get(key)): return "地图参数必须是整数。"
	if data.width < 4 or data.width > 8 or data.height < 4 or data.height > 8: return "地图边长需为 4–8 格。"
	if data.ap < 1 or data.ap > 15: return "行动点需为 1–15。"
	for group in ["heroes", "enemies", "walls", "chests"]:
		if not data.get(group) is Array or data[group].size() > 64: return "地图列表格式无效。"
	if data.heroes.size() > CharacterCatalog.all_ids().size() or data.enemies.size() > 48: return "单位数量超出上限。"
	var used := {}
	var hero_ids := {}
	for group in ["heroes", "enemies"]:
		for unit in data[group]:
			if not unit is Dictionary: return "单位数据格式无效。"
			var kind := "hero" if group == "heroes" else "enemy"
			if unit.get("kind") != kind or not unit.get("id") is String: return "单位标识无效。"
			var sheet = CharacterCatalog.get_definition(unit.id) if kind == "hero" else EnemyCatalog.get_definition(unit.id)
			if sheet == null: return "单位档案不存在。"
			if kind == "hero" and hero_ids.has(unit.id): return "同一角色不能重复上场。"
			hero_ids[unit.id] = true
			if not _valid_cell(unit.get("cell")) or used.has(point(unit.cell)): return "单位位置越界或重叠。"
			used[point(unit.cell)] = true
			for key in ["health", "attack", "defense", "magic_resistance", "shield"]:
				if not unit.has(key): return "缺少单位属性：" + key
			for stat in LIMITS:
				if unit.has(stat) and (not _integer(unit[stat]) or unit[stat] < LIMITS[stat][0] or unit[stat] > LIMITS[stat][1]): return "属性超出范围：" + stat
			if kind == "hero" and (unit.get("ultimate_energy", 0) > sheet.ultimate_energy_max or unit.get("resource_current", 0) > sheet.resource_max): return "角色初始资源超过上限。"
			if kind == "enemy" and unit.get("skill_charge", 0) > unit.get("skill_charge_max", 3): return "初始充能不能高于充能上限。"
	for group in ["walls", "chests"]:
		for value in data[group]:
			if not _valid_cell(value) or used.has(point(value)): return "地形越界或与单位重叠。"
			used[point(value)] = true
	if playable and (data.heroes.is_empty() or data.enemies.is_empty()): return "试玩前至少放置 1 名角色和 1 名敌人。"
	return ""


func _valid_cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1]) and inside(point(value))


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


func encounter() -> EncounterDefinition:
	if not error(true).is_empty(): return null
	var level := EncounterDefinition.new()
	level.level_id = &"custom_sandbox"
	level.display_name_zh = data.name
	level.tactical_hint_zh = "自定义试玩 · F2 返回编辑 · 本模式不结算残晶"
	level.player_cell = point(data.heroes[0].cell)
	for index in range(data.heroes.size()):
		level.character_ids.append(data.heroes[index].id)
		if index > 0: level.ally_cells.append(point(data.heroes[index].cell))
	for unit in data.enemies:
		level.enemy_cells.append(point(unit.cell))
		level.enemy_archetypes.append(unit.id)
	for cell in data.walls: level.obstacles.append(point(cell))
	return level
