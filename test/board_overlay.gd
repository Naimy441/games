class_name BoardOverlay
extends Node2D

var marquee_active := false
var marquee_rect := Rect2()


func _draw() -> void:
	if not marquee_active:
		return
	draw_rect(marquee_rect, Color(1, 1, 1, 0.16))
	draw_rect(marquee_rect, Color.WHITE, false, 1.5)
