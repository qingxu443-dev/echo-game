class_name IntentPlanner
extends RefCounted

## Builds the enemy intents for one player turn.
##
## Pure planning: it reads the battlefield and returns intent snapshots, but it
## never mutates actors or statuses.
##
## Which actions an archetype knows is data (`EnemyDefinition.actions`, in
## priority order). Whether a given action is legal right now is code, because it
## reads the board - distance, line of sight, reachable cells - and a data format
## expressive enough to describe that would be a scripting language. The split
## means a new enemy that reuses existing actions is one .tres, and a genuinely
## new action is one branch here.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")
const HazardFieldScript = preload("res://scripts/battle/hazard_field.gd")

## Damage multipliers per action, kept next to the decision that uses them. These
## describe the action rather than the archetype, so they are not in the .tres.
const CHARGED_STRIKE_MULTIPLIER: float = 1.5
const BASIC_MELEE_MULTIPLIER: float = 0.8
const AIMED_SHOT_MULTIPLIER: float = 1.35
const LIGHT_SHOT_MULTIPLIER: float = 0.75
const GROUND_PULSE_MULTIPLIER: float = 1.15
const ECHO_BOLT_MULTIPLIER: float = 0.7

## Reach and priority per action. Priority only orders the execution list; the
## choice between actions is the order in `actions`.
const CHARGED_STRIKE_RANGE: int = 2
const BASIC_MELEE_RANGE: int = 1
const AIMED_SHOT_MIN_RANGE: int = 3
const AIMED_SHOT_MAX_RANGE: int = 6
const GROUND_PULSE_MIN_RANGE: int = 2
const GROUND_PULSE_MAX_RANGE: int = 4

## Ground-effect signature skills (§15). All three hit "范围 3 个相邻地格"; the
## constants differ only in the reach the boss may stand at, which follows how
## each one fights: 凋樱剑主 closes in, 春痕回响 keeps its distance, 樱庭镇守兽
## guards the door.
const BLIGHT_FIELD_MULTIPLIER: float = 1.0
const BLIGHT_FIELD_RANGE: int = 2
const SPRING_BLOOM_MULTIPLIER: float = 0.75
const SPRING_BLOOM_MIN_RANGE: int = 2
const SPRING_BLOOM_MAX_RANGE: int = 5
const SAKURA_SHOCK_MULTIPLIER: float = 0.75
const SAKURA_SHOCK_RANGE: int = 2
## "持续 2 个完整回合" (§15.1 / §15.3).
const HAZARD_DURATION_TURNS: int = 2
## 凋零 is pinned by the document (0.25 of the skill's damage). 残春 is described
## only as "少量伤害", so this draft lives here and nowhere else - see
## PROJECT_STATUS 的未决清单.
const BLIGHT_HAZARD_MULTIPLIER: float = 0.25
const LINGERING_SPRING_MULTIPLIER: float = 0.2

## 百花锁命 (§14): mark one hero, then fire the strengthened arrow on the next
## enemy phase. The document pins the multiplier at 1.15 of the pre-cut attack,
## so the profile's `skill_damage` carries the final number (1380).
const LOCK_ON_MIN_RANGE: int = 2
const LOCK_ON_MAX_RANGE: int = 6
const LOCKED_SHOT_MULTIPLIER: float = 1.15
## 逐影突袭 (§14): the runner may cover at most three cells and must finish
## adjacent to its mark. 1.05 is the document's multiplier; the profile pins the
## resulting 1260 so cutting base attack cannot cut the skill with it.
const SHADOW_RAID_MAX_RANGE: int = 4
const SHADOW_RAID_STEPS: int = 3
const SHADOW_RAID_MULTIPLIER: float = 1.05
## 腐樱诅咒 (§14): one hero within four cells loses 100 defence until the next
## enemy phase ends. Never stacks - a second curse only refreshes the clock.
const ROT_CURSE_RANGE: int = 4


static func plan(battle) -> Array:
	var actors = battle.actors
	var generated: Array = []
	var occupied: Dictionary = battle.get_occupied_cells()
	var claimed_cells: Dictionary = {}

	for actor_id in actors:
		var enemy = actors[actor_id]
		if not enemy.is_alive() or enemy.team != "enemy":
			continue
		var target = _pick_target_for_enemy(battle, enemy, claimed_cells)
		if target == null:
			continue
		var intent = _choose_intent(battle, enemy, target, occupied, claimed_cells)
		if intent != null:
			generated.append(intent)
			if intent.action_id not in ["wait", "pursuit", "ward_ally"]:
				claimed_cells[intent.target_cell] = true

	generated.sort_custom(func(a, b):
		if a.execution_priority != b.execution_priority:
			return a.execution_priority < b.execution_priority
		var source_a = actors[a.source_actor_id]
		var source_b = actors[b.source_actor_id]
		if source_a.cell.y != source_b.cell.y:
			return source_a.cell.y < source_b.cell.y
		if source_a.cell.x != source_b.cell.x:
			return source_a.cell.x < source_b.cell.x
		return a.source_actor_id < b.source_actor_id
	)
	return generated


## The actions this enemy tries, in order. Falls back loudly rather than silently:
## an archetype with an empty list would stand still every turn, which reads as a
## frozen enemy rather than a data mistake.
static func actions_for(enemy) -> Array[StringName]:
	var actions: Array[StringName] = []
	var definition = EnemyCatalogScript.get_definition(String(enemy.archetype))
	if definition != null:
		actions.append_array(definition.actions)
	if actions.is_empty():
		push_error("IntentPlanner: archetype '%s' declares no actions" % enemy.archetype)
		actions.append(&"basic_melee")
	return actions


## First legal action wins; otherwise the enemy waits. This is the whole of the
## per-archetype behaviour, expressed once instead of three times.
## Picks either the hero or a stationary Relic Beacon so multiple enemies split
## pressure (attacking beacons the player cannot simply walk away from) instead
## of all stacking onto the player's single tile.
static func _pick_target_for_enemy(battle, enemy, claimed_cells: Dictionary):
	var hero = battle.get_defender()
	if hero == null or not hero.is_alive():
		return null
	var beacons: Array[Dictionary] = battle.alive_beacons()
	if beacons.is_empty():
		return hero

	var hero_claimed: bool = claimed_cells.has(hero.cell)
	var best_beacon: Dictionary = {}
	var best_b_dist: int = 999
	for b in beacons:
		# A boss's own 结界 nodes are scenery it protects, not something it
		# attacks. Everything else (the relic chests) stays a valid objective.
		if not bool(b.get("enemy_objective", true)):
			continue
		var bc: Vector2i = b["cell"]
		var d: int = GridRulesScript.manhattan_distance(enemy.cell, bc)
		# Prefer unclaimed beacons first, then nearest beacon
		var penalty: int = 4 if claimed_cells.has(bc) else 0
		if d + penalty < best_b_dist:
			best_b_dist = d + penalty
			best_beacon = b

	var hero_dist: int = GridRulesScript.manhattan_distance(enemy.cell, hero.cell)
	# If another enemy already locked the hero's tile, or a beacon is closer, target the beacon!
	if not best_beacon.is_empty() and (hero_claimed or best_b_dist <= hero_dist):
		return {"cell": best_beacon["cell"], "actor_id": str(best_beacon["id"]), "is_beacon": true}
	return hero


static func _choose_intent(battle, enemy, target, occupied: Dictionary, claimed_cells: Dictionary = {}):
	# 百花锁命 第二段: a mark placed last enemy phase fires now. It is checked
	# before the action list because the shot is not one of the archer's choices -
	# it is the delayed half of a decision already made.
	var locked_intent = _locked_shot(battle, enemy)
	if locked_intent != null:
		return locked_intent

	var actions: Array[StringName] = actions_for(enemy)

	# 1. Try any non-movement attack from the current tile first.
	for action_id in actions:
		if action_id == &"pursuit":
			continue
		var intent = _build_intent(battle, enemy, target, occupied, action_id, claimed_cells)
		if intent != null:
			return intent

	# 2. Into-the-Breach enemy cadence: if out of attack position after turn 1,
	#    reposition first (up to 2 tiles) and IMMEDIATELY telegraph an attack
	#    from the new tile instead of wasting a whole turn just walking.
	#
	#    The move is recorded on the intent (move_path) and applied by
	#    IntentResolver during the enemy phase. Planning must not touch the
	#    board: the old version wrote enemy.cell here and emitted actor_moved,
	#    so calling plan() twice moved the enemy twice and the telegraph could
	#    disagree with what actually happened.
	if actions.has(&"pursuit") and battle.turn_number > 1:
		var move_path: Array[Vector2i] = _compute_move_path(battle, enemy, target)
		if not move_path.is_empty():
			var dest: Vector2i = move_path[move_path.size() - 1]
			var origin: Vector2i = enemy.cell
			# Evaluate the follow-up from the destination, then restore the board
			# exactly as it was. No event, no lasting mutation.
			occupied.erase(origin)
			occupied[dest] = enemy.actor_id
			enemy.cell = dest
			var follow_intent = null
			for action_id in actions:
				# 逐影突袭 already carries its own path; evaluating it again from a
				# simulated destination would stack two moves into one intent.
				if action_id == &"pursuit" or action_id == &"shadow_raid":
					continue
				follow_intent = _build_intent(battle, enemy, target, occupied, action_id, claimed_cells)
				if follow_intent != null:
					break
			enemy.cell = origin
			occupied.erase(dest)
			occupied[origin] = enemy.actor_id
			if follow_intent != null:
				follow_intent.move_path = move_path
				return follow_intent
			# Cannot attack even after stepping: walk instead of the old
			# teleport-then-wait, so the movement is a real intent the resolver
			# animates in the enemy phase.
			return _pursuit(battle, enemy, target)

	# 3. Still too far after moving (or turn 1 setup): fall back to pursuit / wait.
	if actions.has(&"pursuit") and battle.turn_number == 1:
		var p_intent = _pursuit(battle, enemy, target)
		if p_intent != null:
			return p_intent
	return _wait_intent(battle, enemy)


static func _compute_move_path(battle, enemy, target) -> Array[Vector2i]:
	var steps: int = _move_steps_of(enemy)
	if enemy.archetype == "marksman":
		return _ranged_reposition_path(battle, enemy, target, AIMED_SHOT_MIN_RANGE, AIMED_SHOT_MAX_RANGE, true, steps)
	if enemy.archetype == "area_controller":
		return _ranged_reposition_path(battle, enemy, target, GROUND_PULSE_MIN_RANGE, GROUND_PULSE_MAX_RANGE, false, steps)
	return _pursuit_path(battle, enemy.cell, target.cell, enemy.actor_id, steps)


## Reposition budget for this actor. Two is the prototype baseline; a profile
## overrides it to express weight (heavy guard 1, wind runner 3). Read through a
## guard because the planner is also driven by test doubles that only model the
## handful of fields a scenario needs.
static func _move_steps_of(enemy) -> int:
	var steps: int = 2
	if enemy != null and "move_steps" in enemy:
		steps = int(enemy.move_steps)
	return clampi(steps, 1, 4)


## Returns null when the action is not legal on this board. Each branch checks
## only its own preconditions, so adding an action cannot change another one.
static func _build_intent(battle, enemy, target, occupied: Dictionary, action_id: StringName, claimed_cells: Dictionary = {}):
	match action_id:
		&"charged_strike":
			return _charged_strike(battle, enemy, target, occupied)
		&"basic_melee":
			return _basic_melee(battle, enemy, target)
		&"pursuit":
			return _pursuit(battle, enemy, target)
		&"aimed_shot":
			return _aimed_shot(battle, enemy, target, occupied)
		&"light_shot":
			return _light_shot(battle, enemy, target, occupied)
		&"ground_pulse":
			return _ground_pulse(battle, enemy, target, claimed_cells)
		&"echo_bolt":
			return _echo_bolt(battle, enemy, target, claimed_cells)
		&"ward_ally":
			return _ward_ally(battle, enemy, target)
		&"ward_stance":
			return _ward_stance(battle, enemy)
		&"blight_field":
			return _blight_field(battle, enemy, target)
		&"spring_bloom":
			return _spring_bloom(battle, enemy, target)
		&"sakura_shock":
			return _sakura_shock(battle, enemy, target)
		&"lock_on":
			return _lock_on(battle, enemy, target)
		&"locked_shot":
			return _locked_shot(battle, enemy)
		&"shadow_raid":
			return _shadow_raid(battle, enemy, target)
		&"rot_curse":
			return _rot_curse(battle, enemy, target)
	push_error("IntentPlanner: unknown action '%s' for archetype '%s'" % [action_id, enemy.archetype])
	return null


static func _charged_strike(battle, enemy, target, occupied: Dictionary):
	# Signature skill: only fires when the enemy's AP-driven charge bar is full.
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < 1 or distance > CHARGED_STRIKE_RANGE:
		return null
	if not GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, occupied):
		return null
	# 3x2 (6-tile) sweeping cleave directly in front of the Vanguard
	var forward := Vector2i(signi(target.cell.x - enemy.cell.x), signi(target.cell.y - enemy.cell.y))
	var perp := Vector2i(-forward.y, forward.x)
	var affected: Array[Vector2i] = []
	for depth in [1, 2]:
		var row_center: Vector2i = enemy.cell + forward * depth
		for side in [-1, 0, 1]:
			var cell: Vector2i = row_center + perp * side
			if GridRulesScript.is_inside_bounds(cell, battle.grid_size) and not battle.blocked_cells.has(cell):
				affected.append(cell)
	var intent = BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "charged_strike", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, _signature_damage(enemy, CHARGED_STRIKE_MULTIPLIER), 0)
	# §14 樱华蓄斩: the one charged strike the player can break. The flag rides on
	# the intent so the interrupt itself can stay a single generic rule.
	intent.interruptible = "interruptible_skill" in enemy and bool(enemy.interruptible_skill)
	return intent


## Plain-attack damage. §15 gives each boss its own attendance multiplier -
## 樱刃 0.80 / 重盾击 0.70 / 花影弹 0.65 - so a profile may override the action
## default. Everything without the field keeps the generic number.
static func _plain_attack_damage(enemy, default_multiplier: float) -> int:
	var multiplier: float = default_multiplier
	if "basic_attack_multiplier" in enemy and float(enemy.basic_attack_multiplier) > 0.0:
		multiplier = float(enemy.basic_attack_multiplier)
	return CombatMathScript.calculate_raw_damage(enemy.attack, multiplier)


static func _basic_melee(battle, enemy, target):
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance != BASIC_MELEE_RANGE:
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "basic_melee", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], _plain_attack_damage(enemy, BASIC_MELEE_MULTIPLIER), 1)


## 古木壁垒 (§14): shield one *ordinary* ally within two cells. Carried on the
## intent's `damage` field because that is the only integer payload the intent
## has; the resolver reads it as a shield amount, never as damage.
##
## The charge bar doubles as the cooldown: spending it here means the ward cannot
## fire again until the player has burned three more AP, which is the document's
## "冷却 3 个敌方行动阶段" expressed with the mechanism the battle layer already
## has. Ties inside two cells go to the ally with the lowest health ratio.
static func _ward_ally(battle, enemy, target):
	var amount: int = _ward_shield_of(enemy)
	if amount <= 0:
		return null
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var best = null
	# Starts above any real ratio so a full-health ally still becomes a candidate.
	var best_health_ratio: float = 2.0
	for actor_id in battle.actors:
		var ally = battle.actors[actor_id]
		if ally == enemy or ally.team != "enemy" or not ally.is_alive():
			continue
		if _tier_of(ally) != 0:
			continue
		if ally.shield > 0:
			continue
		if GridRulesScript.manhattan_distance(enemy.cell, ally.cell) > 2:
			continue
		var ratio: float = float(ally.health) / float(maxi(1, ally.max_health))
		if ratio < best_health_ratio:
			best_health_ratio = ratio
			best = ally
	if best == null:
		return null
	return BattleIntentScript.new(
		_intent_id(battle, enemy), enemy.actor_id, "ward_ally",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, best.actor_id, best.cell, [], amount, 1
	)


## 结界守护 (§15.2): a temporary shield worth 6% of max health plus 2% per
## standing node. Shield strength is computed here (the planner owns the numbers)
## and carried on the intent's damage field; the resolver only applies it.
static func _ward_stance(battle, enemy):
	var percent: float = _stance_percent_of(enemy)
	if percent <= 0.0:
		return null
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var nodes: int = 0
	for beacon in battle.alive_beacons():
		if str(beacon.get("owner_id", "")) == String(enemy.actor_id):
			nodes += 1
	var bonus: float = _stance_node_bonus_of(enemy)
	var amount: int = roundi(float(enemy.max_health) * (percent + bonus * float(nodes)))
	if amount <= 0:
		return null
	return BattleIntentScript.new(
		_intent_id(battle, enemy), enemy.actor_id, "ward_stance",
		BattleIntentScript.TargetMode.NONE, "", enemy.cell, [], amount, 1
	)


static func _stance_percent_of(enemy) -> float:
	if enemy == null or not ("ward_stance_percent" in enemy):
		return 0.0
	return maxf(0.0, float(enemy.ward_stance_percent))


static func _stance_node_bonus_of(enemy) -> float:
	if enemy == null or not ("ward_stance_node_bonus" in enemy):
		return 0.0
	return maxf(0.0, float(enemy.ward_stance_node_bonus))


static func _ward_shield_of(enemy) -> int:
	if enemy == null or not ("ward_shield" in enemy):
		return 0
	return maxi(0, int(enemy.ward_shield))


static func _tier_of(actor) -> int:
	if actor == null or not ("tier" in actor):
		return 0
	return int(actor.tier)


## Signature-skill damage. §14 requires it to be independent of the base attack
## (the sheets already carry a 30% cut), so a profile that pins `skill_damage`
## wins over the per-action multiplier.
static func _signature_damage(enemy, multiplier: float) -> int:
	if "skill_damage" in enemy and int(enemy.skill_damage) > 0:
		return int(enemy.skill_damage)
	return CombatMathScript.calculate_raw_damage(enemy.attack, multiplier)


static func _pursuit(battle, enemy, target):
	var pursuit_path: Array[Vector2i] = _compute_move_path(battle, enemy, target)
	if pursuit_path.is_empty():
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "pursuit", BattleIntentScript.TargetMode.NONE, "", pursuit_path[pursuit_path.size() - 1], pursuit_path, 0, 2)


static func _aimed_shot(battle, enemy, target, occupied: Dictionary):
	# Signature skill: full AP-driven charge fires a piercing 3-tile line shot (orthogonal or diagonal)
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var dx: int = target.cell.x - enemy.cell.x
	var dy: int = target.cell.y - enemy.cell.y
	var chebyshev: int = maxi(absi(dx), absi(dy))
	if chebyshev < 2 or chebyshev > AIMED_SHOT_MAX_RANGE:
		return null
	var aligned: bool = (dx == 0 or dy == 0 or absi(dx) == absi(dy))
	if not aligned:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	var step := Vector2i(signi(dx), signi(dy))
	var affected: Array[Vector2i] = []
	for offset in [-1, 0, 1]:
		var c: Vector2i = target.cell + step * offset
		if GridRulesScript.is_inside_bounds(c, battle.grid_size) and not battle.blocked_cells.has(c) and c != enemy.cell:
			affected.append(c)
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "aimed_shot", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, _signature_damage(enemy, AIMED_SHOT_MULTIPLIER), 2)


static func _light_shot(battle, enemy, target, occupied: Dictionary):
	var dx: int = target.cell.x - enemy.cell.x
	var dy: int = target.cell.y - enemy.cell.y
	var chebyshev: int = maxi(absi(dx), absi(dy))
	if chebyshev < 2 or chebyshev > AIMED_SHOT_MAX_RANGE:
		return null
	var aligned: bool = (dx == 0 or dy == 0 or absi(dx) == absi(dy))
	if not aligned:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "light_shot", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], _plain_attack_damage(enemy, LIGHT_SHOT_MULTIPLIER), 2)


static func _ground_pulse(battle, enemy, target, claimed_cells: Dictionary = {}):
	# Signature skill: full AP-driven charge fires the 5-tile cross pulse
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var aim_cell: Vector2i = _pick_uncrowded_aim(battle, enemy.cell, target.cell, GROUND_PULSE_MIN_RANGE, GROUND_PULSE_MAX_RANGE, claimed_cells)
	if aim_cell == Vector2i(-1, -1):
		return null
	var affected: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for offset in offsets:
		var cell: Vector2i = aim_cell + offset
		if GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			affected.append(cell)
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "ground_pulse", BattleIntentScript.TargetMode.AREA_LOCKED, "", aim_cell, affected, CombatMathScript.calculate_raw_damage(enemy.attack, GROUND_PULSE_MULTIPLIER), 1, "magical")


static func _echo_bolt(battle, enemy, target, claimed_cells: Dictionary = {}):
	var aim_cell: Vector2i = _pick_uncrowded_aim(battle, enemy.cell, target.cell, GROUND_PULSE_MIN_RANGE, GROUND_PULSE_MAX_RANGE, claimed_cells)
	if aim_cell == Vector2i(-1, -1):
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "echo_bolt", BattleIntentScript.TargetMode.TILE_LOCKED, "", aim_cell, [aim_cell], _plain_attack_damage(enemy, ECHO_BOLT_MULTIPLIER), 1, "magical")


## If target_cell is already locked by another enemy, try locking an adjacent
## escape tile around the target so enemies create a real crossfire net.
static func _pick_uncrowded_aim(battle, source_cell: Vector2i, target_cell: Vector2i, min_r: int, max_r: int, claimed_cells: Dictionary) -> Vector2i:
	var base_dist: int = GridRulesScript.manhattan_distance(source_cell, target_cell)
	if not claimed_cells.has(target_cell) and base_dist >= min_r and base_dist <= max_r:
		return target_cell
	for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var adj: Vector2i = target_cell + offset
		if not GridRulesScript.is_inside_bounds(adj, battle.grid_size) or battle.blocked_cells.has(adj):
			continue
		if claimed_cells.has(adj):
			continue
		var d: int = GridRulesScript.manhattan_distance(source_cell, adj)
		if d >= min_r and d <= max_r:
			return adj
	if base_dist >= min_r and base_dist <= max_r:
		return target_cell
	return Vector2i(-1, -1)


## §15.1 樱落领域: a three-tile sweep that leaves 凋零 on every cell it cuts.
## Reach is two cells - 凋樱剑主 is the mobile melee boss, so the field is what it
## does while closing, and the plain 樱刃 is what it does once adjacent.
static func _blight_field(battle, enemy, target):
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < 1 or distance > BLIGHT_FIELD_RANGE:
		return null
	if not GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells(enemy.actor_id)):
		return null
	var affected: Array[Vector2i] = _three_cell_band(battle, enemy.cell, target.cell, enemy.cell)
	if affected.is_empty():
		return null
	var damage: int = _signature_damage(enemy, BLIGHT_FIELD_MULTIPLIER)
	var blight: int = _hazard_damage_of(enemy, damage, BLIGHT_HAZARD_MULTIPLIER)
	return BattleIntentScript.new(
		_intent_id(battle, enemy), enemy.actor_id, "blight_field",
		BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, damage, 0, "physical",
		affected, HazardFieldScript.KIND_BLIGHT, blight, HAZARD_DURATION_TURNS
	)


## §15.3 春痕绽放: arcane burst that also seeds 残春 on the tiles it covers. The
## document says the field is "2～3 个相邻格" while the blast is three, so reusing
## the blast's cells lands inside that range and keeps the telegraph honest: the
## tiles that hurt are exactly the tiles that will keep hurting.
static func _spring_bloom(battle, enemy, target):
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < SPRING_BLOOM_MIN_RANGE or distance > SPRING_BLOOM_MAX_RANGE:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	var affected: Array[Vector2i] = _three_cell_band(battle, enemy.cell, target.cell, enemy.cell)
	if affected.is_empty():
		return null
	var damage: int = _signature_damage(enemy, SPRING_BLOOM_MULTIPLIER)
	var lingering: int = _hazard_damage_of(enemy, damage, LINGERING_SPRING_MULTIPLIER)
	return BattleIntentScript.new(
		_intent_id(battle, enemy), enemy.actor_id, "spring_bloom",
		BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, damage, 1, "magical",
		affected, HazardFieldScript.KIND_LINGERING_SPRING, lingering, HAZARD_DURATION_TURNS
	)


## §14 樱庭震荡: three orthogonal tiles, nothing else. It was borrowing the
## six-tile cleave, which made an area the document pins at three silently larger
## and let the beast hit tiles the telegraph never promised.
static func _sakura_shock(battle, enemy, target):
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < 1 or distance > SAKURA_SHOCK_RANGE:
		return null
	if not GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells(enemy.actor_id)):
		return null
	var affected: Array[Vector2i] = _three_cell_band(battle, enemy.cell, target.cell, enemy.cell)
	if affected.is_empty():
		return null
	return BattleIntentScript.new(
		_intent_id(battle, enemy), enemy.actor_id, "sakura_shock",
		BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, _signature_damage(enemy, SAKURA_SHOCK_MULTIPLIER), 0
	)


## 百花锁命 第一段 (§14): mark one hero. The mark is placed by the resolver, so
## planning stays read-only, and the shot itself is planned on the next turn -
## that gap is the whole skill: the player sees the mark and gets one turn to
## leave the archer's reach or break its line of sight.
static func _lock_on(battle, enemy, target):
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	if "lock_target_id" in enemy and not String(enemy.lock_target_id).is_empty():
		return null
	# Only a hero can be marked; a relic beacon is not "一名玩家".
	if target is Dictionary:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < LOCK_ON_MIN_RANGE or distance > LOCK_ON_MAX_RANGE:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	return BattleIntentScript.new(
		_intent_id(battle, enemy), enemy.actor_id, "lock_on",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, target.actor_id, target.cell, [], 0, 0
	)


## 百花锁命 第二段: the delayed arrow. It tracks the marked hero rather than the
## tile they stood on, so stepping aside does not dodge it - only leaving the
## six-cell reach or breaking line of sight does. Range and sight are checked
## again at resolve time, because the hero may move after this telegraph.
static func _locked_shot(battle, enemy):
	if not ("lock_target_id" in enemy):
		return null
	var target_id: String = String(enemy.lock_target_id)
	if target_id.is_empty():
		return null
	var target = battle.actors.get(target_id)
	if target == null or not target.is_alive() or target.team != "player":
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < 1 or distance > LOCK_ON_MAX_RANGE:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	return BattleIntentScript.new(
		_intent_id(battle, enemy), enemy.actor_id, "locked_shot",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, target.actor_id, target.cell, [target.cell],
		_signature_damage(enemy, LOCKED_SHOT_MULTIPLIER), 0
	)


## 逐影突袭 (§14): up to three cells of path, then a strike on the mark. The path
## travels on the intent (the resolver walks it, the telegraph draws it) so the
## player is warned about both the destination and the blow, and the skill can be
## dodged by vacating the landing tile rather than by outrunning it.
static func _shadow_raid(battle, enemy, target):
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	if target is Dictionary:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < 2 or distance > SHADOW_RAID_MAX_RANGE:
		return null
	var path: Array[Vector2i] = _pursuit_path(battle, enemy.cell, target.cell, enemy.actor_id, SHADOW_RAID_STEPS)
	if path.is_empty():
		return null
	if GridRulesScript.manhattan_distance(path[path.size() - 1], target.cell) != 1:
		return null
	var intent = BattleIntentScript.new(
		_intent_id(battle, enemy), enemy.actor_id, "shadow_raid",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, target.actor_id, target.cell, [target.cell],
		_signature_damage(enemy, SHADOW_RAID_MULTIPLIER), 0
	)
	intent.move_path = path
	return intent


## 腐樱诅咒 (§14): strip flat defence from one hero within four cells. The
## amount rides on the intent's damage field, exactly like a ward's shield
## amount - the resolver reads it as a penalty, never as damage.
static func _rot_curse(battle, enemy, target):
	if not ("curse_defense_down" in enemy) or int(enemy.curse_defense_down) <= 0:
		return null
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	if target is Dictionary:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < 1 or distance > ROT_CURSE_RANGE:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	return BattleIntentScript.new(
		_intent_id(battle, enemy), enemy.actor_id, "rot_curse",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, target.actor_id, target.cell, [target.cell],
		int(enemy.curse_defense_down), 0, "magical"
	)


## "范围 3 个相邻地格" (§14/§15.1/§15.3). The band crosses the line of approach
## so the aim cell's occupant can still step out of it, and near an edge it
## slides inward instead of clipping to two tiles - the document's number is
## three, so returning two would quietly shrink the skill.
static func _three_cell_band(battle, origin: Vector2i, aim: Vector2i, avoid_cell: Vector2i = Vector2i(-999, -999)) -> Array[Vector2i]:
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
static func _hazard_damage_of(_enemy, skill_damage: int, multiplier: float) -> int:
	return maxi(1, roundi(float(skill_damage) * multiplier))


static func _wait_intent(battle, enemy):
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "wait", BattleIntentScript.TargetMode.NONE, "", enemy.cell, [], 0, 3)


static func _intent_id(battle, enemy) -> String:
	return "intent_%d_%s" % [battle.turn_number, enemy.actor_id]


## Breadth-first walk that stops on the first cell adjacent to the goal, then
## returns the first max_steps of the path. Deterministic direction order.
static func _pursuit_path(battle, start: Vector2i, goal: Vector2i, actor_id: String, max_steps: int) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var came_from := {start: start}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var occupied: Dictionary = battle.get_occupied_cells(actor_id)
	var found_cell := start
	var found := false
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if GridRulesScript.manhattan_distance(current, goal) == 1:
			found_cell = current
			found = true
			break
		for direction in directions:
			var next: Vector2i = current + direction
			if not GridRulesScript.is_inside_bounds(next, battle.grid_size):
				continue
			if battle.blocked_cells.has(next) or occupied.has(next) or came_from.has(next):
				continue
			came_from[next] = current
			queue.append(next)
	if not found or found_cell == start:
		return []
	var reversed_path: Array[Vector2i] = []
	var cursor: Vector2i = found_cell
	while cursor != start:
		reversed_path.push_front(cursor)
		cursor = came_from[cursor]
	var result: Array[Vector2i] = []
	for index in range(mini(max_steps, reversed_path.size())):
		result.append(reversed_path[index])
	return result


## Smart ranged/caster kiting & line-of-fire positioning:
## Picks a reachable cell within max_steps that establishes a valid firing lane
## (or retreats out of dead-zone range) instead of walking into melee range.
static func _ranged_reposition_path(
	battle,
	enemy,
	target,
	min_range: int,
	max_range: int,
	require_line: bool,
	max_steps: int
) -> Array[Vector2i]:
	var occupied: Dictionary = battle.get_occupied_cells(enemy.actor_id)
	var all_occupied: Dictionary = battle.get_occupied_cells()
	var ideal_dist: int = clampi(min_range + 1, min_range, max_range)

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
			if battle.blocked_cells.has(cand) or occupied.has(cand):
				continue
			var path := GridRulesScript.find_path(enemy.cell, cand, battle.grid_size, battle.blocked_cells, occupied, max_steps)
			if path.is_empty():
				continue

			var dist: int = maxi(absi(cand.x - target.cell.x), absi(cand.y - target.cell.y)) if require_line else GridRulesScript.manhattan_distance(cand, target.cell)
			var eff_min: int = 2 if require_line else min_range
			var aligned: bool = (cand.x == target.cell.x or cand.y == target.cell.y or absi(cand.x - target.cell.x) == absi(cand.y - target.cell.y))
			var in_range: bool = dist >= eff_min and dist <= max_range
			var clear_line: bool = false
			if require_line and aligned and in_range:
				var sim_occ := all_occupied.duplicate()
				sim_occ.erase(enemy.cell)
				sim_occ[cand] = enemy.actor_id
				clear_line = GridRulesScript.has_clear_line_of_sight(cand, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id))

			var score: int = 0
			if require_line:
				if clear_line:
					score += 1000
				elif aligned:
					score += 120
			else:
				if in_range:
					score += 800

			if in_range:
				score += 250
			elif dist < min_range:
				# Retreat away from melee dead-zone
				score -= (min_range - dist) * 300
			else:
				# Close distance gently toward firing band
				score -= (dist - max_range) * 80

			score -= absi(dist - ideal_dist) * 15
			# Slight preference for moving closer to an aligned row/column for marksmen
			if require_line and not aligned:
				var axis_gap: int = mini(absi(cand.x - target.cell.x), absi(cand.y - target.cell.y))
				score -= axis_gap * 40

			if score > best_score:
				best_score = score
				best_path = path

	return best_path
