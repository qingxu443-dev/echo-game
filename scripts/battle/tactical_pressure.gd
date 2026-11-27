class_name TacticalPressure
extends RefCounted

## Tactical pressure & counterplay rules:
##   1) Reactive melee tracking: enemies do not swing at empty air while the
##      hero is still right beside them (and elites/bosses step 1 tile to chase).
##   2) Melee tolerance gauge: 2 consecutive melee hits in one player turn on
##      an enemy trigger an immediate counterattack; ranged hits never fill it;
##      cleared at turn end. Multi-hit skills count as 1 melee hit per cast.
##   3) Armor / Break + Kill-refund (+1 AP, up to 2/turn while fight continues)
##      + Boss 50% HP Phase-2 enrage with low-HP escort summons.
##   4) Boss dual-action combo intents (pressure + follow-up in one enemy phase).

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const IntentSupportScript = preload("res://scripts/battle/intent_support.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")
const BattleActorScript = preload("res://scripts/actors/battle_actor.gd")

const ARMOR_REDUCTION_MULT: float = 0.65
const ARMOR_BREAK_VULN_MULT: float = 1.25
const TOLERANCE_COUNTER_MULT: float = 0.65
const MAX_AP_REFUNDS_PER_TURN: int = 2

static func begin_player_action(battle) -> void:
	battle.ledger.pressure_sequence += 1


static func init_enemy_pressure(enemy) -> void:
	enemy.melee_tolerance = 0
	# Melee tolerance counter applies to Elites & Bosses (tier >= 1) so clearing
	# ordinary adds stays crisp while tough foes demand deliberate counterplay.
	enemy.melee_tolerance_max = 2 if int(enemy.tier) >= 1 else 0
	enemy.last_melee_hit_seq = -1
	enemy.boss_phase = 1
	enemy.armor_chip_hits = 0
	enemy.last_armor_chip_seq = -1
	enemy.last_armor_break_seq = -1
	enemy.armor_broken_until_turn = -1
	if int(enemy.tier) >= 2:
		enemy.armor_max = 2
		enemy.armor_layers = 2
	else:
		enemy.armor_max = 0
		enemy.armor_layers = 0


static func reset_turn_tolerance(battle) -> void:
	if battle == null or battle.actors == null:
		return
	for actor_id in battle.actors:
		var actor = battle.actors[actor_id]
		if actor != null and actor.team == "enemy":
			actor.melee_tolerance = 0
			actor.last_melee_hit_seq = -1


## Applies Armor damage reduction or Armor-Break vulnerability before mitigation.
static func adjust_incoming_damage(battle, target, amount: int, action_id: String) -> int:
	if target == null or target.team != "enemy" or amount <= 0:
		return amount
	if action_id in ["oathkeeper_judgment_mark", "absolute_guard_counter", "tolerance_counter"]:
		return amount
	if target.armor_layers > 0:
		return maxi(1, roundi(float(amount) * ARMOR_REDUCTION_MULT))
	if target.armor_max > 0 and target.armor_broken_until_turn >= battle.turn_number:
		return maxi(1, roundi(float(amount) * ARMOR_BREAK_VULN_MULT))
	return amount


## Chips enemy armor on hit, updates melee tolerance gauge (melee only, 1/cast),
## fires immediate counter at 2/2, and triggers Boss Phase-2 enrage at <=50% HP.
static func on_enemy_hit(battle, source, target, action_id: String) -> void:
	if target == null or target.team != "enemy" or not target.is_alive():
		return
	if source == null or source.team != "player" or not source.is_alive():
		return
	if action_id in ["tolerance_counter", "absolute_guard_counter", "oathkeeper_judgment_mark", "hazard_tick", "push_collision"]:
		return

	# 1. Armor chipping on bosses (ultimates / extreme strikes / wall collisions
	#    break 1 layer immediately; ordinary skills chip 1 layer every 2 casts).
	var seq: int = battle.ledger.pressure_sequence
	if target.armor_layers > 0:
		var heavy_break: bool = action_id in ["sakura_endless_fragrance", "sakura_endless_fragrance_finisher", "absolute_guard", "oathkeeper_ultimate", "oathkeeper_heavy_strike", "sakura_extreme_follow_up", "knockback_collision"]
		if heavy_break:
			# A wall/unit collision is a separate physical event after the cast's
			# attack. It must still break armor even if that attack already chipped.
			if action_id == "knockback_collision" or seq <= 0 or target.last_armor_break_seq != seq:
				if action_id != "knockback_collision":
					target.last_armor_break_seq = seq
				shatter_armor(battle, target, 1, "heavy_skill")
		elif seq <= 0 or target.last_armor_chip_seq != seq:
			target.last_armor_chip_seq = seq
			target.armor_chip_hits += 1
			if target.armor_chip_hits >= 2:
				target.armor_chip_hits = 0
				shatter_armor(battle, target, 1, "chip")

	# 2. Boss Phase-2 enrage at <= 50% HP: refill charge, reinforce 1 armor, summon escorts.
	if int(target.tier) >= 2 and target.boss_phase == 1 and target.health * 2 <= target.max_health:
		_trigger_boss_enrage(battle, target)

	# 3. Melee tolerance gauge: strictly melee (Manhattan distance == 1), never ranged!
	if action_id == "knockback_collision" or target.melee_tolerance_max <= 0:
		return
	if GridRulesScript.manhattan_distance(source.cell, target.cell) != 1:
		return
	if seq > 0 and target.last_melee_hit_seq == seq:
		return
	target.last_melee_hit_seq = seq
	target.melee_tolerance += 1
	battle._emit_event("tolerance_updated", target.actor_id, source.actor_id, "stacks=%d/%d" % [target.melee_tolerance, target.melee_tolerance_max])
	if target.melee_tolerance >= target.melee_tolerance_max:
		target.melee_tolerance = 0
		var raw: int = CombatMathScript.calculate_raw_damage(target.attack, TOLERANCE_COUNTER_MULT)
		battle._apply_damage(source.actor_id, raw, target.actor_id, "tolerance_counter", "physical", false, "")
		battle._emit_event("counter_resolved", target.actor_id, source.actor_id, "skill=tolerance_counter raw=%d" % raw)


static func shatter_armor(battle, target, layers: int = 1, reason: String = "break") -> void:
	if target == null or target.armor_layers <= 0 or layers <= 0:
		return
	target.armor_layers = maxi(0, target.armor_layers - layers)
	if target.armor_layers == 0:
		target.armor_broken_until_turn = battle.turn_number + 1
		battle._emit_event("armor_broken", target.actor_id, "", "reason=%s until_turn=%d" % [reason, target.armor_broken_until_turn])
	else:
		battle._emit_event("armor_chipped", target.actor_id, "", "reason=%s left=%d" % [reason, target.armor_layers])


## Called when a player destroys a boss's ward crystal: also shatters 1 armor layer.
static func on_ward_node_destroyed(battle, owner_id: String) -> void:
	if owner_id.is_empty():
		return
	var boss = battle.get_actor(owner_id)
	if boss != null and boss.is_alive():
		shatter_armor(battle, boss, 1, "ward_crystal_broken")


## Kill-refund (+1 AP, max 2/turn) while the battle is still ongoing so killing
## boss escorts or frontline adds fuels chained tactical combos.
static func on_enemy_defeated(battle, target) -> void:
	if battle.phase != battle.BattlePhase.PLAYER or target == null or target.team != "enemy":
		return
	var remaining_enemies := 0
	for actor_id in battle.actors:
		var a = battle.actors[actor_id]
		if a.team == "enemy" and a.is_alive():
			remaining_enemies += 1
	if remaining_enemies <= 0:
		return
	var ledger = battle.ledger
	if ledger.pressure_refund_turn != battle.turn_number:
		ledger.pressure_refund_turn = battle.turn_number
		ledger.pressure_refund_count = 0
	if ledger.pressure_refund_count >= MAX_AP_REFUNDS_PER_TURN:
		return
	if battle.ap.refund(1):
		ledger.pressure_refund_count += 1
		battle._emit_event("ap_refunded", battle.active_character_id, target.actor_id, "reason=kill_refund ap=%d/%d" % [battle.ap.current, battle.ap.maximum])


static func _trigger_boss_enrage(battle, boss) -> void:
	boss.boss_phase = 2
	boss.skill_charge = boss.skill_charge_max
	if boss.armor_max > 0 and boss.armor_layers == 0:
		boss.armor_layers = 1
		boss.armor_broken_until_turn = -1
	var summoned: Array[String] = []
	var escort_specs := [["wind_ranger", 700], ["petal_archer", 600]]
	var occupied: Dictionary = battle.get_occupied_cells()
	var offsets := [
		Vector2i(-2, 1), Vector2i(2, 1), Vector2i(-2, -1), Vector2i(2, -1),
		Vector2i(-1, 2), Vector2i(1, 2), Vector2i(-1, -1), Vector2i(1, -1),
		Vector2i(-2, 0), Vector2i(2, 0),
	]
	var idx := 0
	for spec in escort_specs:
		var arch: String = spec[0]
		var hp_cap: int = int(spec[1])
		var profile = EnemyCatalogScript.get_definition(arch)
		if profile == null:
			continue
		var spawn_cell := Vector2i(-1, -1)
		for off in offsets:
			var c: Vector2i = boss.cell + off
			if GridRulesScript.is_inside_bounds(c, battle.grid_size) and not battle.blocked_cells.has(c) and not occupied.has(c):
				spawn_cell = c
				break
		if spawn_cell == Vector2i(-1, -1):
			continue
		var uid: String = "escort_%s_%d_%d" % [arch, battle.turn_number, idx]
		idx += 1
		var unit = BattleActorScript.new(uid, "enemy", spawn_cell, hp_cap, arch, profile.attack, profile.defense, profile.magic_resistance)
		unit.glyph = profile.glyph
		unit.move_steps = profile.move_steps
		unit.skill_charge_max = 3
		unit.skill_charge = 2
		init_enemy_pressure(unit)
		battle.actors[uid] = unit
		occupied[spawn_cell] = uid
		summoned.append(uid)
	battle._emit_event("boss_enraged", boss.actor_id, "", "phase=2 escorts=%d" % summoned.size())


## Reactive melee pursuit when a tile-locked melee misses its original tile:
## 1) If a living player is STILL adjacent (distance 1), pivot and strike them.
## 2) If this enemy is an Elite/Boss and a living player is within 2 tiles,
##    step 1 tile adjacent and strike instead of swinging at empty air.
static func try_reactive_melee_target(battle, source, intent) -> String:
	if intent.action_id != "basic_melee" or source == null or not source.is_alive():
		return ""
	var best_adj := ""
	var best_two := ""
	var best_two_step := Vector2i(-1, -1)
	var occupied: Dictionary = battle.get_occupied_cells(source.actor_id)
	for actor_id in battle.actors:
		var cand = battle.actors[actor_id]
		if cand.team != "player" or not cand.is_alive():
			continue
		var d: int = GridRulesScript.manhattan_distance(source.cell, cand.cell)
		if d == 1:
			best_adj = String(actor_id)
			break
		if d == 2 and int(source.tier) >= 1 and best_two.is_empty():
			for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var step: Vector2i = source.cell + dir
				if GridRulesScript.manhattan_distance(step, cand.cell) == 1 and GridRulesScript.is_inside_bounds(step, battle.grid_size) and not battle.blocked_cells.has(step) and not occupied.has(step):
					best_two = String(actor_id)
					best_two_step = step
					break
	if not best_adj.is_empty():
		intent.target_cell = battle.actors[best_adj].cell
		return best_adj
	if not best_two.is_empty() and best_two_step != Vector2i(-1, -1):
		source.cell = best_two_step
		intent.target_cell = battle.actors[best_two].cell
		battle._emit_event("actor_moved", source.actor_id, "", "reactive_step dest=%s" % str(best_two_step))
		return best_two
	return ""


## Boss dual-action follow-up intent (from turn 2+, or immediately in Phase 2):
## lets bosses chain movement/defense with an immediate area/melee threat so the
## player must read and counter a two-beat attack sequence.
static func build_boss_combo_intent(battle, boss, primary_intent, target, threatened: Dictionary):
	if boss == null or not boss.is_alive() or int(boss.tier) < 2:
		return null
	if battle.turn_number < 2 and boss.boss_phase < 2:
		return null
	if primary_intent == null or primary_intent.action_id == "wait":
		return null
	var origin: Vector2i = primary_intent.move_path[primary_intent.move_path.size() - 1] if not primary_intent.move_path.is_empty() else boss.cell
	if primary_intent.action_id == "pursuit" and not primary_intent.affected_cells.is_empty():
		origin = primary_intent.affected_cells[primary_intent.affected_cells.size() - 1]
	var dist: int = GridRulesScript.manhattan_distance(origin, target.cell)
	var combo_id: String = "%s_combo" % primary_intent.intent_id
	var prio: int = primary_intent.execution_priority + 1

	# Melee bosses (千枝神将 / 凋樱剑主): follow up with a 3-tile cleave band or melee lock
	if boss.archetype == "boss_thousand_boughs" or boss.archetype == "boss_petalfall":
		if dist >= 1 and dist <= 2:
			var band: Array[Vector2i] = IntentSupportScript.three_cell_band(battle, origin, target.cell, origin)
			var dmg: int = IntentSupportScript.signature_damage(boss, 1.0)
			if boss.archetype == "boss_petalfall":
				return BattleIntentScript.new(combo_id, boss.actor_id, "blight_field", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, band, dmg, prio, "physical", band, "blight", IntentSupportScript.hazard_damage_of(boss, dmg, 0.25), 2)
			return BattleIntentScript.new(combo_id, boss.actor_id, "sakura_shock", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, band, dmg, prio, "physical")
		return null

	# Ranged boss (春痕回响): seal an uncovered escape tile with an arcane cross pulse
	if boss.archetype == "boss_spring_echo" and dist >= 2 and dist <= 5:
		var aim: Vector2i = IntentSupportScript.pick_uncrowded_aim(battle, origin, target.cell, 2, 5, threatened, true)
		if aim != Vector2i(-1, -1):
			var cells: Array[Vector2i] = []
			for off in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var c: Vector2i = aim + off
				if GridRulesScript.is_inside_bounds(c, battle.grid_size):
					cells.append(c)
			return BattleIntentScript.new(combo_id, boss.actor_id, "ground_pulse", BattleIntentScript.TargetMode.AREA_LOCKED, "", aim, cells, CombatMathScript.calculate_raw_damage(boss.attack, 1.0), prio, "magical")
	return null
