class_name SpringRun
extends RefCounted

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

const SAVE_VERSION: int = 1

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

## §10.3: drawn once per run and recorded, so a resumed run never re-rolls it.
var random_event_id: StringName = &""
## Event id -> the option the player picked. Persisted per §16.2.
var event_choices: Dictionary = {}
## At most one hidden place per board (§9.1). Empty until revealed (§9.2).
var hidden_cell: Vector2i = Vector2i.ZERO
var hidden_revealed: bool = false


static func begin(p_seed: int) -> SpringRun:
	var run := SpringRun.new()
	run.seed_value = p_seed
	run.template_id = SpringMapFactory.template_for_seed(p_seed)
	run.template = SpringMapFactory.build(run.template_id)
	run.exploration = ExplorationState.create(run.template)
	run.random_event_id = run._draw_random_event()
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
		# §16.2 also asks for shop stock and purchase records. No shop exists yet;
		# the key is reserved so a later version can fill it without a format bump.
		"shop": {},
	}


static func from_dict(data: Dictionary) -> SpringRun:
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
	return run


func save_to_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


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
