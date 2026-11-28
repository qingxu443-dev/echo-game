class_name SpringBattleBridge
extends RefCounted

const RegionProgressionScript = preload("res://scripts/spring/spring_region_progression.gd")
const SquadLoadoutStoreScript = preload("res://scripts/meta/squad_loadout_store.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")

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
## Captured with a suspended fight, so resuming never depends on a newer map save.
static var suspended_map: Dictionary = {}
static var restore_map: bool = false
## Set by the battle before it changes back; consumed by the map in _ready.
static var last_result: Dictionary = {}
## Optional mode handoff from the Lobby ("normal" / "hard" / "" for resume).
static var requested_mode: String = ""
## Tutorial entry may claim supplies after its first encounter is ready.
static var tutorial_loadout_requested: bool = false
static var last_transition_message: String = ""
## Starting consumables packed at the Atelier hub for the upcoming expedition.
static var starting_loadout: Array[Dictionary] = []


static func consume_tutorial_loadout_request() -> bool:
	var requested := tutorial_loadout_requested
	tutorial_loadout_requested = false
	return requested


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
	if run.party_character_ids.is_empty():
		run.party_character_ids = SquadLoadoutStoreScript.active_character_ids()
	if run.party_character_ids.is_empty():
		run.party_character_ids = [SpringRun.HERO_CHARACTER_ID]
	if run.party_character_ids.size() > 3:
		return false
	var seen_party: Dictionary = {}
	for character_id in run.party_character_ids:
		if seen_party.has(character_id) or not CharacterCatalogScript.has_definition(character_id):
			return false
		seen_party[character_id] = true
	var lead = CharacterCatalogScript.get_definition(run.party_character_ids[0])
	if lead == null:
		return false
	if run.party_vitals.is_empty():
		var lead_changed: bool = run.hero_character_id != String(lead.character_id)
		var previous_max_health: int = run.effective_max_health()
		var health_ratio: float = clampf(float(run.hero_health) / float(maxi(1, previous_max_health)), 0.0, 1.0)
		run.hero_character_id = String(lead.character_id)
		run.hero_base_max_health = lead.max_health
		run.hero_base_attack = lead.attack
		run.hero_base_defense = lead.defense
		run.hero_base_magic_resistance = lead.magic_resistance
		run.hero_max_health = run.effective_max_health()
		if lead_changed:
			run.hero_health = clampi(roundi(float(run.hero_max_health) * health_ratio), 1, run.hero_max_health)
	suspended_map = run.to_dict()
	pending = {
		"encounter": encounter_id,
		"character_ids": run.party_character_ids.duplicate(),
		"party_vitals": run.party_vitals.duplicate(true),
		"hero_character_id": run.hero_character_id,
		"hero_base_max_health": run.hero_base_max_health,
		"hero_base_attack": run.hero_base_attack,
		"hero_base_defense": run.hero_base_defense,
		"hero_base_magic_resistance": run.hero_base_magic_resistance,
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
		int(payload.get("hero_base_max_health", SpringRun.HERO_BASE_MAX_HEALTH)) + int(payload.get("relic_max_health", 0)),
		int(payload.get("hero_base_attack", SpringRun.HERO_BASE_ATTACK)) + int(payload.get("relic_attack", 0)),
		int(payload.get("hero_base_defense", SpringRun.HERO_BASE_DEFENSE)) + int(payload.get("relic_defense", 0)),
		int(payload.get("hero_base_magic_resistance", SpringRun.HERO_BASE_MAGIC_RESISTANCE))
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


## Restore the prepared party snapshot after encounter actors have been created.
## CONTRACT: _test_party_vitals_enter_the_battle_scene
static func restore_party_vitals(battle, payload: Dictionary) -> void:
	var saved: Dictionary = payload.get("party_vitals", {})
	for character_id in saved:
		var actor = battle.actors.get(str(character_id))
		var vitals: Dictionary = saved[character_id]
		if actor == null or actor.team != "player":
			continue
		actor.max_health = maxi(1, int(vitals.get("max_health", actor.max_health)))
		actor.health = clampi(int(vitals.get("health", actor.health)), 0, actor.max_health)
		actor._is_downed = actor.health <= 0
		actor._is_defeated = false


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
	var outcome := {"message": "", "battle": &"", "finished_run": false, "reward_choices": [], "needs_revive": false}
	if not has_result():
		return outcome
	return settle_result(run, consume_result())


static func settle_result(run, result: Dictionary, unlocked_region_ids: Array = [], next_region_scene_available: bool = false) -> Dictionary:
	last_transition_message = ""
	var outcome := {"message": "", "battle": &"", "finished_run": false, "reward_choices": [], "needs_revive": false, "region_transition": {}}
	var kind: String = str(result.get("kind", KIND_BATTLE))
	var place_id := StringName(str(result.get("place", "")))
	var won: bool = str(result.get("result", "")) == "victory"

	run.apply_battle_payload({
		"hero_health": int(result.get("hero_health", run.hero_health)),
		"hero_max_health": int(result.get("hero_max_health", run.effective_max_health())),
		"carry": result.get("carry", run.battle_carry),
	})
	if result.get("party_vitals", {}) is Dictionary:
		run.party_vitals = result.get("party_vitals", {}).duplicate(true)

	if place_id != &"":
		run.exploration.mark_completed(place_id)

	if not won:
		var pity_shards: int = 20
		outcome["atelier_shards"] = pity_shards
		outcome["message"] = "这一处失守了（带回 %d 工坊残晶）。" % pity_shards
		if run.revive_used:
			outcome["message"] += "本区域的续行已经用过，冒险到此为止。"
			run.exploration.finish("defeat")
			outcome["finished_run"] = true
		else:
			run.revive_prompt = true
			outcome["needs_revive"] = true
			outcome["message"] += "可以用 %d 份补给续行一次。" % CONTINUE_SUPPLY_COST
		return outcome

	var win_shards: int = 80 if kind == KIND_BOSS else (55 if kind == KIND_ELITE else 35)
	outcome["atelier_shards"] = win_shards
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
		KIND_BATTLE:
			# Ordinary victories automatically drop one random common collectible.
			# Active consumables enter the stack; passive effects resolve immediately.
			var normal_pool: Array[StringName] = roll_reward_choices(run, "normal", 1, int(result.get("seed", run.seed_value)))
			if not normal_pool.is_empty():
				var normal_reward: StringName = normal_pool[0]
				if run.grant_collectible(normal_reward):
					var effect_note: String = "已收纳，可在藏品栏中选择使用。"
					if not SpringCollectibleCatalog.is_consumable(normal_reward):
						var normal_effect: Dictionary = run.apply_collectible_effect(normal_reward)
						effect_note = str(normal_effect.get("message", "效果已结算。"))
					outcome["message"] = "普通战斗获得藏品「%s」：%s" % [run.collectible_name(normal_reward), effect_note]
			else:
				run.add_coins(20)
				outcome["message"] = "普通战斗胜利。普通藏品已收集齐全，换得 20 花钿。"
		KIND_ELITE:
			# §14: three candidates, pick one, common or rare only.
			var choices: Array[StringName] = roll_reward_choices(run, "elite", 3, int(result.get("seed", run.seed_value)))
			if choices.size() < 3:
				# §14 promises three distinct choices. If fewer than three remain,
				# compensate rather than presenting a broken partial reward panel.
				run.add_coins(40)
				run.add_supplies(2)
				outcome["message"] = "击败了精英。可选藏品不足三件，换得 40 花钿与 2 份补给。"
			else:
				run.reward_choices.assign(choices)
				outcome["reward_choices"] = choices
		KIND_BOSS:
			# §15.4: one random exclusive reward. Drawn once - calling the roll
			# twice would hand out two different answers to the same question.
			var boss_pool: Array[StringName] = roll_reward_choices(run, "boss", 1, int(result.get("seed", run.seed_value)))
			if not boss_pool.is_empty():
				var boss_reward: StringName = boss_pool[0]
				if run.grant_collectible(boss_reward):
					var boss_effect_note: String = "已收纳，可在藏品栏中选择使用。"
					if not SpringCollectibleCatalog.is_consumable(boss_reward):
						var boss_effect: Dictionary = run.apply_collectible_effect(boss_reward)
						boss_effect_note = str(boss_effect.get("message", "效果已结算。"))
					outcome["message"] = "击败了首领。获得藏品「%s」：%s" % [run.collectible_name(boss_reward), boss_effect_note]
			else:
				run.add_coins(60)
				outcome["message"] = "击败了首领。藏品已收集齐全，换得 60 花钿。"
			# Bosses also guarantee one unique relic while the relic pool remains.
			var relic_rng := RandomNumberGenerator.new()
			relic_rng.seed = hash("%d|boss_relic|%d" % [int(result.get("seed", run.seed_value)), run.battles_won])
			var boss_relic: StringName = run.grant_random_relic(relic_rng)
			if boss_relic != &"":
				outcome["message"] += " 获得遗物「%s」。" % run.relic_name(boss_relic)
			else:
				run.add_coins(80)
				outcome["message"] += " 遗物已收集齐全，换得 80 花钿。"
			# §3: the next region requires both a persistent unlock and a real scene.
			var transition: Dictionary = RegionProgressionScript.resolve_next(
				RegionProgressionScript.REGION_SPRING,
				unlocked_region_ids,
				next_region_scene_available
			)
			outcome["region_transition"] = transition
			match str(transition.get("status", "locked")):
				"available":
					outcome["message"] += " 下一层：%s，正在前往。" % str(transition.get("next_region_name", ""))
				"content_unavailable":
					outcome["message"] += " %s已解锁，但区域内容尚未开放，本次探索结束。" % str(transition.get("next_region_name", "下一层"))
				_:
					outcome["message"] += " 下一层：%s尚未解锁，当前探索结束。" % str(transition.get("next_region_name", "后续区域"))
			run.exploration.finish("cleared")
			outcome["finished_run"] = not bool(transition.get("can_enter", false))
		_:
			pass

	var parts: Array[String] = []
	parts.append("战斗胜利")
	parts.append("+%d 工坊残晶" % win_shards)
	if chests > 0:
		parts.append("保住 %d 个宝箱 · +%d 花钿" % [chests, coins])
	if not loot_names.is_empty():
		parts.append("战利品：" + "、".join(loot_names))
	if outcome["message"].is_empty():
		outcome["message"] = "；".join(parts) + "。"
	else:
		var extra_parts: Array[String] = []
		if chests > 0:
			extra_parts.append("保住 %d 个宝箱 · +%d 花钿" % [chests, coins])
		if not loot_names.is_empty():
			extra_parts.append("战利品：" + "、".join(loot_names))
		extra_parts.append("+%d 工坊残晶" % win_shards)
		outcome["message"] += "（" + "；".join(extra_parts) + "）"
	if not (outcome.get("region_transition", {}) as Dictionary).is_empty() and bool(outcome.get("finished_run", false)):
		last_transition_message = str(outcome.get("message", ""))
	return outcome


## Draws reward candidates the player does not own yet. Returns [] when every
## candidate is already owned - the caller then falls back to resources rather
## than offering a dead choice (§6.1).
static func roll_reward_choices(run, source: String, count: int, seed_value: int) -> Array[StringName]:
	var result: Array[StringName] = []
	var candidates: Array[String] = []
	for candidate_id in SpringCollectibleCatalog.candidates_for(source):
		var candidate := StringName(candidate_id)
		if SpringCollectibleCatalog.is_consumable(candidate) or not run.has_collectible(candidate):
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
static func can_continue(run) -> bool:
	return run != null and not run.revive_used and not run.exploration.finished and run.supplies >= CONTINUE_SUPPLY_COST


static func continue_run(run) -> Dictionary:
	var outcome := {"ok": false, "message": ""}
	if run == null or run.exploration.finished:
		outcome["message"] = "本次探索已经结束。"
		return outcome
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
	for character_id in run.party_vitals:
		var vitals: Dictionary = run.party_vitals[character_id]
		var member_max: int = maxi(1, int(vitals.get("max_health", 1)))
		vitals["health"] = maxi(1, int(round(float(member_max) * CONTINUE_HEALTH_FRACTION)))
		run.party_vitals[character_id] = vitals
	run.revive_used = true
	outcome["ok"] = true
	outcome["message"] = "消耗 %d 份补给续行，回复至 %d / %d。" % [CONTINUE_SUPPLY_COST, run.hero_health, run.effective_max_health()]
	return outcome
