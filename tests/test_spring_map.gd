extends "res://tests/framework/test_case.gd"

## 春之境 map templates (设计汇总 2026-11-26 §9).
##
## Asserts the rules the document fixes - boss cells, the 8/6/7 distances, the
## eleven-place shape, the encounter ids each template owns - and the invariants
## the factory must keep (no shared cell, every cell on the board, shops
## repeatable). It deliberately does not pin the draft coordinates of the other
## ten places: those are LAYOUT_ORDER's business and may be replaced wholesale
## when the author supplies the real layout.

const FactoryScript = preload("res://scripts/spring/spring_map_factory.gd")


func _run() -> void:
	_test_every_template_builds()
	_test_boss_cells_match_the_document()
	_test_start_to_boss_distances()
	_test_place_shape()
	_test_cells_are_unique_and_on_board()
	_test_encounters_are_unique_across_templates()
	_test_template_two_anchors_the_letter()
	_test_shop_is_repeatable()
	_test_hidden_places_come_from_free_cells()
	_test_random_pool_excludes_fixed_events()
	_test_layout_order_covers_the_board()


func _test_every_template_builds() -> void:
	for template_id in FactoryScript.template_ids():
		_check(FactoryScript.build(template_id) != null, "template %d builds" % template_id)
	_check(FactoryScript.build(0) == null, "an unknown template id builds nothing")
	_check(FactoryScript.build(4) == null, "the fourth template does not exist")


func _test_boss_cells_match_the_document() -> void:
	var expected := {1: Vector2i(5, 5), 2: Vector2i(5, 3), 3: Vector2i(4, 5)}
	for template_id in expected:
		var template = FactoryScript.build(template_id)
		_check(template.boss_cell == expected[template_id], "template %d boss sits where §9.2 says" % template_id)
		_check(template.boss() != null and template.boss().cell == expected[template_id], "template %d boss place agrees with its cell" % template_id)


func _test_start_to_boss_distances() -> void:
	var expected := {1: 8, 2: 6, 3: 7}
	for template_id in expected:
		var template = FactoryScript.build(template_id)
		var distance: int = SpringMapTemplate.manhattan(template.start_cell, template.boss_cell)
		_check(distance == expected[template_id], "template %d start is %d cells from the boss" % [template_id, expected[template_id]], "got %d" % distance)


func _test_place_shape() -> void:
	for template_id in FactoryScript.template_ids():
		var template = FactoryScript.build(template_id)
		_check(template.places.size() == 11, "template %d has eleven fixed places" % template_id, "got %d" % template.places.size())
		_check(template.places_of(SpringPlace.Kind.BATTLE).size() == 4, "template %d has four normal battles" % template_id)
		_check(template.places_of(SpringPlace.Kind.ELITE).size() == 1, "template %d has one elite battle" % template_id)
		_check(template.places_of(SpringPlace.Kind.BOSS).size() == 1, "template %d has one boss" % template_id)
		_check(template.places_of(SpringPlace.Kind.EVENT).size() == 4, "template %d has three fixed events and one random slot" % template_id)
		_check(template.places_of(SpringPlace.Kind.SHOP).size() == 1, "template %d has one shop" % template_id)


func _test_cells_are_unique_and_on_board() -> void:
	for template_id in FactoryScript.template_ids():
		var template = FactoryScript.build(template_id)
		var seen: Dictionary = {}
		var all_inside: bool = true
		var unique: bool = true
		for place in template.places:
			if not template.is_inside(place.cell):
				all_inside = false
			if seen.has(place.cell):
				unique = false
			seen[place.cell] = true
		_check(all_inside, "template %d keeps every place on the 5x5 board" % template_id)
		_check(unique, "template %d never stacks two places on one cell" % template_id)
		_check(not seen.has(template.start_cell), "template %d leaves the start cell empty" % template_id)


func _test_encounters_are_unique_across_templates() -> void:
	var battles: Array[String] = []
	var elites: Array[String] = []
	for template_id in FactoryScript.template_ids():
		var template = FactoryScript.build(template_id)
		for place in template.places_of(SpringPlace.Kind.BATTLE):
			battles.append(String(place.payload))
		for place in template.places_of(SpringPlace.Kind.ELITE):
			elites.append(String(place.payload))
	_check(battles.size() == 12, "twelve normal battles are placed across the three templates", "got %d" % battles.size())
	_check(_all_unique(battles), "no normal battle appears in two templates", str(battles))
	_check(_all_unique(elites) and elites.size() == 3, "each template owns a different elite", str(elites))


func _test_template_two_anchors_the_letter() -> void:
	var template = FactoryScript.build(2)
	var letter = template.place_by_id(&"event_3")
	_check(letter != null, "template 2 keeps its剧情 event in a known slot")
	if letter == null:
		return
	_check(letter.cell == Vector2i(5, 4), "template 2 puts 没有寄出的信 at (5,4)", str(letter.cell))
	_check(String(letter.payload) == "unsent_letter", "the anchored place is the unsent letter")


func _test_shop_is_repeatable() -> void:
	for template_id in FactoryScript.template_ids():
		var template = FactoryScript.build(template_id)
		var shop = template.places_of(SpringPlace.Kind.SHOP)[0]
		_check(not shop.one_shot, "template %d shop may be entered again" % template_id)
		for place in template.places:
			if place.kind == SpringPlace.Kind.SHOP:
				continue
			_check(place.one_shot, "template %d %s is one-shot" % [template_id, place.id])


func _test_hidden_places_come_from_free_cells() -> void:
	var template = FactoryScript.build(1)
	var free := template.free_cells()
	_check(free.size() == 25 - 11 - 1, "eleven places plus the start leave thirteen free cells", "got %d" % free.size())
	var all_free: bool = true
	for cell in free:
		if template.is_occupied(cell) or cell == template.start_cell:
			all_free = false
	_check(all_free, "free cells never include a place or the start")


func _test_random_pool_excludes_fixed_events() -> void:
	var template_one := FactoryScript.random_candidates(1)
	_check(not template_one.has("lost_traveler"), "template 1 cannot draw its own fixed event")
	_check(not template_one.has("empty_camp"), "template 1 cannot draw 无人的营地 twice")
	_check(template_one.size() == 5, "template 1 draws from five events", str(template_one))

	var template_two := FactoryScript.random_candidates(2)
	_check(not template_two.has("stranded_caravan") and not template_two.has("unworshipped_shrine"), "template 2 excludes both of its fixed events")

	var template_three := FactoryScript.random_candidates(3)
	_check(template_three.size() == 6, "template 3 fixes no pool event, so all six stay eligible", str(template_three))


func _test_layout_order_covers_the_board() -> void:
	var seen: Dictionary = {}
	for cell in FactoryScript.LAYOUT_ORDER:
		seen[cell] = true
	_check(FactoryScript.LAYOUT_ORDER.size() == 25, "the layout order lists 25 cells")
	_check(seen.size() == 25, "the layout order lists each cell once")


func _all_unique(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value):
			return false
		seen[value] = true
	return true
