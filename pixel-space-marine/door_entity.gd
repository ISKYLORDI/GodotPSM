class_name GridDoor
extends Node2D
## `Open`：正常可走开合。`Activate`/`Idle`：`set_door_inactive(false)` 时先正向播 Activate 再 Loop Idle，
## `set_door_inactive(true)` 时对 Activate 倒放；瞬时切换（animated=false）则直接对齐姿态。

const OPEN_ANIM: StringName = &"Open"
const ACTIVATE_ANIM: StringName = &"Activate"
const IDLE_ANIM: StringName = &"Idle"

var grid_pos: Vector2i = Vector2i.ZERO
var tile_size: int = 16

@export var z_index_override: int = -18
@export var play_animation_when_available: bool = true

var inactive: bool = false

enum _DoorAnimIntent {
	NONE,
	PLAY_IDLE_AFTER_ACTIVATE_FORWARD,
	END_AFTER_ACTIVATE_BACKWARD,
	PLAY_IDLE_AFTER_OPEN_CLOSE_BACK,
}

var _intent: _DoorAnimIntent = _DoorAnimIntent.NONE


func _ready() -> void:
	z_as_relative = false
	z_index = z_index_override
	var ap := _get_ap()
	if ap != null and not ap.animation_finished.is_connected(_on_animation_finished):
		ap.animation_finished.connect(_on_animation_finished)


func bind_grid_position(pos: Vector2i, ts: int) -> void:
	grid_pos = pos
	tile_size = ts
	position = Vector2(pos) * float(ts) + Vector2.ONE * (float(ts) * 0.5)


func set_door_inactive(v: bool, animated: bool = true) -> void:
	var ap := _get_ap()
	if ap != null:
		ap.speed_scale = 1.0
	if inactive == v:
		return
	inactive = v
	if inactive:
		_play_disable_activation(animated)
	else:
		_play_enable_activation(animated)


func set_open(is_open: bool, animated: bool = true) -> void:
	if inactive:
		return
	var ap := _get_ap()
	if ap == null or not ap.has_animation(OPEN_ANIM):
		return
	var use_anim := animated and play_animation_when_available

	if use_anim:
		ap.active = true
		ap.speed_scale = 1.0
		if not is_open:
			_intent = _DoorAnimIntent.PLAY_IDLE_AFTER_OPEN_CLOSE_BACK
			# stop(false) / _kill_active_anim 会把片段位置重置到 t=0；Open 的起点多为「已关」姿势，
			# 在 play_backwards 生效前会闪一帧。先对齐到 Open 末尾再倒放，与 Activate 关门径一致。
			var om := ap.get_animation(OPEN_ANIM)
			ap.stop(true)
			ap.play(OPEN_ANIM)
			ap.seek(om.length, true)
			ap.pause()
			ap.play_backwards(OPEN_ANIM)
			return
		_kill_active_anim(ap)
		_intent = _DoorAnimIntent.NONE
		ap.play(OPEN_ANIM)
		return

	_kill_active_anim(ap)

	var anim := ap.get_animation(OPEN_ANIM)
	ap.play(OPEN_ANIM)
	ap.seek(anim.length if is_open else 0.0, true)
	ap.pause()
	if not is_open:
		_snap_idle_when_closed_without_open_anim()


func _get_ap() -> AnimationPlayer:
	return get_node_or_null("AnimationPlayer") as AnimationPlayer


func _has_anim(ap: AnimationPlayer, nm: StringName) -> bool:
	return ap != null and ap.has_animation(nm)


func _kill_active_anim(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	ap.stop(false)
	_intent = _DoorAnimIntent.NONE


func _on_animation_finished(anim_name: StringName) -> void:
	var ap := _get_ap()
	if ap == null:
		return
	match _intent:
		_DoorAnimIntent.PLAY_IDLE_AFTER_ACTIVATE_FORWARD:
			if anim_name == ACTIVATE_ANIM:
				_intent = _DoorAnimIntent.NONE
				_play_idle_loop(ap)
		_DoorAnimIntent.END_AFTER_ACTIVATE_BACKWARD:
			if anim_name == ACTIVATE_ANIM:
				_intent = _DoorAnimIntent.NONE
				_seek_activate_pose_start(ap)
				ap.pause()
		_DoorAnimIntent.PLAY_IDLE_AFTER_OPEN_CLOSE_BACK:
			if anim_name == OPEN_ANIM:
				_intent = _DoorAnimIntent.NONE
				if not inactive:
					_play_idle_loop(ap)
		_:
			pass


func _snap_idle_when_closed_without_open_anim() -> void:
	var ap := _get_ap()
	if ap == null:
		return
	if inactive:
		return
	if _has_anim(ap, IDLE_ANIM):
		_play_idle_loop(ap)
	elif _has_anim(ap, OPEN_ANIM):
		ap.play(OPEN_ANIM)
		ap.seek(0.0, true)
		ap.pause()


func _play_idle_loop(ap: AnimationPlayer) -> void:
	if ap == null or inactive:
		return
	if _has_anim(ap, IDLE_ANIM):
		ap.speed_scale = 1.0
		ap.play(IDLE_ANIM)
		return
	# Fallback：无 Idle 时维持 Open 在时间 0。
	if _has_anim(ap, OPEN_ANIM):
		ap.seek(0.0, true)
		ap.pause()


func _seek_activate_pose_start(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	if _has_anim(ap, ACTIVATE_ANIM):
		ap.play(ACTIVATE_ANIM)
		ap.seek(0.0, true)
		ap.pause()
		return
	# Fallback
	if _has_anim(ap, OPEN_ANIM):
		ap.seek(0.0, true)
		ap.pause()


func _snap_activate_end_pose(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	if _has_anim(ap, ACTIVATE_ANIM):
		var am := ap.get_animation(ACTIVATE_ANIM)
		ap.play(ACTIVATE_ANIM)
		ap.seek(am.length, true)
		ap.pause()


func _play_disable_activation(animated: bool) -> void:
	var ap := _get_ap()
	if ap == null:
		return
	if not animated or not play_animation_when_available:
		_kill_active_anim(ap)
		_seek_activate_pose_start(ap)
		return

	if _has_anim(ap, ACTIVATE_ANIM) and play_animation_when_available:
		_kill_active_anim(ap)
		ap.speed_scale = 1.0
		ap.active = true
		_intent = _DoorAnimIntent.END_AFTER_ACTIVATE_BACKWARD
		var am := ap.get_animation(ACTIVATE_ANIM)
		ap.play(ACTIVATE_ANIM)
		ap.seek(am.length, true)
		ap.pause()
		ap.play_backwards(ACTIVATE_ANIM)
		return

	_kill_active_anim(ap)
	_seek_activate_pose_start(ap)


func _play_enable_activation(animated: bool) -> void:
	var ap := _get_ap()
	if ap == null:
		return
	if not animated or not play_animation_when_available:
		_kill_active_anim(ap)
		_snap_activate_end_pose(ap)
		_play_idle_loop(ap)
		return

	if _has_anim(ap, ACTIVATE_ANIM) and play_animation_when_available:
		_kill_active_anim(ap)
		ap.speed_scale = 1.0
		ap.active = true
		_intent = _DoorAnimIntent.PLAY_IDLE_AFTER_ACTIVATE_FORWARD
		ap.play(ACTIVATE_ANIM)
		return

	_kill_active_anim(ap)
	_play_idle_loop(ap)
