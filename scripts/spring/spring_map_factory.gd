class_name SpringMapFactory
extends RefCounted

## Builds the three 春之境 templates (设计汇总 2026-11-26 §9).
##
## What the document fixes, and therefore what is hard data here:
##   - which boss, and the boss cell of each template (§9.2 table)
##   - the encounter ids and their display names (§9.3, §13)
##   - the three fixed events per template, plus the shared random pool (§10.3)
##   - 11 fixed places on a 5x5 board (§9.2 closing note)
##   - template 2 puts 没有寄出的信 at (5,4), adjacent to its boss (§9.2)
##   - start-to-boss manhattan distances 8 / 6 / 7 (§9.2)
##
## What the document does NOT contain, stated explicitly in §9.2: the per-cell
## coordinates of the other ten places. Rather than invent an authoritative
## layout, the remaining places are placed by LAYOUT_ORDER - one fixed,
## hand-spread order shared by all three templates - so the result is
## deterministic, legal and reviewable. These cells are DRAFT: when the author
## supplies the real layout, replace LAYOUT_ORDER (or add a per-template override)
## and the rest of the map code keeps working.

const SIZE: int = 5

## Start cell. The document gives only the manhattan distance from the start to
## each boss (8 / 6 / 7); (1,1) is the single cell that reproduces all three
## distances against the three boss cells, which is why it is used.
const START_CELL := Vector2i(1, 1)

## A fixed spread over all 25 cells. Row-major order would pile every place into
## the top-left corner, so the order alternates rings: centre, inner diagonals,
## edges, then the four corners.
const LAYOUT_ORDER: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(2, 2), Vector2i(4, 4), Vector2i(2, 4), Vector2i(4, 2),
	Vector2i(1, 3), Vector2i(3, 1), Vector2i(5, 3), Vector2i(3, 5), Vector2i(1, 5),
	Vector2i(5, 1), Vector2i(4, 3), Vector2i(2, 5), Vector2i(5, 2), Vector2i(1, 2),
	Vector2i(3, 4), Vector2i(4, 1), Vector2i(1, 4), Vector2i(2, 1), Vector2i(5, 4),
	Vector2i(2, 3), Vector2i(4, 5), Vector2i(1, 1), Vector2i(3, 2), Vector2i(5, 5),
]

const TEMPLATE_SPECS := {
	1: {
		"boss_id": "boss_petalfall",
		"boss_title": "凋樱剑主",
		"boss_cell": Vector2i(5, 5),
		"battles": ["B001", "B004", "B007", "B009"],
		"battle_titles": ["林间巡逻", "花影追猎", "逐风围猎", "樱落之前"],
		"elite_id": "E-B001",
		"elite_title": "绯樱巡狩",
		"fixed_events": ["lost_traveler", "empty_camp", "unsent_letter"],
		"fixed_event_titles": ["失落的旅人", "无人的营地", "没有寄出的信"],
	},
	2: {
		"boss_id": "boss_thousand_boughs",
		"boss_title": "千枝神将",
		"boss_cell": Vector2i(5, 3),
		"battles": ["B002", "B005", "B008", "B010"],
		"battle_titles": ["花径伏击", "春蚀低语", "无声花阵", "永春守望"],
		"elite_id": "E-B003",
		"elite_title": "古木壁垒",
		"fixed_events": ["stranded_caravan", "unworshipped_shrine", "unsent_letter"],
		"fixed_event_titles": ["受困的商队", "无人祭拜的神龛", "没有寄出的信"],
		# §9.2: 模板2 moves 没有寄出的信 to (5,4) so it sits beside the boss.
		"anchor_event": "unsent_letter",
		"anchor_cell": Vector2i(5, 4),
	},
	3: {
		"boss_id": "boss_spring_echo",
		"boss_title": "春痕回响",
		"boss_cell": Vector2i(4, 5),
		"battles": ["B003", "B006", "B011", "B012"],
		"battle_titles": ["古道守卫", "枯木阵线", "双翼夹击", "守望者的阵地"],
		"elite_id": "E-B005",
		"elite_title": "永春镇守",
		"fixed_events": ["old_contract", "beyond_stone_door", "unsent_letter"],
		"fixed_event_titles": ["旧时代的商契", "石门之后", "没有寄出的信"],
	},
}

## §10.3 shared pool. Each template draws one and excludes its own fixed events.
const RANDOM_EVENT_POOL: Array[String] = [
	"sealed_chest",
	"forest_noise",
	"mysterious_collector",
	"unworshipped_shrine",
	"stranded_caravan",
	"lost_traveler",
]

const RANDOM_EVENT_TITLES := {
	"sealed_chest": "被封存的箱子",
	"forest_noise": "林间的异响",
	"mysterious_collector": "神秘收藏家",
	"unworshipped_shrine": "无人祭拜的神龛",
	"stranded_caravan": "受困的商队",
	"lost_traveler": "失落的旅人",
}

## The order places are handed out. Interleaved so battles do not all sit in the
## middle and the shop is not the last thing on the board.
const SLOT_ORDER: Array[String] = [
	"battle_1", "battle_2", "event_1", "elite", "battle_3",
	"event_2", "shop", "battle_4", "event_3", "event_random",
]


static func template_ids() -> Array[int]:
	return [1, 2, 3]


static func has_template(template_id: int) -> bool:
	return TEMPLATE_SPECS.has(template_id)


## §9.1: the run draws one template at the start. Deterministic on the seed so a
## resumed run can never silently swap boards.
static func template_for_seed(seed_value: int) -> int:
	var ids := template_ids()
	return ids[posmod(seed_value, ids.size())]


static func build(template_id: int) -> SpringMapTemplate:
	var spec: Dictionary = TEMPLATE_SPECS.get(template_id, {})
	if spec.is_empty():
		return null

	var template := SpringMapTemplate.new()
	template.template_id = template_id
	template.boss_cell = spec["boss_cell"]
	template.start_cell = START_CELL

	var used: Dictionary = {START_CELL: true}
	var boss_place := SpringPlace.create(&"boss", SpringPlace.Kind.BOSS, spec["boss_cell"], spec["boss_title"], StringName(spec["boss_id"]))
	template.add_place(boss_place)
	used[spec["boss_cell"]] = true

	# §9.2 anchor (模板2 only). Reserve the cell first so the slot order cannot
	# hand it to a battle.
	var anchored_event: String = str(spec.get("anchor_event", ""))
	if not anchored_event.is_empty():
		var anchor_cell: Vector2i = spec["anchor_cell"]
		var anchor_title: String = RANDOM_EVENT_TITLES.get(anchored_event, anchored_event)
		template.add_place(SpringPlace.create(&"event_3", SpringPlace.Kind.EVENT, anchor_cell, anchor_title, StringName(anchored_event)))
		used[anchor_cell] = true

	for slot in SLOT_ORDER:
		var cell := _next_free_cell(used)
		if cell == Vector2i(-1, -1):
			break
		var place := _make_place(slot, cell, spec, anchored_event)
		if place == null:
			continue
		template.add_place(place)
		used[cell] = true
	return template


static func _next_free_cell(used: Dictionary) -> Vector2i:
	for cell in LAYOUT_ORDER:
		if not used.has(cell):
			return cell
	return Vector2i(-1, -1)


static func _make_place(slot: String, cell: Vector2i, spec: Dictionary, anchored_event: String) -> SpringPlace:
	var battles: Array = spec["battles"]
	var titles: Array = spec["battle_titles"]
	match slot:
		"battle_1", "battle_2", "battle_3", "battle_4":
			var index: int = int(slot.substr(7, 1)) - 1
			return SpringPlace.create(StringName(slot), SpringPlace.Kind.BATTLE, cell, str(titles[index]), StringName(battles[index]))
		"elite":
			return SpringPlace.create(&"elite", SpringPlace.Kind.ELITE, cell, str(spec["elite_title"]), StringName(spec["elite_id"]))
		"shop":
			# §9.4: a shop may be entered again, so it is the only non-one-shot place.
			return SpringPlace.create(&"shop", SpringPlace.Kind.SHOP, cell, "春市", &"spring_shop", false)
		"event_1", "event_2", "event_3":
			var index: int = int(slot.substr(6, 1)) - 1
			var events: Array = spec["fixed_events"]
			var event_titles: Array = spec["fixed_event_titles"]
			var event_id: String = str(events[index])
			if event_id == anchored_event:
				return null
			return SpringPlace.create(StringName(slot), SpringPlace.Kind.EVENT, cell, str(event_titles[index]), StringName(event_id))
		"event_random":
			# Identity is drawn by the run (§10.3); the slot only reserves the cell.
			return SpringPlace.create(&"event_random", SpringPlace.Kind.EVENT, cell, "未知事件", &"", true)
	return null


## The events this template may still draw into its random slot: the shared pool
## minus whatever the template already fixed.
static func random_candidates(template_id: int) -> Array[String]:
	var candidates: Array[String] = []
	var spec: Dictionary = TEMPLATE_SPECS.get(template_id, {})
	var fixed_events: Array = spec.get("fixed_events", [])
	for event_id in RANDOM_EVENT_POOL:
		if not fixed_events.has(event_id):
			candidates.append(event_id)
	return candidates


static func event_title(event_id: String) -> String:
	return str(RANDOM_EVENT_TITLES.get(event_id, event_id))
