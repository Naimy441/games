class_name BoardCamera
extends Camera2D

const MIN_ZOOM := 0.5
const MAX_ZOOM := 3.0
const ZOOM_STEP := 1.15
const ZOOM_SMOOTHNESS := 14.0
const TRACKPAD_PAN_SPEED := 1.75
const TRACKPAD_COAST_FRICTION := 2_800.0

var zoom_target := 1.0
var trackpad_velocity := Vector2.ZERO
var panning := false
var pan_start_screen_position := Vector2.ZERO
var pan_start_camera_position := Vector2.ZERO


func zoom_wheel(inward: bool) -> void:
	if inward:
		zoom_target = minf(zoom_target * ZOOM_STEP, MAX_ZOOM)
	else:
		zoom_target = maxf(zoom_target / ZOOM_STEP, MIN_ZOOM)


func zoom_magnify(factor: float) -> void:
	zoom_target = clampf(zoom_target * factor, MIN_ZOOM, MAX_ZOOM)


func start_pan(screen_position: Vector2) -> void:
	panning = true
	pan_start_screen_position = screen_position
	pan_start_camera_position = global_position


func update_pan(screen_position: Vector2) -> void:
	# Anchor the camera to the initial pointer position. This avoids accumulated
	# rounding error and stays correct at every zoom level.
	global_position = pan_start_camera_position - (screen_position - pan_start_screen_position) / zoom.x
	force_update_scroll()


func pan_trackpad(gesture_delta: Vector2) -> void:
	# Gesture deltas arriving at this CanvasItem are already transformed for
	# the current canvas, so do not scale them by camera zoom.
	var movement := gesture_delta * TRACKPAD_PAN_SPEED
	global_position += movement
	trackpad_velocity = movement * 40.0
	force_update_scroll()


func advance(delta: float) -> bool:
	var redraw := false
	var zoom_changing := not is_equal_approx(zoom.x, zoom_target)
	if zoom_changing:
		# Smoothly zoom toward the target while keeping the spot under the mouse fixed.
		var mouse_before := get_global_mouse_position()
		var blend := 1.0 - exp(-ZOOM_SMOOTHNESS * delta)
		var next_zoom := lerpf(zoom.x, zoom_target, blend)
		if absf(next_zoom - zoom_target) < 0.0008:
			next_zoom = zoom_target
		zoom = Vector2.ONE * next_zoom
		force_update_scroll()
		var mouse_after := get_global_mouse_position()
		global_position += mouse_before - mouse_after
		force_update_scroll()
		redraw = true
	elif _zoom_was_changing:
		redraw = true
	_zoom_was_changing = zoom_changing

	# A short kinetic coast makes trackpad navigation feel light rather than
	# forcing the user to repeatedly push the board across the screen.
	if trackpad_velocity.length() > 1.0:
		global_position += trackpad_velocity * delta
		trackpad_velocity = trackpad_velocity.move_toward(
			Vector2.ZERO,
			TRACKPAD_COAST_FRICTION * delta
		)
		force_update_scroll()
	return redraw


var _zoom_was_changing := false
