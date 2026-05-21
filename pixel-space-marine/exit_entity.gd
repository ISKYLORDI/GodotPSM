class_name GridExit
extends Node2D
## 出口实体：推荐子节点 `AnimationPlayer`，动画名 **Idle**（或 `idle`）在生成时循环播放。

var grid_pos: Vector2i = Vector2i.ZERO
var tile_size: int = 16

@export var z_index_override: int = -18

func _ready() -> void:
	z_as_relative = false
	z_index = z_index_override


func bind_grid_position(pos: Vector2i, ts: int) -> void:
	grid_pos = pos
	tile_size = ts
	position = Vector2(pos) * float(ts) + Vector2.ONE * (float(ts) * 0.5)


func play_idle_if_any() -> void:
	_start_idle_loop()


func _start_idle_loop() -> void:
	var ap := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	var which: StringName = StringName()
	if ap.has_animation(&"Idle"):
		which = &"Idle"
	elif ap.has_animation(&"idle"):
		which = &"idle"
	else:
		return
	var anim := ap.get_animation(which)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	ap.play(which)
