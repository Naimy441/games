class_name RouteLayer
extends Node2D

var squares: SquareLayer
var terrain: TerrainLayer
var dirty := true
var cached_routes: Array[Dictionary] = []


func _draw() -> void:
	if dirty:
		cached_routes = build_routes()
		dirty = false

	for route in cached_routes:
		draw_dotted_route(route["points"], route["color"])


func build_routes() -> Array[Dictionary]:
	terrain.ensure_cells()

	var groups: Dictionary = {}
	var routes: Array[Dictionary] = []

	for index in squares.squares.size():
		var letter: String = squares.squares[index]["letter"]
		if letter == "":
			continue
		if not groups.has(letter):
			groups[letter] = []
		groups[letter].append(index)

	for letter in groups:
		var indices: Array = groups[letter]
		if indices.size() < 2:
			continue
		var color: Color = SquareLayer.color_for(letter)
		for edge in minimum_spanning_tree(indices):
			var route := find_route(edge[0], edge[1])
			if route.size() >= 2:
				routes.append({
					"points": route,
					"color": color
				})
	return routes


func minimum_spanning_tree(indices: Array) -> Array:
	# Prim's algorithm: connects every matching square without redundant links.
	var edges: Array = []
	var connected: Array = [indices[0]]
	var remaining: Array = indices.slice(1)

	while not remaining.is_empty():
		var best_from := -1
		var best_to := -1
		var best_distance := 1e30

		for from_index in connected:
			var from_position: Vector2 = squares.squares[from_index]["position"]
			for to_index in remaining:
				var to_position: Vector2 = squares.squares[to_index]["position"]
				var distance := from_position.distance_squared_to(to_position)
				if distance < best_distance:
					best_distance = distance
					best_from = from_index
					best_to = to_index

		edges.append([best_from, best_to])
		connected.append(best_to)
		remaining.erase(best_to)

	return edges


func find_route(start_index: int, end_index: int) -> PackedVector2Array:
	var start_position: Vector2 = squares.squares[start_index]["position"]
	var end_position: Vector2 = squares.squares[end_index]["position"]
	var start_cell := BoardMetrics.world_to_cell(start_position)
	var end_cell := BoardMetrics.world_to_cell(end_position)
	var bounds := route_search_bounds(start_position, end_position)
	var min_cell := BoardMetrics.world_to_cell(bounds.position)
	var max_cell := BoardMetrics.world_to_cell(bounds.end)
	var blocked_cache: Dictionary = {}
	var open: Array[Vector2i] = [start_cell]
	var open_set: Dictionary = {start_cell: true}
	var closed_set: Dictionary = {}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_cell: 0.0}
	var f_score: Dictionary = {start_cell: route_heuristic(start_cell, end_cell)}
	var visited_nodes := 0

	while not open.is_empty() and visited_nodes < BoardMetrics.ROUTE_MAX_NODES:
		var lowest_index := lowest_f_score_index(open, f_score)
		var current: Vector2i = open.pop_at(lowest_index)
		open_set.erase(current)

		if current == end_cell:
			return build_route(came_from, start_cell, end_cell, start_position, end_position)

		if closed_set.has(current):
			continue

		closed_set[current] = true
		visited_nodes += 1

		for direction in BoardMetrics.ROUTE_DIRECTIONS:
			var next: Vector2i = current + direction
			if not route_cell_in_bounds(next, min_cell, max_cell):
				continue
			if closed_set.has(next):
				continue
			if route_cell_is_blocked(next, start_index, end_index, blocked_cache):
				continue

			# Never cut diagonally through the corner of a padded obstacle.
			if direction.x != 0 and direction.y != 0:
				var side_a := current + Vector2i(direction.x, 0)
				var side_b := current + Vector2i(0, direction.y)
				if route_cell_is_blocked(side_a, start_index, end_index, blocked_cache):
					continue
				if route_cell_is_blocked(side_b, start_index, end_index, blocked_cache):
					continue

			var step_cost := 1.41421356 if direction.x != 0 and direction.y != 0 else 1.0
			var tentative_score: float = g_score[current] + step_cost
			if tentative_score < float(g_score.get(next, 1e30)):
				came_from[next] = current
				g_score[next] = tentative_score
				f_score[next] = tentative_score + route_heuristic(next, end_cell)
				if not open_set.has(next):
					open.append(next)
					open_set[next] = true

	# If a very crowded board exceeds the search budget, skip this one link.
	return PackedVector2Array()


func route_search_bounds(start_position: Vector2, end_position: Vector2) -> Rect2:
	var min_x := minf(start_position.x, end_position.x)
	var min_y := minf(start_position.y, end_position.y)
	var max_x := maxf(start_position.x, end_position.x)
	var max_y := maxf(start_position.y, end_position.y)

	for square in squares.squares:
		var position: Vector2 = square["position"]
		min_x = minf(min_x, position.x)
		min_y = minf(min_y, position.y)
		max_x = maxf(max_x, position.x)
		max_y = maxf(max_y, position.y)

	return Rect2(
		Vector2(min_x - BoardMetrics.ROUTE_SEARCH_MARGIN, min_y - BoardMetrics.ROUTE_SEARCH_MARGIN),
		Vector2(max_x - min_x + BoardMetrics.ROUTE_SEARCH_MARGIN * 2.0, max_y - min_y + BoardMetrics.ROUTE_SEARCH_MARGIN * 2.0)
	)


func route_cell_in_bounds(cell: Vector2i, min_cell: Vector2i, max_cell: Vector2i) -> bool:
	return cell.x >= min_cell.x and cell.x <= max_cell.x and cell.y >= min_cell.y and cell.y <= max_cell.y


func route_cell_is_blocked(
	cell: Vector2i,
	start_index: int,
	end_index: int,
	blocked_cache: Dictionary
) -> bool:
	if blocked_cache.has(cell):
		return blocked_cache[cell]

	if terrain.cells.has(cell):
		blocked_cache[cell] = true
		return true

	var point := BoardMetrics.cell_to_world(cell)
	var blocked := false

	for index in squares.squares.size():
		if index == start_index or index == end_index:
			continue
		var position: Vector2 = squares.squares[index]["position"]
		if BoardMetrics.square_rect(position).grow(BoardMetrics.ROUTE_CLEARANCE).has_point(point):
			blocked = true
			break

	blocked_cache[cell] = blocked
	return blocked


func route_heuristic(from: Vector2i, to: Vector2i) -> float:
	var dx := absi(from.x - to.x)
	var dy := absi(from.y - to.y)
	var straight_steps := maxi(dx, dy)
	var diagonal_steps := mini(dx, dy)
	return float(straight_steps) + float(diagonal_steps) * 0.41421356


func lowest_f_score_index(open: Array[Vector2i], f_score: Dictionary) -> int:
	var lowest_index := 0
	var lowest_score := float(f_score.get(open[0], 1e30))

	for index in range(1, open.size()):
		var score := float(f_score.get(open[index], 1e30))
		if score < lowest_score:
			lowest_score = score
			lowest_index = index

	return lowest_index


func build_route(
	came_from: Dictionary,
	start_cell: Vector2i,
	end_cell: Vector2i,
	start_position: Vector2,
	end_position: Vector2
) -> PackedVector2Array:
	var route_cells: Array[Vector2i] = [end_cell]
	var current := end_cell

	while current != start_cell:
		current = came_from[current]
		route_cells.push_front(current)

	var route := PackedVector2Array([start_position])
	for cell in route_cells:
		var waypoint := BoardMetrics.cell_to_world(cell)
		if waypoint.distance_to(start_position) > BoardMetrics.ROUTE_CELL_SIZE * 0.5 and waypoint.distance_to(end_position) > BoardMetrics.ROUTE_CELL_SIZE * 0.5:
			route.append(waypoint)

	route.append(end_position)
	return route


func draw_dotted_route(route: PackedVector2Array, color: Color) -> void:
	if route.size() < 2:
		return
	for point in sample_route_dots(route):
		draw_circle(point, BoardMetrics.DOT_RADIUS, color)


func sample_route_dots(route: PackedVector2Array) -> PackedVector2Array:
	var dots := PackedVector2Array()
	var length := BoardGeometry.polyline_length(route)
	var start_inset := clearance_along_route(route, false)
	var end_inset := clearance_along_route(route, true)
	var usable := length - start_inset - end_inset
	if usable < BoardMetrics.DOT_SPACING * 0.5:
		var midpoint := BoardGeometry.point_along_polyline(route, length * 0.5)
		if bead_clears_square(midpoint, route[0]) and bead_clears_square(midpoint, route[route.size() - 1]):
			dots.append(midpoint)
		return dots

	# Even spacing, centered on the open span, so corners don't bunch beads up.
	var intervals := maxi(1, roundi(usable / BoardMetrics.DOT_SPACING))
	var spacing := usable / float(intervals)
	for step in intervals + 1:
		dots.append(BoardGeometry.point_along_polyline(route, start_inset + spacing * float(step)))
	return dots


func clearance_along_route(route: PackedVector2Array, from_end: bool) -> float:
	var length := BoardGeometry.polyline_length(route)
	var origin: Vector2 = route[route.size() - 1] if from_end else route[0]
	var low := 0.0
	var high := length

	for _step in 18:
		var mid := (low + high) * 0.5
		var traveled := length - mid if from_end else mid
		if bead_clears_square(BoardGeometry.point_along_polyline(route, traveled), origin):
			high = mid
		else:
			low = mid

	return high


func bead_clears_square(point: Vector2, square_center: Vector2) -> bool:
	var delta := (point - square_center).abs()
	var limit := BoardMetrics.SQUARE_SIZE * 0.5 + BoardMetrics.DOT_RADIUS + BoardMetrics.DOT_EDGE_GAP
	return delta.x > limit or delta.y > limit
