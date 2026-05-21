extends RefCounted
## 与 `FlammableLiquid` 燃烧时的火星粒子效果一致，用于单位身上着火表现。
class_name FireAttachmentVisual

const _PIXEL_LAYER := 700


static func spawn_ignite_burst(origin_global: Vector2, tile_size: int, flame_scale: float) -> void:
	_spawn_flame_particles(origin_global, tile_size, 8, 0.08, 0.16, 6.0, 16.0, flame_scale)


static func spawn_flicker(origin_global: Vector2, tile_size: int, flame_scale: float) -> void:
	_spawn_flame_particles(origin_global, tile_size, 2, 0.06, 0.12, 4.0, 10.0, flame_scale)


## 与 `FlammableLiquid` 每帧火星参数一致（`count=2` 等），便于桶/单位与液体观感统一。
static func spawn_burn_tick_match_liquid(
		origin_global: Vector2,
		tile_size: int,
		flame_scale: float = 5.0,
) -> void:
	_spawn_flame_particles(origin_global, tile_size, 2, 0.06, 0.12, 4.0, 10.0, flame_scale)


## 略强于默认 `spawn_ignite_burst`，用于木桶等着火瞬间。
static func spawn_ignite_burst_intense(origin_global: Vector2, tile_size: int, flame_scale: float = 6.0) -> void:
	_spawn_flame_particles(origin_global, tile_size, 12, 0.08, 0.18, 7.0, 18.0, flame_scale)


static func _get_pixel_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


static func _spawn_flame_particles(
	origin_global: Vector2,
	tile_size: int,
	count: int,
	life_min: float,
	life_max: float,
	speed_min: float,
	speed_max: float,
	flame_scale: float
) -> void:
	var tex: Texture2D = _get_pixel_texture()
	var half_span: float = float(tile_size) * 0.42
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var root := tree.root
	for _i in range(count):
		var p := Sprite2D.new()
		p.texture = tex
		p.centered = true
		p.top_level = true
		p.z_as_relative = false
		p.z_index = _PIXEL_LAYER
		p.scale = Vector2.ONE * flame_scale
		root.add_child(p)
		p.global_position = origin_global + Vector2(
			randf_range(-half_span, half_span),
			randf_range(-half_span, half_span)
		)
		var warm := randf()
		p.modulate = Color(1.0, lerpf(0.35, 0.8, warm), lerpf(0.05, 0.25, warm), 0.95)
		var dir := Vector2(randf_range(-0.2, 0.2), -1.0).normalized()
		var speed := randf_range(speed_min, speed_max)
		var life := randf_range(life_min, life_max)
		var target := p.global_position + dir * speed
		var tween := p.create_tween()
		tween.tween_property(p, "global_position", target, life)
		tween.parallel().tween_property(p, "modulate:a", 0.0, life)
		tween.finished.connect(func() -> void:
			if is_instance_valid(p):
				p.queue_free()
		, CONNECT_ONE_SHOT)
