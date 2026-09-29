class_name TerrainLayer
extends Node2D

const RIVER_COLOR := Color("#2EA2FF")
const LAKE_COLOR := Color("#1565C0")

var terrains: Array[Dictionary] = []
var active_terrain := -1
var brush := "forest"
var show_active := false
var highlighted: Array[int] = []
var squares: SquareLayer
var cells: Dictionary = {}
var cells_dirty := true


func latest(kind: String) -> int:
	for index in range(terrains.size() - 1, -1, -1):
		if terrains[index]["kind"] == kind:
			return index
	return -1


func begin_path(kind: String) -> void:
	if active_terrain >= 0 and active_terrain < terrains.size():
		var existing: PackedVector2Array = terrains[active_terrain]["points"]
		if existing.is_empty():
			terrains.remove_at(active_terrain)
	terrains.append({
		"kind": kind,
		"points": PackedVector2Array()
	})
	active_terrain = terrains.size() - 1
	brush = kind


func place_point(point: Vector2) -> bool:
	if brush == "forest":
		if squares.blocks_rect(forest_rect(point)):
			return false
		terrains.append({
			"kind": "forest",
			"points": PackedVector2Array([point])
		})
		active_terrain = terrains.size() - 1
	elif brush == "mountain":
		if squares.blocks_rect(mountain_rect(point)):
			return false
		terrains.append({
			"kind": "mountain",
			"points": PackedVector2Array([point])
		})
		active_terrain = terrains.size() - 1
	else:
		var existing := PackedVector2Array()
		if active_terrain >= 0 and active_terrain < terrains.size() and terrains[active_terrain]["kind"] == brush:
			existing = terrains[active_terrain]["points"]
		if not existing.is_empty() and existing[existing.size() - 1].distance_to(point) < 10.0:
			return false
		if brush == "river" and squares.blocks_river(existing, point):
			return false
		if brush == "lake":
			var trial := PackedVector2Array(existing)
			trial.append(point)
			if squares.blocks_polygon(BoardGeometry.lake_outline(trial)):
				return false
		if active_terrain < 0 or active_terrain >= terrains.size() or terrains[active_terrain]["kind"] != brush:
			begin_path(brush)
		var feature: Dictionary = terrains[active_terrain]
		var points: PackedVector2Array = feature["points"]
		points.append(point)
		feature["points"] = points
		terrains[active_terrain] = feature
	cells_dirty = true
	return true


func points_of(index: int) -> PackedVector2Array:
	return PackedVector2Array(terrains[index]["points"])


func set_points(index: int, points: PackedVector2Array) -> void:
	var feature: Dictionary = terrains[index]
	feature["points"] = points
	terrains[index] = feature


func remove_descending(indices: Array[int]) -> void:
	var ordered: Array[int] = []
	ordered.assign(indices)
	ordered.sort()
	for index in range(ordered.size() - 1, -1, -1):
		var terrain_index: int = ordered[index]
		terrains.remove_at(terrain_index)
		if active_terrain == terrain_index:
			active_terrain = -1
		elif active_terrain > terrain_index:
			active_terrain -= 1
	cells_dirty = true


func clear_all() -> void:
	terrains.clear()
	active_terrain = -1
	cells.clear()
	cells_dirty = false


func find_at(point: Vector2) -> int:
	var best := -1
	var best_rank := -1
	for index in terrains.size():
		if not contains(terrains[index], point):
			continue
		var rank := 0
		match String(terrains[index]["kind"]):
			"river":
				rank = 1
			"forest":
				rank = 2
			"mountain":
				rank = 3
		if rank >= best_rank:
			best = index
			best_rank = rank
	return best


func indices_in_rect(rect: Rect2) -> Array[int]:
	var hits: Array[int] = []
	for index in terrains.size():
		if hits_rect(terrains[index], rect):
			hits.append(index)
	return hits


func ensure_cells() -> void:
	if not cells_dirty:
		return
	cells.clear()
	for feature in terrains:
		var points: PackedVector2Array = feature["points"]
		if points.is_empty():
			continue
		var kind: String = feature["kind"]
		if kind == "forest":
			mark_blocked_rect(forest_rect(points[0]).grow(BoardMetrics.ROUTE_CLEARANCE))
		elif kind == "mountain":
			mark_blocked_rect(mountain_rect(points[0]).grow(BoardMetrics.ROUTE_CLEARANCE))
		elif kind == "river":
			mark_blocked_river(points)
		elif kind == "lake":
			mark_blocked_lake(points)
	cells_dirty = false


func forest_rect(origin: Vector2) -> Rect2:
	return Rect2(origin + Vector2(-30, -32), Vector2(58, 42))


func mountain_rect(origin: Vector2) -> Rect2:
	return Rect2(origin + Vector2(-44, -36), Vector2(86, 60))


func hits_rect(feature: Dictionary, rect: Rect2) -> bool:
	var points: PackedVector2Array = feature["points"]
	if points.is_empty():
		return false
	var kind: String = feature["kind"]
	if kind == "forest":
		return rect.intersects(forest_rect(points[0]))
	if kind == "mountain":
		return rect.intersects(mountain_rect(points[0]))
	if kind == "river":
		var reach := rect.grow(BoardMetrics.RIVER_HALF_WIDTH)
		if points.size() == 1:
			return reach.has_point(points[0])
		for index in points.size() - 1:
			if BoardGeometry.segment_hits_rect(points[index], points[index + 1], reach):
				return true
		return false
	if kind == "lake":
		return BoardGeometry.polygon_hits_rect(BoardGeometry.lake_outline(points), rect)
	return false


func contains(feature: Dictionary, point: Vector2) -> bool:
	var points: PackedVector2Array = feature["points"]
	if points.is_empty():
		return false
	var kind: String = feature["kind"]
	if kind == "forest":
		return forest_rect(points[0]).has_point(point)
	if kind == "mountain":
		return mountain_rect(points[0]).has_point(point)
	if kind == "river":
		return river_contains(points, point)
	if kind == "lake":
		return BoardGeometry.point_in_polygon(point, BoardGeometry.lake_outline(points))
	return false


func river_contains(points: PackedVector2Array, point: Vector2) -> bool:
	if points.size() == 1:
		return points[0].distance_to(point) <= BoardMetrics.RIVER_HALF_WIDTH
	for index in points.size() - 1:
		if BoardGeometry.distance_to_segment(point, points[index], points[index + 1]) <= BoardMetrics.RIVER_HALF_WIDTH:
			return true
	return false


func mark_blocked_rect(rect: Rect2) -> void:
	var min_cell := BoardMetrics.world_to_cell(rect.position)
	var max_cell := BoardMetrics.world_to_cell(rect.end)
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			cells[Vector2i(x, y)] = true


func mark_blocked_river(points: PackedVector2Array) -> void:
	var reach := BoardMetrics.RIVER_HALF_WIDTH + BoardMetrics.ROUTE_CLEARANCE
	if points.size() == 1:
		mark_blocked_rect(Rect2(points[0] - Vector2.ONE * reach, Vector2.ONE * reach * 2.0))
		return
	for index in points.size() - 1:
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var min_point := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
		var max_point := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
		var min_cell := BoardMetrics.world_to_cell(min_point)
		var max_cell := BoardMetrics.world_to_cell(max_point)
		for x in range(min_cell.x, max_cell.x + 1):
			for y in range(min_cell.y, max_cell.y + 1):
				var cell := Vector2i(x, y)
				if cells.has(cell):
					continue
				if BoardGeometry.distance_to_segment(BoardMetrics.cell_to_world(cell), a, b) <= reach:
					cells[cell] = true


func mark_blocked_lake(points: PackedVector2Array) -> void:
	var outline := BoardGeometry.lake_outline(points)
	if outline.size() < 3:
		return
	var min_point := outline[0]
	var max_point := outline[0]
	for outline_point in outline:
		min_point.x = minf(min_point.x, outline_point.x)
		min_point.y = minf(min_point.y, outline_point.y)
		max_point.x = maxf(max_point.x, outline_point.x)
		max_point.y = maxf(max_point.y, outline_point.y)
	var pad := Vector2.ONE * BoardMetrics.ROUTE_CLEARANCE
	var min_cell := BoardMetrics.world_to_cell(min_point - pad)
	var max_cell := BoardMetrics.world_to_cell(max_point + pad)
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell := Vector2i(x, y)
			var world := BoardMetrics.cell_to_world(cell)
			if BoardGeometry.point_in_polygon(world, outline) or BoardGeometry.point_near_polygon(world, outline, BoardMetrics.ROUTE_CLEARANCE):
				cells[cell] = true


func _draw() -> void:
	for feature in terrains:
		if feature["kind"] == "lake":
			draw_lake(feature["points"])
	for feature in terrains:
		if feature["kind"] == "river":
			draw_river(feature["points"])
	for feature in terrains:
		if feature["kind"] == "forest":
			draw_forest(feature["points"])
	for feature in terrains:
		if feature["kind"] == "mountain":
			draw_mountain(feature["points"])

	if show_active:
		draw_mark(active_terrain)
	for index in highlighted:
		if show_active and index == active_terrain:
			continue
		draw_mark(index)


func draw_mark(index: int) -> void:
	if index < 0 or index >= terrains.size():
		return
	var feature: Dictionary = terrains[index]
	var points: PackedVector2Array = feature["points"]
	if points.is_empty():
		return
	var kind: String = feature["kind"]
	if kind == "forest":
		draw_rect(forest_rect(points[0]), Color.WHITE, false, 2.0)
	elif kind == "mountain":
		draw_rect(mountain_rect(points[0]), Color.WHITE, false, 2.0)
	else:
		for point in points:
			draw_circle(point, 3.2, Color.WHITE)


func draw_forest(points: PackedVector2Array) -> void:
	if points.is_empty():
		return
	var origin := points[0]
	# A small stand of flat pines, back to front, so each one reads as a tree.
	draw_pine(origin + Vector2(-16, 2), 26.0, 11.0, Color("#2E7D32"))
	draw_pine(origin + Vector2(15, 4), 22.0, 10.0, Color("#388E3C"))
	draw_pine(origin + Vector2(-1, 7), 36.0, 13.0, Color("#1B5E20"))


func draw_pine(ground: Vector2, height: float, half_width: float, leaf: Color) -> void:
	var trunk_height := 8.0
	var trunk_half := 2.2
	fill_polygon(PackedVector2Array([
		ground + Vector2(-trunk_half, 0),
		ground + Vector2(trunk_half, 0),
		ground + Vector2(trunk_half, -trunk_height),
		ground + Vector2(-trunk_half, -trunk_height)
	]), Color("#6D4C41"))
	var canopy_base := ground + Vector2(0, -trunk_height * 0.35)
	fill_polygon(PackedVector2Array([
		canopy_base + Vector2(-half_width, 0),
		canopy_base + Vector2(half_width, 0),
		canopy_base + Vector2(0, -(height - trunk_height))
	]), leaf)


func draw_river(points: PackedVector2Array) -> void:
	if points.is_empty():
		return
	if points.size() == 1:
		paint_circle(points[0], BoardMetrics.RIVER_HALF_WIDTH, RIVER_COLOR)
		return
	var line := BoardGeometry.smooth_curve(points)
	paint_circle(line[0], BoardMetrics.RIVER_HALF_WIDTH, RIVER_COLOR)
	paint_circle(line[line.size() - 1], BoardMetrics.RIVER_HALF_WIDTH, RIVER_COLOR)
	fill_polygon(BoardGeometry.ribbon(line, BoardMetrics.RIVER_HALF_WIDTH), RIVER_COLOR)


func draw_lake(points: PackedVector2Array) -> void:
	var outline := BoardGeometry.lake_outline(points)
	if outline.size() < 3:
		return
	fill_polygon(outline, LAKE_COLOR)
	var shore := outline.duplicate()
	shore.append(outline[0])
	draw_polyline(shore, LAKE_COLOR, 2.0, true)


func draw_mountain(points: PackedVector2Array) -> void:
	if points.is_empty():
		return
	var origin := points[0]
	fill_polygon(PackedVector2Array([
		origin + Vector2(-42, 16),
		origin + Vector2(-18, 6),
		origin + Vector2(8, 4),
		origin + Vector2(40, 14),
		origin + Vector2(22, 22),
		origin + Vector2(-28, 22)
	]), Color("#243038"))
	draw_peak(origin + Vector2(-8, 2), 30.0, 15.0, Color("#90A4AE"), Color("#607D8B"), Color("#ECEFF1"))
	draw_peak(origin + Vector2(24, 8), 24.0, 13.0, Color("#78909C"), Color("#455A64"), Color("#F7F9FA"))
	draw_peak(origin + Vector2(-20, 10), 28.0, 16.0, Color("#B0BEC5"), Color("#546E7A"), Color("#FFFFFF"))
	draw_peak(origin + Vector2(4, 12), 46.0, 22.0, Color("#CFD8DC"), Color("#546E7A"), Color("#FFFFFF"))


func draw_peak(base: Vector2, height: float, half_width: float, lit: Color, shaded: Color, snow: Color) -> void:
	var tip := base + Vector2(0, -height)
	var left := base + Vector2(-half_width, 0)
	var right := base + Vector2(half_width * 0.9, 1.5)
	var ridge := left.lerp(right, 0.46)
	fill_polygon(PackedVector2Array([left, tip, ridge]), lit)
	fill_polygon(PackedVector2Array([ridge, tip, right]), shaded)
	fill_polygon(PackedVector2Array([
		tip,
		tip.lerp(left, 0.32),
		tip.lerp(ridge, 0.34),
		tip.lerp(right, 0.26)
	]), snow)


func paint_circle(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color, true, -1.0, true)


func fill_polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(color)
	draw_polygon(points, colors)
