extends "res://tests/framework/test_case.gd"

func _run() -> void:
	for legacy in [false, true]:
		for kind in ["free", "wall", "edge", "unit", "downed", "chest", "ward", "fatal"]:
			_test_push(legacy, kind)
		_test_interrupt(legacy)
	await process_frame

func _battle() -> BattleController:
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3)])
	battle.beacons.clear()
	return battle

func _push(legacy: bool, battle, target, direction: Vector2i) -> void:
	if legacy:
		SkillExecutor._knockback_one(battle, battle.get_active_character(), target, direction, 450)
	else:
		SkillEffects._apply_knockback(battle, battle.get_active_character(), target, direction, 450)

func _test_push(legacy: bool, kind: String) -> void:
	var battle := _battle()
	var target = battle.get_actor("vanguard_00")
	var before: int = target.health
	var origin: Vector2i = target.cell
	var destination := origin + Vector2i.RIGHT
	var other = null
	match kind:
		"wall", "fatal": battle.blocked_cells[destination] = true
		"edge":
			target.cell = Vector2i(7, 3)
			origin = target.cell
		"unit", "downed":
			other = BattleActor.new("other", "player" if kind == "downed" else "enemy", destination, 2000)
			if kind == "downed": other.apply_damage(2000, "true")
			battle.actors["other"] = other
		"chest", "ward":
			battle.beacons[destination] = {"id": "box", "kind": "ward_node" if kind == "ward" else "chest", "health": 700 if kind == "ward" else 2}
	if kind == "fatal": target.health = 1
	var intent := BattleIntent.new("push", target.actor_id, "basic_melee", BattleIntent.TargetMode.TILE_LOCKED, "", Vector2i(3, 3))
	battle.intents = [intent]
	_push(legacy, battle, target, Vector2i.RIGHT)
	if kind == "free":
		_check(target.cell == destination and target.health == before, "free push moves without damage, legacy=%s" % legacy)
		_check(intent.target_cell == Vector2i(4, 3), "free push shifts telegraph with the enemy")
	else:
		_check(target.cell == origin, "collision never overlaps its blocker: " + kind)
		if kind == "fatal":
			_check(target.is_defeated() and battle.enemies_defeated == 1, "fatal collision credits one defeat")
		else:
			_check(target.health == before - 450, "collision applies the shared true damage: " + kind)
		_check(intent.target_cell == Vector2i(3, 3), "blocked displacement never shifts the telegraph")
	if kind == "unit": _check(other.health == 1550, "unit collision also damages the blocking enemy")
	if kind == "downed": _check(other.health == 0 and other.is_downed(), "downed ally blocks without repeating death damage")
	if kind == "chest": _check(battle.beacons[destination].health == 1, "chest collision consumes one chest health")
	if kind == "ward": _check(battle.beacons[destination].health == 250, "ward collision consumes numeric ward health")
	battle.queue_free()

func _test_interrupt(legacy: bool) -> void:
	var battle := _battle()
	var target = battle.get_actor("vanguard_00")
	target.skill_charge = 3
	var intent := BattleIntent.new("charge", target.actor_id, "charged_strike", BattleIntent.TargetMode.AREA_LOCKED, "", Vector2i(3, 3), [Vector2i(3, 3)])
	intent.interruptible = true
	battle.intents = [intent]
	_push(legacy, battle, target, Vector2i.RIGHT)
	_check(intent.state == BattleIntent.IntentState.CANCELED and target.skill_charge == 0, "both displacement paths interrupt a declared interruptible windup")
	_check(target.cell == Vector2i(5, 3), "interrupt still completes legal forced movement")
	battle.queue_free()
