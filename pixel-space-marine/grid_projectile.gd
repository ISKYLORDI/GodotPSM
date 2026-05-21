class_name GridProjectile
extends Node2D

@export var width: float = 2.0
@export var travel_duration: float = 0.1
## 弹头身后拖尾在世界坐标下的长度（保持不变，形如弹体线段）。
@export var bullet_trail_length: float = 11.0
@export var core_color: Color = Color(0.45, 0.9, 1.0, 1.0)
@export var glow_color: Color = Color(0.2, 0.6, 1.0, 0.5)
@export var bolt_scale: float = 3.0

var _line: Line2D = null
var _glow: Line2D = null
var _bolt: Sprite2D = null
var _pixel_tex: Texture2D = null

var _fire_from: Vector2 = Vector2.ZERO
var _fire_to: Vector2 = Vector2.ZERO
var _fire_dir: Vector2 = Vector2.RIGHT
var _fire_trail: float = 1.0

var _path_points: PackedVector2Array = PackedVector2Array()
var _path_lengths: PackedFloat32Array = PackedFloat32Array()
var _path_total_len: float = 1.0
## 单条时间轴：{t0,t1,d0,d1}，暂停段 d0==d1。
var _path_timeline: Array = []
var _path_timeline_total: float = 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 420
	_ensure_nodes()


func fire(from_world: Vector2, to_world: Vector2, duration: float = -1.0) -> void:
	_ensure_nodes()
	_fire_from = from_world
	_fire_to = to_world
	var delta: Vector2 = to_world - from_world
	var dist: float = delta.length()
	if dist > 1e-5:
		_fire_dir = delta / dist
	else:
		_fire_dir = Vector2.RIGHT
	_fire_trail = clampf(bullet_trail_length, 1.0, maxf(dist, 1.0))

	_apply_bullet_visual_frame(0.0)

	var use_duration := travel_duration if duration <= 0.0 else duration
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_method(_apply_bullet_visual_frame, 0.0, 1.0, maxf(0.02, use_duration))
	tween.tween_property(self, "modulate:a", 0.0, 0.05)
	tween.finished.connect(queue_free, CONNECT_ONE_SHOT)


func fire_path(
	points: PackedVector2Array,
	duration: float = -1.0,
	move_speed: float = -1.0,
	corner_pause: float = 0.0
) -> void:
	if points.size() < 2:
		queue_free()
		return
	if points.size() == 2:
		var use_duration := duration
		if use_duration <= 0.0 and move_speed > 0.0:
			var seg_len := points[0].distance_to(points[1])
			use_duration = maxf(0.02, seg_len / move_speed)
		fire(points[0], points[1], use_duration)
		return

	_ensure_nodes()
	_path_points = points
	_rebuild_path_length_table()
	_apply_path_frame_at_distance(0.0)

	modulate = Color(1.0, 1.0, 1.0, 1.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	if move_speed > 0.0:
		_build_path_timeline(move_speed, corner_pause)
		if _path_timeline_total <= 0.0:
			_apply_path_frame_at_distance(_path_total_len)
		else:
			tween.tween_method(_apply_path_timeline, 0.0, _path_timeline_total, _path_timeline_total)
	else:
		var use_duration := travel_duration if duration <= 0.0 else duration
		tween.tween_method(_apply_path_frame, 0.0, 1.0, maxf(0.04, use_duration))
	tween.tween_property(self, "modulate:a", 0.0, 0.05)
	tween.finished.connect(queue_free, CONNECT_ONE_SHOT)


func _rebuild_path_length_table() -> void:
	_path_lengths = PackedFloat32Array()
	_path_total_len = 0.0
	_path_lengths.append(0.0)
	for i in range(1, _path_points.size()):
		_path_total_len += _path_points[i - 1].distance_to(_path_points[i])
		_path_lengths.append(_path_total_len)
	_path_total_len = maxf(_path_total_len, 1.0)


func _build_path_timeline(move_speed: float, corner_pause: float) -> void:
	_path_timeline.clear()
	_path_timeline_total = 0.0
	var speed := maxf(move_speed, 1.0)
	var dist_cursor := 0.0
	var time_cursor := 0.0
	for seg_i in range(1, _path_points.size()):
		var seg_len := _path_points[seg_i - 1].distance_to(_path_points[seg_i])
		if seg_len <= 1e-5:
			continue
		var seg_time := maxf(0.02, seg_len / speed)
		_path_timeline.append({
			"t0": time_cursor,
			"t1": time_cursor + seg_time,
			"d0": dist_cursor,
			"d1": dist_cursor + seg_len,
		})
		time_cursor += seg_time
		dist_cursor += seg_len
		if seg_i < _path_points.size() - 1 and corner_pause > 0.0:
			_path_timeline.append({
				"t0": time_cursor,
				"t1": time_cursor + corner_pause,
				"d0": dist_cursor,
				"d1": dist_cursor,
			})
			time_cursor += corner_pause
	_path_timeline_total = time_cursor


func _apply_path_timeline(elapsed: float) -> void:
	if _path_timeline.is_empty():
		_apply_path_frame_at_distance(_path_total_len)
		return
	elapsed = clampf(elapsed, 0.0, _path_timeline_total)
	for seg_v in _path_timeline:
		var seg: Dictionary = seg_v as Dictionary
		var t1: float = float(seg.get("t1", 0.0))
		if elapsed > t1 + 1e-6:
			continue
		var t0: float = float(seg.get("t0", 0.0))
		var d0: float = float(seg.get("d0", 0.0))
		var d1: float = float(seg.get("d1", 0.0))
		var span := t1 - t0
		var seg_t := 0.0 if span <= 1e-6 else (elapsed - t0) / span
		_apply_path_frame_at_distance(lerpf(d0, d1, clampf(seg_t, 0.0, 1.0)))
		return
	_apply_path_frame_at_distance(_path_total_len)


func _apply_path_frame(t: float) -> void:
	_apply_path_frame_at_distance(clampf(t, 0.0, 1.0) * _path_total_len)


func _apply_bullet_visual_frame(t: float) -> void:
	var head: Vector2 = _fire_from.lerp(_fire_to, t)
	var tail: Vector2 = head - _fire_dir * _fire_trail
	_bolt.global_position = head
	_bolt.rotation = _fire_dir.angle()
	var seg := PackedVector2Array([tail, head])
	_line.points = seg
	_glow.points = seg


func _apply_path_frame_at_distance(dist: float) -> void:
	if _path_points.size() < 2:
		return
	var head := _path_points[0]
	dist = clampf(dist, 0.0, _path_total_len)
	for i in range(1, _path_lengths.size()):
		if _path_lengths[i] >= dist - 0.0001:
			var seg_len := _path_lengths[i] - _path_lengths[i - 1]
			var seg_t := 0.0 if seg_len <= 1e-5 else (dist - _path_lengths[i - 1]) / seg_len
			head = _path_points[i - 1].lerp(_path_points[i], clampf(seg_t, 0.0, 1.0))
			_fire_dir = (_path_points[i] - _path_points[i - 1]).normalized()
			if _fire_dir.length_squared() <= 1e-8:
				_fire_dir = Vector2.RIGHT
			break
		head = _path_points[i]
		_fire_dir = (_path_points[i] - _path_points[i - 1]).normalized()

	_fire_trail = clampf(bullet_trail_length, 1.0, maxf(_path_total_len * 0.35, 1.0))
	var tail: Vector2 = head - _fire_dir * _fire_trail
	_bolt.global_position = head
	_bolt.rotation = _fire_dir.angle()
	var seg := PackedVector2Array([tail, head])
	_line.points = seg
	_glow.points = seg


func _ensure_nodes() -> void:
	if _line == null or not is_instance_valid(_line):
		_line = Line2D.new()
		_line.width = maxf(1.0, width)
		_line.default_color = core_color
		_line.antialiased = true
		_line.top_level = true
		add_child(_line)
	if _glow == null or not is_instance_valid(_glow):
		_glow = Line2D.new()
		_glow.width = maxf(2.0, width * 2.5)
		_glow.default_color = glow_color
		_glow.antialiased = true
		_glow.top_level = true
		add_child(_glow)
	if _bolt == null or not is_instance_valid(_bolt):
		_bolt = Sprite2D.new()
		_bolt.texture = _get_pixel_texture()
		_bolt.centered = true
		_bolt.scale = Vector2(bolt_scale, maxf(1.0, bolt_scale * 0.55))
		_bolt.modulate = core_color
		_bolt.top_level = true
		add_child(_bolt)


func _get_pixel_texture() -> Texture2D:
	if _pixel_tex != null:
		return _pixel_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_pixel_tex = ImageTexture.create_from_image(img)
	return _pixel_tex
