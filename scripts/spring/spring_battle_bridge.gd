class_name SpringBattleBridge
extends RefCounted

## Carries one fight between the map scene and the battle scene.
##
## The two scenes never share an object: the map writes `pending`, the battle
## reads it in `_ready`, and the battle writes `last_result` on the way back. Both
## are static fields on purpose - they survive a scene change without an autoload,
## and headless tests can drive the whole handshake without starting a scene.
##
## What crosses in `pending`: which fight, which place it belongs to, and the
## hero's vitals plus the battle-side carry (gear / backpack / mods). What crosses
## back in `last_result`: the outcome and the health the hero is left with.
##
## Settlement itself lives here rather than in the map view, because "what a win
## is worth" is a rule (§16.1, §14, §15.4), not a drawing concern, and the tests
## need to drive it directly.

const BATTLE_SCENE_PATH: String = "res://scenes/main/main.tscn"
const MAP_SCENE_PATH: String = "res://scenes/spring/spring_map.tscn"
const RegionProgressionScript = preload("res://scripts/spring/spring_region_progression.gd")

## §16.1: a chest that survives the fight pays 10 花钿.
const CHEST_COINS: int = 10
## §11.3: continuing after a loss costs 3 supplies and restores 30% max health.
const CONTINUE_SUPPLY_COST: int = 3
const CONTINUE_HEALTH_FRACTION: float = 0.30

const KIND_BATTLE: String = "battle"
const KIND_ELITE: String = "elite"
const KIND_BOSS: String = "boss"

## Set by the map before it changes scene; read by the battle in _ready.
static var pending: Dictionary = {}
## Set by the battle before it changes back; consumed by the map in _ready.
static var last_result: Dictionary = {}
## Optional mode handoff from the Lobby ("normal" / "hard" / "" for resume).
static var requested_mode: String = ""


static func consume_requested_mode() -> String:
	var mode: String = requested_mode
	requested_mode = ""
	return mode


static func has_pending() -> bool:
	return not pending.is_empty()


static func clear_pending() -> void:
	pending = {}


static func has_result() -> bool:
	return not last_result.is_empty()


static func consume_result() -> Dictionary:
	var result: Dictionary = last_result
	last_result = {}
	return result


## Packs a fight for the battle scene. Returns false when the encounter id has no
## roster, so the map can say so instead of opening an empty board.
static func prepare(run, encounter_id: StringName, place_id: StringName, kind: String = KIND_BATTLE) -> bool:
	if not SpringEncounterCatalog.has_encounter(encounter_id):
		return false
	pending = {
		"encounter": encounter_id,
		"place": place_id,
		"kind": kind,
		"hero_health": run.hero_health,
		"hero_max_health": run.effective_max_health(),
		"bonus_max_health": run.bonus_max_health,
		"carry": run.battle_carry.duplicate(true),
		# Relic bonuses are read here, not in the battle: the battle layer has no
		# idea that relics exist.
		"relic_max_health": SpringRelicCatalog.total_bonus(run.relics, "max_health"),
		"relic_attack": SpringRelicCatalog.total_bonus(run.relics, "attack"),
		"relic_defense": SpringRelicCatalog.total_bonus(run.relics, "defense"),
	}
	return true


## Fills a fresh RunState from `pending`. Kept separate from the battle view so a
## test can assert the mapping without touching a scene.
static func apply_payload(run_state, payload: Dictionary) -> void:
	run_state.reset(
		SpringRun.HERO_BASE_MAX_HEALTH + int(payload.get("relic_max_health", 0)),
		SpringRun.HERO_BASE_ATTACK + int(payload.get("relic_attack", 0)),
		SpringRun.HERO_BASE_DEFENSE + int(payload.get("relic_defense", 0)),
		SpringRun.HERO_BASE_MAGIC_RESISTANCE
	)
	run_state.bonus_max_health = int(payload.get("bonus_max_health", 0))
	run_state.hero_max_health = run_state.effective_max_health()
	run_state.hero_health = clampi(int(payload.get("hero_health", run_state.hero_max_health)), 1, run_state.hero_max_health)

	var carry: Dictionary = payload.get("carry", {})
	for mod_id in carry.get("mods", []):
		run_state.mods.append(StringName(mod_id))
	run_state.equipped_weapon = (carry.get("equipped_weapon", {}) as Dictionary).duplicate(true)
	run_state.equipped_armor = (carry.get("equipped_armor", {}) as Dictionary).duplicate(true)
	run_state.backpack.clear()
	for item in carry.get("backpack", []):
		run_state.backpack.append((item as Dictionary).duplicate(true))


## Packs what the battle left behind so it can be written onto the run.
static func pack_carry(run_state) -> Dictionary:
	return {
		"mods": run_state.mods.duplicate(),
		"equipped_weapon": run_state.equipped_weapon.duplicate(true),
		"equipped_armor": run_state.equipped_armor.duplicate(true),
		"backpack": run_state.backpack.duplicate(true),
	}


## Applies `last_result` to the run. Returns a player-facing summary.
##
## Every branch keeps §16.1's promise: the place is finished either way (a lost
## fight is greyed out and cannot be retried), a win keeps the map position and
## the remaining stamina untouched, and only a win pays.
static func settle(run) -> Dictionary:
	var outcome := {"message": "", "battle": &"", "finished_run": false, "reward_choices": [], "needs_revive": false, "region_transition": {}}
	if not has_result():
		return outcome
	var result: Dictionary = consume_result()
	var kind: String = str(result.get("kind", KIND_BATTLE))
	var place_id := StringName(str(result.get("place", "")))
	var won: bool = str(result.get("result", "")) == "victory"

	run.apply_battle_payload({
		"hero_health": int(result.get("hero_health", run.hero_health)),
		"hero_max_health": int(result.get("hero_max_health", run.effective_max_health())),
		"carry": result.get("carry", run.battle_carry),
	})

	if place_id != &"":
		run.exploration.mark_completed(place_id)

	if not won:
		outcome["message"] = "这一处失守了。"
		if run.revive_used:
			outcome["message"] += "本区域的续行已经用过，冒险到此为止。"
			run.exploration.finish("defeat")
			outcome["finished_run"] = true
		else:
			outcome["needs_revive"] = true
			outcome["message"] += "可以用 %d 份补给续行一次。" % CONTINUE_SUPPLY_COST
		return outcome

	run.battles_won += 1
	var chests: int = int(result.get("chests_saved", 0))
	var coins: int = chests * CHEST_COINS
	if coins > 0:
		run.add_coins(coins)

	var loot_names: Array[String] = []
	for item in result.get("loot", []):
		var item_name: String = str((item as Dictionary).get("name", ""))
		if not item_name.is_empty():
			loot_names.append(item_name)

	match kind:
		KIND_ELITE:
			# §14: three candidates, pick one, common or rare only.
			var choices: Array[StringName] = roll_reward_choices(run, "elite", 3, int(result.get("seed", run.seed_value)))
			if choices.is_empty():
				# §6.1: when the pool cannot fill the hand, pay resources instead of
				# offering an empty panel.
				run.add_coins(40)
				run.add_supplies(2)
				outcome["message"] = "击败了精英。藏品已收集齐全，换得 40 花钿与 2 份补给。"
			else:
				outcome["reward_choices"] = choices
		KIND_BOSS:
			# §15.4: one random exclusive reward. Drawn once - calling the roll
			# twice would hand out two different answers to the same question.
			var boss_pool: Array[StringName] = roll_reward_choices(run, "boss", 1, int(result.get("seed", run.seed_value)))
			if not boss_pool.is_empty():
				var boss_reward: StringName = boss_pool[0]
				run.grant_collectible(boss_reward)
				run.apply_collectible_effect(boss_reward)
				outcome["message"] = "击败了首领。获得藏品「%s」。" % run.collectible_name(boss_reward)
			else:
				run.add_coins(60)
				outcome["message"] = "击败了首领。藏品已收集齐全，换得 60 花钿。"
			# A boss victory requests the next region. This build only unlocks 春之境,
			# so 夏之境 is reported as locked and the current exploration closes cleanly.
			var transition: Dictionary = RegionProgressionScript.resolve_next(
				RegionProgressionScript.REGION_SPRING,
				[RegionProgressionScript.REGION_SPRING]
			)
			outcome["region_transition"] = transition
			if bool(transition.get("can_enter", false)):
				outcome["message"] += " 下一层：%s。" % str(transition.get("next_region_name", ""))
			else:
				outcome["message"] += " 下一层：%s尚未解锁，当前探索结束。" % str(transition.get("next_region_name", "后续区域"))
			run.exploration.finish("cleared")
			outcome["finished_run"] = true
		_:
			pass

	var parts: Array[String] = []
	parts.append("战斗胜利")
	if chests > 0:
		parts.append("保住 %d 个宝箱 · +%d 花钿" % [chests, coins])
	if not loot_names.is_empty():
		parts.append("战利品：" + "、".join(loot_names))
	if outcome["message"].is_empty():
		outcome["message"] = "；".join(parts) + "。"
	return outcome


## Draws reward candidates the player does not own yet. Returns [] when every
## candidate is already owned - the caller then falls back to resources rather
## than offering a dead choice (§6.1).
static func roll_reward_choices(run, source: String, count: int, seed_value: int) -> Array[StringName]:
	var result: Array[StringName] = []
	var candidates: Array[String] = []
	for candidate_id in SpringCollectibleCatalog.candidates_for(source):
		if not run.has_collectible(StringName(candidate_id)):
			candidates.append(candidate_id)
	if candidates.is_empty():
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%d" % [seed_value, source, run.battles_won])
	var pool: Array[String] = candidates.duplicate()
	# Partial Fisher-Yates: stable for a given seed, no duplicates in the hand.
	for index in range(mini(count, pool.size())):
		var swap: int = rng.randi_range(index, pool.size() - 1)
		var held: String = pool[index]
		pool[index] = pool[swap]
		pool[swap] = held
		result.append(StringName(pool[index]))
	return result


## §11.3: one continuation per area, paid in supplies, health restored to 30%.
## Atomic: supplies leave only when the heal actually applies.
static func continue_run(run) -> Dictionary:
	var outcome := {"ok": false, "message": ""}
	if run.revive_used:
		outcome["message"] = "本区域的续行已经用过了。"
		return outcome
	if run.supplies < CONTINUE_SUPPLY_COST:
		outcome["message"] = "补给不足：续行需要 %d 份，现有 %d 份。" % [CONTINUE_SUPPLY_COST, run.supplies]
		return outcome
	if not run.spend_supplies(CONTINUE_SUPPLY_COST):
		outcome["message"] = "补给不足。"
		return outcome
	run.hero_health = maxi(1, int(round(float(run.effective_max_health()) * CONTINUE_HEALTH_FRACTION)))
	run.revive_used = true
	outcome["ok"] = true
	outcome["message"] = "消耗 %d 份补给续行，回复至 %d / %d。" % [CONTINUE_SUPPLY_COST, run.hero_health, run.effective_max_health()]
	return outcome
