class_name BoardGeometry
extends Object


static func point_in_polygon(point: Vector2, poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	var inside := false
	var previous := poly.size() - 1
	for index in poly.size():
		var current := poly[index]
		var prior := poly[previous]
		var crosses := (current.y > point.y) != (prior.y > point.y)
		if crosses and point.x < (prior.x - current.x) * (point.y - current.y) / (prior.y - current.y) + current.x:
			inside = not inside
		previous = index
	return inside


static func point_near_polygon(point: Vector2, poly: PackedVector2Array, padding: float) -> bool:
	if poly.size() < 2:
		return false
	var count := poly.size()
	for index in count:
		if distance_to_segment(point, poly[index], poly[(index + 1) % count]) <= padding:
			return true
	return false


static func segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var top_left := rect.position
	var top_right := rect.position + Vector2(rect.size.x, 0)
	var bottom_right := rect.end
	var bottom_left := rect.position + Vector2(0, rect.size.y)
	return segments_cross(a, b, top_left, top_right) \
		or segments_cross(a, b, top_right, bottom_right) \
		or segments_cross(a, b, bottom_right, bottom_left) \
		or segments_cross(a, b, bottom_left, top_left)


static func segments_cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var direction_a := a2 - a1
	var direction_b := b2 - b1
	var denom := direction_a.cross(direction_b)
	if absf(denom) < 0.00001:
		return false
	var offset := b1 - a1
	var t := offset.cross(direction_b) / denom
	var u := offset.cross(direction_a) / denom
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0


static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_sq := segment.length_squared()
	if length_sq <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(a + segment * t)


static func polygon_hits_rect(poly: PackedVector2Array, rect: Rect2) -> bool:
	if poly.size() < 3:
		return false
	for point in poly:
		if rect.has_point(point):
			return true
	var corners := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	])
	for corner in corners:
		if point_in_polygon(corner, poly):
			return true
	var count := poly.size()
	for index in count:
		if segment_hits_rect(poly[index], poly[(index + 1) % count], rect):
			return true
	return false


static func polyline_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for index in range(points.size() - 1):
		length += points[index].distance_to(points[index + 1])
	return length


static func point_along_polyline(points: PackedVector2Array, distance: float) -> Vector2:
	var remaining := distance
	for index in range(points.size() - 1):
		var segment := points[index + 1] - points[index]
		var segment_length := segment.length()
		if remaining <= segment_length or index == points.size() - 2:
			if segment_length <= 0.001:
				return points[index]
			return points[index] + segment * clampf(remaining / segment_length, 0.0, 1.0)
		remaining -= segment_length
	return points[points.size() - 1]


static func lake_outline(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return PackedVector2Array()
	var hull := convex_hull(points)
	if hull.size() <= 1:
		return circle_outline(points[0], 48.0)
	if hull.size() == 2:
		return capsule_outline(hull[0], hull[1], 34.0)
	return round_convex(hull, 28.0)


static func circle_outline(center: Vector2, radius: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var steps := 28
	for step in steps:
		var angle := TAU * float(step) / float(steps)
		outline.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return outline


static func capsule_outline(a: Vector2, b: Vector2, radius: float) -> PackedVector2Array:
	var direction := b - a
	if direction.length_squared() < 1.0:
		return circle_outline(a, radius)
	var normal := direction.orthogonal().normalized()
	var outline := PackedVector2Array()
	outline.append_array(arc_points(b, normal, -normal, radius))
	outline.append_array(arc_points(a, -normal, normal, radius))
	return outline


static func round_convex(hull: PackedVector2Array, radius: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var count := hull.size()
	for index in count:
		var prev: Vector2 = hull[(index + count - 1) % count]
		var curr: Vector2 = hull[index]
		var next: Vector2 = hull[(index + 1) % count]
		var inward := curr - prev
		var outward := next - curr
		if inward.length_squared() < 0.01 or outward.length_squared() < 0.01:
			outline.append(curr)
			continue
		outline.append_array(arc_points(
			curr,
			inward.orthogonal().normalized(),
			outward.orthogonal().normalized(),
			radius
		))
	return outline


static func arc_points(center: Vector2, from_dir: Vector2, to_dir: Vector2, radius: float) -> PackedVector2Array:
	var start := from_dir.angle()
	var sweep := wrapf(to_dir.angle() - start, 0.0, TAU)
	var steps := maxi(2, int(ceil(sweep / 0.35)))
	var points := PackedVector2Array()
	for step in steps + 1:
		var angle := start + sweep * float(step) / float(steps)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	var sorted: Array[Vector2] = []
	for point in points:
		var duplicate := false
		for existing in sorted:
			if existing.distance_squared_to(point) < 4.0:
				duplicate = true
				break
		if not duplicate:
			sorted.append(point)
	if sorted.size() <= 2:
		var few := PackedVector2Array()
		for point in sorted:
			few.append(point)
		return few

	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	)

	var lower: Array[Vector2] = []
	for point in sorted:
		while lower.size() >= 2 and hull_cross(lower[lower.size() - 2], lower[lower.size() - 1], point) <= 0.0:
			lower.pop_back()
		lower.append(point)

	var upper: Array[Vector2] = []
	for index in range(sorted.size() - 1, -1, -1):
		var point: Vector2 = sorted[index]
		while upper.size() >= 2 and hull_cross(upper[upper.size() - 2], upper[upper.size() - 1], point) <= 0.0:
			upper.pop_back()
		upper.append(point)

	if not lower.is_empty():
		lower.pop_back()
	if not upper.is_empty():
		upper.pop_back()

	var hull := PackedVector2Array()
	for point in lower:
		hull.append(point)
	for point in upper:
		hull.append(point)
	return hull


static func hull_cross(origin: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - origin).cross(b - origin)


static func smooth_curve(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var curve := PackedVector2Array()
	var steps := 8
	for index in points.size() - 1:
		var p0: Vector2 = points[maxi(index - 1, 0)]
		var p1: Vector2 = points[index]
		var p2: Vector2 = points[index + 1]
		var p3: Vector2 = points[mini(index + 2, points.size() - 1)]
		for step in steps:
			curve.append(catmull(p0, p1, p2, p3, float(step) / float(steps)))
	curve.append(points[points.size() - 1])
	return curve


static func catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


static func ribbon(line: PackedVector2Array, half_width: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in line.size():
		var tangent := Vector2.RIGHT
		if index == 0:
			tangent = line[1] - line[0]
		elif index == line.size() - 1:
			tangent = line[index] - line[index - 1]
		else:
			tangent = line[index + 1] - line[index - 1]
		if tangent.length_squared() < 0.0001:
			tangent = Vector2.RIGHT
		var normal := tangent.orthogonal().normalized()
		left.append(line[index] + normal * half_width)
		right.append(line[index] - normal * half_width)

	var poly := PackedVector2Array()
	for point in left:
		poly.append(point)
	for index in range(right.size() - 1, -1, -1):
		poly.append(right[index])
	return poly
