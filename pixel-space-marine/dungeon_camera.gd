extends Camera2D
## 地牢生成后自动居中，并将整张地图纳入视野。

## 计算「整图刚好进视口」时的 zoom 下限系数。
const _MAP_FIT_VIEWPORT_MARGIN: float = 0.95

@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
@export var tile_size: int = 16
@export var highlight_player_after_fit: bool = true
@export var player_path: NodePath = NodePath("../Player")
@export_group("Follow")
@export var follow_player: bool = true
@export_range(0.0, 25.0, 0.1) var follow_speed: float = 10.0
@export var toggle_follow_key: Key = KEY_R
@export_range(0, 8, 1) var follow_boundary_buffer_tiles: int = 1
@export_group("Zoom")
@export var allow_wheel_zoom: bool = true
@export_range(0.01, 0.5, 0.01) var wheel_zoom_step: float = 0.08
## Godot Camera2D：数值越大越「放大」。换层生成后会重新套用；若小于本关「整图可见」所需 zoom，会自动抬高到该下限。
@export_range(0.05, 12.0, 0.01) var initial_zoom: float = 1.0
## 滚轮 / 目标 zoom 的上限（绝对值）。若小于当关「整图可见」所需 zoom，会自动抬高，否则无法完整看到地图。
@export_range(0.05, 16.0, 0.01) var max_zoom: float = 3.0
@export_group("Pan")
@export var allow_mouse_drag_pan: bool = true
@export var drag_pan_button: MouseButton = MOUSE_BUTTON_MIDDLE

@export_group("Shake")
@export var enable_camera_shake: bool = true
@export_range(0.0, 40.0, 0.1) var default_shake_strength: float = 6.0
@export_range(0.01, 0.5, 0.01) var default_shake_duration: float = 0.12

var _dungeon: DungeonGenerator
var _player: Node2D
var _fit_zoom_scalar: float = 1.0
var _target_zoom_scalar: float = 1.0
var _max_zoom_scalar: float = 1.0
var _map_pixel_size: Vector2 = Vector2.ZERO
var _is_drag_panning: bool = false
var _snap_to_player_pending: bool = false
var _shake_time_left: float = 0.0
var _shake_strength: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 换层时沿用缩放（与 `DungeonGenerator.layout_camera_maintain_zoom` 配套）。
var _persisted_zoom_scalar: float = -1.0
## 当前关是否允许跟随 / 平移 / 滚轮（来自预设或默认导出）。
var _layout_allows_camera_control: bool = true
var _export_default_follow: bool = true
var _export_default_allow_wheel: bool = true
var _export_default_allow_pan: bool = true


func _ready() -> void:
	_export_default_follow = follow_player
	_export_default_allow_wheel = allow_wheel_zoom
	_export_default_allow_pan = allow_mouse_drag_pan
	_shake_rng.randomize()
	_bind_dungeon_or_retry()


func _bind_dungeon_or_retry() -> void:
	_resolve_dungeon()
	if _dungeon == null:
		call_deferred("_retry_bind_dungeon")
		return
	_connect_dungeon()


func _retry_bind_dungeon() -> void:
	_resolve_dungeon()
	if _dungeon == null:
		push_warning("DungeonCamera: 未找到 DungeonGenerator。")
		return
	_connect_dungeon()


func _connect_dungeon() -> void:
	# 每次换层都会 emit generation_finished（预设 / 随机），需反复 fit，不能用 ONE_SHOT。
	if not _dungeon.generation_finished.is_connected(_on_dungeon_ready):
		_dungeon.generation_finished.connect(_on_dungeon_ready)
	if not _dungeon.grid_map.is_empty():
		call_deferred("_on_dungeon_ready")


func _on_dungeon_ready() -> void:
	tile_size = _dungeon.tile_size
	_apply_layout_camera_policy_from_dungeon()
	fit_to_map(_dungeon.map_width, _dungeon.map_height)
	_resolve_player()
	if follow_player:
		_snap_to_player_pending = true
		call_deferred("_snap_camera_to_player_immediately")


func _apply_layout_camera_policy_from_dungeon() -> void:
	_layout_allows_camera_control = true
	if _dungeon != null:
		_layout_allows_camera_control = bool(_dungeon.layout_camera_enable_control)
	if _layout_allows_camera_control:
		follow_player = _export_default_follow
		allow_wheel_zoom = _export_default_allow_wheel
		allow_mouse_drag_pan = _export_default_allow_pan
	else:
		follow_player = false
		allow_wheel_zoom = false
		allow_mouse_drag_pan = false
	_snap_to_player_pending = false
	_is_drag_panning = false


func fit_to_map(map_width: int, map_height: int) -> void:
	var map_pixels := Vector2(map_width, map_height) * float(tile_size)
	_map_pixel_size = map_pixels
	position = map_pixels * 0.5
	enabled = true
	make_current()
	_apply_limits(map_pixels)

	await get_tree().process_frame
	_apply_zoom_to_fit(map_pixels)
	if highlight_player_after_fit and _layout_allows_camera_control:
		_pulse_player_marker()


func _apply_zoom_to_fit(map_pixels: Vector2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if map_pixels.x <= 0.0 or map_pixels.y <= 0.0:
		return
	var zoom_x := viewport_size.x / map_pixels.x
	var zoom_y := viewport_size.y / map_pixels.y
	_fit_zoom_scalar = minf(zoom_x, zoom_y) * _MAP_FIT_VIEWPORT_MARGIN
	_max_zoom_scalar = maxf(max_zoom, _fit_zoom_scalar)

	var maintain := _dungeon != null and bool(_dungeon.layout_camera_maintain_zoom)
	if maintain and _persisted_zoom_scalar > 0.0:
		_target_zoom_scalar = _persisted_zoom_scalar
	else:
		_target_zoom_scalar = clampf(initial_zoom, _fit_zoom_scalar, _max_zoom_scalar)
	_persisted_zoom_scalar = _target_zoom_scalar

	zoom = Vector2(_target_zoom_scalar, _target_zoom_scalar)


func _process(delta: float) -> void:
	if _snap_to_player_pending:
		_snap_camera_to_player_immediately()
	_update_zoom(delta)
	_update_follow(delta)
	_update_shake(delta)


func _input(event: InputEvent) -> void:
	if not _layout_allows_camera_control:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == toggle_follow_key:
			follow_player = not follow_player
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		if allow_wheel_zoom and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_set_target_zoom(_target_zoom_scalar + wheel_zoom_step)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_set_target_zoom(_target_zoom_scalar - wheel_zoom_step)
				get_viewport().set_input_as_handled()
				return
		if allow_mouse_drag_pan and event.button_index == drag_pan_button:
			_is_drag_panning = event.pressed
			if _is_drag_panning:
				follow_player = false
			else:
				global_position = _clamp_camera_position(global_position, 0.0)
			get_viewport().set_input_as_handled()
			return
	if allow_mouse_drag_pan and _is_drag_panning and event is InputEventMouseMotion:
		global_position -= event.relative / zoom
		get_viewport().set_input_as_handled()
		return


func _set_target_zoom(value: float) -> void:
	_target_zoom_scalar = clampf(value, _fit_zoom_scalar, _max_zoom_scalar)


func _update_zoom(delta: float) -> void:
	if is_equal_approx(zoom.x, _target_zoom_scalar):
		return
	var t := 1.0 - exp(-12.0 * delta)
	var next_zoom := lerpf(zoom.x, _target_zoom_scalar, t)
	zoom = Vector2(next_zoom, next_zoom)
	var follow_buffer := _follow_buffer_pixels() if follow_player and not _is_drag_panning else 0.0
	global_position = _clamp_camera_position(global_position, follow_buffer)


func _update_follow(delta: float) -> void:
	if not follow_player:
		return
	if _is_drag_panning:
		return
	if _player == null or not is_instance_valid(_player):
		_resolve_player()
		return
	if _snap_to_player_pending:
		_snap_camera_to_player_immediately()
		return
	var t := 1.0 if follow_speed <= 0.0 else (1.0 - exp(-follow_speed * delta))
	var desired := global_position.lerp(_player.global_position, t)
	global_position = _clamp_camera_position(desired, _follow_buffer_pixels())


func _apply_limits(map_pixels: Vector2) -> void:
	# 边界约束改为脚本内手动 clamp，便于区分“跟随缓冲”与“普通边界”。
	limit_enabled = false
	limit_left = 0
	limit_top = 0
	limit_right = int(map_pixels.x)
	limit_bottom = int(map_pixels.y)


func _follow_buffer_pixels() -> float:
	return float(maxi(0, follow_boundary_buffer_tiles) * tile_size)


func _clamp_camera_position(camera_pos: Vector2, buffer_pixels: float) -> Vector2:
	if _map_pixel_size.x <= 0.0 or _map_pixel_size.y <= 0.0:
		return camera_pos
	return Vector2(
		clampf(camera_pos.x, -buffer_pixels, _map_pixel_size.x + buffer_pixels),
		clampf(camera_pos.y, -buffer_pixels, _map_pixel_size.y + buffer_pixels)
	)


func _resolve_player() -> void:
	if not player_path.is_empty():
		_player = get_node_or_null(player_path) as Node2D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D


func _snap_camera_to_player_immediately() -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_player()
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("get"):
		# 优先使用重生后的格点坐标，避免视觉上从旧位置滑向新位置。
		var gp = _player.get("grid_pos")
		if gp is Vector2i:
			var spawn_world := Vector2(gp) * float(tile_size) + Vector2.ONE * (tile_size * 0.5)
			var buffer_spawn := _follow_buffer_pixels() if follow_player else 0.0
			global_position = _clamp_camera_position(spawn_world, buffer_spawn)
			offset = Vector2.ZERO
			_snap_to_player_pending = false
			return
	var buffer := _follow_buffer_pixels() if follow_player else 0.0
	global_position = _clamp_camera_position(_player.global_position, buffer)
	offset = Vector2.ZERO
	_snap_to_player_pending = false


func request_shake(strength: float = -1.0, duration: float = -1.0) -> void:
	if not enable_camera_shake:
		return
	var use_strength := default_shake_strength if strength < 0.0 else strength
	var use_duration := default_shake_duration if duration < 0.0 else duration
	_shake_strength = maxf(_shake_strength, use_strength)
	_shake_time_left = maxf(_shake_time_left, use_duration)


func _update_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		if _shake_offset != Vector2.ZERO:
			offset = Vector2.ZERO
			_shake_offset = Vector2.ZERO
		return
	_shake_time_left = maxf(0.0, _shake_time_left - delta)
	var damping := _shake_time_left / maxf(default_shake_duration, 0.0001)
	var strength := _shake_strength * clampf(damping, 0.0, 1.0)
	_shake_offset = Vector2(
		_shake_rng.randf_range(-strength, strength),
		_shake_rng.randf_range(-strength, strength)
	)
	offset = _shake_offset
	if _shake_time_left <= 0.0:
		offset = Vector2.ZERO
		_shake_offset = Vector2.ZERO
		_shake_strength = 0.0


func _pulse_player_marker() -> void:
	var player := get_node_or_null(player_path) as Sprite2D
	if player == null:
		return
	var base_scale := player.scale
	var tween := create_tween()
	tween.tween_property(player, "scale", base_scale * 1.6, 0.12)
	tween.tween_property(player, "scale", base_scale, 0.12)


func _resolve_dungeon() -> void:
	if not dungeon_generator_path.is_empty():
		var node := get_node_or_null(dungeon_generator_path)
		if node is DungeonGenerator:
			_dungeon = node
	if _dungeon == null:
		var found := get_tree().get_first_node_in_group("dungeon_generator")
		if found is DungeonGenerator:
			_dungeon = found
