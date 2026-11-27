class_name EliteSkills
extends RefCounted

## 九条精英与 Boss 专属技的几何判定。
##
## 通用招式（蓄力斩、近战、远程）留在 intent_planner 里；这里只放那些带
## 独特规则的：给友军上盾、留地格、两段式锁命、带路径突袭、降防。加一条新
## 专属技只需要两处：EnemySkillCatalog 加一行数值，本文件加一个函数并登记到
## executors()——规划器不再需要认识它。

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const EnemySkillCatalogScript = preload("res://scripts/battle/enemy_skill_catalog.gd")
const IntentSupportScript = preload("res://scripts/battle/intent_support.gd")


## 古木壁垒 (§14): shield one *ordinary* ally within two cells. Carried on the
## intent's `damage` field because that is the only integer payload the intent
## has; the resolver reads it as a shield amount, never as damage.
##
## The charge bar doubles as the cooldown: spending it here means the ward cannot
## fire again until the player has burned three more AP, which is the document's
## "冷却 3 个敌方行动阶段" expressed with the mechanism the battle layer already
## has. Ties inside two cells go to the ally with the lowest health ratio.
static func ward_ally(battle, enemy, target):
	var spec = EnemySkillCatalogScript.get_skill(&"ward_ally")
	var amount: int = IntentSupportScript.ward_shield_of(enemy)
	if amount <= 0:
		return null
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	var best = null
	# Starts above any real ratio so a full-health ally still becomes a candidate.
	var best_health_ratio: float = 2.0
	for actor_id in battle.actors:
		var ally = battle.actors[actor_id]
		if ally == enemy or ally.team != "enemy" or not ally.is_alive():
			continue
		if IntentSupportScript.tier_of(ally) != 0:
			continue
		if ally.shield > 0:
			continue
		if GridRulesScript.manhattan_distance(enemy.cell, ally.cell) > spec.max_range:
			continue
		var ratio: float = float(ally.health) / float(maxi(1, ally.max_health))
		if ratio < best_health_ratio:
			best_health_ratio = ratio
			best = ally
	if best == null:
		return null
	return BattleIntentScript.new(
		IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "ward_ally",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, best.actor_id, best.cell, [], amount, spec.execution_priority
	)


## 结界守护 (§15.2): a temporary shield worth 6% of max health plus 2% per
## standing node. Shield strength is computed here (the planner owns the numbers)
## and carried on the intent's damage field; the resolver only applies it.
## 结界守护是自身增益，没有目标。签名仍收一个 target，是因为规划器用同一张
## Callable 表调用九条专属技，参数必须一致；多出来的这一个在这里是死参。
static func ward_stance(battle, enemy, target):
	var spec = EnemySkillCatalogScript.get_skill(&"ward_stance")
	var percent: float = IntentSupportScript.stance_percent_of(enemy)
	if percent <= 0.0:
		return null
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	var nodes: int = 0
	for beacon in battle.alive_beacons():
		if str(beacon.get("owner_id", "")) == String(enemy.actor_id):
			nodes += 1
	var bonus: float = IntentSupportScript.stance_node_bonus_of(enemy)
	var amount: int = roundi(float(enemy.max_health) * (percent + bonus * float(nodes)))
	if amount <= 0:
		return null
	var intent = BattleIntentScript.new(
		IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "ward_stance",
		BattleIntentScript.TargetMode.NONE, "", enemy.cell, [], amount, spec.execution_priority
	)
	# High-mobility bosses advance aggressively while raising their ward instead
	# of standing motionless in the backline.
	if target != null and GridRulesScript.manhattan_distance(enemy.cell, target.cell) > 1:
		var steps: int = clampi(int(enemy.move_steps) if "move_steps" in enemy else 1, 1, 4)
		var charge_path: Array[Vector2i] = IntentSupportScript.pursuit_path(battle, enemy.cell, target.cell, enemy.actor_id, steps)
		if not charge_path.is_empty():
			intent.move_path = charge_path
			intent.target_cell = charge_path[charge_path.size() - 1]
	return intent


## §15.1 樱落领域: a three-tile sweep that leaves 凋零 on every cell it cuts.
## Reach is two cells - 凋樱剑主 is the mobile melee boss, so the field is what it
## does while closing, and the plain 樱刃 is what it does once adjacent.
static func blight_field(battle, enemy, target):
	var spec = EnemySkillCatalogScript.get_skill(&"blight_field")
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < spec.min_range or distance > spec.max_range:
		return null
	if not GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells(enemy.actor_id)):
		return null
	var affected: Array[Vector2i] = IntentSupportScript.three_cell_band(battle, enemy.cell, target.cell, enemy.cell)
	if affected.is_empty():
		return null
	var damage: int = IntentSupportScript.signature_damage(enemy, spec.damage_multiplier)
	var blight: int = IntentSupportScript.hazard_damage_of(enemy, damage, spec.hazard_multiplier)
	return BattleIntentScript.new(
		IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "blight_field",
		BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, damage, spec.execution_priority, spec.damage_type,
		affected, spec.hazard_kind, blight, spec.hazard_duration_turns
	)


## §15.3 春痕绽放: arcane burst that also seeds 残春 on the tiles it covers. The
## document says the field is "2～3 个相邻格" while the blast is three, so reusing
## the blast's cells lands inside that range and keeps the telegraph honest: the
## tiles that hurt are exactly the tiles that will keep hurting.
static func spring_bloom(battle, enemy, target):
	var spec = EnemySkillCatalogScript.get_skill(&"spring_bloom")
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < spec.min_range or distance > spec.max_range:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	var affected: Array[Vector2i] = IntentSupportScript.three_cell_band(battle, enemy.cell, target.cell, enemy.cell)
	if affected.is_empty():
		return null
	var damage: int = IntentSupportScript.signature_damage(enemy, spec.damage_multiplier)
	var lingering: int = IntentSupportScript.hazard_damage_of(enemy, damage, spec.hazard_multiplier)
	return BattleIntentScript.new(
		IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "spring_bloom",
		BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, damage, spec.execution_priority, spec.damage_type,
		affected, spec.hazard_kind, lingering, spec.hazard_duration_turns
	)


## §14 樱庭震荡: three orthogonal tiles, nothing else. It was borrowing the
## six-tile cleave, which made an area the document pins at three silently larger
## and let the beast hit tiles the telegraph never promised.
static func sakura_shock(battle, enemy, target):
	var spec = EnemySkillCatalogScript.get_skill(&"sakura_shock")
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < spec.min_range or distance > spec.max_range:
		return null
	if not GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells(enemy.actor_id)):
		return null
	var affected: Array[Vector2i] = IntentSupportScript.three_cell_band(battle, enemy.cell, target.cell, enemy.cell)
	if affected.is_empty():
		return null
	return BattleIntentScript.new(
		IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "sakura_shock",
		BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, IntentSupportScript.signature_damage(enemy, spec.damage_multiplier), spec.execution_priority
	)


## 百花锁命 第一段 (§14): mark one hero. The mark is placed by the resolver, so
## planning stays read-only, and the shot itself is planned on the next turn -
## that gap is the whole skill: the player sees the mark and gets one turn to
## leave the archer's reach or break its line of sight.
static func lock_on(battle, enemy, target):
	var spec = EnemySkillCatalogScript.get_skill(&"lock_on")
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	if "lock_target_id" in enemy and not String(enemy.lock_target_id).is_empty():
		return null
	# Only a hero can be marked; a relic beacon is not "一名玩家".
	if target is Dictionary:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < spec.min_range or distance > spec.max_range:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	return BattleIntentScript.new(
		IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "lock_on",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, target.actor_id, target.cell, [], 0, spec.execution_priority
	)


## 百花锁命 第二段: the delayed arrow. It tracks the marked hero rather than the
## tile they stood on, so stepping aside does not dodge it - only leaving the
## six-cell reach or breaking line of sight does. Range and sight are checked
## again at resolve time, because the hero may move after this telegraph.
static func locked_shot(battle, enemy):
	var spec = EnemySkillCatalogScript.get_skill(&"locked_shot")
	if not ("lock_target_id" in enemy):
		return null
	var target_id: String = String(enemy.lock_target_id)
	if target_id.is_empty():
		return null
	var target = battle.actors.get(target_id)
	if target == null or not target.is_alive() or target.team != "player":
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < spec.min_range or distance > spec.max_range:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	return BattleIntentScript.new(
		IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "locked_shot",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, target.actor_id, target.cell, [target.cell],
		IntentSupportScript.signature_damage(enemy, spec.damage_multiplier), spec.execution_priority
	)


## 逐影突袭 (§14): up to three cells of path, then a strike on the mark. The path
## travels on the intent (the resolver walks it, the telegraph draws it) so the
## player is warned about both the destination and the blow, and the skill can be
## dodged by vacating the landing tile rather than by outrunning it.
static func shadow_raid(battle, enemy, target):
	var spec = EnemySkillCatalogScript.get_skill(&"shadow_raid")
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	if target is Dictionary:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < spec.min_range or distance > spec.max_range:
		return null
	var path: Array[Vector2i] = IntentSupportScript.pursuit_path(battle, enemy.cell, target.cell, enemy.actor_id, spec.move_steps)
	if path.is_empty():
		return null
	if GridRulesScript.manhattan_distance(path[path.size() - 1], target.cell) != 1:
		return null
	var intent = BattleIntentScript.new(
		IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "shadow_raid",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, target.actor_id, target.cell, [target.cell],
		IntentSupportScript.signature_damage(enemy, spec.damage_multiplier), spec.execution_priority
	)
	intent.move_path = path
	return intent


## 腐樱诅咒 (§14): strip flat defence from one hero within four cells. The
## amount rides on the intent's damage field, exactly like a ward's shield
## amount - the resolver reads it as a penalty, never as damage.
static func rot_curse(battle, enemy, target):
	var spec = EnemySkillCatalogScript.get_skill(&"rot_curse")
	if not ("curse_defense_down" in enemy) or int(enemy.curse_defense_down) <= 0:
		return null
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	if target is Dictionary:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < spec.min_range or distance > spec.max_range:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	return BattleIntentScript.new(
		IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "rot_curse",
		BattleIntentScript.TargetMode.ACTOR_LOCKED, target.actor_id, target.cell, [target.cell],
		int(enemy.curse_defense_down), spec.execution_priority, spec.damage_type
	)

## action_id → 构造函数。九条统一为 (battle, enemy, target)，规划器才能用
## 一次 .call 分派，而不用为每条判断参数个数。
## 规划器先查这张表，查不到才走自己的通用分支。
## 用 Callable 而不是 match，是因为 match 每加一条就要改规划器，而这张表
## 随技能一起放在本文件里，改一处就够。
static func executors() -> Dictionary:
	return {
		&"ward_ally": Callable(EliteSkills, "ward_ally"),
		&"ward_stance": Callable(EliteSkills, "ward_stance"),
		&"blight_field": Callable(EliteSkills, "blight_field"),
		&"spring_bloom": Callable(EliteSkills, "spring_bloom"),
		&"sakura_shock": Callable(EliteSkills, "sakura_shock"),
		&"lock_on": Callable(EliteSkills, "lock_on"),
		&"locked_shot": Callable(EliteSkills, "locked_shot"),
		&"shadow_raid": Callable(EliteSkills, "shadow_raid"),
		&"rot_curse": Callable(EliteSkills, "rot_curse"),
	}


## 规划器用这个开关决定「这条是不是专属技」，而不是维护第二份 id 名单。
static func handles(action_id: StringName) -> bool:
	return executors().has(action_id)

