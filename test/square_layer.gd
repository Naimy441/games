class_name SquareLayer
extends Node2D

const VIVID_COLORS := [
	Color("#FF1744"), # A - red
	Color("#FF6D00"), # B - orange
	Color("#FFD600"), # C - yellow
	Color("#AEEA00"), # D - lime
	Color("#00E676"), # E - green
	Color("#00C853"), # F - emerald
	Color("#00E5FF"), # G - cyan
	Color("#00B0FF"), # H - sky blue
	Color("#80D8FF"), # I - light blue
	Color("#82B1FF"), # J - periwinkle
	Color("#B39DDB"), # K - lavender
	Color("#EA80FC"), # L - bright lilac
	Color("#D500F9"), # M - magenta
	Color("#F50057"), # N - hot pink
	Color("#FF4081"), # O - pink
	Color("#FF5252"), # P - coral
	Color("#FF9100"), # Q - amber
	Color("#C6FF00"), # R - chartreuse
	Color("#64DD17"), # S - leaf green
	Color("#1DE9B6"), # T - turquoise
	Color("#18FFFF"), # U - aqua
	Color("#40C4FF"), # V - light blue
	Color("#90CAF9"), # W - pale blue
	Color("#FFAB91"), # X - peach
	Color("#CE93D8"), # Y - orchid
	Color("#EA80FC")  # Z - fuchsia
]

var squares: Array[Dictionary] = []
var highlighted: Array[int] = []
var camera: Camera2D


static func color_for(letter: String) -> Color:
	return VIVID_COLORS[letter.unicode_at(0) - "A".unicode_at(0)]


func find_at(point: Vector2) -> int:
	for i in range(squares.size() - 1, -1, -1):
		var square := squares[i]
		if BoardMetrics.square_rect(square["position"]).has_point(point):
			return i
	return -1


func position_of(index: int) -> Vector2:
	return squares[index]["position"]


func move_square(index: int, position: Vector2) -> void:
	var square := squares[index]
	square["position"] = position
	squares[index] = square


func set_letter(index: int, letter: String) -> void:
	var square := squares[index]
	square["letter"] = letter
	squares[index] = square


func add_square(position: Vector2) -> int:
	squares.append({
		"position": position,
		"letter": ""
	})
	return squares.size() - 1


func remove_descending(indices: Array[int]) -> void:
	var ordered: Array[int] = []
	ordered.assign(indices)
	ordered.sort()
	for index in range(ordered.size() - 1, -1, -1):
		squares.remove_at(ordered[index])


func clear_all() -> void:
	squares.clear()


func indices_in_rect(rect: Rect2) -> Array[int]:
	var hits: Array[int] = []
	for index in squares.size():
		var square: Dictionary = squares[index]
		if rect.intersects(BoardMetrics.square_rect(square["position"])):
			hits.append(index)
	return hits


func best_free_position(
	desired_position: Vector2,
	ignore_index: int,
	previous_position: Vector2,
	prefer_previous: bool
) -> Vector2:
	if position_is_free(desired_position, ignore_index):
		return desired_position

	# The desired spot is blocked. Try the closest positions directly beside
	# every blocking square, then choose the one nearest to the pointer.
	var candidates: Array[Vector2] = []
	var clearance := BoardMetrics.SQUARE_SIZE + BoardMetrics.PLACEMENT_GAP

	# Keep the existing collision edge as an option. This prevents flicker when
	# two nearby edges are nearly tied for the closest placement.
	if prefer_previous and position_is_free(previous_position, ignore_index):
		candidates.append(previous_position)

	for i in squares.size():
		if i == ignore_index:
			continue

		var square := squares[i]
		var other_position: Vector2 = square["position"]

		candidates.append(Vector2(
			other_position.x - clearance,
			clampf(desired_position.y, other_position.y - clearance, other_position.y + clearance)
		))
		candidates.append(Vector2(
			other_position.x + clearance,
			clampf(desired_position.y, other_position.y - clearance, other_position.y + clearance)
		))
		candidates.append(Vector2(
			clampf(desired_position.x, other_position.x - clearance, other_position.x + clearance),
			other_position.y - clearance
		))
		candidates.append(Vector2(
			clampf(desired_position.x, other_position.x - clearance, other_position.x + clearance),
			other_position.y + clearance
		))

	var best_position := desired_position
	var best_distance := 1e30

	for candidate in candidates:
		if position_is_free(candidate, ignore_index):
			var score := candidate.distance_squared_to(desired_position)
			if prefer_previous:
				score += candidate.distance_squared_to(previous_position) * 0.2

			if score < best_distance:
				best_position = candidate
				best_distance = score

	if best_distance < 1e30:
		return best_position

	# A rare fallback for crowded clusters: look outward in smooth circles.
	for radius in range(1, 301):
		for step in range(24):
			var angle := TAU * float(step) / 24.0
			var radial_candidate := desired_position + Vector2(cos(angle), sin(angle)) * radius
			if position_is_free(radial_candidate, ignore_index):
				return radial_candidate

	return desired_position


func position_is_free(center: Vector2, ignore_index: int) -> bool:
	var candidate := BoardMetrics.square_rect(center)
	for i in squares.size():
		if i != ignore_index:
			var square := squares[i]
			if candidate.intersects(BoardMetrics.square_rect(square["position"])):
				return false
	return true


func group_free(starts: Array[Vector2], ignored: Array[int], delta: Vector2) -> bool:
	for index in starts.size():
		var candidate := BoardMetrics.square_rect(starts[index] + delta)
		for other in squares.size():
			if ignored.has(other):
				continue
			var other_square: Dictionary = squares[other]
			if candidate.intersects(BoardMetrics.square_rect(other_square["position"])):
				return false
	return true


func blocks_rect(rect: Rect2) -> bool:
	for square in squares:
		if rect.intersects(BoardMetrics.square_rect(square["position"])):
			return true
	return false


func blocks_river(existing: PackedVector2Array, point: Vector2) -> bool:
	for square in squares:
		var padded := BoardMetrics.square_rect(square["position"]).grow(BoardMetrics.RIVER_HALF_WIDTH)
		if padded.has_point(point):
			return true
		if not existing.is_empty() and BoardGeometry.segment_hits_rect(existing[existing.size() - 1], point, padded):
			return true
	return false


func blocks_polygon(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	for square in squares:
		var rect := BoardMetrics.square_rect(square["position"])
		if BoardGeometry.point_in_polygon(rect.get_center(), poly):
			return true
		var count := poly.size()
		for index in count:
			if BoardGeometry.segment_hits_rect(poly[index], poly[(index + 1) % count], rect):
				return true
	return false


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var text_oversampling := 1.0
	if camera != null:
		text_oversampling = camera.zoom.x

	for i in squares.size():
		var square := squares[i]
		var position: Vector2 = square["position"]
		var letter: String = square["letter"]
		var rect := BoardMetrics.square_rect(position)

		var color := Color.WHITE
		if letter != "":
			color = color_for(letter)

		draw_rect(rect, color)

		if letter != "":
			# Match the glyph texture to the current zoom so the camera isn't scaling a stale raster.
			var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
			var label_position := Vector2(
				rect.get_center().x - text_size.x / 2.0,
				rect.get_center().y + (font.get_ascent(26) - font.get_descent(26)) / 2.0
			)
			draw_string(
				font,
				label_position,
				letter,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				26,
				Color.BLACK,
				3,
				0,
				0,
				text_oversampling
			)

		if highlighted.has(i):
			draw_rect(rect, Color.WHITE, false, 3.0)
