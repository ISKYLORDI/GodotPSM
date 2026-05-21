class_name FlammableLiquid
extends Sprite2D

const _LIQUID_ALPHA_SHADER: Shader = preload("res://shaders/flammable_liquid_sprite.gdshader")

@export var burning_turns_default: int = 8
@export var liquid_material: Material = null
@export_range(0.5, 20.0, 0.5) var flame_particle_scale: float = 5.0

@export_group("Liquid modulation (HSVA)")
## 色相（0–1）。约 0.33 偏绿，0.55 附近偏青。
@export_range(0.0, 1.0, 0.001) var liquid_idle_h: float = 0.555555
@export_range(0.0, 1.0, 0.01) var liquid_idle_s: float = 0.75
@export_range(0.0, 1.0, 0.01) var liquid_idle_v: float = 1.0
@export_range(0.0, 1.0, 0.01) var liquid_idle_a: float = 0.84
## 点燃后的液体色调（与火苗粒子分开调）。
@export_range(0.0, 1.0, 0.001) var liquid_burning_h: float = 0.0882
@export_range(0.0, 1.0, 0.01) var liquid_burning_s: float = 0.85
@export_range(0.0, 1.0, 0.01) var liquid_burning_v: float = 1.0
@export_range(0.0, 1.0, 0.01) var liquid_burning_a: float = 1.0

@export_group("Liquid 不透明度")
## 放大图集像素自身的 alpha。`modulate`/HSVA 的 A 只乘在已有透明度上，贴图很透时调 A 几乎看不出变化。
@export_range(1.0, 4.0, 0.05) var liquid_texture_alpha_gain: float = 1.0

@export_group("Atlas Visual")
@export var liquid_atlas_texture: Texture2D = null
@export_range(1, 128, 1) var liquid_hframes: int = 1
@export_range(1, 128, 1) var liquid_vframes: int = 1
@export var liquid_idle_frame_coords: Vector2i = Vector2i.ZERO
@export var liquid_burning_frame_coords: Vector2i = Vector2i.ZERO
@export var liquid_idle_frame_options: Array[Vector2i] = []
@export var liquid_burning_frame_options: Array[Vector2i] = []

var grid_pos: Vector2i = Vector2i.ZERO
var tile_size: int = 16
var _burning_turns_left: int = 0
var _has_been_ignited: bool = false
var _pending_activation: bool = false
var _pixel_tex: Texture2D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _flame_emit_accum: float = 0.0
var _flame_emit_interval: float = 0.045
var _chosen_idle_frame: Vector2i = Vector2i.ZERO
var _chosen_burning_frame: Vector2i = Vector2i.ZERO
var _alpha_shader_material: ShaderMaterial = null


func _ready() -> void:
	add_to_group("flammable_liquid")
	_rng.randomize()
	_refresh_random_frame_choices()
	apply_canvas_depth()
	_ensure_visual_setup()
	_update_visual()
	set_process(true)


## 与 `DungeonGenerator.get_flammable_liquid_canvas_z_index()` 对齐：仅高于地板，低于玩家/敌人。
func apply_canvas_depth(dungeon_generator: DungeonGenerator = null) -> void:
	z_as_relative = false
	if dungeon_generator == null:
		var found := get_tree().get_first_node_in_group("dungeon_generator")
		if found is DungeonGenerator:
			dungeon_generator = found
	if dungeon_generator != null:
		z_index = dungeon_generator.get_flammable_liquid_canvas_z_index()
	else:
		z_index = -19


func bind_grid_position(pos: Vector2i) -> void:
	grid_pos = pos
	_snap_to_grid_center()


func ignite(turns: int = 8, refresh_existing: bool = true) -> void:
	if _has_been_ignited:
		## 每摊液体只允许一次真正点燃；烧尽后亦不可复燃（`refresh_existing` 不再改变回合）。
		return
	_has_been_ignited = true
	_pending_activation = true
	var duration := turns if turns > 0 else burning_turns_default
	_burning_turns_left = duration
	_update_visual()
	if is_burning():
		_spawn_ignite_flame_burst()


func is_burning() -> bool:
	return _burning_turns_left > 0


func advance_turn() -> void:
	if _burning_turns_left <= 0:
		return
	_burning_turns_left -= 1
	_update_visual()


func can_receive_melee() -> bool:
	return false


func is_burned_out() -> bool:
	return _has_been_ignited and _burning_turns_left <= 0


func should_resolve_this_turn() -> bool:
	if not is_burning():
		return false
	if _pending_activation:
		_pending_activation = false
		return false
	return true


func _ensure_visual_setup() -> void:
	centered = true
	material = _resolve_draw_material()
	_apply_sprite_texture_source()
	_snap_to_grid_center()


func _snap_to_grid_center() -> void:
	position = Vector2(grid_pos) * float(tile_size) + Vector2.ONE * (tile_size * 0.5)


func _update_visual() -> void:
	material = _resolve_draw_material()
	_apply_sprite_texture_source()
	var frame_size := _current_frame_pixel_size()
	var target_size := float(tile_size) * 0.85
	var sx := target_size / maxf(1.0, frame_size.x)
	var sy := target_size / maxf(1.0, frame_size.y)
	scale = Vector2(sx, sy)
	if is_burning():
		modulate = _modulate_from_hsva(liquid_burning_h, liquid_burning_s, liquid_burning_v, liquid_burning_a)
		_apply_frame_coords(_resolved_burning_frame())
	else:
		modulate = _modulate_from_hsva(liquid_idle_h, liquid_idle_s, liquid_idle_v, liquid_idle_a)
		_apply_frame_coords(_chosen_idle_frame)


func _resolve_draw_material() -> Material:
	if liquid_texture_alpha_gain <= 1.001:
		return liquid_material
	if _alpha_shader_material == null:
		_alpha_shader_material = ShaderMaterial.new()
		_alpha_shader_material.shader = _LIQUID_ALPHA_SHADER
	_alpha_shader_material.set_shader_parameter("texture_alpha_gain", liquid_texture_alpha_gain)
	return _alpha_shader_material


func _modulate_from_hsva(h: float, s: float, v: float, a: float) -> Color:
	var hh := fposmod(h, 1.0)
	return Color.from_hsv(hh, clampf(s, 0.0, 1.0), clampf(v, 0.0, 1.0), clampf(a, 0.0, 1.0))


func _spawn_ignite_flame_burst() -> void:
	_spawn_flame_particles(8, 0.08, 0.16, 6.0, 16.0)


func _spawn_flame_flicker_particles() -> void:
	_spawn_flame_particles(4, 0.06, 0.12, 4.0, 10.0)


func _spawn_flame_particles(count: int, life_min: float, life_max: float, speed_min: float, speed_max: float) -> void:
	if not visible:
		return
	var origin := global_position
	var half_span: float = float(tile_size) * 0.42
	for _i in range(count):
		var p := Sprite2D.new()
		p.texture = _get_pixel_texture()
		p.centered = true
		p.top_level = true
		p.z_as_relative = false
		p.z_index = 700
		p.scale = Vector2.ONE * flame_particle_scale
		p.global_position = origin + Vector2(
			randf_range(-half_span, half_span),
			randf_range(-half_span, half_span)
		)
		var warm := randf()
		p.modulate = Color(1.0, lerpf(0.35, 0.8, warm), lerpf(0.05, 0.25, warm), 0.95)
		add_child(p)
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


func _get_pixel_texture() -> Texture2D:
	if _pixel_tex != null:
		return _pixel_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_pixel_tex = ImageTexture.create_from_image(img)
	return _pixel_tex


func _apply_sprite_texture_source() -> void:
	if liquid_atlas_texture != null:
		texture = liquid_atlas_texture
		hframes = maxi(1, liquid_hframes)
		vframes = maxi(1, liquid_vframes)
		return
	texture = _get_pixel_texture()
	hframes = 1
	vframes = 1


func _apply_frame_coords(coords: Vector2i) -> void:
	if hframes <= 1 and vframes <= 1:
		return
	var max_x := hframes - 1
	var max_y := vframes - 1
	var clamped := Vector2i(clampi(coords.x, 0, max_x), clampi(coords.y, 0, max_y))
	frame_coords = clamped


func _refresh_random_frame_choices() -> void:
	_chosen_idle_frame = _pick_random_frame(liquid_idle_frame_options, liquid_idle_frame_coords)
	_chosen_burning_frame = _pick_random_frame(liquid_burning_frame_options, liquid_burning_frame_coords)


func _pick_random_frame(candidates: Array[Vector2i], fallback: Vector2i) -> Vector2i:
	if candidates.is_empty():
		return fallback
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _current_frame_pixel_size() -> Vector2:
	if texture == null:
		return Vector2.ONE
	var tex_size := texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Vector2.ONE
	var fw := tex_size.x / float(maxi(1, hframes))
	var fh := tex_size.y / float(maxi(1, vframes))
	return Vector2(maxf(1.0, fw), maxf(1.0, fh))


func _resolved_burning_frame() -> Vector2i:
	# 若未配置燃烧帧（数组和单帧都留空/默认），自动复用 idle 帧并叠加燃烧色。
	var has_burning_options := not liquid_burning_frame_options.is_empty()
	var has_explicit_burning_single := liquid_burning_frame_coords != Vector2i.ZERO
	if has_burning_options or has_explicit_burning_single:
		return _chosen_burning_frame
	return _chosen_idle_frame


func _process(delta: float) -> void:
	if not is_burning():
		_flame_emit_accum = 0.0
		return
	if not visible:
		_flame_emit_accum = 0.0
		return
	_flame_emit_accum += delta
	while _flame_emit_accum >= _flame_emit_interval:
		_flame_emit_accum -= _flame_emit_interval
		_spawn_flame_particles(2, 0.06, 0.12, 4.0, 10.0)
