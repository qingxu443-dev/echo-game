class_name CustomGrid
extends Control

signal pressed(cell: Vector2i, button: int)
signal dragged(cell: Vector2i)
signal released(cell: Vector2i)
var design: CustomLevelData
var selected := Vector2i(-1, -1)
var hovered := Vector2i(-1, -1)
var dragging: bool = false
var portraits: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	mouse_exited.connect(func(): hovered = Vector2i(-1, -1); queue_redraw())


func board_rect() -> Rect2:
	var dimensions := design.size() if design != null else Vector2i(8, 8)
	var edge := minf(58, minf((size.x - 60) / dimensions.x, (size.y - 70) / dimensions.y))
	var bounds := Vector2(dimensions) * edge
	return Rect2((size - bounds) * 0.5, bounds)


func cell_rect(cell: Vector2i) -> Rect2:
	var rect := board_rect()
	var edge := rect.size.x / design.size().x
	return Rect2(rect.position + Vector2(cell) * edge, Vector2.ONE * edge)


func cell_at(pos: Vector2) -> Vector2i:
	if design == null or not board_rect().has_point(pos): return Vector2i(-1, -1)
	var rect := board_rect()
	return Vector2i(floor((pos.x - rect.position.x) / (rect.size.x / design.size().x)), floor((pos.y - rect.position.y) / (rect.size.y / design.size().y)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var cell := cell_at(event.position)
		if event.pressed:
			dragging = event.button_index == MOUSE_BUTTON_LEFT
			if cell.x >= 0: pressed.emit(cell, event.button_index)
		elif event.button_index == MOUSE_BUTTON_LEFT and dragging:
			dragging = false
			released.emit(cell)
		accept_event()
	elif event is InputEventMouseMotion:
		var cell := cell_at(event.position)
		if cell != hovered:
			hovered = cell
			if dragging and cell.x >= 0: dragged.emit(cell)
			queue_redraw()


func _draw() -> void:
	if design == null: return
	var font := ThemeDB.fallback_font
	var rect := board_rect()
	draw_rect(rect.grow(10), Color("#111922"))
	for y in range(design.size().y):
		for x in range(design.size().x):
			var cell := Vector2i(x, y)
			var tile := cell_rect(cell).grow(-2)
			draw_rect(tile, Color("#273441") if (x + y) % 2 == 0 else Color("#22303b"))
			draw_rect(tile, Color("#3e4c58"), false)
			if design.data.walls.has([x, y]):
				draw_rect(tile.grow(-6), Color("#5b6267"))
				draw_line(tile.position + Vector2(6, 6), tile.position + Vector2(tile.size.x - 6, 6), UiPalette.GOLD, 2)
				draw_line(tile.position + Vector2(6, tile.size.y * 0.5), tile.position + Vector2(tile.size.x - 6, tile.size.y * 0.5), Color("#394650"), 2)
			elif design.data.chests.has([x, y]):
				var chest := tile.grow(-11)
				draw_rect(chest, Color("#806d43"))
				draw_rect(chest, UiPalette.GOLD_LIGHT, false, 1.5)
				draw_line(chest.position + Vector2(0, chest.size.y * 0.4), chest.position + Vector2(chest.size.x, chest.size.y * 0.4), UiPalette.GOLD_PALE, 2)
			var unit := design.unit_at(cell)
			if not unit.is_empty(): _draw_unit(tile, unit)
			if cell == hovered: draw_rect(tile, Color(1, 1, 1, 0.4), false, 1.5)
			if cell == selected: draw_rect(tile.grow(1), UiPalette.CYAN, false, 2.5)
	for x in range(design.size().x):
		var tile := cell_rect(Vector2i(x, 0))
		draw_string(font, Vector2(tile.get_center().x - 4, rect.position.y - 13), str(x + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiPalette.TEXT_DIM)
	for y in range(design.size().y):
		var tile := cell_rect(Vector2i(0, y))
		draw_string(font, Vector2(rect.position.x - 24, tile.get_center().y + 4), str(y + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiPalette.TEXT_DIM)


func _draw_unit(rect: Rect2, unit: Dictionary) -> void:
	var hero: bool = unit.kind == "hero"
	var sheet = CharacterCatalog.get_definition(unit.id) if hero else EnemyCatalog.get_definition(unit.id)
	var color := UiPalette.CYAN if hero else (UiPalette.GOLD_LIGHT if sheet.tier == 2 else Color("#cda0d8") if sheet.tier == 1 else Color("#de8e7a"))
	draw_rect(rect.grow(-3), Color(color, 0.16))
	draw_rect(rect.grow(-3), color, false, 1.5)
	var id: String = unit.id
	if not portraits.has(id):
		var path := "res://assets/actors/portraits/%s.png" % id
		portraits[id] = load(path) if ResourceLoader.exists(path) else null
	var icon: Texture2D = portraits[id]
	if icon != null:
		draw_texture_rect(icon, Rect2(rect.position + Vector2(9, 4), Vector2(rect.size.x - 18, rect.size.y - 18)), false)
	else:
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x * 0.5 - 12, rect.size.y * 0.5 + 3), str(sheet.glyph), HORIZONTAL_ALIGNMENT_LEFT, -1, 23, color)
	var text := str(unit.health) if int(unit.health) < 10000 else "%.1f万" % (float(unit.health) / 10000.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, rect.size.y - 5), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 10, color)
