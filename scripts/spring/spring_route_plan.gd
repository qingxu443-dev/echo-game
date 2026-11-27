class_name SpringRoutePlan
extends RefCounted

## Hard-mode route planner for 春之境 (定轨规划模式).
##
## Before taking a single step, the player plots a complete sequence of
## destinations starting from `template.start_cell` and ending strictly on
## `template.boss_cell` within the stamina budget. Once locked, movement is
## restricted to stepping sequentially through the locked waypoints until the
## route reaches the boss or the run ends.

const AUTO_STEP_DELAY: float = 0.45

var hard_mode: bool = false
var locked: bool = false
var waypoints: Array[Vector2i] = []
var cursor: int = 0
## Runtime-only countdown (seconds) for automatic stepping along a locked route.
var auto_step_timer: float = -1.0


static func create(is_hard: bool = false) -> SpringRoutePlan:
	var plan := SpringRoutePlan.new()
	plan.hard_mode = is_hard
	return plan


func is_planning() -> bool:
	return hard_mode and not locked


func is_locked_active() -> bool:
	return hard_mode and locked


func tail_cell(start_cell: Vector2i) -> Vector2i:
	if waypoints.is_empty():
		return start_cell
	return waypoints[waypoints.size() - 1]


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func total_cost(start_cell: Vector2i) -> int:
	var cost: int = 0
	var prev: Vector2i = start_cell
	for cell in waypoints:
		cost += manhattan(prev, cell)
		prev = cell
	return cost


func ends_at_boss(template: SpringMapTemplate) -> bool:
	if template == null or waypoints.is_empty():
		return false
	return waypoints[waypoints.size() - 1] == template.boss_cell


## Adds a waypoint during planning, or pops it if the player taps the current
## tail cell again. Returns {"ok": bool, "action": String, "message": String}.
func toggle_waypoint(cell: Vector2i, template: SpringMapTemplate, stamina_budget: int) -> Dictionary:
	if not is_planning():
		return {"ok": false, "action": "none", "message": "路线已锁定，无法修改。"}
	if template == null or not template.is_inside(cell):
		return {"ok": false, "action": "none", "message": "所选格超出地图范围。"}
	if not waypoints.is_empty() and waypoints[waypoints.size() - 1] == cell:
		waypoints.pop_back()
		return {"ok": true, "action": "pop", "message": "已撤销上一步节点。"}
	if cell == template.start_cell:
		return {"ok": false, "action": "none", "message": "起点已固定，请点击后续节点绘制路线。"}
	if waypoints.has(cell):
		return {"ok": false, "action": "none", "message": "该格已在路线中；点击尾部节点可撤销。"}
	if ends_at_boss(template):
		return {"ok": false, "action": "none", "message": "终点已连至首领（王），请锁定启程或先撤销尾部。"}
	var step_cost: int = manhattan(tail_cell(template.start_cell), cell)
	var next_total: int = total_cost(template.start_cell) + step_cost
	if next_total > stamina_budget:
		return {
			"ok": false,
			"action": "none",
			"message": "体力不足：加入此格将需 %d / %d 体力。" % [next_total, stamina_budget],
		}
	waypoints.append(cell)
	if cell == template.boss_cell:
		return {
			"ok": true,
			"action": "push",
			"message": "已连接至首领（王）！总计 %d 站、消耗 %d / %d 体力，可点击「锁定启程」。" % [waypoints.size(), next_total, stamina_budget],
		}
	return {
		"ok": true,
		"action": "push",
		"message": "已加入第 %d 站（累计 %d / %d 体力）；请继续连线直到首领（王）。" % [waypoints.size(), next_total, stamina_budget],
	}


func pop_last() -> bool:
	if not is_planning() or waypoints.is_empty():
		return false
	waypoints.pop_back()
	return true


func clear_plan() -> bool:
	if not is_planning():
		return false
	waypoints.clear()
	cursor = 0
	return true


func lock_validation_error(template: SpringMapTemplate, stamina_budget: int) -> String:
	if not hard_mode:
		return "当前并非困难模式。"
	if locked:
		return "路线已锁定。"
	if template == null or waypoints.is_empty():
		return "请先点击地图节点绘制路线，且尾部必须是首领（王）。"
	if not ends_at_boss(template):
		return "绘制的路线尾部必须是首领（王）格！"
	var needed: int = total_cost(template.start_cell)
	if needed > stamina_budget:
		return "路线总消耗 %d 体力，超出可用 %d 体力。" % [needed, stamina_budget]
	return ""


func can_lock(template: SpringMapTemplate, stamina_budget: int) -> bool:
	return lock_validation_error(template, stamina_budget).is_empty()


func lock_plan(template: SpringMapTemplate, stamina_budget: int) -> Dictionary:
	var err := lock_validation_error(template, stamina_budget)
	if not err.is_empty():
		return {"ok": false, "message": err}
	locked = true
	cursor = 0
	auto_step_timer = 0.35
	return {
		"ok": true,
		"message": "定轨锁定！共 %d 站，正在按路线自动启程…" % waypoints.size(),
	}


func has_next_stop() -> bool:
	return is_locked_active() and cursor >= 0 and cursor < waypoints.size()


func next_stop() -> Vector2i:
	if not has_next_stop():
		return Vector2i(-1, -1)
	return waypoints[cursor]


func is_allowed_destination(cell: Vector2i) -> bool:
	if not hard_mode:
		return true
	if not locked:
		return false
	return has_next_stop() and waypoints[cursor] == cell


func advance_cursor() -> void:
	if has_next_stop():
		cursor += 1


func to_dict() -> Dictionary:
	var serialized: Array = []
	for cell in waypoints:
		serialized.append([cell.x, cell.y])
	return {
		"hard_mode": hard_mode,
		"locked": locked,
		"waypoints": serialized,
		"cursor": cursor,
	}


static func from_dict(data: Dictionary) -> SpringRoutePlan:
	var plan := SpringRoutePlan.new()
	if data.is_empty():
		return plan
	plan.hard_mode = bool(data.get("hard_mode", false))
	plan.locked = bool(data.get("locked", false))
	plan.cursor = maxi(0, int(data.get("cursor", 0)))
	for pair in data.get("waypoints", []):
		if pair is Array and pair.size() == 2:
			plan.waypoints.append(Vector2i(int(pair[0]), int(pair[1])))
	return plan
