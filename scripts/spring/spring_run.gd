class_name SpringRun
extends RefCounted

const SaveMigrationScript = preload("res://scripts/spring/spring_run_migration.gd")

## One 春之境 expedition: the board, the explorer on it, and the resources that
## survive from place to place (设计汇总 2026-11-26 §4, §5, §16.2).
##
## Kept separate from run_state.gd on purpose. run_state holds what a single
## battle needs (gear, mods, the backpack); SpringRun holds what the map needs.
## §4 forbids the two modes from sharing their in-run resources, so sharing one
## state object would quietly break that rule.
##
## Resource amounts that the document leaves open - starting supplies, 四时花露
## capacity - are NOT invented here. They start at zero and are injected by
## content, which is what "尚未确定" means in practice.

const SAVE_PATH := "user://spring_run.json"
const SAVE_VERSION: int = 4

## The hero's battle-side baseline, mirroring `data/characters/sakura.tres`.
## §2 makes 樱 the narrative lead of 春之境, and this mode now fights as her
## rather than borrowing 瑟弗林's sheet. The four numbers are duplicated here
## because SpringRun must not depend on the battle layer (§4); a suite asserts
## that they still match the sheet, so the copy cannot drift silently.
const HERO_BASE_MAX_HEALTH: int = 1800
const HERO_BASE_ATTACK: int = 520
const HERO_BASE_DEFENSE: int = 180
const HERO_BASE_MAGIC_RESISTANCE: int = 111
## The character sheet the spring battles deploy.
const HERO_CHARACTER_ID: String = "sakura"

## The run lead follows the first character in its snapshotted squad. These
## values are captured from the character sheet so SpringRun stays battle-agnostic.
var hero_character_id: String = HERO_CHARACTER_ID
var hero_base_max_health: int = HERO_BASE_MAX_HEALTH
var hero_base_attack: int = HERO_BASE_ATTACK
var hero_base_defense: int = HERO_BASE_DEFENSE
var hero_base_magic_resistance: int = HERO_BASE_MAGIC_RESISTANCE

## §5.1: 补给 is shared by the whole party, not carried per character.
var seed_value: int = 0
var template_id: int = 1
var template: SpringMapTemplate
var exploration: ExplorationState

var coins: int = 0
var supplies: int = 0
## spring / summer / autumn / winter, sharing one cap (§5.4).
var dew: Dictionary = {"spring": 0, "summer": 0, "autumn": 0, "winter": 0}
var dew_cap: int = 0
var memory_pages: int = 0
var relics: Array[StringName] = []

## §11.2: health carries from fight to fight and is never restored by winning.
## The bonus is what relics and epic collectibles add for the rest of the run.
var hero_max_health: int = HERO_BASE_MAX_HEALTH
var hero_health: int = HERO_BASE_MAX_HEALTH
var bonus_max_health: int = 0
## Ceiling the battle layer reported back (gear can raise it, §11.2 keeps gear
## effects between fights). 0 means "no fight has reported yet".
var carry_max_health: int = 0

## §6.1: collectibles are never duplicated, so this is a set with an order.
var collectibles: Array[StringName] = []

## What the battle layer needs to hand back: gear, backpack and skill mods. Kept
## as an opaque snapshot on purpose - SpringRun must not start interpreting
## battle rules (§4), it only carries the box between fights.
var battle_carry: Dictionary = {"mods": [], "equipped_weapon": {}, "equipped_armor": {}, "backpack": []}
var battles_won: int = 0

## §7.3 / §10.4: an economic event prices the *next* shop only, applied on
## arrival, and expires when that shop is left.
var shop_price_multiplier: float = 1.0
var shop_price_notes: Array[String] = []
var shop: SpringShop

## Decisions that must survive closing the game before their overlay is resolved.
var pending_event: Dictionary = {}
var reward_choices: Array[StringName] = []
var revive_prompt: bool = false
## §11.3: one continuation per area. Spring's map is a single area today, so
## this flag lasts the whole run. There is no area concept in the code yet -
## nothing resets it after it is used - so a future area transition must reset
## it here, or the "one per area" promise becomes one per run.
var revive_used: bool = false
## Event id -> {"option": int, "log": [...]}. §16.2 asks for the choices.
var event_log: Dictionary = {}
## Set when a collectible promises a reveal; the map consumes it on the next
## redraw, because only the map knows which cells are still free.
var pending_hidden_reveal: bool = false

## §10.3: drawn once per run and recorded, so a resumed run never re-rolls it.
var random_event_id: StringName = &""
## Event id -> the option the player picked. Persisted per §16.2.
var event_choices: Dictionary = {}
## At most one hidden place per board (§9.1). Empty until revealed (§9.2).
var hidden_cell: Vector2i = Vector2i.ZERO
var hidden_revealed: bool = false
var route_plan: SpringRoutePlan = SpringRoutePlan.create(false)
## Party roster is snapshotted when an expedition first enters battle.
var party_character_ids: Array[String] = []
## Per-character HP carried between encounters; equipment carry remains separate.
var party_vitals: Dictionary = {}


static func begin(p_seed: int, hard_mode: bool = false) -> SpringRun:
	var run := SpringRun.new()
	run.seed_value = p_seed
	run.template_id = SpringMapFactory.template_for_seed(p_seed)
	run.template = SpringMapFactory.build(run.template_id)
	run.exploration = ExplorationState.create(run.template)
	run.random_event_id = run._draw_random_event()
	run.route_plan = SpringRoutePlan.create(hard_mode)
	return run


func _draw_random_event() -> StringName:
	var candidates := SpringMapFactory.random_candidates(template_id)
	if candidates.is_empty():
		return &""
	var index: int = posmod(seed_value * 7 + 3, candidates.size())
	return StringName(candidates[index])


func random_event_place() -> SpringPlace:
	return template.place_by_id(&"event_random")


## The random slot's label follows the run's draw, not the template's placeholder.
func title_of(place: SpringPlace) -> String:
	if place == null:
		return ""
	if place.id == &"event_random" and not String(random_event_id).is_empty():
		return SpringMapFactory.event_title(String(random_event_id))
	return place.title_zh


func dew_total() -> int:
	var total: int = 0
	for key in dew:
		total += int(dew[key])
	return total


## §5.4: when the storage is full the player must be told, never silently
## dropped. Returning false is that signal.
func add_dew(kind: String, amount: int) -> bool:
	if amount <= 0 or not dew.has(kind):
		return false
	if dew_total() + amount > dew_cap:
		return false
	dew[kind] = int(dew[kind]) + amount
	return true


func add_coins(amount: int) -> void:
	coins = maxi(0, coins + amount)


func spend_coins(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false
	coins -= amount
	return true


func add_supplies(amount: int) -> void:
	supplies = maxi(0, supplies + amount)


func spend_supplies(amount: int) -> bool:
	if amount < 0 or supplies < amount:
		return false
	supplies -= amount
	return true


func add_memory_pages(amount: int) -> void:
	memory_pages = maxi(0, memory_pages + amount)


func add_relic(relic_id: StringName) -> void:
	if relic_id == &"":
		return
	relics.append(relic_id)


# --- hero vitals (§11.2) -----------------------------------------------------

func effective_max_health() -> int:
	return maxi(1, maxi(hero_base_max_health + bonus_max_health, carry_max_health))


## Returns how much was actually restored, so the caller can say "回复 37 点"
## instead of promising a number the cap ate.
func heal_hero(amount: int) -> int:
	if amount <= 0:
		return 0
	var before: int = hero_health
	hero_health = mini(effective_max_health(), hero_health + amount)
	return hero_health - before


## §10.1: an event may hurt, but it may not end the run by itself - the floor is
## one point, and losing the last point stays a battle's job.
func damage_hero(amount: int) -> int:
	if amount <= 0:
		return 0
	var before: int = hero_health
	hero_health = maxi(1, hero_health - amount)
	return before - hero_health


func heal_fraction(fraction: float) -> int:
	return heal_hero(int(round(float(effective_max_health()) * fraction)))


func add_bonus_max_health(amount: int) -> void:
	if amount == 0:
		return
	bonus_max_health = maxi(0, bonus_max_health + amount)
	if amount > 0:
		hero_health = mini(effective_max_health(), hero_health + amount)
	else:
		hero_health = clampi(hero_health, 1, effective_max_health())


# --- collectibles (§6.1) -----------------------------------------------------

func has_collectible(collectible_id: StringName) -> bool:
	return collectibles.has(collectible_id)


## §6.1: no duplicates, ever. Returns false when the player already owns it.
func grant_collectible(collectible_id: StringName) -> bool:
	if collectible_id == &"" or collectibles.has(collectible_id):
		return false
	if not SpringCollectibleCatalog.has_collectible(collectible_id):
		return false
	collectibles.append(collectible_id)
	return true


## Draws one the player does not own yet. Returns &"" when the pool is exhausted;
## the caller then falls back to a resource reward so the option is never dead
## (§6.1 closing rule).
func grant_random_collectible(rng: RandomNumberGenerator, source: String = "event") -> StringName:
	var candidates: Array[String] = []
	for candidate_id in SpringCollectibleCatalog.candidates_for(source):
		if not collectibles.has(StringName(candidate_id)):
			candidates.append(candidate_id)
	if candidates.is_empty():
		return &""
	var picked: StringName = StringName(candidates[rng.randi_range(0, candidates.size() - 1)])
	if not grant_collectible(picked):
		return &""
	return picked


## §7.4 / 神秘收藏家: handing one over removes the newest, which is the one the
## player just saw in the log.
func consume_collectible() -> StringName:
	if collectibles.is_empty():
		return &""
	return collectibles.pop_back()


func collectible_name(collectible_id: StringName) -> String:
	return SpringCollectibleCatalog.name_of(collectible_id)


func relic_name(relic_id: StringName) -> String:
	return SpringRelicCatalog.name_of(relic_id)


## Applies a collectible's effect. Resource kinds land immediately; the two that
## need the map (a reveal) and the run (a stat) set state the map/bridge reads.
func apply_collectible_effect(collectible_id: StringName) -> Dictionary:
	var effect: Dictionary = SpringCollectibleCatalog.effect_of(collectible_id)
	var result := {"ok": false, "message": ""}
	if effect.is_empty():
		return result
	match str(effect.get("kind", "")):
		"coins":
			add_coins(int(effect.get("amount", 0)))
		"supplies":
			add_supplies(int(effect.get("amount", 0)))
		"pages":
			add_memory_pages(int(effect.get("amount", 0)))
		"dew":
			var dew_kind: String = str(effect.get("dew_kind", "spring"))
			if not add_dew(dew_kind, int(effect.get("amount", 0))):
				result["message"] = "四时花露已满，这一份没能收下。"
				return result
		"max_health":
			add_bonus_max_health(int(effect.get("amount", 0)))
		"reveal_hidden":
			pending_hidden_reveal = true
		_:
			return result
	result["ok"] = true
	result["message"] = SpringCollectibleCatalog.desc_of(collectible_id)
	return result


# --- battle carry (§11.2) ----------------------------------------------------

func battle_backpack() -> Array:
	if not battle_carry.has("backpack"):
		battle_carry["backpack"] = []
	return battle_carry["backpack"]


func add_battle_item(item: Dictionary) -> void:
	if item.is_empty():
		return
	battle_backpack().append(item.duplicate(true))


func remove_battle_item(index: int) -> bool:
	var bag: Array = battle_backpack()
	if index < 0 or index >= bag.size():
		return false
	bag.remove_at(index)
	return true


## Snapshot handed to the battle layer when a fight starts.
func battle_payload() -> Dictionary:
	return {
		"hero_health": hero_health,
		"hero_max_health": effective_max_health(),
		"bonus_max_health": bonus_max_health,
		"carry": battle_carry.duplicate(true),
	}


## Writes back what the fight left behind. Health is clamped to the run's max,
## because gear sold or lost mid-fight can shrink the ceiling.
func apply_battle_payload(payload: Dictionary) -> void:
	if payload.has("hero_health"):
		hero_health = clampi(int(payload["hero_health"]), 1, effective_max_health())
	if payload.has("hero_max_health"):
		carry_max_health = maxi(0, int(payload["hero_max_health"]))
	if payload.has("carry"):
		battle_carry = (payload["carry"] as Dictionary).duplicate(true)
	if payload.has("bonus_max_health"):
		bonus_max_health = maxi(0, int(payload["bonus_max_health"]))


# --- shop (§7.3) -------------------------------------------------------------

func apply_shop_price_modifier(multiplier: float, note: String = "") -> void:
	if multiplier <= 0.0:
		return
	shop_price_multiplier *= multiplier
	if not note.is_empty():
		shop_price_notes.append(note)


## Rolls stock on first arrival and reuses it afterwards (§7.2). The price
## modifier is consumed here - it prices this shop and no other.
func enter_shop() -> SpringShop:
	if shop == null:
		shop = SpringShop.create(seed_value + template_id * 131, shop_price_multiplier)
		shop_price_multiplier = 1.0
		shop_price_notes.clear()
	return shop


## Called when the player walks away: the shop object (and its stock, purchase
## records and used services) is kept for the next visit, only the pending price
## effect is dropped.
func leave_shop() -> void:
	shop_price_multiplier = 1.0
	shop_price_notes.clear()


## Finishes a place and closes the exhausted-turn window if that is what the
## player was doing when the bar emptied.
func complete_place(place: SpringPlace) -> void:
	if place == null:
		return
	exploration.mark_completed(place.id)


func reveal_hidden(cell: Vector2i) -> bool:
	if hidden_revealed:
		return false
	return _place_hidden(cell)


## Shared by the reveal path and the save path. Split out because a restore sets
## `hidden_revealed` from the file before rebuilding the place, and the public
## entry point refuses to run once that flag is true.
func _place_hidden(cell: Vector2i) -> bool:
	if not template.is_inside(cell) or template.is_occupied(cell):
		return false
	hidden_cell = cell
	hidden_revealed = true
	var place := SpringPlace.create(&"hidden", SpringPlace.Kind.HIDDEN, cell, "隐秘之地", &"hidden_event")
	template.add_place(place)
	return true


# --- persistence (§16.2) -----------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"seed": seed_value,
		"template_id": template_id,
		"exploration": exploration.to_dict(),
		"random_event": String(random_event_id),
		"event_choices": event_choices.duplicate(true),
		"hidden": {
			"cell": [hidden_cell.x, hidden_cell.y],
			"revealed": hidden_revealed,
		},
		"resources": {
			"coins": coins,
			"supplies": supplies,
			"dew": dew.duplicate(true),
			"dew_cap": dew_cap,
			"memory_pages": memory_pages,
			"relics": relics.duplicate(),
		},
		"hero": {
			"health": hero_health,
			"bonus_max_health": bonus_max_health,
			"carry_max_health": carry_max_health,
			"character_id": hero_character_id,
			"base_max_health": hero_base_max_health,
			"base_attack": hero_base_attack,
			"base_defense": hero_base_defense,
			"base_magic_resistance": hero_base_magic_resistance,
		},
		"collectibles": _names_to_strings(collectibles),
		"battle_carry": battle_carry.duplicate(true),
		"battles_won": battles_won,
		"pending_event": pending_event.duplicate(true),
		"reward_choices": _names_to_strings(reward_choices),
		"revive_prompt": revive_prompt,
		"revive_used": revive_used,
		"event_log": event_log.duplicate(true),
		"price": {
			"multiplier": shop_price_multiplier,
			"notes": shop_price_notes.duplicate(),
		},
		# §16.2: stock, remaining counts, purchase records and used services all
		# travel with the save.
		"shop": {} if shop == null else shop.to_dict(),
		"route_plan": {} if route_plan == null else route_plan.to_dict(),
		"party_character_ids": party_character_ids.duplicate(),
		"party_vitals": party_vitals.duplicate(true),
	}


static func _names_to_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result


static func from_dict(data: Dictionary) -> SpringRun:
	var invalid := SpringSaveValidation.invalid_field(data)
	if not invalid.is_empty():
		push_warning("SpringRun.from_dict: invalid field %s" % invalid)
		return null
	data = data.duplicate(true)
	# 先把旧档推到当前版本，再读任何字段。迁移表放在文件末尾，加版本时只加
	# 一行；以前是一串 `if version < N` 散在读字段的逻辑中间，第三个版本
	# 进来时已经很难看出「哪一段属于哪一次升级」。
	var migration_defaults := {
		"hero_character_id": HERO_CHARACTER_ID,
		"base_max_health": HERO_BASE_MAX_HEALTH,
		"base_attack": HERO_BASE_ATTACK,
		"base_defense": HERO_BASE_DEFENSE,
		"base_magic_resistance": HERO_BASE_MAGIC_RESISTANCE,
	}
	var version_problem: String = SaveMigrationScript.migrate_to_current(data, SAVE_VERSION, migration_defaults)
	if not version_problem.is_empty():
		push_error("SpringRun.from_dict: %s" % version_problem)
		return null

	var template_id_value: int = int(data.get("template_id", 0))
	if not SpringMapFactory.has_template(template_id_value):
		return null
	var run := SpringRun.new()
	run.seed_value = int(data.get("seed", 0))
	run.template_id = template_id_value
	run.template = SpringMapFactory.build(template_id_value)
	run.exploration = ExplorationState.create(run.template)
	run.exploration.restore_from_dict(data.get("exploration", {}))

	# Restored, never redrawn: §16.2 forbids re-rolling the map, the events or the
	# shop stock when a run is resumed.
	var saved_event: String = str(data.get("random_event", ""))
	run.random_event_id = StringName(saved_event) if not saved_event.is_empty() else run._draw_random_event()
	run.event_choices = data.get("event_choices", {}).duplicate(true)

	var hidden: Dictionary = data.get("hidden", {})
	var hidden_cell_data: Array = hidden.get("cell", [0, 0])
	run.hidden_cell = Vector2i(int(hidden_cell_data[0]), int(hidden_cell_data[1]))
	run.hidden_revealed = false
	if bool(hidden.get("revealed", false)) and run.template.place_by_id(&"hidden") == null:
		run._place_hidden(run.hidden_cell)

	var resources: Dictionary = data.get("resources", {})
	run.coins = int(resources.get("coins", 0))
	run.supplies = int(resources.get("supplies", 0))
	run.dew_cap = int(resources.get("dew_cap", 0))
	var saved_dew: Dictionary = resources.get("dew", {})
	for key in run.dew:
		run.dew[key] = int(saved_dew.get(key, 0))
	run.memory_pages = int(resources.get("memory_pages", 0))
	run.relics = []
	for relic_id in resources.get("relics", []):
		run.relics.append(StringName(relic_id))

	# Everything below arrived with save version 2. A version-1 file simply has no
	# such keys, and each default matches what version 1 meant, so old saves load.
	# Anything version-specific has already been handled by _migrate_to_current.
	var hero: Dictionary = data.get("hero", {})
	run.hero_character_id = str(hero.get("character_id", HERO_CHARACTER_ID))
	run.hero_base_max_health = maxi(1, int(hero.get("base_max_health", HERO_BASE_MAX_HEALTH)))
	run.hero_base_attack = maxi(0, int(hero.get("base_attack", HERO_BASE_ATTACK)))
	run.hero_base_defense = maxi(0, int(hero.get("base_defense", HERO_BASE_DEFENSE)))
	run.hero_base_magic_resistance = maxi(0, int(hero.get("base_magic_resistance", HERO_BASE_MAGIC_RESISTANCE)))
	run.bonus_max_health = maxi(0, int(hero.get("bonus_max_health", 0)))
	run.carry_max_health = maxi(0, int(hero.get("carry_max_health", 0)))
	run.hero_health = clampi(int(hero.get("health", run.effective_max_health())), 1, run.effective_max_health())
	run.hero_max_health = run.effective_max_health()
	for collectible_id in data.get("collectibles", []):
		run.collectibles.append(StringName(collectible_id))
	var carry: Dictionary = data.get("battle_carry", {})
	if not carry.is_empty():
		run.battle_carry = carry.duplicate(true)
	run.battles_won = int(data.get("battles_won", 0))
	run.pending_event = data.get("pending_event", {}).duplicate(true)
	if not run.pending_event.is_empty() and run.template.place_by_id(StringName(run.pending_event["place"])) == null:
		push_warning("SpringRun.from_dict: invalid field pending_event.place")
		return null
	for choice in data.get("reward_choices", []):
		run.reward_choices.append(StringName(choice))
	run.revive_prompt = bool(data.get("revive_prompt", false))
	run.revive_used = bool(data.get("revive_used", false))
	run.event_log = data.get("event_log", {}).duplicate(true)
	var price: Dictionary = data.get("price", {})
	run.shop_price_multiplier = float(price.get("multiplier", 1.0))
	for note in price.get("notes", []):
		run.shop_price_notes.append(str(note))
	var shop_data: Dictionary = data.get("shop", {})
	if not shop_data.is_empty():
		run.shop = SpringShop.from_dict(shop_data)
	run.route_plan = SpringRoutePlan.from_dict(data.get("route_plan", {}))
	for character_id in data.get("party_character_ids", []):
		run.party_character_ids.append(str(character_id))
	run.party_vitals = data.get("party_vitals", {}).duplicate(true)
	return run


func save_to_file(path: String) -> bool:
	return SaveFile.write_json(path, to_dict())


static func load_from_file(path: String) -> SpringRun:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)
