extends "res://tests/framework/test_case.gd"

const ThemeScript = preload("res://scripts/spring/spring_theme_view.gd")
const LobbyScript = preload("res://scripts/ui/lobby_view.gd")
const CollectibleCatalogScript = preload("res://scripts/spring/spring_collectible_catalog.gd")
const RelicCatalogScript = preload("res://scripts/spring/spring_relic_catalog.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")
const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")


func _run() -> void:
	_test_lobby_routes_to_theme()
	await _test_compendium_uses_live_catalogs()
	await _test_enemy_roster_is_complete()
	await _test_navigation_and_map_handoff()


func _test_lobby_routes_to_theme() -> void:
	var spring_entry: Dictionary = LobbyScript.MAP_ENTRIES[1]
	_check(str(spring_entry.get("scene_path", "")) == "res://scenes/spring/spring_theme.tscn",
		"choosing the spring chapter opens the dedicated theme scene")
	_check(ResourceLoader.exists("res://scenes/spring/spring_theme.tscn"),
		"the spring theme scene resource exists")
	_check(str(spring_entry.get("cta", "")) == "进入主题界面",
		"the chapter card communicates the new intermediate destination")


func _test_compendium_uses_live_catalogs() -> void:
	var view = ThemeScript.new()
	root.add_child(view)
	await process_frame
	var entries: Array[Dictionary] = view.collectible_entries()
	_check(entries.size() == CollectibleCatalogScript.COLLECTIBLES.size() + RelicCatalogScript.RELICS.size(),
		"the compendium includes every current collectible and relic catalog entry")
	var seen: Dictionary = {}
	for entry in entries:
		var id := str(entry.get("id", ""))
		_check(not id.is_empty() and not seen.has(id), "compendium IDs are nonempty and unique: " + id)
		seen[id] = true
		_check(not str(entry.get("name", "")).is_empty(), "compendium entry has a display name: " + id)
		_check(not str(entry.get("desc", "")).is_empty(), "compendium entry has an effect description: " + id)
	view.collectible_filter = "藏品"
	_check(view.filtered_collectibles().size() == CollectibleCatalogScript.COLLECTIBLES.size(),
		"the collectible filter excludes relics")
	view.collectible_filter = "遗物"
	_check(view.filtered_collectibles().size() == RelicCatalogScript.RELICS.size(),
		"the relic filter shows all relics")
	view.queue_free()
	await process_frame


func _test_enemy_roster_is_complete() -> void:
	var view = ThemeScript.new()
	root.add_child(view)
	await process_frame
	var entries: Array[Dictionary] = view.enemy_entries()
	var expected := (
		EnemyCatalogScript.SPRING_COMMON_DEFINITIONS.size()
		+ EnemyCatalogScript.SPRING_ELITE_DEFINITIONS.size()
		+ EnemyCatalogScript.SPRING_BOSS_DEFINITIONS.size()
	)
	_check(entries.size() == expected, "the bestiary contains every registered spring enemy")
	_check(view.filtered_enemies().size() == EnemyCatalogScript.SPRING_COMMON_DEFINITIONS.size(),
		"ordinary filter contains the complete ordinary roster")
	view.enemy_filter = "精英"
	_check(view.filtered_enemies().size() == EnemyCatalogScript.SPRING_ELITE_DEFINITIONS.size(),
		"elite filter contains the complete elite roster")
	view.enemy_filter = "首领"
	_check(view.filtered_enemies().size() == EnemyCatalogScript.SPRING_BOSS_DEFINITIONS.size(),
		"boss filter contains the complete boss roster")
	for entry in entries:
		var definition: EnemyDefinition = entry.definition
		_check(definition.is_valid(), "enemy profile is valid: " + str(definition.archetype_id))
		_check(not definition.actions.is_empty(), "enemy has at least one declared action: " + str(definition.archetype_id))
	view.queue_free()
	await process_frame


func _test_navigation_and_map_handoff() -> void:
	var view = ThemeScript.new()
	root.add_child(view)
	await process_frame
	view.open_page("collectibles")
	_check(view.page == "collectibles" and view.selected_index == 0,
		"opening the collectible archive resets its selection")
	view.open_page("enemies")
	_check(view.page == "enemies" and view.selected_index == 0,
		"opening the bestiary resets its selection")
	view.open_page("story")
	_check(view.page == "story", "the story recall page is reachable")
	view.open_page("home")
	var observed: Dictionary = {}
	view.scene_change = func(_tree, path: String, title: String) -> Error:
		observed["path"] = path
		observed["title"] = title
		return OK
	BridgeScript.requested_mode = ""
	_check(view.transition_to_map("hard"), "a successful chapter transition is accepted")
	_check(str(observed.get("path", "")) == "res://scenes/spring/spring_map.tscn",
		"the start-travel action targets the actual spring exploration map")
	_check(str(observed.get("title", "")) == "踏入春之境",
		"the map transition uses the spring chapter title")
	_check(BridgeScript.requested_mode == "hard",
		"the selected hard-route mode is handed to the map initializer")
	view.scene_change = func(_tree, _path: String, _title: String) -> Error:
		return ERR_CANT_OPEN
	_check(not view.transition_to_map("normal"), "a failed map transition is rejected")
	_check(BridgeScript.requested_mode.is_empty(), "a failed transition clears the pending mode handoff")
	view.queue_free()
	await process_frame
	BridgeScript.requested_mode = ""
