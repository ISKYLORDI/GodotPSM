extends Sprite2D
## 像素地牢式严格格子移动（挂在 Sprite2D 上）。

signal grid_position_changed(grid_pos: Vector2i)

@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")

var tile_size: int = 16

const _KEY_TO_DIR: Dictionary = {
	KEY_UP: Vector2i(0, -1),
	KEY_DOWN: Vector2i(0, 1),
	KEY_LEFT: Vector2i(-1, 0),
	KEY_RIGHT: Vector2i(1, 0),
	KEY_W: Vector2i(0, -1),
	KEY_S: Vector2i(0, 1),
	KEY_A: Vector2i(-1, 0),
	KEY_D: Vector2i(1, 0),
}
const FOOTSTEP_SFX_NAMES: PackedStringArray = ["Footstep1", "Footstep2", "Footstep3"]
const WATER_FOOTSTEP_SFX_NAMES: PackedStringArray = ["WaterFootstep1", "WaterFootstep2", "WaterFootstep3"]
## 常驻瞄准线段（虚实线）相对原绘制 alpha 的整体倍率。
const AIM_GUN_LINE_ALPHA_SCALE: float = 0.5
## Line2D 画在图层根上：玩家足下框 < 枪线 < 远端准星（假定玩家本体 z≈45~55）。
const AIM_Z_PLAYER_CELL_CORNERS := 44
const AIM_Z_GUN_LINE := 46
const AIM_Z_REMOTE_CROSSHAIR := 620
const AIM_LINE_SURFACE_BIAS: float = 0.85

@export_group("Map")
@export var dungeon_generator_path: NodePath = NodePath("")
@export var spawn_at_random_floor: bool = true

@export_group("Movement")
@export var move_duration: float = 0.1
@export var wall_bump_distance_ratio: float = 0.15
@export var wall_bump_duration: float = 0.05
@export var diagonal_move: bool = true
## 两个方向键的最大间隔时间（秒），在此范围内视为斜向输入
@export_range(0.05, 0.5, 0.01) var diagonal_input_window: float = 0.15
@export var hold_repeat: bool = true
## 按住后开始连续移动前的初始延迟（秒）
@export_range(0.05, 1.0, 0.05) var hold_repeat_delay: float = 0.25
## 连续移动的间隔（秒）
@export_range(0.05, 0.5, 0.05) var hold_repeat_interval: float = 0.1
@export_range(0.03, 0.5, 0.01) var footstep_repeat_interval: float = 0.1

@export_group("Spawn")
@export var starting_grid_pos: Vector2i = Vector2i(-1, -1)

@export_group("Animation")
@export var idle_animation: StringName = &"Idle"
@export var walk_animation: StringName = &"Walk"
@export var attack_animation: StringName = &"Attack"
@export var death_animation: StringName = &"Death"
@export var reload_animation: StringName = &"Reload"
@export var aim_animation: StringName = &"Aim"
@export var aim_unload_animation: StringName = &"AimUnload"
@export_range(0.1, 4.0, 0.05) var attack_animation_speed_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var death_animation_speed_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var reload_animation_speed_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var aim_animation_speed_scale: float = 1.0
@export var auto_fit_sprite_to_tile: bool = true
@export var visual_offset: Vector2 = Vector2.ZERO

@export_group("Combat")
@export var max_hp: int = 10
@export var attack_damage: int = 1
@export var melee_lunge_distance_ratio: float = 0.28
@export var melee_lunge_duration: float = 0.06
@export var melee_impact_particle_count: int = 14
@export var melee_impact_particle_speed_min: float = 10.0
@export var melee_impact_particle_speed_max: float = 28.0
@export var melee_impact_particle_life_min: float = 0.10
@export var melee_impact_particle_life_max: float = 0.24
@export var melee_camera_shake_strength: float = 7.0
@export var melee_camera_shake_duration: float = 0.10
@export_group("Ranged")
@export var ranged_clip_size: int = 6
@export var ranged_damage: int = 1
@export_range(1, 500, 1) var ranged_max_distance: int = 12
@export_range(1, 100, 1) var ranged_auto_refill_turns: int = 20
@export var ranged_attack_animation: StringName = &"Attack"
## 在 `attack_animation_speed_scale` 基础上的远程额外倍率（1.0 = 仅使用近战同项倍率）。
@export_range(0.1, 4.0, 0.05) var ranged_attack_animation_speed_scale: float = 1.0
@export var target_highlight_color: Color = Color(1.0, 0.2, 0.2, 0.9)
@export var target_highlight_line_width: float = 2.0
@export_range(2.0, 24.0, 1.0) var aim_dash_length: float = 8.0
@export_range(1.0, 24.0, 1.0) var aim_dash_gap: float = 5.0
@export_range(0.0, 120.0, 1.0) var aim_dash_speed: float = 36.0
@export_range(2.0, 24.0, 1.0) var aim_crosshair_length: float = 8.0
@export_range(0.5, 4.0, 0.1) var aim_crosshair_line_width: float = 1.0
@export_range(2.0, 24.0, 1.0) var aim_square_corner_length: float = 6.0
@export_range(0.05, 1.0, 0.05) var aim_square_transparency: float = 0.78
@export_range(0.5, 10.0, 0.1) var aim_flash_speed: float = 3.2
@export_range(0.5, 4.0, 0.1) var aim_line_width: float = 1.0
## 未上膛时瞄准 UI（准星、边框、枪线、足下框等）使用的统一灰色调。
@export var aim_unloaded_ui_color: Color = Color(0.52, 0.52, 0.56, 1.0)
## 转动小角标相对外框向内的边距（像素），略小于外圈边框。
@export_range(0.5, 8.0, 0.05) var aim_spin_border_inset: float = 2.25
## 转动角长度相对 `aim_square_corner_length` 的比例（整体更小）。
@export_range(0.35, 1.0, 0.05) var aim_spin_corner_scale: float = 0.68
## 沿内边框跑一整圈的路径速度（每秒圈数）。
@export_range(0.05, 6.0, 0.05) var aim_spin_path_laps_per_sec: float = 1.6
## 第二段转角相对主路径在周长上落后（或超前）的比例，同向运动；0.5 为对侧。
@export_range(0.0, 1.0, 0.01) var aim_spin_second_path_perimeter_frac: float = 0.5

@export_group("Transition")
@export_range(0.01, 1.0, 0.01) var level_fade_out_duration: float = 0.15
@export_range(0.0, 1.0, 0.01) var level_black_hold_duration: float = 0.08
@export_range(0.01, 1.5, 0.01) var level_fade_in_duration: float = 0.18

var grid_pos: Vector2i = Vector2i.ZERO
var dungeon_generator: DungeonGenerator = null
var turn_controller: TurnController = null

var _grid_map: Array = []
var _map_width: int = 0
var _map_height: int = 0
var _is_moving: bool = false
var _move_tween: Tween
var _spawned: bool = false
var _last_dir: Vector2i = Vector2i.ZERO
var _last_dir_time_ms: int = 0
var _pending_single_dir: Vector2i = Vector2i.ZERO
var _pending_single_dir_time_ms: int = 0
var _queued_dir: Vector2i = Vector2i.ZERO
var _move_start_grid_pos: Vector2i = Vector2i.ZERO
var _hold_timer: float = 0.0
var _hold_active: bool = false
var _hold_last_dir: Vector2i = Vector2i.ZERO
var _current_animation: StringName = &""
var _base_scale_x: float = 1.0
var _hp: int = 10
var _dead: bool = false
var _last_attack_duration: float = 0.08
var _last_damage_feedback_duration: float = 0.08
var _last_wait_duration: float = 0.0
var _action_lock_remaining: float = 0.0
var _blood_particle_texture: Texture2D = null
var _ui_pixel_texture: Texture2D = null
var _auto_path: Array[Vector2i] = []
var _auto_force_mode: bool = false
var _auto_known_visible_enemy_ids: Dictionary = {}
var _auto_attack_target_id: int = 0
var _is_level_transitioning: bool = false
var _transition_layer: CanvasLayer = null
var _transition_rect: ColorRect = null
var _suppress_move_input_until_release: bool = false
var _footstep_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_footstep_time_ms: int = -1000000000
var _health_bar_root: Node2D = null
var _health_bar_bg: Sprite2D = null
var _health_bar_fill: Sprite2D = null
var _is_aim_mode: bool = false
var _ammo_in_clip: int = 0
var _is_reloaded: bool = true
var _last_ranged_attack_duration: float = 0.0
var _ranged_target_marker: Dictionary = {}
var _aim_hit_crosshair_lines: Array[Line2D] = []
var _aim_hit_square_lines: Array[Line2D] = []
var _aim_preview_solid_line: Line2D = null
var _aim_preview_dashed_lines: Array[Line2D] = []
var _aim_player_cell_corner_lines: Array[Line2D] = []
## 命中格内沿内缩边框滑动的转角：主路径 + 同向周长偏移的第二路径（非镜像，方向一致）。
var _aim_hit_spin_corner_line: Line2D = null
var _aim_hit_spin_corner_line_b: Line2D = null
var _aim_dash_phase: float = 0.0
## 枪口射线在开火动画期间短时隐藏，`Time.get_ticks_msec()` 在此前不绘制枪线。
var _aim_gun_lines_suppressed_until_ms: int = 0
var _reload_indicator_node: Sprite2D = null
var _ammo_nodes: Array[Sprite2D] = []
var _turns_since_auto_refill: int = 0
var _fog_of_war: Node = null
var _level_flow_controller: LevelFlowController = null
var _fire_attachment_turns: int = 0
var _fire_particle_accum: float = 0.0
const _FIRE_ATTACH_PARTICLE_INTERVAL := 0.045
var _preserve_player_state_on_next_floor: bool = false
var _pending_next_floor_state: Dictionary = {}


## 与门图层的基准 z：与任一门占位格同行时夹在门下，否则略高于门以保持纵深感。
const PLAYER_Z_DEFAULT_OVERLAY: int = -10


## 与 `DungeonGenerator` 地板层（约 -20）与门/柱/出口 Overlay（运行时约 0）之间的深度。
## 仅当逻辑格与某一扇门的网格 **Y（纵轴同行）** 相同时才把玩家压在门下，否则始终在门图层之上绘制。
func _apply_actor_depth_vs_overlay() -> void:
	z_as_relative = false
	if dungeon_generator == null or dungeon_generator.grid_map.is_empty():
		z_index = PLAYER_Z_DEFAULT_OVERLAY
		return
	var door_canvas_z: int = dungeon_generator.get_door_canvas_z_index()
	if dungeon_generator.is_aligned_with_any_door_row(grid_pos):
		z_index = mini(PLAYER_Z_DEFAULT_OVERLAY, door_canvas_z - 1)
	else:
		z_index = door_canvas_z + 1


func _ready() -> void:
	_apply_actor_depth_vs_overlay()
	add_to_group("player")
	_footstep_rng.randomize()
	_base_scale_x = absf(scale.x) if not is_zero_approx(scale.x) else 1.0
	_hp = maxi(1, max_hp)
	_dead = false
	visible = true
	_ensure_visible_texture()
	_ensure_transition_overlay()
	_ensure_health_bar_nodes()
	_ammo_in_clip = maxi(0, ranged_clip_size)
	_is_reloaded = true
	_resolve_dungeon_reference()
	_resolve_turn_controller()
	_resolve_level_flow_controller()
	_connect_turn_controller_signals()
	if dungeon_generator == null:
		push_error("Player: 未找到 DungeonGenerator，无法出生。")
		return

	if not dungeon_generator.generation_finished.is_connected(_on_dungeon_generation_finished):
		dungeon_generator.generation_finished.connect(_on_dungeon_generation_finished)
	call_deferred("_try_spawn_after_dungeon")


func _try_spawn_after_dungeon() -> void:
	if _spawned:
		return
	if dungeon_generator == null or dungeon_generator.grid_map.is_empty():
		return
	_on_dungeon_ready()


## 地图重载后仍为同一场上的玩家时需要刷新与门的 z 排序。
func _on_dungeon_generation_finished() -> void:
	if _spawned:
		if dungeon_generator != null:
			tile_size = dungeon_generator.tile_size
		_sync_cached_map_size_from_dungeon()
		_apply_actor_depth_vs_overlay()
		return
	_on_dungeon_ready()


func _sync_cached_map_size_from_dungeon() -> void:
	if dungeon_generator == null:
		return
	_map_width = dungeon_generator.map_width
	_map_height = dungeon_generator.map_height


func _on_dungeon_ready() -> void:
	if _spawned:
		return
	_spawned = true
	_dead = false
	_action_lock_remaining = 0.0
	_clear_auto_navigation()
	_clear_ranged_target_markers()
	var restore_state := _preserve_player_state_on_next_floor and not _pending_next_floor_state.is_empty()
	if restore_state:
		_hp = clampi(int(_pending_next_floor_state.get("hp", _hp)), 1, maxi(1, max_hp))
		_ammo_in_clip = clampi(int(_pending_next_floor_state.get("ammo_in_clip", _ammo_in_clip)), 0, maxi(0, ranged_clip_size))
		_is_reloaded = _pending_next_floor_state.get("is_reloaded", _is_reloaded) == true
		_turns_since_auto_refill = maxi(0, int(_pending_next_floor_state.get("turns_since_auto_refill", _turns_since_auto_refill)))
		var restore_aim_mode: bool = _pending_next_floor_state.get("is_aim_mode", false) == true and _ammo_in_clip > 0
		_set_aim_mode(restore_aim_mode)
	else:
		_hp = maxi(1, max_hp)
		_set_aim_mode(false)
		_ammo_in_clip = maxi(0, ranged_clip_size)
		_is_reloaded = true
		_turns_since_auto_refill = 0
	_preserve_player_state_on_next_floor = false
	_pending_next_floor_state.clear()
	modulate = Color.WHITE

	if dungeon_generator != null:
		tile_size = dungeon_generator.tile_size
		_sync_cached_map_size_from_dungeon()
	_ensure_visible_texture()
	if auto_fit_sprite_to_tile:
		_fit_sprite_to_tile()
	_apply_spawn_position()

	if not is_walkable(grid_pos):
		grid_pos = _find_nearest_walkable(grid_pos)

	_snap_to_grid_center()
	_apply_actor_depth_vs_overlay()
	_play_player_animation(idle_animation)
	_update_health_bar_visual()
	print("Player 出生: grid=%s world=%s" % [grid_pos, position])
	grid_position_changed.emit(grid_pos)


## 按当前 `position` 反推所在格（含移动补间），与足下框、预览枪线一致。
func _visual_aim_origin_cell() -> Vector2i:
	var q: Vector2 = (position - visual_offset) / float(tile_size) - Vector2(0.5, 0.5)
	return Vector2i(floori(q.x), floori(q.y))


func _input(event: InputEvent) -> void:
	if _dead or _is_action_locked() or _is_level_transitioning:
		return
	if _try_handle_aim_and_shot_input(event):
		return
	if _suppress_move_input_until_release:
		return
	if _try_handle_mouse_command(event):
		return
	if _try_handle_wait_input(event):
		return
	_handle_move_input(event)


func _process(delta: float) -> void:
	_sync_fire_ambience_audio()
	_update_fire_attachment_visuals(delta)
	if _action_lock_remaining > 0.0:
		_action_lock_remaining = maxf(0.0, _action_lock_remaining - delta)
	if _dead:
		_update_health_bar_visual()
		_update_ranged_ui()
		return
	if _suppress_move_input_until_release:
		if _get_held_direction() == Vector2i.ZERO:
			_suppress_move_input_until_release = false
		_update_health_bar_visual()
		_update_ranged_ui()
		return
	if _is_action_locked() or _is_level_transitioning:
		_update_health_bar_visual()
		_update_ranged_ui()
		return
	_update_health_bar_visual()
	_update_ranged_ui()
	_update_auto_navigation()
	if _spawned:
		_apply_actor_depth_vs_overlay()
	_flush_pending_single_direction()

	if not hold_repeat or not _spawned:
		return

	var held_dir := _get_held_direction()

	# 方向改变（含松开）时重置计时
	if held_dir != _hold_last_dir:
		_hold_last_dir = held_dir
		_hold_timer = 0.0
		_hold_active = false
		if held_dir == Vector2i.ZERO and not _is_moving:
			if _is_aim_mode:
				_hold_aim_pose()
			else:
				_play_player_animation(idle_animation)
		return

	if held_dir == Vector2i.ZERO:
		return

	_hold_timer += delta
	var threshold := hold_repeat_delay if not _hold_active else hold_repeat_interval
	if _hold_timer >= threshold and not _is_moving:
		_hold_active = true
		_hold_timer -= threshold  # 保留余量，维持匀速节奏
		_pending_single_dir = Vector2i.ZERO
		_try_move(held_dir)


func _handle_move_input(event: InputEvent) -> void:
	if not _spawned:
		return
	if event is InputEventKey and event.is_echo():
		return
	if not event.is_pressed():
		_handle_move_release(event)
		return

	var direction := _direction_from_event(event)
	if direction == Vector2i.ZERO:
		return
	_clear_auto_navigation()

	var now_ms := Time.get_ticks_msec()

	# 斜向优化：先短暂缓冲第一下方向键，只提交一次最终方向，避免敌人双回合。
	if diagonal_move:
		if _pending_single_dir != Vector2i.ZERO and direction != _pending_single_dir:
			var elapsed_ms := now_ms - _pending_single_dir_time_ms
			if elapsed_ms <= int(diagonal_input_window * 1000.0) \
					and _are_adjacent_dirs(_pending_single_dir, direction):
				var diag := _pending_single_dir + direction
				_pending_single_dir = Vector2i.ZERO
				_pending_single_dir_time_ms = 0
				_submit_direction(diag)
				get_viewport().set_input_as_handled()
				return

		if _pending_single_dir == Vector2i.ZERO:
			_pending_single_dir = direction
			_pending_single_dir_time_ms = now_ms
		elif direction != _pending_single_dir:
			_pending_single_dir = direction
			_pending_single_dir_time_ms = now_ms

		_last_dir = direction
		_last_dir_time_ms = now_ms
		get_viewport().set_input_as_handled()
		return

	_submit_direction(direction)
	get_viewport().set_input_as_handled()


func _handle_move_release(event: InputEvent) -> void:
	if not diagonal_move:
		return
	if _pending_single_dir == Vector2i.ZERO:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not _KEY_TO_DIR.has(key_event.keycode):
		return

	var released_dir: Vector2i = _KEY_TO_DIR[key_event.keycode]
	if released_dir != _pending_single_dir:
		return
	if _get_held_direction() != Vector2i.ZERO:
		return

	var dir := _pending_single_dir
	_pending_single_dir = Vector2i.ZERO
	_pending_single_dir_time_ms = 0
	_submit_direction(dir)
	get_viewport().set_input_as_handled()


func _flush_pending_single_direction() -> void:
	if _pending_single_dir == Vector2i.ZERO:
		return
	var elapsed_ms := Time.get_ticks_msec() - _pending_single_dir_time_ms
	if elapsed_ms < int(diagonal_input_window * 1000.0):
		return
	var dir := _pending_single_dir
	_pending_single_dir = Vector2i.ZERO
	_pending_single_dir_time_ms = 0
	_submit_direction(dir)


func _submit_direction(direction: Vector2i) -> void:
	if _is_action_locked():
		return
	_last_dir = direction
	_last_dir_time_ms = Time.get_ticks_msec()
	if _is_moving:
		_queued_dir = direction
	else:
		_try_move(direction)


func set_grid_map(map: Array, width: int = 0, height: int = 0) -> void:
	_grid_map = map
	_map_width = width if width > 0 else (_grid_map[0].size() if not _grid_map.is_empty() else 0)
	_map_height = height if height > 0 else _grid_map.size()


func bind_dungeon(generator: DungeonGenerator) -> void:
	dungeon_generator = generator
	_grid_map.clear()
	tile_size = generator.tile_size
	_sync_cached_map_size_from_dungeon()


func is_walkable(target_grid_pos: Vector2i) -> bool:
	if dungeon_generator != null:
		if dungeon_generator.is_inactive_door_at(target_grid_pos):
			return false
		return dungeon_generator.get_tile(target_grid_pos) == DungeonGenerator.TileType.FLOOR
	if _grid_map.is_empty():
		return false
	if not _is_grid_in_bounds(target_grid_pos):
		return false
	return _grid_map[target_grid_pos.y][target_grid_pos.x] == DungeonGenerator.TileType.FLOOR


func grid_to_world(grid: Vector2i) -> Vector2:
	return Vector2(grid) * float(tile_size) + Vector2.ONE * (tile_size * 0.5) + visual_offset


## 棋盘格中心的视口／世界坐标（与 Line2D `top_level` 一致）；`grid_to_world` 为相对于父节点的局部坐标。
func _grid_cell_center_global(cell: Vector2i) -> Vector2:
	var lp := grid_to_world(cell)
	var par := get_parent()
	if par is Node2D:
		return (par as Node2D).to_global(lp)
	return lp


func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / float(tile_size)),
		floori(world_pos.y / float(tile_size))
	)


func _try_move(direction: Vector2i) -> void:
	if turn_controller != null:
		turn_controller.queue_player_direction(direction)
		return
	var target_grid := grid_pos + direction
	if is_walkable(target_grid):
		_face_toward(direction)
		_move_start_grid_pos = grid_pos
		grid_pos = target_grid
		_start_move_tween(grid_to_world(grid_pos))
	else:
		_move_start_grid_pos = grid_pos
		_play_wall_bump(direction)


func _start_move_tween(target_world: Vector2, play_walk_animation: bool = true) -> void:
	_kill_move_tween()
	_is_moving = true
	if play_walk_animation:
		_play_player_animation(walk_animation)
		_play_footstep_sfx()
	else:
		## 桶等平台击退：禁止进入 Walk，死亡/受击动画优先级更高。
		_play_player_animation(idle_animation)
	_update_health_bar_visual()
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_LINEAR)
	_move_tween.set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(self, "position", target_world, move_duration)
	_move_tween.finished.connect(_on_move_tween_finished, CONNECT_ONE_SHOT)


func _play_wall_bump(direction: Vector2i) -> void:
	_kill_move_tween()
	_is_moving = true
	var home := grid_to_world(grid_pos)
	var nudge := Vector2(direction) * (tile_size * wall_bump_distance_ratio)
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_SINE)
	_move_tween.set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "position", home + nudge, wall_bump_duration)
	_move_tween.tween_property(self, "position", home, wall_bump_duration)
	_move_tween.finished.connect(_on_move_tween_finished, CONNECT_ONE_SHOT)


func _on_move_tween_finished() -> void:
	_is_moving = false
	_move_tween = null
	position = grid_to_world(grid_pos)
	_update_health_bar_visual()
	if _dead:
		return
	grid_position_changed.emit(grid_pos)
	# 到达出口：触发地图重新生成
	if dungeon_generator != null and dungeon_generator.exit_pos == grid_pos:
		_trigger_exit()
		return
	# 如果移动中有排队的方向，立即执行
	if _queued_dir != Vector2i.ZERO:
		var dir := _queued_dir
		_queued_dir = Vector2i.ZERO
		_try_move(dir)
		return
	if hold_repeat and _get_held_direction() != Vector2i.ZERO:
		_play_player_animation(walk_animation)
	else:
		var has_auto_intent := not _auto_path.is_empty() or _auto_attack_target_id != 0
		if not _is_action_locked() and not has_auto_intent:
			if _is_aim_mode:
				_hold_aim_pose()
			else:
				_play_player_animation(idle_animation)


func _capture_player_state_for_next_floor() -> void:
	_pending_next_floor_state = {
		"hp": _hp,
		"ammo_in_clip": _ammo_in_clip,
		"is_reloaded": _is_reloaded,
		"turns_since_auto_refill": _turns_since_auto_refill,
		"is_aim_mode": _is_aim_mode,
	}


func _trigger_exit(preserve_player_state: bool = true) -> void:
	if _is_level_transitioning:
		return
	_play_sfx_if_available("Exit")
	_is_level_transitioning = true
	_preserve_player_state_on_next_floor = preserve_player_state
	if preserve_player_state:
		_capture_player_state_for_next_floor()
	else:
		_pending_next_floor_state.clear()
	_spawned = false
	_queued_dir = Vector2i.ZERO
	_pending_single_dir = Vector2i.ZERO
	_pending_single_dir_time_ms = 0
	_hold_active = false
	_hold_timer = 0.0
	_last_dir = Vector2i.ZERO
	_hold_last_dir = Vector2i.ZERO
	_clear_auto_navigation()
	_clear_ranged_target_markers()
	_set_aim_mode(false)
	if turn_controller != null:
		turn_controller.clear_queued_actions()
	_kill_move_tween()
	_is_moving = false
	await _fade_transition_to(1.0, level_fade_out_duration)
	if _level_flow_controller != null and is_instance_valid(_level_flow_controller):
		_level_flow_controller.advance_floor()
	else:
		dungeon_generator.generate_dungeon()
	if level_black_hold_duration > 0.0:
		await get_tree().create_timer(level_black_hold_duration).timeout
	await _fade_transition_to(0.0, level_fade_in_duration)
	_is_level_transitioning = false


func _kill_move_tween() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null


func _play_player_animation(animation_name: StringName, speed_scale: float = 1.0, loop: bool = true) -> void:
	if anim_player == null:
		return
	var anim := anim_player.get_animation(animation_name)
	if anim == null:
		return
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if _current_animation == animation_name and anim_player.is_playing():
		anim_player.speed_scale = maxf(speed_scale, 0.01)
		return
	_current_animation = animation_name
	anim_player.play(animation_name, -1.0, maxf(speed_scale, 0.01))


func _snap_to_grid_center() -> void:
	position = grid_to_world(grid_pos)


func _draw() -> void:
	# 血条改为 top_level 世界空间节点绘制，避免受角色翻转/缩放影响。
	pass


func _apply_spawn_position() -> void:
	if starting_grid_pos.x >= 0 and starting_grid_pos.y >= 0:
		grid_pos = starting_grid_pos
		if not is_walkable(grid_pos):
			grid_pos = _find_nearest_walkable(grid_pos)
		return
	if spawn_at_random_floor and dungeon_generator != null:
		grid_pos = dungeon_generator.get_random_room_floor_cell()
		return
	grid_pos = world_to_grid(position)


func _find_nearest_walkable(from: Vector2i) -> Vector2i:
	if is_walkable(from):
		return from
	var dim: int = 1
	if dungeon_generator != null:
		dim = maxi(dungeon_generator.map_width, dungeon_generator.map_height)
	elif _map_width > 0 and _map_height > 0:
		dim = maxi(_map_width, _map_height)
	for radius in range(1, dim + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := from + Vector2i(dx, dy)
				if is_walkable(candidate):
					return candidate
	return from


func _fit_sprite_to_tile() -> void:
	var fit_texture := _texture_for_size_fit()
	if fit_texture == null:
		return
	var tex_size := fit_texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	scale = Vector2(float(tile_size) / tex_size.x, float(tile_size) / tex_size.y)


func _texture_for_size_fit() -> Texture2D:
	if texture != null:
		return texture
	if anim_player != null:
		for animation_name in [idle_animation, walk_animation]:
			var anim := anim_player.get_animation(animation_name)
			if anim == null:
				continue
			for track_i in anim.get_track_count():
				if anim.track_get_type(track_i) != Animation.TYPE_VALUE:
					continue
				var track_path := str(anim.track_get_path(track_i))
				if not track_path.ends_with(":texture"):
					continue
				for key_i in anim.track_get_key_count(track_i):
					var value = anim.track_get_key_value(track_i, key_i)
					if value is Texture2D:
						return value
	return null


func _ensure_visible_texture() -> void:
	if texture != null:
		centered = true
		modulate = Color.WHITE
		return
	var img := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.95, 0.2, 0.15, 1.0))
	for x in tile_size:
		img.set_pixel(x, 0, Color.WHITE)
		img.set_pixel(x, tile_size - 1, Color.WHITE)
	for y in tile_size:
		img.set_pixel(0, y, Color.WHITE)
		img.set_pixel(tile_size - 1, y, Color.WHITE)
	texture = ImageTexture.create_from_image(img)
	centered = true
	modulate = Color.WHITE


func _resolve_dungeon_reference() -> void:
	if not is_inside_tree():
		return

	if dungeon_generator == null and not dungeon_generator_path.is_empty():
		var node := get_node_or_null(dungeon_generator_path)
		if node is DungeonGenerator:
			bind_dungeon(node)

	if dungeon_generator == null:
		var found := get_tree().get_first_node_in_group("dungeon_generator")
		if found is DungeonGenerator:
			bind_dungeon(found)

	if dungeon_generator == null and get_parent() != null:
		var sibling := get_parent().get_node_or_null("DungeonGenerator")
		if sibling is DungeonGenerator:
			bind_dungeon(sibling)

	if dungeon_generator != null:
		_sync_cached_map_size_from_dungeon()


func _resolve_turn_controller() -> void:
	if not is_inside_tree():
		return
	if turn_controller != null:
		return
	var found := get_tree().get_first_node_in_group("turn_controller")
	if found is TurnController:
		turn_controller = found
		_connect_turn_controller_signals()


func _resolve_level_flow_controller() -> void:
	if not is_inside_tree():
		return
	if _level_flow_controller != null and is_instance_valid(_level_flow_controller):
		return
	var found := get_tree().get_first_node_in_group("level_flow_controller")
	if found is LevelFlowController:
		_level_flow_controller = found


func _connect_turn_controller_signals() -> void:
	if turn_controller == null:
		return
	var cb := Callable(self, "_on_turn_resolved")
	if not turn_controller.turn_resolved.is_connected(cb):
		turn_controller.turn_resolved.connect(cb)


func _on_turn_resolved(_turn_index: int, player_consumed_turn: bool, _had_attack: bool) -> void:
	if not player_consumed_turn or _dead:
		return
	_turns_since_auto_refill += 1
	var refill_interval := maxi(1, ranged_auto_refill_turns)
	if _turns_since_auto_refill < refill_interval:
		return
	_turns_since_auto_refill = 0
	if _ammo_in_clip >= ranged_clip_size:
		return
	_ammo_in_clip = mini(ranged_clip_size, _ammo_in_clip + 1)


func _is_grid_in_bounds(pos: Vector2i) -> bool:
	if dungeon_generator != null:
		return (
			pos.x >= 0
			and pos.y >= 0
			and pos.x < dungeon_generator.map_width
			and pos.y < dungeon_generator.map_height
		)
	if _map_width > 0 and _map_height > 0:
		return pos.x >= 0 and pos.y >= 0 and pos.x < _map_width and pos.y < _map_height
	if pos.y < 0 or pos.y >= _grid_map.size():
		return false
	var row: Array = _grid_map[pos.y]
	return pos.x >= 0 and pos.x < row.size()


func _get_held_direction() -> Vector2i:
	var dir := Vector2i.ZERO
	if Input.is_key_pressed(KEY_UP)    or Input.is_action_pressed("ui_up"):    dir += Vector2i(0, -1)
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_action_pressed("ui_down"):  dir += Vector2i(0,  1)
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_action_pressed("ui_left"):  dir += Vector2i(-1, 0)
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_action_pressed("ui_right"): dir += Vector2i( 1, 0)
	if Input.is_key_pressed(KEY_W): dir += Vector2i(0, -1)
	if Input.is_key_pressed(KEY_S): dir += Vector2i(0,  1)
	if Input.is_key_pressed(KEY_A): dir += Vector2i(-1, 0)
	if Input.is_key_pressed(KEY_D): dir += Vector2i( 1, 0)
	return dir


func _are_adjacent_dirs(a: Vector2i, b: Vector2i) -> bool:
	# 方向相同或相反（a+b=0）时不构成斜向
	return (a + b) != Vector2i.ZERO


func _direction_from_event(event: InputEvent) -> Vector2i:
	if event is InputEventKey:
		if _KEY_TO_DIR.has(event.keycode):
			return _KEY_TO_DIR[event.keycode]
	if event.is_action_pressed("ui_up"):
		return Vector2i(0, -1)
	if event.is_action_pressed("ui_down"):
		return Vector2i(0, 1)
	if event.is_action_pressed("ui_left"):
		return Vector2i(-1, 0)
	if event.is_action_pressed("ui_right"):
		return Vector2i(1, 0)
	return Vector2i.ZERO


func execute_turn_move(target_grid: Vector2i, play_walk_animation: bool = true) -> void:
	if _dead:
		return
	_face_toward(target_grid - grid_pos)
	_move_start_grid_pos = grid_pos
	grid_pos = target_grid
	_start_move_tween(grid_to_world(grid_pos), play_walk_animation)


## 桶击退等平台位移：清空缓冲区、短暂锁定输入，避免与持续按方向键/血条 top_level 错位打架。
func prepare_for_forced_grid_push(lock_duration_override: float = -1.0) -> void:
	if _dead:
		return
	var dur := move_duration
	if lock_duration_override >= 0.0:
		dur = lock_duration_override
	_cancel_all_buffered_input()
	_suppress_move_input_until_release = true
	_clear_auto_navigation()
	_queued_dir = Vector2i.ZERO
	_pending_single_dir = Vector2i.ZERO
	_pending_single_dir_time_ms = 0
	_hold_active = false
	_hold_timer = 0.0
	_lock_actions_for(dur)


func play_blocked_feedback(direction: Vector2i) -> void:
	_move_start_grid_pos = grid_pos
	_play_wall_bump(direction)


func play_attack_feedback(target_grid: Vector2i) -> void:
	_face_toward(target_grid - grid_pos)
	var speed_scale := _melee_attack_animation_speed_scale()
	var anim_duration := _play_animation_and_get_duration(attack_animation, speed_scale, false)
	_last_attack_duration = maxf(0.08, maxf(anim_duration, melee_lunge_duration * 2.0))
	_play_player_animation(attack_animation, speed_scale, false)
	_lock_actions_for(_last_attack_duration)
	var dir := target_grid - grid_pos
	_play_melee_lunge(dir)
	_play_melee_impact_particles(dir)
	_request_camera_shake(melee_camera_shake_strength, melee_camera_shake_duration)
	_pending_single_dir = Vector2i.ZERO
	_pending_single_dir_time_ms = 0
	_queued_dir = Vector2i.ZERO
	_schedule_idle_after(_last_attack_duration)


func get_turn_move_duration() -> float:
	return move_duration


func get_block_feedback_duration() -> float:
	return wall_bump_duration * 2.0


func get_attack_feedback_duration() -> float:
	return _last_attack_duration


func get_attack_damage() -> int:
	return attack_damage


func apply_damage(amount: int, source_grid: Vector2i = Vector2i.ZERO) -> void:
	if _dead:
		return
	if source_grid != Vector2i.ZERO:
		_face_toward(source_grid - grid_pos)
	_hp -= maxi(0, amount)
	_cancel_all_buffered_input()
	_suppress_move_input_until_release = true
	_clear_auto_navigation()
	_update_health_bar_visual()
	if _hp <= 0:
		_die()
		return
	_play_sfx_if_available("Hurt")
	play_hit_feedback(source_grid)


func get_damage_feedback_duration() -> float:
	return _last_damage_feedback_duration


func is_dead() -> bool:
	return _dead


func _die() -> void:
	if _dead:
		return
	_clear_fire_attachment()
	_dead = true
	_play_sfx_if_available("PlayerDeath1")
	_play_sfx_if_available("PlayerDeath2")
	_update_health_bar_visual()
	_kill_move_tween()
	_is_moving = false
	_pending_single_dir = Vector2i.ZERO
	_queued_dir = Vector2i.ZERO
	_hold_active = false
	_hold_timer = 0.0
	if turn_controller != null:
		turn_controller.clear_queued_actions()
	var duration := _play_animation_and_get_duration(death_animation, death_animation_speed_scale, false)
	_play_player_animation(death_animation, death_animation_speed_scale, false)
	_last_damage_feedback_duration = duration
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
	await _restart_current_floor_after_death()


func _restart_current_floor_after_death() -> void:
	if not is_inside_tree():
		return
	_is_level_transitioning = true
	_spawned = false
	_preserve_player_state_on_next_floor = false
	_pending_next_floor_state.clear()
	_kill_move_tween()
	_is_moving = false
	if turn_controller != null:
		turn_controller.clear_queued_actions()
	await _fade_transition_to(1.0, level_fade_out_duration)
	if _level_flow_controller != null and is_instance_valid(_level_flow_controller):
		_level_flow_controller.reload_current_floor()
	elif dungeon_generator != null:
		dungeon_generator.generate_dungeon()
	if level_black_hold_duration > 0.0:
		await get_tree().create_timer(level_black_hold_duration).timeout
	await _fade_transition_to(0.0, level_fade_in_duration)
	_is_level_transitioning = false


func _melee_attack_animation_speed_scale() -> float:
	return clampf(attack_animation_speed_scale, 0.1, 4.0)


func _ranged_attack_animation_speed_scale() -> float:
	return clampf(attack_animation_speed_scale * ranged_attack_animation_speed_scale, 0.1, 4.0)


func _play_animation_and_get_duration(animation_name: StringName, speed_scale: float, loop: bool) -> float:
	if anim_player == null:
		return 0.0
	var anim := anim_player.get_animation(animation_name)
	if anim == null:
		return 0.0
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return anim.length / maxf(speed_scale, 0.01)


func _schedule_idle_after(delay: float) -> void:
	if _dead:
		return
	var timer := get_tree().create_timer(maxf(0.0, delay))
	timer.timeout.connect(func() -> void:
		# 避免等待动画结束回调打断正在进行的行走动画，导致“卡顿/瞬移感”。
		if not _dead and not _is_moving and _queued_dir == Vector2i.ZERO and _auto_path.is_empty():
			if _is_aim_mode:
				_hold_aim_pose()
			else:
				_play_player_animation(idle_animation)
	, CONNECT_ONE_SHOT)


func _face_toward(delta: Vector2i) -> void:
	if delta.x == 0:
		return
	scale.x = _base_scale_x if delta.x > 0 else -_base_scale_x


func _try_handle_wait_input(event: InputEvent) -> bool:
	if turn_controller == null:
		return false
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if key_event.is_echo():
		return false
	if key_event.keycode != KEY_SPACE:
		return false
	if not key_event.is_pressed():
		return true
	_clear_auto_navigation()
	turn_controller.queue_player_wait()
	get_viewport().set_input_as_handled()
	return true


func play_wait_feedback() -> void:
	_last_wait_duration = _play_animation_and_get_duration(reload_animation, reload_animation_speed_scale, false)
	if _last_wait_duration <= 0.0:
		_last_wait_duration = 0.08
	_play_player_animation(reload_animation, reload_animation_speed_scale, false)
	_play_sfx_if_available("Reload")
	if not _is_reloaded:
		_is_reloaded = true
	# 跳过回合动画为低优先级演出：不阻塞输入与回合。
	_schedule_idle_after(_last_wait_duration)


func get_wait_feedback_duration() -> float:
	return _last_wait_duration


func _is_action_locked() -> bool:
	return _action_lock_remaining > 0.0


func is_busy_for_turn() -> bool:
	return _is_action_locked() or _is_moving or _is_level_transitioning


func _lock_actions_for(duration: float) -> void:
	_action_lock_remaining = maxf(_action_lock_remaining, maxf(0.0, duration))


func play_hit_feedback(source_grid: Vector2i) -> void:
	var dir := Vector2(source_grid - grid_pos)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	_last_damage_feedback_duration = 0.12
	_lock_actions_for(_last_damage_feedback_duration)
	_spawn_blood_particles(dir, 10, Color(0.95, 0.15, 0.15, 0.95))
	modulate = Color(1.0, 0.45, 0.45, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, _last_damage_feedback_duration)


func _draw_health_bar(current_hp: int, max_hp_value: int) -> void:
	pass


func _spawn_blood_particles(direction: Vector2, count: int, color: Color) -> void:
	var tex := _get_blood_particle_texture()
	var dir := direction.normalized()
	for _i in count:
		var particle := Sprite2D.new()
		particle.texture = tex
		particle.centered = true
		particle.modulate = color
		particle.position = Vector2.ZERO
		add_child(particle)
		var spread := dir.rotated(randf_range(-0.9, 0.9))
		var speed := randf_range(7.0, 20.0)
		var target := particle.position + spread * speed
		var life := randf_range(0.16, 0.32)
		var tween := create_tween()
		tween.tween_property(particle, "position", target, life)
		tween.parallel().tween_property(particle, "modulate:a", 0.0, life)
		tween.finished.connect(func() -> void:
			if is_instance_valid(particle):
				particle.queue_free()
		, CONNECT_ONE_SHOT)


func _get_blood_particle_texture() -> Texture2D:
	if _blood_particle_texture != null:
		return _blood_particle_texture
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	_blood_particle_texture = ImageTexture.create_from_image(img)
	return _blood_particle_texture


func _get_ui_pixel_texture() -> Texture2D:
	if _ui_pixel_texture != null:
		return _ui_pixel_texture
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_ui_pixel_texture = ImageTexture.create_from_image(img)
	return _ui_pixel_texture


func _ensure_health_bar_nodes() -> void:
	if _health_bar_root != null and is_instance_valid(_health_bar_root):
		return
	_health_bar_root = Node2D.new()
	_health_bar_root.name = "HealthBarRoot"
	_health_bar_root.top_level = true
	_health_bar_root.z_as_relative = false
	_health_bar_root.z_index = 500
	add_child(_health_bar_root)

	_health_bar_bg = Sprite2D.new()
	_health_bar_bg.name = "HealthBarBG"
	_health_bar_bg.texture = _get_ui_pixel_texture()
	_health_bar_bg.centered = false
	_health_bar_bg.modulate = Color(0.0, 0.0, 0.0, 0.65)
	_health_bar_root.add_child(_health_bar_bg)

	_health_bar_fill = Sprite2D.new()
	_health_bar_fill.name = "HealthBarFill"
	_health_bar_fill.texture = _get_ui_pixel_texture()
	_health_bar_fill.centered = false
	_health_bar_root.add_child(_health_bar_fill)

	_reload_indicator_node = Sprite2D.new()
	_reload_indicator_node.name = "ReloadIndicator"
	_reload_indicator_node.texture = _get_ui_pixel_texture()
	_reload_indicator_node.centered = false
	_health_bar_root.add_child(_reload_indicator_node)

	for i in range(maxi(0, ranged_clip_size)):
		var bullet := Sprite2D.new()
		bullet.name = "Ammo%d" % i
		bullet.texture = _get_ui_pixel_texture()
		bullet.centered = false
		_health_bar_root.add_child(bullet)
		_ammo_nodes.append(bullet)


func _update_health_bar_visual() -> void:
	if not _spawned:
		if _health_bar_root != null:
			_health_bar_root.visible = false
		return
	_ensure_health_bar_nodes()
	if _health_bar_root == null or _health_bar_bg == null or _health_bar_fill == null:
		return
	_health_bar_root.visible = true

	var width := float(tile_size) * 0.9
	var height := 4.0
	var ratio := 0.0 if max_hp <= 0 else clampf(float(maxi(_hp, 0)) / float(max_hp), 0.0, 1.0)
	var fill_color := Color(0.2, 0.85, 0.25, 1.0)
	if ratio <= 0.5:
		fill_color = Color(0.95, 0.75, 0.2, 1.0)
	if ratio <= 0.25:
		fill_color = Color(0.95, 0.2, 0.2, 1.0)

	var top_left := Vector2(-width * 0.5, -float(tile_size) * 0.95)
	_health_bar_root.global_position = global_position

	_health_bar_bg.position = top_left
	_health_bar_bg.scale = Vector2(width, height)
	_health_bar_bg.modulate = Color(0.0, 0.0, 0.0, 0.65)

	var inner_width := maxf(0.0, (width - 2.0) * ratio)
	_health_bar_fill.position = top_left + Vector2.ONE
	_health_bar_fill.scale = Vector2(inner_width, maxf(0.0, height - 2.0))
	_health_bar_fill.modulate = fill_color

	# 弹匣 UI（玩家脚下）
	var ammo_bar_y := float(tile_size) * 0.65
	var bullet_w := 4.0
	var bullet_h := 3.0
	var spacing := 1.0
	var ammo_total_w := float(maxi(1, ranged_clip_size)) * bullet_w + float(maxi(0, ranged_clip_size - 1)) * spacing
	for i in _ammo_nodes.size():
		var node := _ammo_nodes[i]
		node.position = Vector2(-ammo_total_w * 0.5 + i * (bullet_w + spacing), ammo_bar_y)
		node.scale = Vector2(bullet_w, bullet_h)
		node.modulate = Color(0.95, 0.85, 0.25, 1.0) if i < _ammo_in_clip else Color(0.25, 0.25, 0.25, 0.8)

	# 上膛指示器
	_reload_indicator_node.position = Vector2(-4.0, ammo_bar_y + 5.0)
	_reload_indicator_node.scale = Vector2(8.0, 2.0)
	_reload_indicator_node.modulate = Color(0.25, 0.95, 0.4, 1.0) if _is_reloaded else Color(0.95, 0.25, 0.25, 1.0)


func _play_melee_lunge(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return
	var home := grid_to_world(grid_pos)
	var lunge_vec := Vector2(direction).normalized() * float(tile_size) * melee_lunge_distance_ratio
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", home + lunge_vec, melee_lunge_duration)
	tween.tween_property(self, "position", home, melee_lunge_duration)


func _play_melee_impact_particles(direction: Vector2i) -> void:
	var dir := Vector2(direction)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var hit_world := grid_to_world(grid_pos + direction)
	var hit_origin := to_local(hit_world)
	var particle_parent := get_parent()
	if particle_parent == null:
		particle_parent = self
	var tex := _get_blood_particle_texture()
	for _i in melee_impact_particle_count:
		var particle := Sprite2D.new()
		particle.texture = tex
		particle.centered = true
		particle.modulate = Color(1.0, 0.95, 0.7, 0.95)
		particle.top_level = true
		particle_parent.add_child(particle)
		particle.global_position = to_global(hit_origin)
		var spread := dir.normalized().rotated(randf_range(-0.75, 0.75))
		var speed := randf_range(melee_impact_particle_speed_min, melee_impact_particle_speed_max)
		var life := randf_range(melee_impact_particle_life_min, melee_impact_particle_life_max)
		var target := particle.global_position + spread * speed
		var tween := create_tween()
		tween.tween_property(particle, "global_position", target, life)
		tween.parallel().tween_property(particle, "modulate:a", 0.0, life)
		tween.finished.connect(func() -> void:
			if is_instance_valid(particle):
				particle.queue_free()
		, CONNECT_ONE_SHOT)


func _request_camera_shake(strength: float, duration: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.has_method("request_shake"):
		camera.call("request_shake", strength, duration)


func _ensure_transition_overlay() -> void:
	if _transition_layer != null and is_instance_valid(_transition_layer):
		return
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 1000
	add_child(_transition_layer)
	_transition_rect = ColorRect.new()
	_transition_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_rect.anchor_left = 0.0
	_transition_rect.anchor_top = 0.0
	_transition_rect.anchor_right = 1.0
	_transition_rect.anchor_bottom = 1.0
	_transition_rect.offset_left = 0.0
	_transition_rect.offset_top = 0.0
	_transition_rect.offset_right = 0.0
	_transition_rect.offset_bottom = 0.0
	_transition_layer.add_child(_transition_rect)


func _fade_transition_to(target_alpha: float, duration: float) -> void:
	_ensure_transition_overlay()
	if _transition_rect == null:
		return
	var clamped := clampf(target_alpha, 0.0, 1.0)
	if duration <= 0.0:
		var color := _transition_rect.color
		color.a = clamped
		_transition_rect.color = color
		return
	var tween := create_tween()
	var color_target := _transition_rect.color
	color_target.a = clamped
	tween.tween_property(_transition_rect, "color", color_target, duration)
	await tween.finished


func _try_handle_mouse_command(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not mb.pressed:
		return true
	if not _spawned or turn_controller == null:
		return true

	var target_grid := world_to_grid(get_global_mouse_position())
	if not _is_grid_in_bounds(target_grid):
		return true
	if _is_cell_unseen(target_grid):
		return true

	var clicked_enemy := turn_controller.get_enemy_at(target_grid)
	if clicked_enemy != null and clicked_enemy.visible:
		_issue_enemy_attack_command(clicked_enemy)
		get_viewport().set_input_as_handled()
		return true

	if not is_walkable(target_grid):
		return true
	_issue_move_path_command(target_grid)
	get_viewport().set_input_as_handled()
	return true


func _issue_move_path_command(target_grid: Vector2i) -> void:
	_auto_attack_target_id = 0
	_auto_path = _build_path_to(target_grid, false)
	_auto_known_visible_enemy_ids = _collect_visible_enemy_ids()
	_auto_force_mode = not _auto_known_visible_enemy_ids.is_empty()
	if _auto_path.is_empty():
		_auto_force_mode = false


func _issue_enemy_attack_command(enemy: EnemyGridController) -> void:
	if enemy == null or enemy.is_dead():
		return
	var enemy_grid := enemy.grid_pos
	var delta := enemy_grid - grid_pos
	if maxi(absi(delta.x), absi(delta.y)) == 1:
		_clear_auto_navigation()
		_submit_direction(delta)
		return

	_auto_attack_target_id = enemy.get_instance_id()
	_auto_known_visible_enemy_ids = _collect_visible_enemy_ids()
	_auto_force_mode = not _auto_known_visible_enemy_ids.is_empty()
	_rebuild_attack_path_to_target()


func _update_auto_navigation() -> void:
	if _auto_path.is_empty() and _auto_attack_target_id == 0:
		return
	if _is_moving or _is_action_locked() or _dead:
		return

	var current_visible_enemy_ids := _collect_visible_enemy_ids()
	if _auto_force_mode:
		# 强行移动：只在“新敌人进入视野”时中止。
		for id in current_visible_enemy_ids.keys():
			if not _auto_known_visible_enemy_ids.has(id):
				_clear_auto_navigation()
				return
	else:
		# 普通自动移动：一旦视野内出现敌人即中止。
		if not current_visible_enemy_ids.is_empty():
			_clear_auto_navigation()
			return

	if _auto_attack_target_id != 0:
		var target := _find_enemy_by_id(_auto_attack_target_id)
		if target == null or target.is_dead() or not target.visible:
			_clear_auto_navigation()
			return
		var target_delta := target.grid_pos - grid_pos
		if maxi(absi(target_delta.x), absi(target_delta.y)) == 1:
			_auto_path.clear()
			_submit_direction(target_delta)
			_auto_attack_target_id = 0
			return
		if _auto_path.is_empty():
			_rebuild_attack_path_to_target()
			if _auto_path.is_empty():
				_clear_auto_navigation()
				return

	if _auto_path.is_empty():
		return
	var next_grid := _auto_path[0]
	if next_grid == grid_pos:
		_auto_path.remove_at(0)
		return

	var blocker := turn_controller.get_enemy_at(next_grid)
	if blocker != null and blocker.visible:
		# 自动移动途中撞见敌人：暂停自动移动，等待玩家下一条命令。
		_clear_auto_navigation()
		return

	var direction := next_grid - grid_pos
	if absi(direction.x) > 1 or absi(direction.y) > 1:
		_clear_auto_navigation()
		return
	_auto_path.remove_at(0)
	_submit_direction(direction)


func _rebuild_attack_path_to_target() -> void:
	var target := _find_enemy_by_id(_auto_attack_target_id)
	if target == null:
		_auto_path.clear()
		return
	var options: Array[Dictionary] = []
	for offset in _path_neighbor_offsets():
		var candidate := target.grid_pos + offset
		if not _is_grid_in_bounds(candidate):
			continue
		if not is_walkable(candidate):
			continue
		if turn_controller.get_enemy_at(candidate) != null:
			continue
		var path := _build_path_to(candidate, false)
		if path.is_empty():
			continue
		options.append({"path": path, "score": path.size()})
	if options.is_empty():
		_auto_path.clear()
		return
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) < int(b["score"])
	)
	_auto_path = options[0]["path"] as Array[Vector2i]


func _build_path_to(target: Vector2i, allow_occupied_target: bool) -> Array[Vector2i]:
	if target == grid_pos:
		return []

	# 先做最短路距离图（步数最短），再在最短路集合中优先“少拐弯、趋直线”。
	var dist: Dictionary = {}
	var queue: Array[Vector2i] = [target]
	dist[target] = 0

	while not queue.is_empty():
		var current := queue.pop_front() as Vector2i
		var current_dist := int(dist[current])
		for offset in _path_neighbor_offsets():
			var next := current + offset
			if dist.has(next):
				continue
			if not _can_step_for_path(current, next, target, allow_occupied_target):
				continue
			dist[next] = current_dist + 1
			queue.append(next)

	if not dist.has(grid_pos):
		return []

	var path: Array[Vector2i] = []
	var cursor := grid_pos
	var prev_dir := Vector2i.ZERO
	while cursor != target:
		var cursor_dist := int(dist[cursor])
		var candidates: Array[Vector2i] = []
		for offset in _path_neighbor_offsets():
			var next := cursor + offset
			if not dist.has(next):
				continue
			if int(dist[next]) != cursor_dist - 1:
				continue
			candidates.append(next)
		if candidates.is_empty():
			return []
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var dir_a := a - cursor
			var dir_b := b - cursor
			var turn_a := _path_turn_penalty(prev_dir, dir_a)
			var turn_b := _path_turn_penalty(prev_dir, dir_b)
			if turn_a != turn_b:
				return turn_a < turn_b
			var align_a := a.distance_squared_to(target)
			var align_b := b.distance_squared_to(target)
			if align_a != align_b:
				return align_a < align_b
			# 兜底稳定排序，避免抖动。
			return a.x < b.x if a.y == b.y else a.y < b.y
		)
		var chosen := candidates[0]
		path.append(chosen)
		prev_dir = chosen - cursor
		cursor = chosen
	return path


func _path_neighbor_offsets() -> Array[Vector2i]:
	if diagonal_move:
		return [
			Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
		]
	return [
		Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1),
	]


func _can_step_for_path(from: Vector2i, to: Vector2i, target: Vector2i, allow_occupied_target: bool) -> bool:
	if not _is_grid_in_bounds(from) or not _is_grid_in_bounds(to):
		return false
	if not is_walkable(to):
		return false

	if dungeon_generator != null and dungeon_generator._door_set.has(to):
		# 玩家可走门（由回合逻辑负责开门），路径阶段也视作可通行。
		pass

	var delta := to - from
	if absi(delta.x) > 1 or absi(delta.y) > 1:
		return false
	if not diagonal_move and delta.x != 0 and delta.y != 0:
		return false

	if delta.x != 0 and delta.y != 0 and turn_controller != null and turn_controller.forbid_diagonal_corner_cutting:
		var side_a := from + Vector2i(delta.x, 0)
		var side_b := from + Vector2i(0, delta.y)
		var side_a_walkable := is_walkable(side_a)
		var side_b_walkable := is_walkable(side_b)
		if not side_a_walkable and not side_b_walkable:
			if not turn_controller.allow_diagonal_pillar_gap:
				return false

	if turn_controller != null:
		var blocker := turn_controller.get_enemy_at(to)
		if blocker != null:
			if allow_occupied_target and to == target:
				return true
			# 不可见敌人在寻路中不作为阻挡，避免“阴影区无形墙”。
			if blocker.visible:
				return false
	return true


func _path_turn_penalty(prev_dir: Vector2i, new_dir: Vector2i) -> int:
	if prev_dir == Vector2i.ZERO:
		return 0
	if prev_dir == new_dir:
		return 0
	if prev_dir + new_dir == Vector2i.ZERO:
		return 3
	return 1


func _collect_visible_enemy_ids() -> Dictionary:
	var result: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemy"):
		if node == null or not is_instance_valid(node):
			continue
		if node.visible:
			result[node.get_instance_id()] = true
	return result


func _has_new_visible_enemy() -> bool:
	if _auto_path.is_empty() and _auto_attack_target_id == 0:
		return false
	var current := _collect_visible_enemy_ids()
	for id in current.keys():
		if not _auto_known_visible_enemy_ids.has(id):
			return true
	return false


func _find_enemy_by_id(instance_id: int) -> EnemyGridController:
	for node in get_tree().get_nodes_in_group("enemy"):
		if node == null or not is_instance_valid(node):
			continue
		if node.get_instance_id() == instance_id and node is EnemyGridController:
			return node as EnemyGridController
	return null


func _clear_auto_navigation() -> void:
	_auto_path.clear()
	_auto_force_mode = false
	_auto_known_visible_enemy_ids.clear()
	_auto_attack_target_id = 0


func _try_handle_aim_and_shot_input(event: InputEvent) -> bool:
	if turn_controller == null:
		return false
	if not (event is InputEventMouseButton):
		return false
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _ammo_in_clip <= 0:
			_set_aim_mode(false)
		else:
			_set_aim_mode(not _is_aim_mode)
		get_viewport().set_input_as_handled()
		return true
	if not _is_aim_mode:
		return false
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if not _is_reloaded or _ammo_in_clip <= 0:
			get_viewport().set_input_as_handled()
			return true
		var shot_info: Dictionary = _resolve_mouse_shot_target_info()
		var valid_shot: bool = shot_info.get("valid", false) == true
		if not valid_shot:
			get_viewport().set_input_as_handled()
			return true
		var request_grid: Vector2i = shot_info.get("request_grid", grid_pos) as Vector2i
		var hit_grid: Vector2i = shot_info.get("hit_grid", request_grid) as Vector2i
		if _is_adjacent_wall_shot_forbidden(hit_grid):
			get_viewport().set_input_as_handled()
			return true
		_clear_auto_navigation()
		turn_controller.queue_player_shot(request_grid)
		_is_reloaded = false
		_ammo_in_clip = maxi(0, _ammo_in_clip - 1)
		if _ammo_in_clip <= 0:
			_set_aim_mode(false)
		get_viewport().set_input_as_handled()
		return true
	return false


func begin_ranged_attack(target_grid: Vector2i) -> bool:
	if _dead or _is_action_locked():
		return false
	_face_toward(target_grid - grid_pos)
	var speed_scale := _ranged_attack_animation_speed_scale()
	_last_ranged_attack_duration = _play_animation_and_get_duration(ranged_attack_animation, speed_scale, false)
	if _last_ranged_attack_duration <= 0.0:
		_last_ranged_attack_duration = 0.08
	_play_player_animation(ranged_attack_animation, speed_scale, false)
	_lock_actions_for(_last_ranged_attack_duration)
	_request_camera_shake(melee_camera_shake_strength * 0.7, melee_camera_shake_duration * 0.8)
	_schedule_idle_after(_last_ranged_attack_duration)
	_hide_aim_lines()
	_aim_gun_lines_suppressed_until_ms = Time.get_ticks_msec() + int(ceili(_last_ranged_attack_duration * 1000.0))
	return true


func play_ranged_impact_feedback(hit_grid: Vector2i) -> void:
	var hit_world := grid_to_world(hit_grid)
	_play_colored_impact_particles(hit_world, Color(0.55, 0.9, 1.0, 0.95), 10, 9.0, 22.0, 0.10, 0.22)
	_play_bullet_burst_ring(hit_world, Color(0.35, 0.8, 1.0, 0.8))


func get_ranged_attack_damage() -> int:
	return ranged_damage


func get_ranged_attack_feedback_duration() -> float:
	return _last_ranged_attack_duration


func _update_ranged_ui() -> void:
	_update_aim_preview_visuals()


func _update_aim_target_markers() -> void:
	pass


func _update_aim_preview_visuals() -> void:
	if not _is_aim_mode or turn_controller == null or _dead:
		_hide_aim_preview_visuals()
		return
	_aim_dash_phase += get_process_delta_time() * aim_dash_speed
	_ensure_aim_preview_nodes()
	var shot_info: Dictionary = _resolve_mouse_shot_target_info()
	var can_preview: bool = shot_info.get("valid", false) == true
	var unloaded_muted: bool = not _is_reloaded
	var bracket_color: Color
	if unloaded_muted:
		bracket_color = aim_unloaded_ui_color
		bracket_color.a = aim_square_transparency * 0.82
	else:
		bracket_color = Color(1.0, 1.0, 1.0, aim_square_transparency * 0.82)
	var target_grid := grid_pos
	var hit_grid := grid_pos
	var base_color := Color.WHITE
	var hit_is_destroyable: bool = false

	if not can_preview:
		_hide_hit_indicators()
		_hide_aim_lines()
	else:
		target_grid = shot_info.get("request_grid", grid_pos) as Vector2i
		hit_grid = shot_info.get("hit_grid", target_grid) as Vector2i
		var hit_node: Node = shot_info.get("target_node", null) as Node
		hit_is_destroyable = _is_destroyable_target(hit_node)
		if unloaded_muted:
			base_color = aim_unloaded_ui_color
		else:
			base_color = Color(1.0, 0.2, 0.2, 1.0) if hit_is_destroyable else Color(1.0, 1.0, 1.0, 1.0)
		var flash_alpha: float
		if unloaded_muted:
			flash_alpha = 0.88
		else:
			var flash_t := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * aim_flash_speed)
			flash_alpha = lerpf(0.62, 1.0, flash_t)
		var crosshair_color := base_color
		crosshair_color.a = 1.0 * flash_alpha
		var square_color := base_color
		square_color.a = aim_square_transparency * flash_alpha
		bracket_color = square_color
		_draw_hit_crosshair(hit_grid, crosshair_color)
		_draw_hit_square_indicator(hit_grid, square_color)
		if not unloaded_muted:
			_draw_hit_square_spin_corner(hit_grid, square_color)
		else:
			_hide_aim_hit_spin_corner()

	_draw_player_cell_corner_brackets(bracket_color)

	if not can_preview:
		return

	var hit_world := _grid_cell_center_global(hit_grid)
	var line_tint := aim_unloaded_ui_color if unloaded_muted else base_color
	var gun_dashed_style: bool = unloaded_muted or not hit_is_destroyable
	if Time.get_ticks_msec() < _aim_gun_lines_suppressed_until_ms:
		_hide_aim_lines()
	else:
		_update_aim_gun_line(hit_world, line_tint, gun_dashed_style)


func _ensure_aim_preview_nodes() -> void:
	while _aim_hit_crosshair_lines.size() < 4:
		_aim_hit_crosshair_lines.append(_make_preview_line(aim_crosshair_line_width, AIM_Z_REMOTE_CROSSHAIR))
	while _aim_hit_square_lines.size() < 8:
		_aim_hit_square_lines.append(_make_preview_line(aim_crosshair_line_width, AIM_Z_REMOTE_CROSSHAIR))
	if _aim_preview_solid_line == null or not is_instance_valid(_aim_preview_solid_line):
		_aim_preview_solid_line = _make_preview_line(aim_line_width, AIM_Z_GUN_LINE)


func _ensure_player_cell_corner_brackets() -> void:
	while _aim_player_cell_corner_lines.size() < 8:
		_aim_player_cell_corner_lines.append(_make_preview_line(aim_crosshair_line_width, AIM_Z_PLAYER_CELL_CORNERS))


func _hide_player_cell_corner_brackets_visual() -> void:
	for line in _aim_player_cell_corner_lines:
		if line != null and is_instance_valid(line):
			line.visible = false


func _draw_player_cell_corner_brackets(color: Color) -> void:
	_ensure_player_cell_corner_brackets()
	## 以精灵全局位置为中心画格框，移动补间时与视觉同步（避免“格心离散跳格”）。
	var c := global_position
	var hs := float(tile_size) * 0.5
	var corner := clampf(aim_square_corner_length, 1.0, hs)
	var segments: Array[PackedVector2Array] = [
		PackedVector2Array([c + Vector2(-hs, -hs), c + Vector2(-hs + corner, -hs)]),
		PackedVector2Array([c + Vector2(hs - corner, -hs), c + Vector2(hs, -hs)]),
		PackedVector2Array([c + Vector2(hs, -hs), c + Vector2(hs, -hs + corner)]),
		PackedVector2Array([c + Vector2(hs, hs - corner), c + Vector2(hs, hs)]),
		PackedVector2Array([c + Vector2(hs, hs), c + Vector2(hs - corner, hs)]),
		PackedVector2Array([c + Vector2(-hs + corner, hs), c + Vector2(-hs, hs)]),
		PackedVector2Array([c + Vector2(-hs, hs), c + Vector2(-hs, hs - corner)]),
		PackedVector2Array([c + Vector2(-hs, -hs + corner), c + Vector2(-hs, -hs)]),
	]
	var n := mini(segments.size(), _aim_player_cell_corner_lines.size())
	for i in range(n):
		var line := _aim_player_cell_corner_lines[i]
		if line == null or not is_instance_valid(line):
			continue
		line.points = segments[i]
		line.default_color = color
		line.width = aim_crosshair_line_width
		line.visible = true


func _ensure_aim_hit_spin_lines() -> void:
	if _aim_hit_spin_corner_line == null or not is_instance_valid(_aim_hit_spin_corner_line):
		_aim_hit_spin_corner_line = _make_preview_line(aim_crosshair_line_width, AIM_Z_REMOTE_CROSSHAIR)
		_aim_hit_spin_corner_line.z_index = AIM_Z_REMOTE_CROSSHAIR + 1
	if _aim_hit_spin_corner_line_b == null or not is_instance_valid(_aim_hit_spin_corner_line_b):
		_aim_hit_spin_corner_line_b = _make_preview_line(aim_crosshair_line_width, AIM_Z_REMOTE_CROSSHAIR)
		_aim_hit_spin_corner_line_b.z_index = AIM_Z_REMOTE_CROSSHAIR + 2


func _hide_aim_hit_spin_corner() -> void:
	for ln in [_aim_hit_spin_corner_line, _aim_hit_spin_corner_line_b]:
		if ln != null and is_instance_valid(ln):
			ln.visible = false


## 顶点沿内边框周长弧线 `arc ∈ [0, P)` CCW：`(-hs,-hs)→右上→右下→左上`。
func _aim_square_inner_perimeter_vertex(center_global: Vector2, hs_half: float, arc: float) -> Vector2:
	var P: float = 8.0 * hs_half
	var a: float = fposmod(arc, P)
	var verts := PackedVector2Array([
		Vector2(-hs_half, -hs_half),
		Vector2(hs_half, -hs_half),
		Vector2(hs_half, hs_half),
		Vector2(-hs_half, hs_half),
	])
	var edge_len: float = 2.0 * hs_half
	var acc: float = 0.0
	for i in range(4):
		var vb: Vector2 = verts[i]
		var ve: Vector2 = verts[(i + 1) % 4]
		if a <= acc + edge_len + 1e-6:
			var t_loc: float = clampf((a - acc) / edge_len, 0.0, 1.0)
			return center_global + vb.lerp(ve, t_loc)
		acc += edge_len
	return center_global + verts[0]


## 沿命中格「内缩方框」整条周长按弧长匀速滑动的一角折线 ×2：第二条同向，仅相差固定周长比例。
func _draw_hit_square_spin_corner(gp: Vector2i, color: Color) -> void:
	_ensure_aim_hit_spin_lines()
	var c := _grid_cell_center_global(gp)
	var hs := float(tile_size) * 0.5
	var max_inset: float = maxf(0.6, hs - 2.0)
	var inset := clampf(aim_spin_border_inset, 0.5, max_inset)
	var hs_i := hs - inset
	if hs_i < 2.0:
		_hide_aim_hit_spin_corner()
		return
	var perim := 8.0 * hs_i
	var max_cl := minf(perim * 0.22, hs_i * 1.92)
	var clen := clampf(aim_square_corner_length * aim_spin_corner_scale, 1.0, max_cl)
	var arc_mid := aim_spin_path_laps_per_sec * perim * float(Time.get_ticks_msec()) * 0.001
	var off_frac: float = clampf(aim_spin_second_path_perimeter_frac, 0.0, 0.999)
	var arc_b := arc_mid + perim * off_frac

	var primary := PackedVector2Array([
		_aim_square_inner_perimeter_vertex(c, hs_i, arc_mid - clen),
		_aim_square_inner_perimeter_vertex(c, hs_i, arc_mid),
		_aim_square_inner_perimeter_vertex(c, hs_i, arc_mid + clen),
	])
	_aim_hit_spin_corner_line.points = primary
	_aim_hit_spin_corner_line.default_color = color
	_aim_hit_spin_corner_line.width = aim_crosshair_line_width
	_aim_hit_spin_corner_line.visible = true

	var secondary := PackedVector2Array([
		_aim_square_inner_perimeter_vertex(c, hs_i, arc_b - clen),
		_aim_square_inner_perimeter_vertex(c, hs_i, arc_b),
		_aim_square_inner_perimeter_vertex(c, hs_i, arc_b + clen),
	])
	_aim_hit_spin_corner_line_b.points = secondary
	_aim_hit_spin_corner_line_b.default_color = color
	_aim_hit_spin_corner_line_b.width = aim_crosshair_line_width
	_aim_hit_spin_corner_line_b.visible = true


func _make_preview_line(line_width: float, line_z_index: int = AIM_Z_REMOTE_CROSSHAIR) -> Line2D:
	var line := Line2D.new()
	line.top_level = true
	line.z_as_relative = false
	line.z_index = line_z_index
	line.width = line_width
	line.default_color = target_highlight_color
	line.closed = false
	get_tree().root.add_child(line)
	return line


func _square_ray_smallest_positive_hit(
	origin_global: Vector2,
	dir_unit: Vector2,
	cell_center_global: Vector2,
	half_extent: float,
	min_positive_t: float = 1e-4,
) -> float:
	var mn := Vector2(cell_center_global.x - half_extent, cell_center_global.y - half_extent)
	var mx := Vector2(cell_center_global.x + half_extent, cell_center_global.y + half_extent)
	var dx := dir_unit.x
	var dy := dir_unit.y
	var ox := origin_global.x
	var oy := origin_global.y
	var eps := 1e-7
	var best := INF

	for xv in [mn.x, mx.x]:
		if absf(dx) < eps:
			continue
		var t: float = (float(xv) - ox) / dx
		if t < min_positive_t:
			continue
		var yy: float = oy + dy * t
		if yy >= mn.y - eps and yy <= mx.y + eps:
			best = minf(best, t)

	for yv in [mn.y, mx.y]:
		if absf(dy) < eps:
			continue
		var t2: float = (float(yv) - oy) / dy
		if t2 < min_positive_t:
			continue
		var xx: float = ox + dx * t2
		if xx >= mn.x - eps and xx <= mx.x + eps:
			best = minf(best, t2)

	return best


func _point_on_square_ray_near_face(
	origin_global: Vector2,
	dir_unit: Vector2,
	cell_center_global: Vector2,
	half_extent: float,
) -> Vector2:
	var raw_t := _square_ray_smallest_positive_hit(origin_global, dir_unit, cell_center_global, half_extent)
	if is_inf(raw_t) or raw_t <= 0.0 or is_nan(raw_t):
		var to_c := cell_center_global - origin_global
		var dll := to_c.length()
		if dll < 1e-6:
			return cell_center_global
		var du2 := to_c / dll
		return cell_center_global - du2 * half_extent

	var biased_t := raw_t - AIM_LINE_SURFACE_BIAS
	var t_eff := biased_t if biased_t >= 1e-4 else raw_t * 0.999
	return origin_global + dir_unit * t_eff


func _update_aim_gun_line(hit_center_global: Vector2, color: Color, dashed_style: bool) -> void:
	_ensure_aim_preview_nodes()

	var inward := global_position
	## 与足下框同源：枪口射线贴脸参考盒以 `global_position` 为中心，补间不切格心不抖。
	var shooter_cell_center := global_position
	var to_hit := hit_center_global - inward
	var ray_len := to_hit.length()
	if ray_len <= 1e-5:
		_hide_aim_lines()
		return
	var dn := to_hit / ray_len
	var half_e := float(tile_size) * 0.5
	var probe_step := maxf(AIM_LINE_SURFACE_BIAS * 3.5, float(tile_size) * 0.07)

	var line_origin := _point_on_square_ray_near_face(inward, dn, shooter_cell_center, half_e)
	var probe_after_origin := line_origin + dn * maxf(probe_step, 0.6)
	var hit_edge := _point_on_square_ray_near_face(probe_after_origin, dn, hit_center_global, half_e)

	var lc := color
	lc.a = 0.9 * AIM_GUN_LINE_ALPHA_SCALE

	if not dashed_style:
		for line in _aim_preview_dashed_lines:
			if line != null and is_instance_valid(line):
				line.visible = false
		if _aim_preview_solid_line != null and is_instance_valid(_aim_preview_solid_line):
			_aim_preview_solid_line.width = aim_line_width
			_aim_preview_solid_line.points = PackedVector2Array([line_origin, hit_edge])
			_aim_preview_solid_line.default_color = lc
			_aim_preview_solid_line.visible = true
		return

	if _aim_preview_solid_line != null and is_instance_valid(_aim_preview_solid_line):
		_aim_preview_solid_line.visible = false

	var dash_vec := hit_edge - line_origin
	var dash_dist := dash_vec.length()
	if dash_dist <= 1e-4:
		for line in _aim_preview_dashed_lines:
			if line != null and is_instance_valid(line):
				line.visible = false
		return
	var unit := dash_vec / dash_dist
	var step := maxf(1.0, aim_dash_length + aim_dash_gap)
	var phase := fmod(_aim_dash_phase, step)
	var d := -phase
	var visible_count := 0
	while d < dash_dist:
		var seg_start := clampf(d, 0.0, dash_dist)
		var seg_end := clampf(d + aim_dash_length, 0.0, dash_dist)
		if seg_end > seg_start + 0.001:
			var ln := _get_or_create_dash_line(visible_count)
			ln.width = aim_line_width
			ln.points = PackedVector2Array([line_origin + unit * seg_start, line_origin + unit * seg_end])
			ln.default_color = lc
			ln.visible = true
			visible_count += 1
		d += step
	for i in range(visible_count, _aim_preview_dashed_lines.size()):
		var leftover := _aim_preview_dashed_lines[i]
		if leftover != null and is_instance_valid(leftover):
			leftover.visible = false


func _get_or_create_dash_line(index: int) -> Line2D:
	while _aim_preview_dashed_lines.size() <= index:
		var line := _make_preview_line(aim_line_width, AIM_Z_GUN_LINE)
		_aim_preview_dashed_lines.append(line)
	return _aim_preview_dashed_lines[index]


func _draw_hit_square_indicator(gp: Vector2i, color: Color) -> void:
	_ensure_aim_preview_nodes()
	var c := _grid_cell_center_global(gp)
	var hs := float(tile_size) * 0.5
	var corner := clampf(aim_square_corner_length, 1.0, hs)
	var segments: Array[PackedVector2Array] = [
		PackedVector2Array([c + Vector2(-hs, -hs), c + Vector2(-hs + corner, -hs)]),
		PackedVector2Array([c + Vector2(hs - corner, -hs), c + Vector2(hs, -hs)]),
		PackedVector2Array([c + Vector2(hs, -hs), c + Vector2(hs, -hs + corner)]),
		PackedVector2Array([c + Vector2(hs, hs - corner), c + Vector2(hs, hs)]),
		PackedVector2Array([c + Vector2(hs, hs), c + Vector2(hs - corner, hs)]),
		PackedVector2Array([c + Vector2(-hs + corner, hs), c + Vector2(-hs, hs)]),
		PackedVector2Array([c + Vector2(-hs, hs), c + Vector2(-hs, hs - corner)]),
		PackedVector2Array([c + Vector2(-hs, -hs + corner), c + Vector2(-hs, -hs)]),
	]
	for i in range(8):
		var line := _aim_hit_square_lines[i]
		if line == null or not is_instance_valid(line):
			continue
		line.points = segments[i]
		line.default_color = color
		line.width = aim_crosshair_line_width
		line.visible = true


func _draw_hit_crosshair(gp: Vector2i, color: Color) -> void:
	_ensure_aim_preview_nodes()
	var c := _grid_cell_center_global(gp)
	var hs := float(tile_size) * 0.5
	var half_len := aim_crosshair_length * 0.5
	var lines: Array[PackedVector2Array] = [
		PackedVector2Array([c + Vector2(0.0, -hs - half_len), c + Vector2(0.0, -hs + half_len)]), # top
		PackedVector2Array([c + Vector2(0.0, hs - half_len), c + Vector2(0.0, hs + half_len)]),   # bottom
		PackedVector2Array([c + Vector2(-hs - half_len, 0.0), c + Vector2(-hs + half_len, 0.0)]), # left
		PackedVector2Array([c + Vector2(hs - half_len, 0.0), c + Vector2(hs + half_len, 0.0)]),   # right
	]
	for i in range(4):
		var line := _aim_hit_crosshair_lines[i]
		if line == null or not is_instance_valid(line):
			continue
		line.points = lines[i]
		line.default_color = color
		line.width = aim_crosshair_line_width
		line.visible = true


func _hide_hit_indicators() -> void:
	for line in _aim_hit_crosshair_lines:
		if line != null and is_instance_valid(line):
			line.visible = false
	for line in _aim_hit_square_lines:
		if line != null and is_instance_valid(line):
			line.visible = false
	_hide_aim_hit_spin_corner()


func _hide_aim_lines() -> void:
	if _aim_preview_solid_line != null and is_instance_valid(_aim_preview_solid_line):
		_aim_preview_solid_line.visible = false
	for line in _aim_preview_dashed_lines:
		if line != null and is_instance_valid(line):
			line.visible = false


func _hide_aim_preview_visuals() -> void:
	_hide_hit_indicators()
	_hide_player_cell_corner_brackets_visual()
	_hide_aim_lines()


func _is_destroyable_target(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return (
		node is EnemyGridController
		or node is BreakablePillar
		or node is BreakableBarrel
		or node is FlammableLiquid
		or node is GridWallSwitch
	)


func _resolve_mouse_shot_target_info() -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"request_grid": grid_pos,
		"hit_grid": grid_pos,
		"target_node": null,
	}
	if turn_controller == null:
		return result
	var from_vis: Vector2i = _visual_aim_origin_cell()
	var raw_target: Vector2i = world_to_grid(get_global_mouse_position())
	var request_grid := _clamp_shot_target_to_range(from_vis, raw_target)
	result["request_grid"] = request_grid
	var trace: Dictionary = turn_controller.preview_player_shot_trace(request_grid, from_vis)
	var hit_grid: Vector2i = trace.get("hit_grid", request_grid) as Vector2i
	result["hit_grid"] = hit_grid
	result["target_node"] = trace.get("target_node", null)
	result["valid"] = _is_grid_in_bounds(hit_grid)
	return result


func _clamp_shot_target_to_range(from_grid: Vector2i, target_grid: Vector2i) -> Vector2i:
	if from_grid == target_grid:
		return target_grid
	var delta := Vector2(target_grid - from_grid)
	var dist := delta.length()
	if dist <= float(ranged_max_distance):
		return target_grid
	var clamped := Vector2(from_grid) + (delta / dist) * float(ranged_max_distance)
	var clamped_grid := Vector2i(roundi(clamped.x), roundi(clamped.y))
	if clamped_grid == from_grid:
		clamped_grid = from_grid + Vector2i(signi(target_grid.x - from_grid.x), signi(target_grid.y - from_grid.y))
	return clamped_grid


func _resolve_fog_of_war() -> void:
	if _fog_of_war != null and is_instance_valid(_fog_of_war):
		return
	_fog_of_war = get_tree().get_first_node_in_group("fog_of_war")


func _is_cell_unseen(pos: Vector2i) -> bool:
	_resolve_fog_of_war()
	if _fog_of_war == null or not is_instance_valid(_fog_of_war):
		return false
	if _fog_of_war.has_method("is_cell_unseen"):
		return _fog_of_war.call("is_cell_unseen", pos) == true
	return false


func _clear_ranged_target_markers() -> void:
	for id in _ranged_target_marker.keys():
		var marker_node: Node = _ranged_target_marker[id] as Node
		if marker_node != null and is_instance_valid(marker_node):
			marker_node.queue_free()
	_ranged_target_marker.clear()
	for line in _aim_hit_crosshair_lines:
		if line != null and is_instance_valid(line):
			line.queue_free()
	for line in _aim_hit_square_lines:
		if line != null and is_instance_valid(line):
			line.queue_free()
	for line in _aim_player_cell_corner_lines:
		if line != null and is_instance_valid(line):
			line.queue_free()
	if _aim_hit_spin_corner_line != null and is_instance_valid(_aim_hit_spin_corner_line):
		_aim_hit_spin_corner_line.queue_free()
	if _aim_hit_spin_corner_line_b != null and is_instance_valid(_aim_hit_spin_corner_line_b):
		_aim_hit_spin_corner_line_b.queue_free()
	if _aim_preview_solid_line != null and is_instance_valid(_aim_preview_solid_line):
		_aim_preview_solid_line.queue_free()
	for line in _aim_preview_dashed_lines:
		if line != null and is_instance_valid(line):
			line.queue_free()
	_aim_hit_crosshair_lines.clear()
	_aim_hit_square_lines.clear()
	_aim_player_cell_corner_lines.clear()
	_aim_hit_spin_corner_line = null
	_aim_hit_spin_corner_line_b = null
	_aim_preview_solid_line = null
	_aim_preview_dashed_lines.clear()


func _set_aim_mode(enabled: bool) -> void:
	if _is_aim_mode == enabled:
		return
	_is_aim_mode = enabled
	if _is_aim_mode:
		_play_sfx_if_available("Aim")
		_play_aim_enter_animation()
		return
	_play_sfx_if_available("Holster")
	if not _dead and not _is_moving and not _is_action_locked():
		_play_player_animation(idle_animation)


func _play_aim_enter_animation() -> void:
	if anim_player == null:
		return
	var pose_anim_name := _get_current_aim_pose_animation()
	var anim := anim_player.get_animation(pose_anim_name)
	if anim == null:
		return
	_play_player_animation(pose_anim_name, aim_animation_speed_scale, false)
	var duration := anim.length / maxf(aim_animation_speed_scale, 0.01)
	var timer := get_tree().create_timer(maxf(0.0, duration))
	timer.timeout.connect(func() -> void:
		if not _is_aim_mode or _dead or _is_moving:
			return
		_hold_aim_pose()
	, CONNECT_ONE_SHOT)


func _hold_aim_pose() -> void:
	if anim_player == null:
		return
	var pose_anim_name := _get_current_aim_pose_animation()
	var anim := anim_player.get_animation(pose_anim_name)
	if anim == null:
		return
	_play_player_animation(pose_anim_name, aim_animation_speed_scale, false)
	# 跳到末帧附近并暂停，稳定保持瞄准末姿态。
	var end_time := maxf(0.0, anim.length - 0.0001)
	anim_player.seek(end_time, true)
	anim_player.pause()
	_current_animation = pose_anim_name


func _get_current_aim_pose_animation() -> StringName:
	var preferred := aim_animation if _is_reloaded else aim_unload_animation
	if anim_player == null:
		return preferred
	var anim := anim_player.get_animation(preferred)
	if anim != null:
		return preferred
	return aim_animation


func _play_colored_impact_particles(origin_world: Vector2, color: Color, count: int, speed_min: float, speed_max: float, life_min: float, life_max: float) -> void:
	var particle_parent := get_parent()
	if particle_parent == null:
		particle_parent = self
	var tex := _get_blood_particle_texture()
	for _i in count:
		var particle := Sprite2D.new()
		particle.texture = tex
		particle.centered = true
		particle.modulate = color
		particle.top_level = true
		particle_parent.add_child(particle)
		particle.global_position = origin_world
		var dir := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		var speed := randf_range(speed_min, speed_max)
		var life := randf_range(life_min, life_max)
		var target := particle.global_position + dir * speed
		var tween := create_tween()
		tween.tween_property(particle, "global_position", target, life)
		tween.parallel().tween_property(particle, "modulate:a", 0.0, life)
		tween.finished.connect(func() -> void:
			if is_instance_valid(particle):
				particle.queue_free()
		, CONNECT_ONE_SHOT)


func _play_bullet_burst_ring(origin_world: Vector2, color: Color) -> void:
	var particle_parent := get_parent()
	if particle_parent == null:
		particle_parent = self
	var ring := Line2D.new()
	ring.width = 1.6
	ring.default_color = color
	ring.closed = true
	ring.top_level = true
	particle_parent.add_child(ring)
	var segments := 16
	var base_radius := 2.0
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(origin_world + Vector2.RIGHT.rotated(angle) * base_radius)
	ring.points = points
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var radius := lerpf(2.0, 8.0, t)
		var frame := PackedVector2Array()
		for i in range(segments):
			var angle := TAU * float(i) / float(segments)
			frame.append(origin_world + Vector2.RIGHT.rotated(angle) * radius)
		ring.points = frame
		ring.default_color = Color(color.r, color.g, color.b, color.a * (1.0 - t))
	, 0.0, 1.0, 0.12)
	tween.finished.connect(func() -> void:
		if is_instance_valid(ring):
			ring.queue_free()
	, CONNECT_ONE_SHOT)


func _is_adjacent_wall_shot_forbidden(target_grid: Vector2i) -> bool:
	if dungeon_generator == null:
		return false
	if maxi(absi(target_grid.x - grid_pos.x), absi(target_grid.y - grid_pos.y)) != 1:
		return false
	return DungeonGenerator.tile_blocks_movement(
		dungeon_generator.get_tile(target_grid) as DungeonGenerator.TileType
	)


func _cancel_all_buffered_input() -> void:
	_pending_single_dir = Vector2i.ZERO
	_pending_single_dir_time_ms = 0
	_queued_dir = Vector2i.ZERO
	_hold_active = false
	_hold_timer = 0.0
	_hold_last_dir = Vector2i.ZERO
	if turn_controller != null:
		turn_controller.clear_queued_actions()


func _sync_fire_ambience_audio() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var want := false
	if _spawned and not _dead and turn_controller != null and turn_controller.has_method("is_any_burning_liquid_visible_to_player"):
		want = bool(turn_controller.call("is_any_burning_liquid_visible_to_player"))
	for autoload_name in ["AudioManager", "audiomanager", "SfxManager"]:
		var node := tree.root.get_node_or_null(NodePath(autoload_name))
		if node != null and node.has_method("update_fire_ambience"):
			node.call("update_fire_ambience", want)
			return
	for child in tree.root.get_children():
		if child != null and child.has_method("update_fire_ambience"):
			child.call("update_fire_ambience", want)
			return


func _play_sfx_if_available(sfx_name: String) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	for autoload_name in ["AudioManager", "audiomanager", "SfxManager"]:
		var node := tree.root.get_node_or_null(NodePath(autoload_name))
		if node != null and node.has_method("play_sfx"):
			node.call("play_sfx", sfx_name)
			return
	for child in tree.root.get_children():
		if child != null and child.has_method("play_sfx"):
			child.call("play_sfx", sfx_name)
			return
	push_warning("PlayerGridController: 未找到可用的 AudioManager Autoload（需包含 play_sfx 方法）。")


func _play_footstep_sfx() -> void:
	if FOOTSTEP_SFX_NAMES.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	var min_interval_ms := int(footstep_repeat_interval * 1000.0)
	var is_continuous_move := _hold_active or not _auto_path.is_empty()
	if is_continuous_move and now_ms - _last_footstep_time_ms < min_interval_ms:
		return
	var pool := FOOTSTEP_SFX_NAMES
	if _is_player_foot_cell_liquid(grid_pos):
		if not WATER_FOOTSTEP_SFX_NAMES.is_empty():
			pool = WATER_FOOTSTEP_SFX_NAMES
	var sfx_name := pool[_footstep_rng.randi_range(0, pool.size() - 1)]
	_play_sfx_if_available(sfx_name)
	_last_footstep_time_ms = now_ms


func _is_player_foot_cell_liquid(cell: Vector2i) -> bool:
	if turn_controller == null:
		return false
	if not turn_controller.has_method("get_liquid_at"):
		return false
	return turn_controller.call("get_liquid_at", cell) != null


func set_fire_attachment_turns(turns: int, refresh_existing: bool = true) -> void:
	var dur := maxi(0, turns)
	var was := _fire_attachment_turns > 0
	if refresh_existing:
		_fire_attachment_turns = dur
	else:
		_fire_attachment_turns = maxi(_fire_attachment_turns, dur)
	if not was and _fire_attachment_turns > 0:
		FireAttachmentVisual.spawn_ignite_burst_intense(global_position, tile_size, 6.0)


func get_fire_attachment_turns() -> int:
	return _fire_attachment_turns


func advance_fire_attachment_turn() -> void:
	if _fire_attachment_turns > 0:
		_fire_attachment_turns -= 1
	if _fire_attachment_turns <= 0:
		_fire_particle_accum = 0.0


func _clear_fire_attachment() -> void:
	_fire_attachment_turns = 0
	_fire_particle_accum = 0.0


func _update_fire_attachment_visuals(delta: float) -> void:
	if _fire_attachment_turns <= 0 or _dead:
		_fire_particle_accum = 0.0
		return
	_fire_particle_accum += delta
	while _fire_particle_accum >= _FIRE_ATTACH_PARTICLE_INTERVAL:
		_fire_particle_accum -= _FIRE_ATTACH_PARTICLE_INTERVAL
		FireAttachmentVisual.spawn_burn_tick_match_liquid(global_position, tile_size, 5.0)

