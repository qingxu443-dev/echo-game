extends Control

## Chapter hub for 春之境 · 未尽之春.
## The chapter screen is deliberately separate from the exploration map:
## browsing the compendia never creates or mutates a run.

const LOBBY_SCENE_PATH := "res://scenes/lobby/lobby.tscn"
const MAP_SCENE_PATH := "res://scenes/spring/spring_map.tscn"
const PORTRAIT_PATH := "res://assets/actors/portraits/sakura.png"

const CollectibleCatalogScript = preload("res://scripts/spring/spring_collectible_catalog.gd")
const RelicCatalogScript = preload("res://scripts/spring/spring_relic_catalog.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")
const EnemySkillCatalogScript = preload("res://scripts/battle/enemy_skill_catalog.gd")
const MemoryThreadScript = preload("res://scripts/spring/spring_memory_thread.gd")
const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")

const PAGE_HOME := "home"
const PAGE_COLLECTIBLES := "collectibles"
const PAGE_ENEMIES := "enemies"
const PAGE_STORY := "story"

const ACTION_LABELS := {
	"charged_strike": "蓄力横扫",
	"basic_melee": "近战斩击",
	"pursuit": "追击与走位",
	"aimed_shot": "贯通狙击",
	"light_shot": "点射",
	"ground_pulse": "裂地脉冲",
	"echo_bolt": "回声弹",
	"ward_ally": "古木壁垒",
	"ward_stance": "结界守护",
	"lock_on": "锁命",
	"locked_shot": "锁命箭",
	"shadow_raid": "逐影突袭",
	"rot_curse": "腐樱诅咒",
	"blight_field": "樱落领域",
	"spring_bloom": "春痕绽放",
	"sakura_shock": "樱庭震荡",
}

var page: String = PAGE_HOME
var collectible_filter: String = "全部"
var enemy_filter: String = "普通"
var selected_index: int = 0
var list_scroll: int = 0
var selected_mode: String = "normal"
var confirm_open: bool = false
var active_run: bool = false
var active_run_hard: bool = false
var active_run_stamina: int = 0
var status_notice: String = ""
var elapsed: float = 0.0
var portrait: Texture2D
var petals: Array[Dictionary] = []
var scene_change: Callable = Callable()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	portrait = _load_texture(PORTRAIT_PATH)
	_init_petals()
	refresh_expedition_state()
	queue_redraw()


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var texture = ResourceLoader.load(path)
		if texture is Texture2D:
			return texture
	return null


func _init_petals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261128
	for i in range(30):
		petals.append({
			"x": rng.randf_range(0.0, 1280.0),
			"y": rng.randf_range(0.0, 720.0),
			"speed": rng.randf_range(9.0, 23.0),
			"sway": rng.randf_range(0.7, 1.8),
			"phase": rng.randf_range(0.0, TAU),
			"radius": rng.randf_range(1.5, 3.4),
		})


func _process(delta: float) -> void:
	elapsed += delta
	for petal in petals:
		petal.x = fposmod(float(petal.x) + sin(elapsed * float(petal.sway) + float(petal.phase)) * 7.0 * delta, maxf(size.x, 1.0))
		petal.y = float(petal.y) + float(petal.speed) * delta
		if float(petal.y) > size.y + 8.0:
			petal.y = -8.0
	queue_redraw()


func _sx() -> float:
	return maxf(1.0, size.x) / 1280.0


func _sy() -> float:
	return maxf(1.0, size.y) / 720.0


func _r(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(x * _sx(), y * _sy(), w * _sx(), h * _sy())


func back_rect() -> Rect2: return _r(28, 24, 124, 42)
func nav_collectibles_rect() -> Rect2: return _r(270, 26, 150, 42)
func nav_enemies_rect() -> Rect2: return _r(430, 26, 150, 42)
func nav_story_rect() -> Rect2: return _r(590, 26, 150, 42)
func start_rect() -> Rect2: return _r(900, 548, 340, 132)
func feature_collectibles_rect() -> Rect2: return _r(48, 548, 252, 132)
func feature_enemies_rect() -> Rect2: return _r(318, 548, 252, 132)
func feature_story_rect() -> Rect2: return _r(588, 548, 252, 132)
func modal_rect() -> Rect2: return _r(350, 180, 580, 360)
func modal_normal_rect() -> Rect2: return _r(390, 330, 235, 52)
func modal_hard_rect() -> Rect2: return _r(655, 330, 235, 52)
func modal_confirm_rect() -> Rect2: return _r(620, 438, 190, 48)
func modal_cancel_rect() -> Rect2: return _r(420, 438, 160, 48)


func refresh_expedition_state() -> void:
	active_run = false
	active_run_hard = false
	active_run_stamina = 0
	status_notice = ""
	if SpringSaveTransaction.is_pending(AtelierStash.SAVE_PATH):
		if not SpringSaveTransaction.recover(SpringRun.SAVE_PATH, AtelierStash.SAVE_PATH):
			status_notice = "出征存档尚未恢复，请返回工坊检查后重试。"
			return
	var restored := SpringRun.load_from_file(SpringRun.SAVE_PATH)
	if restored != null and not restored.exploration.finished:
		active_run = true
		active_run_hard = restored.route_plan != null and restored.route_plan.hard_mode
		active_run_stamina = restored.exploration.stamina


func collectible_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var ids: Array = CollectibleCatalogScript.COLLECTIBLES.keys()
	ids.sort()
	for raw_id in ids:
		var id := String(raw_id)
		var data: Dictionary = CollectibleCatalogScript.COLLECTIBLES[id]
		entries.append({
			"id": id,
			"name": str(data.get("name", id)),
			"desc": str(data.get("desc", "")),
			"rarity": str(data.get("rarity", "普通")),
			"kind": "藏品",
			"source": _collectible_source(str(data.get("pool", "any"))),
		})
	var relic_ids: Array = RelicCatalogScript.RELICS.keys()
	relic_ids.sort()
	for raw_id in relic_ids:
		var id := String(raw_id)
		var data: Dictionary = RelicCatalogScript.RELICS[id]
		entries.append({
			"id": id,
			"name": str(data.get("name", id)),
			"desc": str(data.get("desc", "")),
			"rarity": "遗物",
			"kind": "遗物",
			"source": "首领奖励与隐秘之地等遗物来源",
		})
	return entries


func _collectible_source(pool: String) -> String:
	match pool:
		"boss": return "首领奖励池"
		"elite": return "精英奖励池"
		_: return "春之境探索奖励、事件与商店候选"


func enemy_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	_append_enemy_group(entries, EnemyCatalogScript.SPRING_COMMON_DEFINITIONS, "普通")
	_append_enemy_group(entries, EnemyCatalogScript.SPRING_ELITE_DEFINITIONS, "精英")
	_append_enemy_group(entries, EnemyCatalogScript.SPRING_BOSS_DEFINITIONS, "首领")
	return entries


func _append_enemy_group(target: Array[Dictionary], definitions: Array, group: String) -> void:
	for definition in definitions:
		target.append({"definition": definition, "group": group, "id": String(definition.archetype_id), "name": definition.display_name_zh})


func filtered_collectibles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in collectible_entries():
		if collectible_filter == "全部" or str(entry.kind) == collectible_filter:
			result.append(entry)
	return result


func filtered_enemies() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in enemy_entries():
		if str(entry.group) == enemy_filter:
			result.append(entry)
	return result


func _selected_collectible() -> Dictionary:
	var entries := filtered_collectibles()
	if entries.is_empty():
		return {}
	return entries[clampi(selected_index, 0, entries.size() - 1)]


func _selected_enemy() -> Dictionary:
	var entries := filtered_enemies()
	if entries.is_empty():
		return {}
	return entries[clampi(selected_index, 0, entries.size() - 1)]


func open_page(next_page: String) -> void:
	page = next_page
	selected_index = 0
	list_scroll = 0
	confirm_open = false
	queue_redraw()


func return_to_lobby() -> bool:
	var error := SceneTravel.change(get_tree(), LOBBY_SCENE_PATH, "返回黄昏工坊")
	if error != OK:
		status_notice = "暂时无法返回工坊大厅。"
		queue_redraw()
		return false
	return true


func begin_expedition() -> bool:
	refresh_expedition_state()
	if not status_notice.is_empty():
		queue_redraw()
		return false
	var requested := "" if active_run else selected_mode
	return transition_to_map(requested)


func transition_to_map(requested: String) -> bool:
	var error: Error
	if scene_change.is_valid():
		error = scene_change.call(get_tree(), MAP_SCENE_PATH, "踏入春之境")
	else:
		error = SceneTravel.change(get_tree(), MAP_SCENE_PATH, "踏入春之境")
	if error != OK:
		BridgeScript.requested_mode = ""
		status_notice = "春之境暂时无法载入，请稍后重试。"
		queue_redraw()
		return false
	BridgeScript.requested_mode = requested
	return true


func _collectible_row_rect(index: int) -> Rect2:
	return _r(66, 198 + float(index - list_scroll) * 44.0, 410, 38)


func _enemy_row_rect(index: int) -> Rect2:
	return _r(66, 198 + float(index - list_scroll) * 44.0, 410, 38)


func _category_rect(index: int, enemy: bool = false) -> Rect2:
	var labels := ["普通", "精英", "首领"] if enemy else ["全部", "藏品", "遗物"]
	return _r(850 + float(index) * 124.0, 142, 112, 34)


func _move_selection(direction: int) -> void:
	var count := filtered_collectibles().size() if page == PAGE_COLLECTIBLES else filtered_enemies().size()
	if count <= 0:
		return
	selected_index = clampi(selected_index + direction, 0, count - 1)
	if selected_index < list_scroll:
		list_scroll = selected_index
	elif selected_index >= list_scroll + 8:
		list_scroll = selected_index - 7
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if confirm_open:
		if event.keycode == KEY_ESCAPE:
			confirm_open = false
			queue_redraw()
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_ESCAPE:
			if page != PAGE_HOME:
				open_page(PAGE_HOME)
			else:
				return_to_lobby()
			get_viewport().set_input_as_handled()
		KEY_UP:
			if page in [PAGE_COLLECTIBLES, PAGE_ENEMIES]:
				_move_selection(-1)
				get_viewport().set_input_as_handled()
		KEY_DOWN:
			if page in [PAGE_COLLECTIBLES, PAGE_ENEMIES]:
				_move_selection(1)
				get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if page == PAGE_HOME:
				confirm_open = true
				refresh_expedition_state()
				queue_redraw()
				get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and page in [PAGE_COLLECTIBLES, PAGE_ENEMIES]:
			list_scroll = maxi(0, list_scroll - 1)
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and page in [PAGE_COLLECTIBLES, PAGE_ENEMIES]:
			var count := filtered_collectibles().size() if page == PAGE_COLLECTIBLES else filtered_enemies().size()
			list_scroll = mini(maxi(0, count - 8), list_scroll + 1)
			queue_redraw()
			accept_event()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(event.position)
		accept_event()


func _handle_click(point: Vector2) -> void:
	if confirm_open:
		if modal_cancel_rect().has_point(point):
			confirm_open = false
		elif active_run and modal_confirm_rect().has_point(point):
			begin_expedition()
			return
		elif not active_run and modal_normal_rect().has_point(point):
			selected_mode = "normal"
		elif not active_run and modal_hard_rect().has_point(point):
			selected_mode = "hard"
		elif not active_run and modal_confirm_rect().has_point(point):
			begin_expedition()
			return
		queue_redraw()
		return
	if back_rect().has_point(point):
		if page == PAGE_HOME:
			return_to_lobby()
		else:
			open_page(PAGE_HOME)
		return
	if nav_collectibles_rect().has_point(point):
		open_page(PAGE_COLLECTIBLES)
		return
	if nav_enemies_rect().has_point(point):
		open_page(PAGE_ENEMIES)
		return
	if nav_story_rect().has_point(point):
		open_page(PAGE_STORY)
		return
	if page == PAGE_HOME:
		if feature_collectibles_rect().has_point(point):
			open_page(PAGE_COLLECTIBLES)
		elif feature_enemies_rect().has_point(point):
			open_page(PAGE_ENEMIES)
		elif feature_story_rect().has_point(point):
			open_page(PAGE_STORY)
		elif start_rect().has_point(point):
			refresh_expedition_state()
			confirm_open = true
			queue_redraw()
		return
	if page == PAGE_COLLECTIBLES:
		for i in range(3):
			if _category_rect(i).has_point(point):
				collectible_filter = ["全部", "藏品", "遗物"][i]
				selected_index = 0
				list_scroll = 0
				queue_redraw()
				return
		var entries := filtered_collectibles()
		for i in range(entries.size()):
			if _collectible_row_rect(i).has_point(point):
				selected_index = i
				queue_redraw()
				return
	elif page == PAGE_ENEMIES:
		for i in range(3):
			if _category_rect(i, true).has_point(point):
				enemy_filter = ["普通", "精英", "首领"][i]
				selected_index = 0
				list_scroll = 0
				queue_redraw()
				return
		var entries := filtered_enemies()
		for i in range(entries.size()):
			if _enemy_row_rect(i).has_point(point):
				selected_index = i
				queue_redraw()
				return


func _draw() -> void:
	var sx := _sx()
	var sy := _sy()
	var font := ThemeDB.fallback_font
	_draw_background(sx, sy)
	_draw_header(font, sx, sy)
	match page:
		PAGE_HOME: _draw_home(font, sx, sy)
		PAGE_COLLECTIBLES: _draw_collectibles(font, sx, sy)
		PAGE_ENEMIES: _draw_enemies(font, sx, sy)
		PAGE_STORY: _draw_story(font, sx, sy)
	if confirm_open:
		_draw_confirm(font, sx, sy)
	if not status_notice.is_empty():
		_draw_text(font, status_notice, 34, 708, 11, Color("#f0b7a9"), 1100)


func _draw_background(sx: float, sy: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#160f19"), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.28, 0.10, 0.18, 0.24), true)
	for i in range(12):
		var x := float(i) * 118.0 * sx
		draw_line(Vector2(x, 0), Vector2(x + 120.0 * sx, size.y), Color(0.88, 0.56, 0.62, 0.025), 1.0)
	draw_circle(Vector2(size.x * 0.78, size.y * 0.38), 260.0 * sx, Color(0.55, 0.16, 0.28, 0.12))
	draw_circle(Vector2(size.x * 0.82, size.y * 0.35), 190.0 * sx, Color(0.86, 0.39, 0.48, 0.06))
	for petal in petals:
		var p := Vector2(float(petal.x) * sx, float(petal.y) * sy)
		var r := float(petal.radius) * sy
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.7, 0), p + Vector2(0, r), p + Vector2(-r * 0.7, 0)]), Color(0.98, 0.68, 0.72, 0.36))


func _draw_header(font: Font, sx: float, sy: float) -> void:
	_draw_button(font, back_rect(), "← 返回" if page != PAGE_HOME else "← 工坊大厅", false, sx, sy, 12)
	_draw_button(font, nav_collectibles_rect(), "藏品图鉴", page == PAGE_COLLECTIBLES, sx, sy, 13)
	_draw_button(font, nav_enemies_rect(), "敌人图鉴", page == PAGE_ENEMIES, sx, sy, 13)
	_draw_button(font, nav_story_rect(), "剧情回顾", page == PAGE_STORY, sx, sy, 13)
	_draw_text(font, "ECHO  /  SPRING CHAPTER", 780, 40, 11, Color("#c99ba5"), 440, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_line(Vector2(28 * sx, 82 * sy), Vector2(1250 * sx, 82 * sy), Color(0.87, 0.60, 0.65, 0.32), 1.0)


func _draw_home(font: Font, sx: float, sy: float) -> void:
	_draw_text(font, "CHAPTER 02  ·  THE UNFINISHED SPRING", 58, 142, 13, Color("#d69aa7"), 650)
	_draw_text(font, "未尽之春", 54, 216, 48, Color("#fff0e7"), 650)
	_draw_text(font, "春之境", 58, 260, 22, Color("#e9b5bd"), 360)
	_draw_text(font, "花期没有尽头，遗失的回声仍藏在旧日花径之间。", 60, 316, 16, Color("#e0cbd0"), 600)
	_draw_text(font, "与樱一同踏上旅途，寻找散落的记忆，面对春境深处的守望者。", 60, 348, 13, Color("#bdaeb7"), 650)
	_draw_text(font, "5 × 5 探索地图   ·   普通探索   ·   困难定轨", 60, 397, 12, Color("#d8a9b0"), 650)
	if portrait != null:
		var tex_size := portrait.get_size()
		var target := Vector2(420 * sx, 450 * sy)
		var scale_f := minf(target.x / maxf(tex_size.x, 1.0), target.y / maxf(tex_size.y, 1.0))
		var drawn := tex_size * scale_f
		var pos := Vector2(770 * sx, 92 * sy) + Vector2((target.x - drawn.x) * 0.5, (target.y - drawn.y) * 0.5)
		draw_texture_rect(portrait, Rect2(pos, drawn), false)
	_draw_feature_card(font, feature_collectibles_rect(), "藏品图鉴", "查看已收录的藏品与遗物", "01", false, sx, sy)
	_draw_feature_card(font, feature_enemies_rect(), "敌人图鉴", "认识春境中的普通敌人与首领", "02", false, sx, sy)
	_draw_feature_card(font, feature_story_rect(), "剧情回顾", "重新拾起旅途中收集的记忆", "03", false, sx, sy)
	var start_label := "继续当前旅程" if active_run else "开始旅行"
	var start_sub := ("困难·定轨  /  剩余体力 %d" % active_run_stamina) if active_run and active_run_hard else (("普通探索  /  剩余体力 %d" % active_run_stamina) if active_run else "启程前确认探索方式")
	_draw_feature_card(font, start_rect(), start_label, start_sub, "→", true, sx, sy)
	if active_run:
		_draw_text(font, "已有一段未完成的旅程，启程后将继续原进度。", 602, 524, 11, Color("#d9bdc2"), 310, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_feature_card(font: Font, rect: Rect2, title: String, subtitle: String, mark: String, primary: bool, sx: float, sy: float) -> void:
	var fill := Color("#4b202f", 0.96) if primary else Color("#211923", 0.94)
	var border := Color("#e6a4ad", 0.95) if primary else Color("#91606e", 0.62)
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, 1.7 if primary else 1.0)
	_draw_text(font, mark, rect.position.x / sx + 16, rect.position.y / sy + 32, 11 if not primary else 18, Color("#f1c3c8"), 40)
	_draw_text(font, title, rect.position.x / sx + 18, rect.position.y / sy + 70, 19 if primary else 17, Color("#fff0e8"), rect.size.x / sx - 30)
	_draw_text(font, subtitle, rect.position.x / sx + 18, rect.position.y / sy + 101, 11, Color("#d5b8bf"), rect.size.x / sx - 30)


func _draw_collectibles(font: Font, sx: float, sy: float) -> void:
	_draw_text(font, "COLLECTIBLE ARCHIVE", 58, 124, 11, Color("#c58e9b"), 500)
	_draw_text(font, "藏品图鉴", 58, 160, 28, Color("#fff0e7"), 500)
	_draw_text(font, "收录当前版本已定义的藏品与遗物；未收录内容不会显示为虚构条目。", 58, 184, 11, Color("#bcaab2"), 700)
	var entries := filtered_collectibles()
	for i in range(3):
		var rect := _category_rect(i)
		_draw_button(font, rect, ["全部", "藏品", "遗物"][i], collectible_filter == ["全部", "藏品", "遗物"][i], sx, sy, 11)
	_draw_panel(_r(54, 188, 432, 390), Color("#211923"), Color("#875a68"))
	_draw_panel(_r(508, 188, 716, 390), Color("#211923"), Color("#875a68"))
	var visible_count := mini(8, maxi(0, entries.size() - list_scroll))
	for i in range(visible_count):
		var index := list_scroll + i
		var row := _collectible_row_rect(index)
		var entry: Dictionary = entries[index]
		var selected := index == selected_index
		draw_rect(row, Color("#4a2735") if selected else Color("#2b202a"), true)
		draw_rect(row, Color("#d59aa6", 0.9) if selected else Color("#6b4b58", 0.45), false, 1.0)
		_draw_text(font, str(entry.name), row.position.x / sx + 12, row.position.y / sy + 25, 13, Color("#fff0e7"), 220)
		_draw_text(font, str(entry.rarity), row.position.x / sx + 300, row.position.y / sy + 24, 10, Color("#d7aab1"), 90, HORIZONTAL_ALIGNMENT_RIGHT)
	var selected_entry := _selected_collectible()
	if selected_entry.is_empty():
		_draw_text(font, "当前分类暂无条目。", 550, 230, 16, Color("#cbb9bf"), 500)
	else:
		_draw_text(font, str(selected_entry.name), 552, 206, 25, Color("#fff0e7"), 600)
		_draw_text(font, str(selected_entry.kind) + "  ·  " + str(selected_entry.rarity), 554, 236, 12, Color("#d8a0ab"), 600)
		_draw_text(font, "档案编号  " + str(selected_entry.id), 554, 278, 11, Color("#a995a0"), 620)
		_draw_text(font, "效果说明", 554, 326, 12, Color("#e4b8bf"), 620)
		_draw_text(font, str(selected_entry.desc), 554, 356, 16, Color("#f0dfe1"), 620)
		_draw_text(font, "获取途径", 554, 412, 12, Color("#e4b8bf"), 620)
		_draw_text(font, str(selected_entry.source), 554, 440, 13, Color("#d4c0c6"), 620)
		_draw_text(font, "持有规则：被动藏品与遗物按唯一条目记录；主动消耗品规则以当前正式目录为准。", 554, 510, 11, Color("#a995a0"), 640)
	_draw_text(font, "%d 项记录  ·  鼠标滚轮或方向键浏览" % entries.size(), 66, 604, 10, Color("#a995a0"), 400)


func _draw_enemies(font: Font, sx: float, sy: float) -> void:
	_draw_text(font, "BESTIARY  /  SPRING REALM", 58, 124, 11, Color("#c58e9b"), 500)
	_draw_text(font, "敌人图鉴", 58, 160, 28, Color("#fff0e7"), 500)
	_draw_text(font, "资料直接读取当前敌人档案与技能目录。属性是当前配置值，普通敌人部分数值仍属草案。", 58, 184, 11, Color("#bcaab2"), 900)
	for i in range(3):
		var rect := _category_rect(i, true)
		_draw_button(font, rect, ["普通", "精英", "首领"][i], enemy_filter == ["普通", "精英", "首领"][i], sx, sy, 11)
	var entries := filtered_enemies()
	_draw_panel(_r(54, 188, 432, 390), Color("#211923"), Color("#875a68"))
	_draw_panel(_r(508, 142, 716, 436), Color("#211923"), Color("#875a68"))
	var visible_count := mini(8, maxi(0, entries.size() - list_scroll))
	for i in range(visible_count):
		var index := list_scroll + i
		var row := _enemy_row_rect(index)
		var entry: Dictionary = entries[index]
		var definition: EnemyDefinition = entry.definition
		var selected := index == selected_index
		draw_rect(row, Color("#4a2735") if selected else Color("#2b202a"), true)
		draw_rect(row, Color("#d59aa6") if selected else Color("#6b4b58", 0.45), false, 1.0)
		_draw_text(font, definition.display_name_zh, row.position.x / sx + 12, row.position.y / sy + 25, 13, Color("#fff0e7"), 250)
		_draw_text(font, str(entry.group), row.position.x / sx + 300, row.position.y / sy + 24, 10, Color("#d7aab1"), 90, HORIZONTAL_ALIGNMENT_RIGHT)
	if entries.is_empty():
		_draw_text(font, "当前分类暂无敌人。", 550, 230, 16, Color("#cbb9bf"), 500)
	else:
		var entry := _selected_enemy()
		var definition: EnemyDefinition = entry.definition
		_draw_text(font, definition.display_name_zh, 552, 204, 25, Color("#fff0e7"), 620)
		_draw_text(font, str(entry.group) + "  ·  " + str(definition.archetype_id), 554, 232, 11, Color("#d8a0ab"), 620)
		_draw_text(font, "生命  %d      攻击  %d      物理防御  %d      魔法抗性  %d" % [definition.health, definition.attack, definition.defense, definition.magic_resistance], 554, 276, 13, Color("#f0dfe1"), 640)
		_draw_text(font, "行动与招式", 554, 326, 12, Color("#e4b8bf"), 620)
		var actions: Array[String] = []
		for action_id in definition.actions:
			var skill = EnemySkillCatalogScript.get_skill(action_id)
			if skill != null:
				actions.append(str(skill.label_zh))
		_draw_text(font, "、".join(actions), 554, 356, 15, Color("#f0dfe1"), 640)
		_draw_text(font, "移动能力  每次最多移动 %d 格" % definition.move_steps, 554, 414, 12, Color("#d4c0c6"), 620)
		if definition.skill_damage > 0:
			_draw_text(font, "专属技能基础伤害  %d" % definition.skill_damage, 554, 444, 12, Color("#d4c0c6"), 620)
		if definition.ward_shield > 0:
			_draw_text(font, "守护护盾  %d" % definition.ward_shield, 554, 474, 12, Color("#d4c0c6"), 620)
		if definition.curse_defense_down > 0:
			_draw_text(font, "防御削减  %d" % definition.curse_defense_down, 554, 504, 12, Color("#d4c0c6"), 620)
	_draw_text(font, "%d 名敌人  ·  鼠标滚轮或方向键浏览" % entries.size(), 66, 604, 10, Color("#a995a0"), 400)


func _draw_story(font: Font, sx: float, sy: float) -> void:
	_draw_text(font, "MEMORY THREAD", 58, 124, 11, Color("#c58e9b"), 500)
	_draw_text(font, "剧情回顾", 58, 160, 28, Color("#fff0e7"), 500)
	_draw_panel(_r(54, 188, 1170, 390), Color("#211923"), Color("#875a68"))
	_draw_text(font, "未尽之春 · 归乡记忆线", 88, 236, 22, Color("#fff0e7"), 700)
	_draw_text(font, "樱沿着旧花径寻找散落的记忆。旅人、神龛与一封未寄出的信，留下了彼此呼应的片段。", 90, 278, 14, Color("#d4c0c6"), 1050)
	var run := SpringRun.load_from_file(SpringRun.SAVE_PATH)
	var log: Dictionary = run.event_log if run != null else {}
	var fragments := MemoryThreadScript.collected(log)
	_draw_text(font, "本次旅程已拾起的记忆  %d / 3" % fragments.size(), 90, 344, 14, Color("#e4b8bf"), 800)
	for i in range(3):
		var y := 390.0 + float(i) * 48.0
		var labels := ["旅人遗失的方向", "无人供奉的神龛", "未曾寄出的信"]
		var event_ids := ["lost_traveler", "unworshipped_shrine", "unsent_letter"]
		var record: Dictionary = log.get(event_ids[i], {})
		var found := not record.is_empty() and int(record.get("option", -1)) == 0
		_draw_text(font, ("✓  " if found else "◇  ") + labels[i], 100, y, 14, Color("#f0dfe1") if found else Color("#a995a0"), 400)
	_draw_text(font, MemoryThreadScript.reflection_for(log) if not fragments.is_empty() else "尚未拾起记忆片段。开始旅行后，部分事件选择会留下可回顾的记忆。", 90, 544, 12, Color("#d8aab2"), 1050)


func _draw_confirm(font: Font, sx: float, sy: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.04, 0.76), true)
	var panel := modal_rect()
	draw_rect(panel, Color("#211923"), true)
	draw_rect(panel, Color("#d58d9c"), false, 1.8)
	_draw_text(font, "踏入春之境", 410, 236, 25, Color("#fff0e7"), 460, HORIZONTAL_ALIGNMENT_CENTER)
	if active_run:
		_draw_text(font, "检测到尚未结束的旅程。继续后将保留原地图、资源与探索进度。", 405, 286, 13, Color("#d4c0c6"), 470, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(font, "当前模式：%s   ·   剩余探索体力：%d" % ["困难·定轨" if active_run_hard else "普通探索", active_run_stamina], 405, 318, 12, Color("#e4b8bf"), 470, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_draw_text(font, "选择本次旅程的探索方式，确认后正式进入春之境。", 405, 286, 13, Color("#d4c0c6"), 470, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_button(font, modal_normal_rect(), "普通探索", selected_mode == "normal", sx, sy, 13)
		_draw_button(font, modal_hard_rect(), "困难 · 定轨", selected_mode == "hard", sx, sy, 13)
	_draw_button(font, modal_cancel_rect(), "再准备一下", false, sx, sy, 12)
	_draw_button(font, modal_confirm_rect(), "继续旅程" if active_run else "正式启程", true, sx, sy, 13)


func _draw_panel(rect: Rect2, fill: Color, border: Color) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, 1.2)


func _draw_button(font: Font, rect: Rect2, label: String, selected: bool, sx: float, sy: float, font_size: int) -> void:
	draw_rect(rect, Color("#55303d") if selected else Color("#2b202a"), true)
	draw_rect(rect, Color("#e1a0aa") if selected else Color("#815965"), false, 1.2)
	draw_string(font, rect.position + Vector2(0, rect.size.y * 0.64), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, roundi(float(font_size) * sy), Color("#fff0e7") if selected else Color("#d9c4ca"))


func _draw_text(font: Font, value: String, x: float, y: float, font_size: int, color: Color, width: float = 600.0, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, Vector2(x * _sx(), y * _sy()), value, alignment, width * _sx(), roundi(float(font_size) * _sy()), color)
