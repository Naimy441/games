class_name BoardSave
extends Object

const PATH := "user://board.json"


static func save(squares: Array[Dictionary], terrains: Array[Dictionary]) -> void:
	var saved_squares: Array = []
	for square in squares:
		var position: Vector2 = square["position"]
		saved_squares.append({
			"x": position.x,
			"y": position.y,
			"letter": square["letter"]
		})

	var saved_terrains: Array = []
	for feature in terrains:
		var points: PackedVector2Array = feature["points"]
		if points.is_empty():
			continue
		var saved_points: Array = []
		for point in points:
			saved_points.append({
				"x": point.x,
				"y": point.y
			})
		saved_terrains.append({
			"kind": feature["kind"],
			"points": saved_points
		})

	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"squares": saved_squares,
		"terrains": saved_terrains
	}, "\t"))


static func load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}

	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	return {
		"squares": _squares(parsed.get("squares", [])),
		"terrains": _terrains(parsed.get("terrains", []))
	}


static func _squares(loaded: Variant) -> Array[Dictionary]:
	var restored: Array[Dictionary] = []
	if typeof(loaded) != TYPE_ARRAY:
		return restored
	for entry in loaded:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not entry.has("x") or not entry.has("y"):
			continue
		var letter := ""
		var raw_letter: Variant = entry.get("letter", "")
		if typeof(raw_letter) == TYPE_STRING:
			letter = raw_letter
		restored.append({
			"position": Vector2(float(entry["x"]), float(entry["y"])),
			"letter": letter
		})
	return restored


static func _terrains(loaded: Variant) -> Array[Dictionary]:
	var restored: Array[Dictionary] = []
	if typeof(loaded) != TYPE_ARRAY:
		return restored
	for feature in loaded:
		if typeof(feature) != TYPE_DICTIONARY:
			continue
		var kind: Variant = feature.get("kind", "")
		if typeof(kind) != TYPE_STRING:
			continue
		if kind != "forest" and kind != "river" and kind != "lake" and kind != "mountain":
			continue
		var raw_points: Variant = feature.get("points", [])
		if typeof(raw_points) != TYPE_ARRAY:
			continue
		var points := PackedVector2Array()
		for raw_point in raw_points:
			if typeof(raw_point) != TYPE_DICTIONARY:
				continue
			if not raw_point.has("x") or not raw_point.has("y"):
				continue
			points.append(Vector2(float(raw_point["x"]), float(raw_point["y"])))
		if points.is_empty():
			continue
		restored.append({
			"kind": kind,
			"points": points
		})
	return restored
