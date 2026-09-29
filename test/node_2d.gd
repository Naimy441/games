extends Node2D

const AUTOSAVE_DELAY := 0.4

var place_mode := "pan"
var square_layer: SquareLayer
var terrain_layer: TerrainLayer
var route_layer: RouteLayer
var overlay: BoardOverlay
var camera: BoardCamera

var selected_squares: Array[int] = []
var selected_terrains: Array[int] = []
var marquee_active := false
var marquee_start := Vector2.ZERO
var marquee_end := Vector2.ZERO
var pending_selection_drag := false
var moving_selection := false
var drag_press_position := Vector2.ZERO
var drag_hit_square := -1
var drag_hit_terrain := -1
var move_anchor := Vector2.ZERO
var move_delta := Vector2.ZERO
var drag_square_starts: Array[Vector2] = []
var drag_terrain_starts: Array[PackedVector2Array] = []
var dragging := false
var drag_offset := Vector2.ZERO
var pending_blank_click := false
var blank_press_screen_position := Vector2.ZERO
var board_dirty := false
var autosave_wait := 0.0
var tool_label: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	# Keep glyph edges sharp instead of linearly blurring them during zoom.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED

	camera = BoardCamera.new()
	camera.name = "BoardCamera"
	add_child(camera)
	camera.position = get_viewport_rect().size / 2.0
	camera.make_current()

	terrain_layer = TerrainLayer.new()
	terrain_layer.name = "Terrain"
	square_layer = SquareLayer.new()
	square_layer.name = "Squares"
	square_layer.camera = camera
	route_layer = RouteLayer.new()
	route_layer.name = "Routes"
	overlay = BoardOverlay.new()
	overlay.name = "Overlay"

	terrain_layer.squares = square_layer
	terrain_layer.highlighted = selected_terrains
	square_layer.highlighted = selected_squares
	route_layer.squares = square_layer
	route_layer.terrain = terrain_layer

	add_child(terrain_layer)
	add_child(route_layer)
	add_child(square_layer)
	add_child(overlay)

	get_viewport().size_changed.connect(refresh)
	setup_tool_label()
	load_board()
	update_tool_label()
	refresh()


func _process(delta: float) -> void:
	if camera.advance(delta):
		# Dots and letters are rasterized for the zoom at draw time. Rebuild them
		# while the zoom moves, or the camera just stretches a soft snapshot.
		refresh()

	if board_dirty:
		autosave_wait -= delta
		if autosave_wait <= 0.0:
			save_board()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if board_dirty:
			save_board()


func _exit_tree() -> void:
	if board_dirty:
		save_board()


func refresh() -> void:
	overlay.marquee_active = marquee_active
	if marquee_active:
		overlay.marquee_rect = marquee_rect()
	queue_redraw()
	terrain_layer.queue_redraw()
	route_layer.queue_redraw()
	square_layer.queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color.BLACK)


func note_board_changed() -> void:
	board_dirty = true
	autosave_wait = AUTOSAVE_DELAY
	route_layer.dirty = true


func note_terrain_changed() -> void:
	terrain_layer.cells_dirty = true
	note_board_changed()


func save_board() -> void:
	BoardSave.save(square_layer.squares, terrain_layer.terrains)
	board_dirty = false


func load_board() -> void:
	var loaded := BoardSave.load()
	if loaded.is_empty():
		return
	square_layer.squares = loaded["squares"]
	terrain_layer.terrains = loaded["terrains"]
	terrain_layer.active_terrain = -1
	terrain_layer.cells_dirty = true
	route_layer.dirty = true


func start_drag_pan(screen_position: Vector2) -> void:
	camera.start_pan(screen_position)
	pending_blank_click = false
	dragging = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera.zoom_wheel(true)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera.zoom_wheel(false)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				start_drag_pan(event.position)
			else:
				camera.panning = false
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if place_mode == "pan" or Input.is_key_pressed(KEY_SPACE):
					start_drag_pan(event.position)
				else:
					var click_position := get_global_mouse_position()
					if place_mode == "square" and square_layer.find_at(click_position) >= 0:
						begin_click(click_position)
					elif place_mode == "select":
						var square_hit := square_layer.find_at(click_position)
						var terrain_hit := terrain_layer.find_at(click_position)
						blank_press_screen_position = event.position
						if square_hit >= 0 or terrain_hit >= 0:
							pending_selection_drag = true
							drag_press_position = click_position
							drag_hit_square = square_hit
							drag_hit_terrain = terrain_hit
						else:
							pending_blank_click = true
							marquee_start = click_position
							marquee_end = click_position
					else:
						pending_blank_click = true
						blank_press_screen_position = event.position
			else:
				if moving_selection:
					moving_selection = false
					pending_selection_drag = false
				elif marquee_active:
					apply_marquee_selection()
					marquee_active = false
					pending_blank_click = false
				elif pending_selection_drag:
					pending_selection_drag = false
					if drag_hit_square >= 0:
						select_only_square(drag_hit_square)
					elif drag_hit_terrain >= 0:
						select_only_terrain(drag_hit_terrain)
				elif pending_blank_click:
					pending_blank_click = false
					var release_position := get_global_mouse_position()
					if place_mode == "select":
						var square_hit := square_layer.find_at(release_position)
						var terrain_hit := terrain_layer.find_at(release_position)
						if square_hit >= 0:
							select_only_square(square_hit)
						elif terrain_hit >= 0:
							select_only_terrain(terrain_hit)
						else:
							clear_selection()
					elif place_mode == "terrain":
						place_terrain_point(release_position)
					else:
						begin_click(release_position)
				dragging = false
				camera.panning = false

	elif event is InputEventMouseMotion:
		if dragging and selected_squares.size() == 1:
			move_selected_square(get_global_mouse_position() + drag_offset)
		elif moving_selection:
			update_selection_drag(get_global_mouse_position())
		elif pending_selection_drag:
			if event.position.distance_to(blank_press_screen_position) >= 6.0:
				start_selection_drag()
				update_selection_drag(get_global_mouse_position())
		elif pending_blank_click and place_mode == "select":
			marquee_end = get_global_mouse_position()
			if event.position.distance_to(blank_press_screen_position) >= 6.0:
				marquee_active = true
			if marquee_active:
				refresh()
		elif pending_blank_click:
			if event.position.distance_to(blank_press_screen_position) >= 6.0:
				start_drag_pan(blank_press_screen_position)
				camera.update_pan(event.position)
		elif camera.panning:
			camera.update_pan(event.position)

	elif event is InputEventPanGesture:
		camera.pan_trackpad(event.delta)

	elif event is InputEventMagnifyGesture:
		camera.zoom_magnify(event.factor)

	elif event is InputEventKey:
		if event.pressed and not event.echo:
			if handle_tool_key(event.keycode):
				pass
			elif event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE:
				if place_mode != "pan":
					erase_selection()
			elif selected_squares.size() == 1 and (place_mode == "select" or place_mode == "square") and event.keycode >= KEY_A and event.keycode <= KEY_Z:
				square_layer.set_letter(selected_squares[0], OS.get_keycode_string(event.keycode))
				note_board_changed()
				refresh()


func handle_tool_key(keycode: Key) -> bool:
	if keycode == KEY_9 or keycode == KEY_KP_9:
		clear_board()
		return true
	if keycode == KEY_1 or keycode == KEY_KP_1:
		set_place_mode("pan")
		return true
	if keycode == KEY_2 or keycode == KEY_KP_2:
		set_place_mode("select")
		return true
	if keycode == KEY_3 or keycode == KEY_KP_3:
		set_place_mode("square")
		return true
	if keycode == KEY_4 or keycode == KEY_KP_4:
		set_place_mode("terrain")
		return true
	if place_mode != "terrain":
		return false
	if keycode == KEY_F:
		terrain_layer.brush = "forest"
		terrain_layer.active_terrain = terrain_layer.latest("forest")
		update_tool_label()
		refresh()
		return true
	if keycode == KEY_M:
		terrain_layer.brush = "mountain"
		terrain_layer.active_terrain = terrain_layer.latest("mountain")
		update_tool_label()
		refresh()
		return true
	if keycode == KEY_R:
		terrain_layer.begin_path("river")
		update_tool_label()
		refresh()
		return true
	if keycode == KEY_L:
		terrain_layer.begin_path("lake")
		update_tool_label()
		refresh()
		return true
	return false


func set_place_mode(mode: String) -> void:
	place_mode = mode
	dragging = false
	marquee_active = false
	pending_blank_click = false
	pending_selection_drag = false
	moving_selection = false
	terrain_layer.show_active = mode == "terrain"
	update_tool_label()
	refresh()


func place_terrain_point(point: Vector2) -> void:
	if not terrain_layer.place_point(point):
		return
	note_terrain_changed()
	refresh()


func erase_selection() -> void:
	var remove_squares: Array[int] = []
	var remove_terrains: Array[int] = []
	remove_squares.assign(selected_squares)
	remove_terrains.assign(selected_terrains)
	if remove_squares.is_empty() and remove_terrains.is_empty() and terrain_layer.active_terrain >= 0 and terrain_layer.active_terrain < terrain_layer.terrains.size():
		remove_terrains.append(terrain_layer.active_terrain)
	if remove_squares.is_empty() and remove_terrains.is_empty():
		return

	var removed_terrain := not remove_terrains.is_empty()
	square_layer.remove_descending(remove_squares)
	terrain_layer.remove_descending(remove_terrains)
	selected_squares.clear()
	selected_terrains.clear()
	dragging = false
	if removed_terrain:
		note_terrain_changed()
	else:
		note_board_changed()
	refresh()


func clear_board() -> void:
	square_layer.clear_all()
	terrain_layer.clear_all()
	selected_squares.clear()
	selected_terrains.clear()
	dragging = false
	marquee_active = false
	pending_selection_drag = false
	moving_selection = false
	note_board_changed()
	refresh()


func select_only_square(index: int) -> void:
	selected_squares.clear()
	selected_terrains.clear()
	selected_squares.append(index)
	dragging = false
	refresh()


func select_only_terrain(index: int) -> void:
	selected_squares.clear()
	selected_terrains.clear()
	selected_terrains.append(index)
	dragging = false
	refresh()


func clear_selection() -> void:
	selected_squares.clear()
	selected_terrains.clear()
	dragging = false
	refresh()


func start_selection_drag() -> void:
	if drag_hit_square >= 0:
		if not selected_squares.has(drag_hit_square):
			select_only_square(drag_hit_square)
	elif drag_hit_terrain >= 0:
		if not selected_terrains.has(drag_hit_terrain):
			select_only_terrain(drag_hit_terrain)
	pending_selection_drag = false
	moving_selection = true
	move_anchor = drag_press_position
	move_delta = Vector2.ZERO
	drag_square_starts.clear()
	for index in selected_squares:
		drag_square_starts.append(square_layer.position_of(index))
	drag_terrain_starts.clear()
	for index in selected_terrains:
		drag_terrain_starts.append(terrain_layer.points_of(index))


func update_selection_drag(pointer: Vector2) -> void:
	var desired := pointer - move_anchor
	var candidate := desired
	if not square_layer.group_free(drag_square_starts, selected_squares, candidate):
		var slide_x := Vector2(desired.x, move_delta.y)
		var slide_y := Vector2(move_delta.x, desired.y)
		if square_layer.group_free(drag_square_starts, selected_squares, slide_x):
			candidate = slide_x
		elif square_layer.group_free(drag_square_starts, selected_squares, slide_y):
			candidate = slide_y
		else:
			candidate = move_delta
	if candidate == move_delta:
		return
	move_delta = candidate
	for index in selected_squares.size():
		square_layer.move_square(selected_squares[index], drag_square_starts[index] + move_delta)
	for index in selected_terrains.size():
		var origin: PackedVector2Array = drag_terrain_starts[index]
		var moved := PackedVector2Array()
		moved.resize(origin.size())
		for point_index in origin.size():
			moved[point_index] = origin[point_index] + move_delta
		terrain_layer.set_points(selected_terrains[index], moved)
	if selected_terrains.is_empty():
		note_board_changed()
	else:
		note_terrain_changed()
	refresh()


func apply_marquee_selection() -> void:
	var rect := marquee_rect()
	selected_squares.clear()
	selected_terrains.clear()
	for index in square_layer.indices_in_rect(rect):
		selected_squares.append(index)
	for index in terrain_layer.indices_in_rect(rect):
		selected_terrains.append(index)
	refresh()


func marquee_rect() -> Rect2:
	var rect := Rect2(marquee_start, Vector2.ZERO)
	return rect.expand(marquee_end)


func begin_click(click_position: Vector2) -> void:
	var hit_square := square_layer.find_at(click_position)
	selected_terrains.clear()
	if hit_square >= 0:
		selected_squares.clear()
		selected_squares.append(hit_square)
		drag_offset = square_layer.position_of(hit_square) - click_position
		dragging = true
	else:
		var target_position := square_layer.best_free_position(click_position, -1, click_position, false)
		var index := square_layer.add_square(target_position)
		selected_squares.clear()
		selected_squares.append(index)
		drag_offset = target_position - click_position
		dragging = true
		note_board_changed()
	refresh()


func move_selected_square(new_position: Vector2) -> void:
	var selected_index := selected_squares[0]
	var current_position := square_layer.position_of(selected_index)
	var next_position := square_layer.best_free_position(
		new_position,
		selected_index,
		current_position,
		true
	)
	if next_position != current_position:
		square_layer.move_square(selected_index, next_position)
		note_board_changed()
	refresh()


func setup_tool_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	tool_label = Label.new()
	tool_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_label.add_theme_font_size_override("font_size", 11)
	tool_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	layer.add_child(tool_label)
	get_viewport().size_changed.connect(_position_tool_label)
	_position_tool_label()


func _position_tool_label() -> void:
	if tool_label == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	tool_label.position = Vector2(10, viewport_size.y - 18)
	tool_label.size = Vector2(120, 14)


func update_tool_label() -> void:
	if tool_label == null:
		return
	if place_mode == "pan":
		tool_label.text = "Drag"
	elif place_mode == "select":
		tool_label.text = "Select"
	elif place_mode == "square":
		tool_label.text = "Squares"
	else:
		match terrain_layer.brush:
			"forest":
				tool_label.text = "Forest"
			"river":
				tool_label.text = "River"
			"lake":
				tool_label.text = "Lake"
			"mountain":
				tool_label.text = "Mountains"
