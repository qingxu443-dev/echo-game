class_name BoardOverlayRegion
extends RefCounted

const P = preload("res://scripts/ui/theme_palette.gd")
## Solid, muted fills keep the same visible colour on light/dark slabs and
## overlapping intents. Selection takes fill priority; threat outlines remain.
const ATTACK_FILL := Color("#66363c")
const ATTACK_LINE := Color("#ff7373")
const MOVE_FILL := Color("#31564b")
const MOVE_LINE := Color("#83e3b5")
const SKILL_FILL := Color("#b3a475")
const SKILL_LINE := Color("#ffe6a3")


## CONTRACT: _test_region_boundaries_and_colours
static func boundary_edges(cells: Dictionary) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var neighbours := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for cell in cells:
		var points := P.cell_diamond(cell)
		var view_cell := P.to_view_cell(cell)
		for index in range(4):
			var adjacent := P.from_view_cell(view_cell + neighbours[index])
			if not cells.has(adjacent): result.append(PackedVector2Array([points[index], points[(index + 1) % 4]]))
	return result


static func draw_fill(canvas: CanvasItem, cells: Dictionary, colour: Color) -> void:
	for cell in cells:
		var tile := P.cell_diamond(cell)
		canvas.draw_colored_polygon(tile, colour)
		# Subtle cell boundaries keep distances countable inside a solid region.
		P.draw_polyline_closed(canvas, tile, colour.lightened(0.12), 0.8)


static func draw_boundary(canvas: CanvasItem, cells: Dictionary, colour: Color, width: float = 2.4) -> void:
	for edge in boundary_edges(cells): canvas.draw_line(edge[0], edge[1], colour, width, true)


static func draw(canvas: CanvasItem, cells: Dictionary, fill: Color, line: Color) -> void:
	draw_fill(canvas, cells, fill)
	draw_boundary(canvas, cells, line)
