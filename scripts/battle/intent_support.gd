class_name IntentSupport
extends RefCounted

## 规划器与专属技共用的几何与数值工具。
##
## 拆出来的原因很实际：这些函数不能留在 intent_planner 里，否则
## elite_skills.gd 一 preload 规划器就成了循环依赖；也不能各抄一份，否则
## 「三格带」「路径搜索」迟早出现两个版本。它们只读战场，不产生意图。

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")


## Charge throttling, in one place. Eight signature branches used to spell out
## the same three-line check; a data flag plus one predicate means a new
## charge-gated skill cannot forget it and an ungated one cannot inherit it.
##
## "Full charge required" only applies to units that HAVE a charge bar. A profile
## with `skill_charge_max == 0` is not on that clock, so the gate opens for it -
## the original inline checks worked the same way, and flipping this branch made
## 千枝神将 stand still for four turns.
static func charge_ready(enemy, spec) -> bool:
	if not spec.requires_full_charge:
		return true
	if enemy.skill_charge_max <= 0:
		return true
	return enemy.skill_charge >= enemy.skill_charge_max


## Signature-skill damage. §14 requires it to be independent of the base attack
## (the sheets already carry a 30% cut), so a profile that pins `skill_damage`
## wins over the per-action multiplier.
static func signature_damage(enemy, multiplier: float) -> int:
	if "skill_damage" in enemy and int(enemy.skill_damage) > 0:
		return int(enemy.skill_damage)
	return CombatMathScript.calculate_raw_damage(enemy.attack, multiplier)


## Plain-attack damage. §15 gives each boss its own attendance multiplier -
## 樱刃 0.80 / 重盾击 0.70 / 花影弹 0.65 - so a profile may override the action
## default. Everything without the field keeps the generic number.
static func plain_attack_damage(enemy, default_multiplier: float) -> int:
	var multiplier: float = default_multiplier
	if "basic_attack_multiplier" in enemy and float(enemy.basic_attack_multiplier) > 0.0:
		multiplier = float(enemy.basic_attack_multiplier)
	return CombatMathScript.calculate_raw_damage(enemy.attack, multiplier)


static func ward_shield_of(enemy) -> int:
	if enemy == null or not ("ward_shield" in enemy):
		return 0
	return maxi(0, int(enemy.ward_shield))


static func stance_percent_of(enemy) -> float:
	if enemy == null or not ("ward_stance_percent" in enemy):
		return 0.0
	return maxf(0.0, float(enemy.ward_stance_percent))


static func stance_node_bonus_of(enemy) -> float:
	if enemy == null or not ("ward_stance_node_bonus" in enemy):
		return 0.0
	return maxf(0.0, float(enemy.ward_stance_node_bonus))


static func tier_of(actor) -> int:
	if actor == null or not ("tier" in actor):
		return 0
	return int(actor.tier)


## "范围 3 个相邻地格" (§14/§15.1/§15.3). The band crosses the line of approach
## so the aim cell's occupant can still step out of it, and near an edge it
## slides inward instead of clipping to two tiles - the document's number is
## three, so returning two would quietly shrink the skill.
static func three_cell_band(battle, origin: Vector2i, aim: Vector2i, avoid_cell: Vector2i = Vector2i(-999, -999)) -> Array[Vector2i]:
	var forward := Vector2i(signi(aim.x - origin.x), signi(aim.y - origin.y))
	if forward == Vector2i.ZERO:
		forward = Vector2i.RIGHT
	var axes: Array[Vector2i] = [Vector2i(-forward.y, forward.x), forward]
	# Bands that do not cover the caster come first: the boss is immune to its own
	# ground, so a sweep that only ever lands under its own feet would look like a
	# bug even when it is harmless.
	var bands: Array = []
	for axis in axes:
		bands.append([aim - axis, aim, aim + axis])
		bands.append([aim, aim - axis, aim - axis * 2])
		bands.append([aim, aim + axis, aim + axis * 2])
	var clean: Array = []
	var dirty: Array = []
	for band in bands:
		if band.has(avoid_cell):
			dirty.append(band)
		else:
			clean.append(band)
	for candidate in clean + dirty:
		var cells: Array[Vector2i] = []
		var legal := true
		for raw_cell in candidate:
			var cell: Vector2i = raw_cell
			if not GridRulesScript.is_inside_bounds(cell, battle.grid_size):
				legal = false
				break
			cells.append(cell)
		if legal:
			return cells
	var fallback: Array[Vector2i] = [aim]
	return fallback


## Per-trigger hazard damage. §15.1 pins 凋零 at 0.25 of the skill's damage;
## 残春 only says "少量", so its multiplier is the single draft constant above.
static func hazard_damage_of(_enemy, skill_damage: int, multiplier: float) -> int:
	return maxi(1, roundi(float(skill_damage) * multiplier))


static func intent_id(battle, enemy) -> String:
	return "intent_%d_%s" % [battle.turn_number, enemy.actor_id]


## Breadth-first walk that targets an unreserved cell adjacent to the goal,
## avoiding ally destination collisions. If every adjacent tile is blocked or
## reserved, advances toward the closest reachable unreserved cell so melee
## units surround instead of idling behind teammates.
static func pursuit_path(
	battle,
	start: Vector2i,
	goal: Vector2i,
	actor_id: String,
	max_steps: int,
	reserved_cells: Dictionary = {}
) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var came_from := {start: start}
	var dist_map := {start: 0}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var occupied: Dictionary = battle.get_occupied_cells(actor_id)
	var found_cell := start
	var found := false
	var best_close_cell := start
	var best_close_dist: int = GridRulesScript.manhattan_distance(start, goal)
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var cur_d: int = GridRulesScript.manhattan_distance(current, goal)
		if current != start and cur_d == 1 and not reserved_cells.has(current):
			found_cell = current
			found = true
			break
		if current != start and not reserved_cells.has(current) and cur_d < best_close_dist:
			best_close_dist = cur_d
			best_close_cell = current
		for direction in directions:
			var next: Vector2i = current + direction
			if not GridRulesScript.is_inside_bounds(next, battle.grid_size):
				continue
			if battle.blocked_cells.has(next) or occupied.has(next) or came_from.has(next):
				continue
			came_from[next] = current
			dist_map[next] = int(dist_map[current]) + 1
			queue.append(next)
	var chosen := found_cell if found else best_close_cell
	if chosen == start:
		return []
	var reversed_path: Array[Vector2i] = []
	var cursor: Vector2i = chosen
	while cursor != start:
		reversed_path.push_front(cursor)
		cursor = came_from[cursor]
	var result: Array[Vector2i] = []
	for index in range(mini(max_steps, reversed_path.size())):
		result.append(reversed_path[index])
	if not result.is_empty() and reserved_cells.has(result[result.size() - 1]):
		while not result.is_empty() and reserved_cells.has(result[result.size() - 1]):
			result.pop_back()
	return result


## Tactical melee movement:
## Returns 0 (horizontal), 1 (vertical), 2 (diag \), 3 (diag /), or -1 if unaligned.
static func fire_axis_of(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var dx: int = to_cell.x - from_cell.x
	var dy: int = to_cell.y - from_cell.y
	if dx == 0 and dy == 0:
		return -1
	if dy == 0:
		return 0
	if dx == 0:
		return 1
	if absi(dx) == absi(dy):
		return 2 if (dx * dy > 0) else 3
	return -1


## True if a cell is impassable terrain (out of bounds, wall, or intact chest/node).
static func _is_terrain_blocked(battle, cell: Vector2i) -> bool:
	if not GridRulesScript.is_inside_bounds(cell, battle.grid_size):
		return true
	if battle.blocked_cells.has(cell):
		return true
	if battle.beacons.has(cell) and int(battle.beacons[cell].get("health", 0)) > 0:
		return true
	return false


## Counts how many open escape cells adjacent to target_cell would be newly
## covered by a forward orthogonal sweep from cand, ignoring walls/chests.
static func _uncovered_escape_count(battle, cand: Vector2i, target_cell: Vector2i, threatened: Dictionary) -> int:
	var forward := Vector2i(signi(target_cell.x - cand.x), signi(target_cell.y - cand.y))
	var perp := Vector2i(-forward.y, forward.x)
	var sweep: Dictionary = {}
	for depth in [1, 2]:
		var rc: Vector2i = cand + forward * depth
		for side in [-1, 0, 1]:
			sweep[rc + perp * side] = true
	var hits: int = 0
	for off in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var esc: Vector2i = target_cell + off
		if _is_terrain_blocked(battle, esc):
			continue
		if sweep.has(esc) and not threatened.has(esc):
			hits += 1
	return hits


## True when standing on cand would step directly onto an allied backline's
## unobstructed 8-way firing lane to target_cell (blocking friendly fire).
static func _blocks_ranged_sight(battle, cand: Vector2i, target_cell: Vector2i, ranged_cells: Array, sight_blockers: Dictionary) -> bool:
	for raw_rc in ranged_cells:
		var rc: Vector2i = raw_rc
		if rc == cand or rc == target_cell:
			continue
		if fire_axis_of(rc, target_cell) < 0:
			continue
		if fire_axis_of(rc, cand) != fire_axis_of(rc, target_cell):
			continue
		if GridRulesScript.manhattan_distance(rc, cand) + GridRulesScript.manhattan_distance(cand, target_cell) != GridRulesScript.manhattan_distance(rc, target_cell):
			continue
		if GridRulesScript.has_clear_line_of_sight(rc, target_cell, battle.blocked_cells, sight_blockers):
			return true
	return false


## True when cand lies on the protective screen between target_cell and any ally
## backline ranged cell (closer to both than their full separation).
static func _screens_ranged_ally(cand: Vector2i, target_cell: Vector2i, ranged_cells: Array) -> bool:
	for raw_rc in ranged_cells:
		var rc: Vector2i = raw_rc
		var d_tr: int = GridRulesScript.manhattan_distance(target_cell, rc)
		if d_tr < 2:
			continue
		var d_tc: int = GridRulesScript.manhattan_distance(target_cell, cand)
		var d_cr: int = GridRulesScript.manhattan_distance(cand, rc)
		if d_tc + d_cr <= d_tr + 1 and d_cr < d_tr:
			return true
	return false


## Global BFS detour when walls or chests block every firing lane within max_steps:
## finds the nearest unreserved cell anywhere on the board that has a clear firing
## lane / sightline to target_cell, then returns the first max_steps along it.
static func _find_ranged_detour_path(
	battle,
	enemy,
	target,
	eff_min: int,
	max_range: int,
	require_line: bool,
	need_sight: bool,
	max_steps: int,
	occupied: Dictionary,
	sight_blockers: Dictionary,
	reserved_cells: Dictionary
) -> Array[Vector2i]:
	var start: Vector2i = enemy.cell
	var queue: Array[Vector2i] = [start]
	var came_from := {start: start}
	var goal_cell := start
	var found := false
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur != start and not reserved_cells.has(cur):
			var dist: int = maxi(absi(cur.x - target.cell.x), absi(cur.y - target.cell.y)) if require_line else GridRulesScript.manhattan_distance(cur, target.cell)
			if dist >= eff_min and dist <= max_range:
				var aligned: bool = fire_axis_of(cur, target.cell) >= 0
				if require_line:
					if aligned and GridRulesScript.has_clear_line_of_sight(cur, target.cell, battle.blocked_cells, sight_blockers):
						goal_cell = cur
						found = true
						break
				elif not need_sight or (aligned and GridRulesScript.has_clear_line_of_sight(cur, target.cell, battle.blocked_cells, sight_blockers)):
					goal_cell = cur
					found = true
					break
		for dir in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var nxt: Vector2i = cur + dir
			if not GridRulesScript.is_inside_bounds(nxt, battle.grid_size):
				continue
			if battle.blocked_cells.has(nxt) or occupied.has(nxt) or came_from.has(nxt):
				continue
			came_from[nxt] = cur
			queue.append(nxt)
	if not found:
		return []
	var rev: Array[Vector2i] = []
	var cursor: Vector2i = goal_cell
	while cursor != start:
		rev.push_front(cursor)
		cursor = came_from[cursor]
	var out: Array[Vector2i] = []
	for i in range(mini(max_steps, rev.size())):
		out.append(rev[i])
	while not out.is_empty() and reserved_cells.has(out[out.size() - 1]):
		out.pop_back()
	return out


## Tactical melee movement with formation & terrain awareness:
## 1) If a 2-tile orthogonal cleave/signature is ready, step into an unreserved
##    orthogonal launch cell that seals uncovered real escape tiles.
## 2) In Shield-Wall formation, screen between hero and backline WITHOUT stepping
##    into friendly archers' clear firing lanes.
## 3) In Pincer formation, exploit walls/chests as natural pinning barriers.
static func melee_tactical_path(
	battle,
	enemy,
	target,
	max_steps: int,
	prefer_ortho_range2: bool,
	reserved_cells: Dictionary = {},
	formation: Dictionary = {}
) -> Array[Vector2i]:
	var occupied: Dictionary = battle.get_occupied_cells(enemy.actor_id)
	var sight_blockers: Dictionary = battle.get_sight_blockers(enemy.actor_id)
	var form_id: String = str(formation.get("id", ""))
	var ranged_cells: Array = formation.get("ranged_cells", [])
	var threatened: Dictionary = formation.get("threatened_cells", {})
	var best_score: int = -999999
	var best_path: Array[Vector2i] = []
	for dy in range(-max_steps, max_steps + 1):
		for dx in range(-max_steps, max_steps + 1):
			if dx == 0 and dy == 0:
				continue
			if absi(dx) + absi(dy) > max_steps:
				continue
			var cand: Vector2i = enemy.cell + Vector2i(dx, dy)
			if not GridRulesScript.is_inside_bounds(cand, battle.grid_size):
				continue
			if battle.blocked_cells.has(cand) or occupied.has(cand) or reserved_cells.has(cand):
				continue
			var d: int = GridRulesScript.manhattan_distance(cand, target.cell)
			var ortho_cleave_ok := false
			if prefer_ortho_range2 and d >= 1 and d <= 2 and (cand.x == target.cell.x or cand.y == target.cell.y):
				ortho_cleave_ok = GridRulesScript.has_clear_orthogonal_line(cand, target.cell, battle.blocked_cells, occupied)
			if d != 1 and not ortho_cleave_ok:
				continue
			var path := GridRulesScript.find_path(enemy.cell, cand, battle.grid_size, battle.blocked_cells, occupied, max_steps)
			if path.is_empty():
				continue
			var score: int = 0
			if ortho_cleave_ok:
				score += 1200 + (80 if d == 2 else 0)
				score += _uncovered_escape_count(battle, cand, target.cell, threatened) * 100
			if d == 1:
				score += 900
				var opposite: Vector2i = target.cell * 2 - cand
				if occupied.has(opposite) or reserved_cells.has(opposite):
					score += 260 if form_id == "pincer_lockdown" else 160
				elif _is_terrain_blocked(battle, opposite):
					# Pin the hero against a wall or intact chest!
					score += 220 if form_id == "pincer_lockdown" else 120
				elif form_id == "pincer_lockdown":
					for perp in [Vector2i(cand.y - target.cell.y, target.cell.x - cand.x), Vector2i(target.cell.y - cand.y, cand.x - target.cell.x)]:
						var side_c: Vector2i = target.cell + perp
						if occupied.has(side_c) or reserved_cells.has(side_c) or _is_terrain_blocked(battle, side_c):
							score += 130
							break
			if form_id == "shield_wall":
				if _blocks_ranged_sight(battle, cand, target.cell, ranged_cells, sight_blockers):
					score -= 260
				elif _screens_ranged_ally(cand, target.cell, ranged_cells):
					score += 260
			score -= path.size() * 20
			if score > best_score:
				best_score = score
				best_path = path
	if not best_path.is_empty():
		return best_path
	return pursuit_path(battle, enemy.cell, target.cell, enemy.actor_id, max_steps, reserved_cells)


## Smart ranged/caster kiting & formation crossfire positioning with obstacle detour:
## Picks an unreserved reachable cell within max_steps that establishes a valid
## firing lane or line-of-sight around walls/chests; if every local cell is
## occluded by terrain, routes around obstacles via _find_ranged_detour_path.
static func ranged_reposition_path(
	battle,
	enemy,
	target,
	min_range: int,
	max_range: int,
	require_line: bool,
	max_steps: int,
	need_sight: bool = false,
	reserved_cells: Dictionary = {},
	formation: Dictionary = {}
) -> Array[Vector2i]:
	var occupied: Dictionary = battle.get_occupied_cells(enemy.actor_id)
	var sight_blockers: Dictionary = battle.get_sight_blockers(enemy.actor_id)
	var ideal_dist: int = clampi(min_range + 1, min_range, max_range)
	var eff_min: int = 2 if require_line else min_range
	var form_id: String = str(formation.get("id", ""))
	var used_axes: Dictionary = formation.get("used_axes", {})
	var melee_cells: Array = formation.get("melee_cells", [])
	var nearest_melee_dist: int = 999
	for raw_mc in melee_cells:
		nearest_melee_dist = mini(nearest_melee_dist, GridRulesScript.manhattan_distance(target.cell, raw_mc))

	var best_score: int = -999999
	var best_path: Array[Vector2i] = []
	var found_clear_local := false
	for dy in range(-max_steps, max_steps + 1):
		for dx in range(-max_steps, max_steps + 1):
			if dx == 0 and dy == 0:
				continue
			if absi(dx) + absi(dy) > max_steps:
				continue
			var cand: Vector2i = enemy.cell + Vector2i(dx, dy)
			if not GridRulesScript.is_inside_bounds(cand, battle.grid_size):
				continue
			if battle.blocked_cells.has(cand) or occupied.has(cand) or reserved_cells.has(cand):
				continue
			var path := GridRulesScript.find_path(enemy.cell, cand, battle.grid_size, battle.blocked_cells, occupied, max_steps)
			if path.is_empty():
				continue

			var dist: int = maxi(absi(cand.x - target.cell.x), absi(cand.y - target.cell.y)) if require_line else GridRulesScript.manhattan_distance(cand, target.cell)
			var aligned: bool = (cand.x == target.cell.x or cand.y == target.cell.y or absi(cand.x - target.cell.x) == absi(cand.y - target.cell.y))
			var in_range: bool = dist >= eff_min and dist <= max_range
			var clear_line: bool = false
			if require_line and aligned and in_range:
				clear_line = GridRulesScript.has_clear_line_of_sight(cand, target.cell, battle.blocked_cells, sight_blockers)
			var clear_sight: bool = false
			if not require_line and need_sight and in_range and aligned:
				clear_sight = GridRulesScript.has_clear_line_of_sight(cand, target.cell, battle.blocked_cells, sight_blockers)

			if clear_line or (not require_line and in_range and (not need_sight or clear_sight)):
				found_clear_local = true

			var score: int = 0
			if require_line:
				if clear_line:
					score += 1000
					var axis: int = fire_axis_of(cand, target.cell)
					if axis >= 0 and not used_axes.is_empty() and not used_axes.has(axis):
						score += 320 if form_id == "crossfire_net" else 260
				elif aligned and in_range:
					# Aligned but blocked by a wall/chest: penalize hugging the occluded line!
					score -= 80
			else:
				if in_range:
					score += 800
				if need_sight and clear_sight:
					score += 700

			if in_range:
				score += 320
				if form_id == "shield_wall" and nearest_melee_dist < 999 and GridRulesScript.manhattan_distance(cand, target.cell) > nearest_melee_dist:
					score += 120
			elif dist < eff_min:
				score -= (eff_min - dist) * 450
			else:
				score -= (dist - max_range) * 80

			score -= absi(dist - ideal_dist) * 15
			if require_line and not aligned:
				var adx: int = absi(cand.x - target.cell.x)
				var ady: int = absi(cand.y - target.cell.y)
				var line_gap: int = mini(mini(adx, ady), absi(adx - ady))
				score -= line_gap * 55

			if score > best_score:
				best_score = score
				best_path = path

	# When walls or chests occlude every local cell, route smoothly around them
	# toward the nearest unobstructed firing lane instead of hugging the wall.
	if not found_clear_local:
		var detour := _find_ranged_detour_path(battle, enemy, target, eff_min, max_range, require_line, need_sight, max_steps, occupied, sight_blockers, reserved_cells)
		if not detour.is_empty():
			return detour
	return best_path


## Picks an aim cell that maximizes lockdown across the target and its REAL open
## escape tiles (ignoring walls and intact chests the hero cannot enter).
static func pick_uncrowded_aim(
	battle,
	source_cell: Vector2i,
	target_cell: Vector2i,
	min_r: int,
	max_r: int,
	claimed_cells: Dictionary,
	is_cross_area: bool = false
) -> Vector2i:
	var base_dist: int = GridRulesScript.manhattan_distance(source_cell, target_cell)
	if not claimed_cells.has(target_cell) and base_dist >= min_r and base_dist <= max_r:
		return target_cell
	var best_aim := Vector2i(-1, -1)
	var best_score: int = -9999
	for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var adj: Vector2i = target_cell + offset
		if _is_terrain_blocked(battle, adj):
			continue
		var d: int = GridRulesScript.manhattan_distance(source_cell, adj)
		if d < min_r or d > max_r:
			continue
		var score: int = 0
		if not claimed_cells.has(adj):
			score += 100
		if is_cross_area:
			for off2 in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var c: Vector2i = adj + off2
				if _is_terrain_blocked(battle, c):
					continue
				if GridRulesScript.manhattan_distance(c, target_cell) <= 1 and not claimed_cells.has(c):
					score += 80
		elif not claimed_cells.has(adj):
			return adj
		if score > best_score:
			best_score = score
			best_aim = adj
	if best_aim != Vector2i(-1, -1) and best_score > 0:
		return best_aim
	if base_dist >= min_r and base_dist <= max_r:
		return target_cell
	return Vector2i(-1, -1)
