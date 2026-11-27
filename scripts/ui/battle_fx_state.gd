class_name BattleFxState
extends RefCounted

## 战斗视觉效果的专属状态容器（P1 拆分：从 battle_view.gd 抽出）。
##
## 持有全部瞬态 FX 数据（角色视觉位置、跳跃/受击/突进、飘字、冲击环、
## 敌方分步演出计时），并提供三类操作：
##   1. advance(delta, controller) —— 每帧推进动画与分步敌方回合
##   2. reset_for_encounter(controller) —— 新遭遇清空
##   3. on_event(type, event, controller) —— 战斗事件触发 FX
##   4. snapshot(hover_cell) —— 生成下游 board/hud 视图只读消费的 fx_state 字典
##
## 下游（BoardView / BoardThreatView / BoardObjectsView / HudView）仍按旧字典
## 契约读取，零改动；本类只负责状态的持有与推进，不绘制任何东西。

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const Palette = preload("res://scripts/ui/theme_palette.gd")
const BoardThreatViewScript = preload("res://scripts/ui/board_threat_view.gd")

var time: float = 0.0
var actor_visual_pos: Dictionary = {}
var actor_hop_state: Dictionary = {}
var actor_hit_flash: Dictionary = {}
var actor_lunge: Dictionary = {}
var floating_popups: Array = []
var impact_flashes: Array = []
var enemy_step_timer: float = 0.0
var enemy_phase_finishing: bool = false
var acting_enemy_id: String = ""


## 新遭遇开始：清空所有瞬态 FX 并重置角色视觉位置到当前格。
func reset_for_encounter(controller) -> void:
	actor_visual_pos.clear()
	actor_hop_state.clear()
	actor_hit_flash.clear()
	actor_lunge.clear()
	floating_popups.clear()
	impact_flashes.clear()
	enemy_step_timer = 0.0
	enemy_phase_finishing = false
	acting_enemy_id = ""
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		actor_visual_pos[String(actor_id)] = Palette.cell_center(actor.cell)


## 每帧推进：平滑跳跃插值、受击闪烁衰减、突进衰减、飘字/冲击环老化，
## 以及敌方回合的分步演出。返回是否需要调用方 queue_redraw()。
func advance(delta: float, controller) -> bool:
	time += delta

	# Smooth hop-interpolated movement for every living/downed actor
	for actor_id in controller.actors:
		var key := String(actor_id)
		var actor = controller.actors[actor_id]
		var target_pos: Vector2 = Palette.cell_center(actor.cell)
		if not actor_visual_pos.has(key):
			actor_visual_pos[key] = target_pos
		if actor_hop_state.has(key):
			var hop: Dictionary = actor_hop_state[key]
			hop["age"] = float(hop["age"]) + delta
			var u: float = clampf(float(hop["age"]) / maxf(0.05, float(hop["duration"])), 0.0, 1.0)
			var ease_u: float = 1.0 - pow(1.0 - u, 3.0)
			var base: Vector2 = Vector2(hop["from"]).lerp(target_pos, ease_u)
			var arc_y: float = -sin(u * PI) * 14.0
			actor_visual_pos[key] = base + Vector2(0.0, arc_y)
			if u >= 1.0:
				actor_visual_pos[key] = target_pos
				actor_hop_state.erase(key)
		else:
			var cur: Vector2 = actor_visual_pos[key]
			if cur.distance_to(target_pos) > 1.0:
				actor_visual_pos[key] = cur.lerp(target_pos, minf(1.0, delta * 18.0))
			else:
				actor_visual_pos[key] = target_pos

	# Decay hit flashes
	for key in actor_hit_flash.keys():
		var left: float = float(actor_hit_flash[key]) - delta * 3.8
		if left <= 0.0:
			actor_hit_flash.erase(key)
		else:
			actor_hit_flash[key] = left

	# Decay attack lunges
	for key in actor_lunge.keys():
		var vec: Vector2 = actor_lunge[key]
		vec = vec.lerp(Vector2.ZERO, minf(1.0, delta * 14.0))
		if vec.length() < 0.4:
			actor_lunge.erase(key)
		else:
			actor_lunge[key] = vec

	# Advance floating damage/shield popups
	var alive_popups: Array = []
	for item in floating_popups:
		item["age"] = float(item["age"]) + delta
		if float(item["age"]) < float(item["duration"]):
			alive_popups.append(item)
	floating_popups = alive_popups

	# Advance impact flash rings
	var alive_impacts: Array = []
	for item in impact_flashes:
		item["age"] = float(item["age"]) + delta
		if float(item["age"]) < float(item["duration"]):
			alive_impacts.append(item)
	impact_flashes = alive_impacts

	return true


## 敌方分步演出：由调用方在 _process 中按 BattlePhase.ENEMY 条件调用。
## 返回状态栏消息（若攻势结束），否则返回空字符串。
func step_enemy_phase(delta: float, controller) -> String:
	enemy_step_timer -= delta
	if enemy_step_timer > 0.0:
		return ""
	if enemy_phase_finishing:
		enemy_phase_finishing = false
		acting_enemy_id = ""
		controller.finish_enemy_phase_stepped()
		if controller.phase == ControllerScript.BattlePhase.PLAYER:
			return "敌方攻势结束，轮到你的回合！"
	else:
		acting_enemy_id = ""
		for it in controller.intents:
			if it.state == 0:
				acting_enemy_id = it.source_actor_id
				break
		var ran: bool = controller.resolve_next_enemy_intent()
		if ran:
			enemy_step_timer = 0.56
		else:
			acting_enemy_id = ""
			enemy_phase_finishing = true
			enemy_step_timer = 0.28
	return ""


## 摄像机旋转后：中断进行中的跳跃并把所有角色视觉位置直接对齐到新投影格。
func snap_actor_positions(controller) -> void:
	actor_hop_state.clear()
	actor_lunge.clear()
	floating_popups.clear()
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		actor_visual_pos[String(actor_id)] = Palette.cell_center(actor.cell)


## 敌方分步回合开始：清除上一轮的收尾标记并设置首步延迟。
func prepare_enemy_step() -> void:
	enemy_phase_finishing = false
	acting_enemy_id = ""
	enemy_step_timer = 0.25


## 生成下游视图消费的只读快照（键名与旧 fx_state 字典完全一致）。
func snapshot(hover_cell: Vector2i) -> Dictionary:
	return {
		"time": time,
		"hover_cell": hover_cell,
		"acting_enemy": acting_enemy_id,
		"actor_pos": actor_visual_pos,
		"hit_flash": actor_hit_flash,
		"lunge": actor_lunge,
		"popups": floating_popups,
		"impacts": impact_flashes,
	}


## 战斗事件 → FX。返回 true 表示该事件已被处理（调用方无需再处理）。
## status_message 会通过 out_status 传出；selected_skill 通过 out_selected_skill 传出。
func on_event(
	event_type: String,
	event: Dictionary,
	controller,
	out_status: Array,
	out_selected_skill: Array
) -> bool:
	match event_type:
		"actor_moved":
			var mover_id: String = str(event.get("actor_id", ""))
			var mover = controller.get_actor(mover_id)
			if not mover_id.is_empty() and mover != null:
				var from_pos: Vector2 = actor_visual_pos.get(mover_id, Palette.cell_center(mover.cell))
				actor_hop_state[mover_id] = {"from": from_pos, "age": 0.0, "duration": 0.18}
			BoardThreatViewScript.push_event_callout(controller, event, floating_popups, impact_flashes)
			return true
		"enemy_action_resolved", "counter_resolved", "boss_enraged":
			var callout: String = BoardThreatViewScript.push_event_callout(controller, event, floating_popups, impact_flashes)
			if not callout.is_empty():
				out_status.append(callout)
			return true
		"damage_applied":
			trigger_damage_fx(event, controller)
			return true
		"beacon_damaged":
			trigger_beacon_fx(event, controller)
			return true
		"enemy_action_missed":
			trigger_miss_fx(event, controller)
			return true
		"chest_stolen_by_enemy":
			var thief_id: String = str(event.get("actor_id", ""))
			var thief = controller.get_actor(thief_id)
			if thief != null:
				append_popup(
					Palette.cell_center(thief.cell) + Vector2(-46.0, -78.0),
					str(event.get("detail", "夺宝强化!")),
					Palette.GOLD_LIGHT,
					1.35
				)
			return true
		"loot_dropped":
			var dead_id: String = str(event.get("actor_id", ""))
			var dead = controller.get_actor(dead_id)
			if dead != null:
				append_popup(
					Palette.cell_center(dead.cell) + Vector2(-36.0, -56.0),
					str(event.get("detail", "掉落装备!")),
					Palette.GOLD_PALE,
					1.35
				)
			return true
		"loot_picked_up":
			var hero = controller.get_active_character()
			if hero != null:
				var nm: String = str(event.get("detail", "装备"))
				out_status.append("拾取了掉落装备「%s」（按 [B] 穿戴）！" % nm)
				append_popup(
					Palette.cell_center(hero.cell) + Vector2(-36.0, -78.0),
					"拾取 " + nm,
					Palette.GOLD_PALE,
					1.25
				)
			return true
		"player_turn_started":
			out_selected_skill.append(-1)
			return false  # 技能栏重建仍由 view 负责
	return false


func append_popup(pos: Vector2, text: String, color: Color, duration: float) -> void:
	floating_popups.append({
		"pos": pos,
		"text": text,
		"color": color,
		"age": 0.0,
		"duration": duration,
	})


func trigger_beacon_fx(event: Dictionary, controller) -> void:
	var source_id: String = str(event.get("actor_id", ""))
	var detail: String = str(event.get("detail", ""))
	var applied: int = _extract_int_field(detail, "applied=")
	var source = controller.get_actor(source_id)
	for b_cell in controller.beacons:
		if str(controller.beacons[b_cell]["id"]) == str(event.get("target_id", "")):
			var is_ward := str(controller.beacons[b_cell].get("kind", "")) == "ward_node"
			impact_flashes.append({"cell": b_cell, "color": Color("#6ef2c8") if is_ward else Palette.TELEGRAPH_CHARGE_LINE, "age": 0.0, "duration": 0.38})
			append_popup(
				Palette.cell_center(b_cell) + Vector2(-24.0, -54.0),
				("结界 -%d" if is_ward else "宝箱 -%d") % applied,
				Color("#8ef5d4") if is_ward else Palette.WARN,
				0.95
			)
			if source != null:
				var dir: Vector2 = (Palette.cell_center(b_cell) - Palette.cell_center(source.cell)).normalized()
				actor_lunge[source_id] = dir * 18.0
			break


func trigger_miss_fx(event: Dictionary, controller) -> void:
	var source_id: String = str(event.get("actor_id", ""))
	var source = controller.get_actor(source_id)
	if source != null:
		for intent in controller.intents:
			if intent.source_actor_id == source_id:
				impact_flashes.append({"cell": intent.target_cell, "color": Palette.GOLD_LIGHT, "age": 0.0, "duration": 0.30})
				append_popup(
					Palette.cell_center(intent.target_cell) + Vector2(-14.0, -24.0),
					"落空",
					Palette.TEXT_DIM,
					0.75
				)
				var dir: Vector2 = (Palette.cell_center(intent.target_cell) - Palette.cell_center(source.cell)).normalized()
				actor_lunge[source_id] = dir * 16.0
				break


func trigger_damage_fx(event: Dictionary, controller) -> void:
	var source_id: String = str(event.get("actor_id", ""))
	var target_id: String = str(event.get("target_id", ""))
	var detail: String = str(event.get("detail", ""))
	var applied: int = _extract_int_field(detail, "applied=")
	var absorbed: int = _extract_int_field(detail, "absorbed=")

	var target = controller.get_actor(target_id)
	var source = controller.get_actor(source_id)
	if target != null:
		actor_hit_flash[target_id] = 1.0
		var pos: Vector2 = actor_visual_pos.get(target_id, Palette.cell_center(target.cell)) + Vector2(-14.0, -56.0)
		if applied > 0:
			append_popup(
				pos,
				"-%d" % applied,
				Palette.WARN if target.team == "player" else Palette.GOLD_PALE,
				0.85
			)
		elif absorbed > 0:
			append_popup(
				pos,
				"格挡 %d" % absorbed,
				Palette.CYAN,
				0.85
			)
	if source != null and target != null and source_id != target_id:
		var src_pos: Vector2 = Palette.cell_center(source.cell)
		var dst_pos: Vector2 = Palette.cell_center(target.cell)
		var dir: Vector2 = (dst_pos - src_pos).normalized()
		actor_lunge[source_id] = dir * 16.0


static func _extract_int_field(detail: String, prefix: String) -> int:
	var idx: int = detail.find(prefix)
	if idx < 0:
		return 0
	var start: int = idx + prefix.length()
	var end: int = detail.find(" ", start)
	var raw: String = detail.substr(start) if end < 0 else detail.substr(start, end - start)
	return int(raw) if raw.is_valid_int() else 0
