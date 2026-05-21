extends RefCounted
## 桶坠入深渊时在 **世界节点**下播放短暂朝上水花（不占位，不绑定被摧毁的单位）。
## 使用 `world_parent` 的**局部**坐标（与 TileMap/单位 `position` 对齐），避免 global/local 混用导致偏移。
class_name BarrelAbyssSplashEffect


static func play(world_parent: Node, grid_cell: Vector2i, tile_size: int) -> void:
	var wp2d := world_parent as Node2D
	if wp2d == null:
		return
	var holder := Node2D.new()
	holder.name = "AbyssSplashEffect"
	holder.z_index = 500
	holder.z_as_relative = false
	wp2d.add_child(holder)
	var ts := float(tile_size)
	var half := ts * 0.5
	## 与单位 `_snap_to_grid_center` 一致：格中心 + 轻微下移使水花从“坑口”起跳
	var local_base := Vector2(grid_cell) * ts + Vector2(half, half + ts * 0.22)
	holder.position = local_base
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.55, 0.82, 1.0, 0.95))
	var dot: Texture2D = ImageTexture.create_from_image(img)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in range(14):
		var p := Sprite2D.new()
		p.texture = dot
		p.centered = true
		p.scale = Vector2.ONE * rng.randf_range(2.8, 4.2)
		## 子节点全部用相对 holder 的 position，tween 也用 position，避免父节点有偏移时 global 错位
		p.position = Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(3.0, 8.0))
		p.modulate = Color(0.7, 0.9, 1.0, 0.95)
		holder.add_child(p)
		var dir := Vector2(rng.randf_range(-0.32, 0.32), -1.0).normalized()
		var speed := rng.randf_range(ts * 1.08, ts * 2.05)
		var life := rng.randf_range(0.16, 0.28)
		var target := p.position + dir * speed
		var tween := holder.create_tween()
		tween.tween_property(p, "position", target, life)
		tween.parallel().tween_property(p, "modulate:a", 0.0, life)

	var kill_tw := holder.create_tween()
	kill_tw.tween_interval(0.45)
	kill_tw.tween_callback(func() -> void:
		if is_instance_valid(holder):
			holder.queue_free()
	)
