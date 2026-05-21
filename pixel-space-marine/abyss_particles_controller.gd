extends Node2D

var _fog_rect: ColorRect
var _particles: GPUParticles2D


func _ready() -> void:
	_cache_nodes()


func _cache_nodes() -> void:
	if _fog_rect == null:
		_fog_rect = get_node_or_null("FogRect") as ColorRect
	if _particles == null:
		_particles = get_node_or_null("GPUParticles2D") as GPUParticles2D


func set_emission_rect(map_pixel_size: Vector2) -> void:
	_cache_nodes()
	var size := Vector2(maxf(map_pixel_size.x, 1.0), maxf(map_pixel_size.y, 1.0))

	# 全局雾层：覆盖整张地图并以中心对齐。
	if _fog_rect != null:
		_fog_rect.size = size
		_fog_rect.position = -size * 0.5

	# 让粒子作为点缀铺满全图，而不是聚在中心。
	if _particles != null:
		var pm := _particles.process_material as ParticleProcessMaterial
		if pm != null:
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(size.x * 0.5, size.y * 0.5, 1.0)

	# 颗粒数量按面积缩放，避免大地图太稀疏。
	var area := size.x * size.y
	if _particles != null:
		_particles.amount = int(clampf(area / 2400.0, 120.0, 1200.0))

	# 给 atmosphere shader 同步地图尺寸，保证 tiling 视觉稳定。
	if _fog_rect != null:
		var mat := _fog_rect.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("map_size", size)
