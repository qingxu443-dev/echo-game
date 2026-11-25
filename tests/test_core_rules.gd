extends "res://tests/framework/test_case.gd"

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const APBudgetScript = preload("res://scripts/battle/ap_budget.gd")
const BattleActorScript = preload("res://scripts/actors/battle_actor.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")


func _run() -> void:
	var blocked := {}
	var occupied := {}

	var one_step: Array[Vector2i] = [Vector2i(1, 0)]
	_check(GridRulesScript.is_path_legal(Vector2i.ZERO, one_step, Vector2i(8, 8), blocked, occupied), "one orthogonal step is legal")

	var two_steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	_check(GridRulesScript.is_path_legal(Vector2i.ZERO, two_steps, Vector2i(8, 8), blocked, occupied), "two orthogonal steps are legal")

	var diagonal: Array[Vector2i] = [Vector2i(1, 1)]
	_check(not GridRulesScript.is_path_legal(Vector2i.ZERO, diagonal, Vector2i(8, 8), blocked, occupied), "diagonal step is rejected")

	var too_long: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	_check(not GridRulesScript.is_path_legal(Vector2i.ZERO, too_long, Vector2i(8, 8), blocked, occupied), "path longer than two cells is rejected")

	blocked[Vector2i(1, 0)] = true
	_check(not GridRulesScript.is_path_legal(Vector2i.ZERO, one_step, Vector2i(8, 8), blocked, occupied), "blocked cell is rejected")
	blocked.clear()

	occupied[Vector2i(1, 0)] = true
	_check(not GridRulesScript.is_path_legal(Vector2i.ZERO, one_step, Vector2i(8, 8), blocked, occupied), "occupied cell is rejected")
	occupied.clear()

	var ap = APBudgetScript.new(3)
	_check(ap.current == 3, "AP starts at maximum")
	_check(ap.spend(2) and ap.current == 1, "AP spend succeeds once")
	_check(not ap.spend(2) and ap.current == 1, "insufficient AP does not mutate budget")
	ap.clear()
	_check(ap.current == 0, "ending turn clears unused AP")
	ap.reset()
	_check(ap.current == 3, "new turn resets AP")

	var actor = BattleActorScript.new("test_enemy", "enemy", Vector2i(3, 3), 3)
	_check(actor.apply_damage(2) == 2 and actor.health == 1 and actor.is_alive(), "damage reduces health deterministically")
	_check(actor.apply_damage(5) == 1 and actor.health == 0 and actor.is_defeated(), "lethal damage clamps health to zero and defeats actor")
	_check(actor.apply_damage(1) == 0, "defeated actor cannot take additional damage")

	_check(CombatMathScript.calculate_raw_damage(2000, 1.5) == 3000, "skill multiplier scales attack power")
	_check(CombatMathScript.calculate_damage(3000, 500) == 2000, "resistance reduces raw damage with diminishing returns")
	var armored_actor = BattleActorScript.new("armored", "enemy", Vector2i(2, 2), 5000, "vanguard", 1200, 1000, 500)
	_check(armored_actor.apply_damage(2000, "physical") == 1000, "physical damage uses defense")
	_check(armored_actor.apply_damage(2000, "magical") == 1333, "magical damage uses magic resistance instead of defense")

	_report()
