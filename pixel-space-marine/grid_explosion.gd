class_name GridExplosion
extends Node2D

@export var duration: float = 0.12
@export var start_radius: float = 2.0
@export var end_radius: float = 24.0
@export var ring_mid_ratio: float = 0.68
@export var ring_inner_ratio: float = 0.38
@export var segments: int = 16
@export var show_range_box: bool = true
@export var range_box_line_width: float = 2.0

var _time: float = 0.0
var _outer_color: Color = Color(1.0, 0.55, 0.2, 0.85)
var _mid_color: Color = Color(1.0, 0.75, 0.35, 0.9)
var _inner_color: Color = Color(1.0, 0.95, 0.55, 1.0)
var _box_color: Color = Color(1.0, 0.95, 0.6, 0.85)
var _tile_size: float = 16.0
var _range_tiles: int = 1


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 800
	set_process(false)


func play(center_world: Vector2, base_color: Color, target_radius: float = -1.0, custom_duration: float = -1.0, tile_size_px: float = 16.0, range_tiles: int = 1) -> void:
	global_position = center_world
	if target_radius > 0.0:
		end_radius = target_radius
	if custom_duration > 0.0:
		duration = custom_duration
	_tile_size = maxf(1.0, tile_size_px)
	_range_tiles = maxi(1, range_tiles)
	_outer_color = Color(base_color.r * 0.45, base_color.g * 0.45, base_color.b * 0.45, base_color.a * 0.85)
	_mid_color = Color(base_color.r * 0.75, base_color.g * 0.75, base_color.b * 0.75, base_color.a * 0.9)
	_inner_color = Color(minf(1.0, base_color.r * 1.15), minf(1.0, base_color.g * 1.15), minf(1.0, base_color.b * 1.15), base_color.a)
	_box_color = Color(minf(1.0, base_color.r * 1.2), minf(1.0, base_color.g * 1.2), minf(1.0, base_color.b * 1.2), base_color.a)
	_time = 0.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _time >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if duration <= 0.0:
		return
	var t: float = clampf(_time / duration, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	var r_outer: float = maxf(1.0, floor(lerpf(start_radius, end_radius, eased)))
	var r_mid: float = maxf(1.0, floor(r_outer * ring_mid_ratio))
	var r_inner: float = maxf(1.0, floor(r_outer * ring_inner_ratio))
	var fade: float = clampf(1.0 - t * 1.35, 0.0, 1.0)
	_draw_pixel_disc(r_outer, Color(_outer_color.r, _outer_color.g, _outer_color.b, _outer_color.a * fade))
	_draw_pixel_disc(r_mid, Color(_mid_color.r, _mid_color.g, _mid_color.b, _mid_color.a * fade))
	_draw_pixel_disc(r_inner, Color(_inner_color.r, _inner_color.g, _inner_color.b, _inner_color.a * fade))
	if show_range_box:
		_draw_range_box(fade)


func _draw_pixel_disc(radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var seg := maxi(8, segments)
	for i in range(seg):
		var a: float = TAU * float(i) / float(seg)
		var x: float = roundf(cos(a) * radius)
		var y: float = roundf(sin(a) * radius)
		pts.append(Vector2(x, y))
	draw_colored_polygon(pts, color)


func _draw_range_box(fade: float) -> void:
	var half := _tile_size * (float(_range_tiles) + 0.5)
	var rect := Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0))
	var c := Color(_box_color.r, _box_color.g, _box_color.b, _box_color.a * fade)
	draw_rect(rect, c, false, range_box_line_width)
