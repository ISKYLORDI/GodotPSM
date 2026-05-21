class_name EnemyGridController
extends Sprite2D

signal grid_position_changed(grid_pos: Vector2i)
signal death_animation_finished

@export_group("Map")
@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
@export var turn_controller_path: NodePath = NodePath("../TurnController")

@export_group("Movement")
@export var move_duration: float = 0.05
@export var attack_feedback_duration: float = 0.08
@export var visual_offset: Vector2 = Vector2.ZERO
@export_range(0, 9999, 1) var turn_order: int = 0

@export_group("Combat")
@export var max_hp: int = 1
@export var attack_damage: int = 1

@export_group("AI")
@export_range(1, 20, 1) var detection_range: int = 8
@export_range(0.0, 1.0, 0.05) var wander_chance_per_turn: float = 0.45
@export var detection_flash_color: Color = Color(1.0, 0.95, 0.3, 1.0)
@export var lost_flash_color: Color = Color(0.65, 0.9, 1.0, 1.0)
@export_range(0.05, 0.4, 0.01) var lost_flash_step_duration: float = 0.12
@export var can_open_doors_flag: bool = true
@export_range(2, 30, 1) var wander_target_min_distance: int = 5

@export_group("Traits")
## 若为 true：视为浮空，**深渊格（ABYSS）**可被移动／寻路与占用；默认为地面单位。
@export var floating: bool = false

@export_group("Animation")
@export var idle_animation: StringName = &"Idle"
@export var walk_animation: StringName = &"Walk"
@export var attack_animation: StringName = &"Attack"
@export var death_animation: StringName = &"Death"
@export_range(0.1, 4.0, 0.05) var walk_animation_speed_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var attack_animation_speed_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var death_animation_speed_scale: float = 1.0

var grid_pos: Vector2i = Vector2i.ZERO
var tile_size: int = 16
var dungeon_generator: DungeonGenerator = null
var turn_controller: TurnController = null

var _move_tween: Tween = null
var _current_animation: StringName = &""
var _last_attack_duration: float = 0.0
var _hp: int = 1
var _dead: bool = false
var _base_scale_x: float = 1.0
var _ai_state: StringName = &"idle"
var _last_known_player_grid: Vector2i = Vector2i(-1, -1)
var _search_pause_turns_remaining: int = 0
var _wander_target: Vector2i = Vector2i(-1, -1)
const ENEMY_DEATH_SFX_NAMES: PackedStringArray = ["EnemyDeath1", "EnemyDeath2"]
const AUDIO_MANAGER_CANDIDATE_NAMES: PackedStringArray = ["AudioManager", "audiomanager", "SfxManager"]
var _death_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _audio_manager_missing_logged: bool = false
var _fire_attachment_turns: int = 0
var _fire_particle_accum: float = 0.0
const _FIRE_ATTACH_PARTICLE_INTERVAL := 0.045
@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")


func _ready() -> void:
	z_as_relative = false
	z_index = -10
	add_to_group("enemy")
	_death_rng.randomize()
	_base_scale_x = absf(scale.x) if not is_zero_approx(scale.x) else 1.0
	_resolve_references()
	_ensure_visible_texture()
	_snap_to_grid_center()
	_hp = maxi(1, max_hp)
	_play_enemy_animation(idle_animation, 1.0, true)
	if turn_controller != null:
		turn_controller.register_enemy(self)
	set_process(true)


func _process(delta: float) -> void:
	_update_fire_attachment_visuals(delta)


func bind_grid_position(pos: Vector2i) -> void:
	grid_pos = pos
	_snap_to_grid_center()
	queue_redraw()
	grid_position_changed.emit(grid_pos)


func decide_turn_action(player_grid: Vector2i, _turn: TurnController) -> Dictionary:
	if _dead:
		return {"type": "wait"}
	if _turn == null:
		return {"type": "wait"}

	var sees_player := _turn.has_line_of_sight(grid_pos, player_grid, detection_range)
	if sees_player:
		_last_known_player_grid = player_grid
		if _ai_state != &"chasing":
			_show_state_flash(detection_flash_color)
		_ai_state = &"chasing"
		_search_pause_turns_remaining = 0
	elif _ai_state == &"chasing":
		_ai_state = &"searching_last_known"
		_search_pause_turns_remaining = 0

	var delta := player_grid - grid_pos
	if maxi(absi(delta.x), absi(delta.y)) == 1:
		return {
			"type": "attack",
			"target_grid": player_grid,
		}

	if _ai_state == &"chasing":
		var chase_step := _turn.pick_enemy_step(self, player_grid)
		if chase_step != grid_pos:
			return {"type": "move", "target_grid": chase_step}
		return {"type": "wait"}

	if _ai_state == &"searching_last_known":
		if _last_known_player_grid == Vector2i(-1, -1):
			_ai_state = &"idle"
			return {"type": "wait"}
		if grid_pos != _last_known_player_grid:
			var search_step := _turn.pick_enemy_step(self, _last_known_player_grid)
			if search_step != grid_pos:
				return {"type": "move", "target_grid": search_step}
			_ai_state = &"idle"
			_last_known_player_grid = Vector2i(-1, -1)
			return {"type": "wait"}
		if _search_pause_turns_remaining <= 0:
			_search_pause_turns_remaining = 1
			return {"type": "wait"}
		_search_pause_turns_remaining = 0
		_ai_state = &"idle"
		_last_known_player_grid = Vector2i(-1, -1)
		_wander_target = Vector2i(-1, -1)
		_show_state_flash_burst(lost_flash_color, 3, lost_flash_step_duration)
		return {"type": "wait"}

	if randf() > wander_chance_per_turn and _wander_target == Vector2i(-1, -1):
		return {"type": "wait"}

	if _wander_target == Vector2i(-1, -1) or _wander_target == grid_pos:
		_wander_target = _turn.pick_random_wander_target(self, grid_pos, wander_target_min_distance)

	var wander_step := _turn.pick_enemy_step(self, _wander_target)
	if wander_step != grid_pos:
		return {"type": "move", "target_grid": wander_step}

	_wander_target = Vector2i(-1, -1)
	return {"type": "wait"}


func execute_turn_move(target_grid: Vector2i) -> void:
	if _dead:
		return
	_face_toward(target_grid - grid_pos)
	grid_pos = target_grid
	_play_enemy_animation(walk_animation, walk_animation_speed_scale, true)
	_start_move_tween(grid_to_world(target_grid))
	grid_position_changed.emit(grid_pos)


func play_attack_feedback(_target_grid: Vector2i) -> void:
	if _dead:
		return
	_face_toward(_target_grid - grid_pos)
	_last_attack_duration = _play_enemy_animation(attack_animation, attack_animation_speed_scale, false)
	if _last_attack_duration <= 0.0:
		_last_attack_duration = attack_feedback_duration

	# 攻击高亮反馈可与动画并行。
	modulate = Color(1.0, 0.6, 0.6, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, minf(_last_attack_duration, attack_feedback_duration))
	if anim_player != null and idle_animation != StringName():
		_schedule_idle_after(_last_attack_duration)


func get_turn_move_duration() -> float:
	return move_duration


func get_attack_feedback_duration() -> float:
	return maxf(_last_attack_duration, attack_feedback_duration)


func play_death_animation() -> void:
	_dead = true
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null
	var death_sfx_name := ENEMY_DEATH_SFX_NAMES[_death_rng.randi_range(0, ENEMY_DEATH_SFX_NAMES.size() - 1)]
	_play_sfx_if_available(death_sfx_name)
	var duration := _play_enemy_animation(death_animation, death_animation_speed_scale, false)
	if duration <= 0.0:
		death_animation_finished.emit()
		queue_free()
		return
	await get_tree().create_timer(duration).timeout
	death_animation_finished.emit()
	queue_free()


func apply_damage(amount: int, source_grid: Vector2i = Vector2i.ZERO) -> bool:
	if _dead:
		return true
	if source_grid != Vector2i.ZERO:
		_face_toward(source_grid - grid_pos)
	_hp -= maxi(0, amount)
	queue_redraw()
	if _hp <= 0:
		_dead = true
		play_death_animation()
		return true
	play_attack_feedback(source_grid)
	return false


func is_dead() -> bool:
	return _dead


func get_attack_damage() -> int:
	return attack_damage


func can_open_doors() -> bool:
	return can_open_doors_flag


func grid_to_world(grid: Vector2i) -> Vector2:
	return Vector2(grid) * float(tile_size) + Vector2.ONE * (tile_size * 0.5) + visual_offset


func _start_move_tween(target_world: Vector2) -> void:
	if _dead:
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_LINEAR)
	_move_tween.set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(self, "position", target_world, move_duration)
	_move_tween.finished.connect(func() -> void:
		if _dead:
			return
		_play_enemy_animation(idle_animation, 1.0, true)
	, CONNECT_ONE_SHOT)


func _snap_to_grid_center() -> void:
	position = grid_to_world(grid_pos)


func _draw() -> void:
	var compensate_x := -1.0 if scale.x < 0.0 else 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(compensate_x, 1.0))
	_draw_health_bar(_hp, max_hp)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _resolve_references() -> void:
	if dungeon_generator == null and not dungeon_generator_path.is_empty():
		var dungeon_node := get_node_or_null(dungeon_generator_path)
		if dungeon_node is DungeonGenerator:
			dungeon_generator = dungeon_node
	if dungeon_generator == null:
		var found_dungeon := get_tree().get_first_node_in_group("dungeon_generator")
		if found_dungeon is DungeonGenerator:
			dungeon_generator = found_dungeon

	if turn_controller == null and not turn_controller_path.is_empty():
		var turn_node := get_node_or_null(turn_controller_path)
		if turn_node is TurnController:
			turn_controller = turn_node
	if turn_controller == null:
		var found_turn := get_tree().get_first_node_in_group("turn_controller")
		if found_turn is TurnController:
			turn_controller = found_turn

	if dungeon_generator != null:
		tile_size = dungeon_generator.tile_size


func _ensure_visible_texture() -> void:
	if texture != null:
		centered = true
		return
	var img := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.75, 0.1, 0.2, 1.0))
	for x in tile_size:
		img.set_pixel(x, 0, Color(1.0, 0.9, 0.9, 1.0))
		img.set_pixel(x, tile_size - 1, Color(1.0, 0.9, 0.9, 1.0))
	for y in tile_size:
		img.set_pixel(0, y, Color(1.0, 0.9, 0.9, 1.0))
		img.set_pixel(tile_size - 1, y, Color(1.0, 0.9, 0.9, 1.0))
	texture = ImageTexture.create_from_image(img)
	centered = true


func _schedule_idle_after(delay: float) -> void:
	if delay <= 0.0:
		_play_enemy_animation(idle_animation, 1.0, true)
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		_play_enemy_animation(idle_animation, 1.0, true)
	, CONNECT_ONE_SHOT)


func _play_enemy_animation(animation_name: StringName, speed_scale: float, loop: bool) -> float:
	if anim_player == null or animation_name == StringName():
		return 0.0
	var anim := anim_player.get_animation(animation_name)
	if anim == null:
		return 0.0

	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if _current_animation != animation_name or not anim_player.is_playing():
		anim_player.play(animation_name, -1.0, maxf(speed_scale, 0.01))
	else:
		anim_player.speed_scale = maxf(speed_scale, 0.01)
	_current_animation = animation_name
	return anim.length / maxf(speed_scale, 0.01)


func _face_toward(delta: Vector2i) -> void:
	if delta.x == 0:
		return
	scale.x = _base_scale_x if delta.x > 0 else -_base_scale_x


func _draw_health_bar(current_hp: int, max_hp_value: int) -> void:
	if _dead or max_hp_value <= 1:
		return
	var width := float(tile_size) * 0.8
	var height := 3.0
	var top_left := Vector2(-width * 0.5, -float(tile_size) * 0.9)
	var ratio := clampf(float(maxi(current_hp, 0)) / float(max_hp_value), 0.0, 1.0)
	var fill_color := Color(0.9, 0.2, 0.2, 1.0)
	draw_rect(Rect2(top_left, Vector2(width, height)), Color(0.0, 0.0, 0.0, 0.6), true)
	draw_rect(Rect2(top_left + Vector2.ONE, Vector2((width - 2.0) * ratio, height - 2.0)), fill_color, true)


func _show_state_flash(color: Color) -> void:
	modulate = color
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.22)


func _show_state_flash_burst(color: Color, flashes: int, step_duration: float) -> void:
	if flashes <= 0:
		return
	var tween := create_tween()
	for _i in flashes:
		tween.tween_property(self, "modulate", color, step_duration)
		tween.tween_property(self, "modulate", Color.WHITE, step_duration)


func _play_sfx_if_available(sfx_name: String) -> void:
	var audio_manager := _get_audio_manager()
	if audio_manager != null:
		audio_manager.call("play_sfx", sfx_name)
		return
	if not _audio_manager_missing_logged:
		_audio_manager_missing_logged = true
		push_warning("EnemyGridController: 未找到可用的 AudioManager Autoload（需包含 play_sfx 方法）。")


func _get_audio_manager() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	for autoload_name in AUDIO_MANAGER_CANDIDATE_NAMES:
		var node := tree.root.get_node_or_null(NodePath(autoload_name))
		if node != null and node.has_method("play_sfx"):
			return node
	for child in tree.root.get_children():
		if child != null and child.has_method("play_sfx"):
			return child
	return null


func set_fire_attachment_turns(turns: int, refresh_existing: bool = true) -> void:
	var dur := maxi(0, turns)
	var was := _fire_attachment_turns > 0
	if refresh_existing:
		_fire_attachment_turns = dur
	else:
		_fire_attachment_turns = maxi(_fire_attachment_turns, dur)
	if not was and _fire_attachment_turns > 0:
		FireAttachmentVisual.spawn_ignite_burst(global_position, tile_size, 5.0)


func get_fire_attachment_turns() -> int:
	return _fire_attachment_turns


func advance_fire_attachment_turn() -> void:
	if _fire_attachment_turns > 0:
		_fire_attachment_turns -= 1
	if _fire_attachment_turns <= 0:
		_fire_particle_accum = 0.0


func _update_fire_attachment_visuals(delta: float) -> void:
	if _fire_attachment_turns <= 0 or _dead:
		_fire_particle_accum = 0.0
		return
	_fire_particle_accum += delta
	while _fire_particle_accum >= _FIRE_ATTACH_PARTICLE_INTERVAL:
		_fire_particle_accum -= _FIRE_ATTACH_PARTICLE_INTERVAL
		FireAttachmentVisual.spawn_flicker(global_position, tile_size, 5.0)
