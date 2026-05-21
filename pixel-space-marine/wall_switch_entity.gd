
class_name GridWallSwitch
extends Node2D
## 墙/地板上的开关：受来自**规定朝向格**的近战或弹射命中时触发 `DungeonGenerator.toggle_doors_adjacent_to_wall_switch`。
## 弹射与近战均用「命中格沿弹道**上一格**」作为朝向来源；与正交一格相比，另接受同侧的**斜邻格**（约 45° 入射）。
## 爆炸、地板燃烧等环境效果走 `trigger_from_environment_damage()`，不校验朝向。
## 四种朝向由 `PresetFloorLayout` 指示层图块语义 + `DungeonGenerator` 四张贴图对应。
## 命名说明：`UP_FROM_SOUTH` = 玩家在南侧邻格**自下往上**打墙；此处使用 Legacy 精灵表 Idle。`DOWN_FROM_NORTH` = 玩家在北侧**自上往下**打墙，静态贴图。

const IDLE_ANIM: StringName = &"Idle"
const LEGACY_IDLE_SHEET: Texture2D = preload(
	"res://Resources/Tech Dungeon Roguelite - Asset Pack (v7)/Props and Items/props and items x2.png"
)
const LEGACY_IDLE_HFRAMES: int = 24
const LEGACY_IDLE_VFRAMES: int = 22
const LEGACY_IDLE_START_FRAME: int = 58
const INTERACTION_GLOW_SHADER: Shader = preload("res://wall_switch_interaction_glow.gdshader")

enum Facing {
	## 盖住墙格；玩家在南侧邻格自下往上打（Preset `marker_wall_switch_face_down_*`）。
	UP_FROM_SOUTH = 0,
	## 盖住墙格；玩家在北邻格自上往下打（Preset `marker_wall_switch_face_up_*`）。
	DOWN_FROM_NORTH = 1,
	## 锚点在可走地板格，东侧附着墙：`get_occupancy_grid_pos`=东邻墙；近战须**站在锚点朝东**打墙上互动点。
	APPROACH_WEST_HIT_EAST = 2,
	## 锚点在可走地板格，西侧附着墙：占用西侧墙格互动；近战须**站在锚点朝西**打墙。
	APPROACH_EAST_HIT_WEST = 3,
}

@export var dungeon_generator_path: NodePath
## AnimationPlayer 相对本节点的路径（未设置时依次尝试 `$Sprite2D/AnimationPlayer`、`AnimationPlayer`）。
@export var animation_player_path: NodePath = NodePath("Sprite2D/AnimationPlayer")

@export_group("选图预览（Tile Picker Inspector）", "editor_atlas_pick_")
## 任选其一：**直接拖入保存好的 TileSet 资源（推荐）**；或绑定下方 TileMapLayer 借其 `.tile_set` 预览。
@export var editor_atlas_pick_tile_set: TileSet
## （可选）与关卡一致的 TileMapLayer，仅取其 `tile_set` 用来选图预览；不配时可仅用 `editor_atlas_pick_tile_set`。
@export var editor_atlas_pick_layer: TileMapLayer
## 与语义图块所属的 atlas source 对齐（门/开关语义一般与 Preset.marker_door_source_id 一致）。编辑器内为 **-1** 时预览用 source **0**，请自行对齐或填非负 id。
@export var editor_atlas_pick_source_id: int = -1

@export_group("选图占位（仅用首坐标）", "marker_switch_visual_")
## Preset `marker_wall_switch_face_down_*` → `UP_FROM_SOUTH`（自下往上打、可播 Idle）。
@export var marker_switch_visual_attack_from_south_row_tiles: Array[Vector2i] = []
## Preset `marker_wall_switch_face_up_*` → `DOWN_FROM_NORTH`（自上往下打，静态）。
@export var marker_switch_visual_attack_from_north_row_tiles: Array[Vector2i] = []
@export var marker_switch_visual_floor_west_tiles: Array[Vector2i] = []
@export var marker_switch_visual_floor_east_tiles: Array[Vector2i] = []

@export_group("Default Textures", "texture_")
## 低于 atlas 裁图；`UP_FROM_SOUTH` 在不用 Legacy 精灵表时作静态回退（一般留空由 Legacy 负责）。
@export var texture_fallback_attack_from_south_row: Texture2D
## 低于 atlas 裁图；`DOWN_FROM_NORTH` 静态外观。
@export var texture_fallback_attack_from_north_row: Texture2D
## 东西向可走锚点侧（西向东打）。
@export var texture_floor_west_appr_to_east: Texture2D
## 东西向可走锚点侧（东向西打）。
@export var texture_floor_east_appr_to_west: Texture2D

@export_group("Toggle SFX")
@export_range(0.0, 2.0, 0.01) var toggle_sfx_delay_seconds: float = 0.3

@export_group("互动光源（双层同心，像素感边缘）", "interaction_glow_")
@export var interaction_glow_inner_color: Color = Color(0.22, 0.9, 1.0, 0.52)
@export var interaction_glow_outer_color: Color = Color(0.05, 0.42, 0.62, 0.0)
@export_range(4.0, 48.0, 1.0) var interaction_glow_quant_steps: float = 18.0
@export_range(0.0, 0.55, 0.01) var interaction_glow_inner_radius: float = 0.14
@export_range(0.0, 0.8, 0.01) var interaction_glow_mid_radius: float = 0.34
@export_range(0.0, 1.0, 0.01) var interaction_glow_outer_radius: float = 0.5
@export_range(0.0, 2.0, 0.05) var interaction_glow_inner_alpha_mul: float = 1.05
@export_range(0.0, 2.0, 0.05) var interaction_glow_outer_alpha_mul: float = 0.88
@export_range(0.0, 40.0, 0.5) var interaction_glow_flicker_speed: float = 11.0
@export_range(0.0, 1.0, 0.02) var interaction_glow_flicker_amount: float = 0.24
@export_range(0.5, 3.5, 0.05) var interaction_glow_rect_scale: float = 1.75

var grid_pos: Vector2i = Vector2i.ZERO
var tile_size: int = 16
var facing: int = Facing.UP_FROM_SOUTH

var _dungeon_generator: DungeonGenerator = null
var _visual_atlas_coords: Vector2i = Vector2i(-1, -1)
## 最近一次成功互动后是否显示外圈高亮（再次互动关闭）。
var _interaction_glow_on: bool = false
var _glow_rect: ColorRect = null
var _glow_shader_mat: ShaderMaterial = null
var _audio_manager_missing_warned: bool = false


func _ready() -> void:
	add_to_group("wall_switch")
	z_as_relative = false
	z_index = -18
	set_process(false)


func bind_grid_position(pos: Vector2i, ts: int, dungeon_or_null: Variant = null) -> void:
	grid_pos = pos
	tile_size = ts
	if dungeon_or_null is DungeonGenerator:
		_dungeon_generator = dungeon_or_null
	_refresh_world_position()
	var sp := get_node_or_null("Sprite2D") as Sprite2D
	if sp != null:
		_sync_sprite_scale_to_grid(sp)
	_refresh_interaction_glow_geometry()


func bind_dungeon(generator: DungeonGenerator) -> void:
	_dungeon_generator = generator


func apply_facing_visual(
		face: int,
		texture_override: Texture2D,
		atlas_coords: Vector2i = Vector2i(-1, -1),
) -> void:
	facing = face
	var sp := get_node_or_null("Sprite2D") as Sprite2D
	if sp == null:
		_refresh_world_position()
		return
	sp.flip_h = false
	if facing == Facing.UP_FROM_SOUTH:
		_visual_atlas_coords = Vector2i(-1, -1)
		_restore_legacy_idle_spritesheet(sp)
		_refresh_world_position()
		refresh_idle_animation_for_facing()
		_refresh_interaction_glow_geometry()
		return
	_visual_atlas_coords = atlas_coords
	var tex := texture_override
	if tex == null:
		tex = _default_texture_for_facing(face)
	if tex != null:
		_apply_static_switch_texture(sp, tex)
		_apply_tile_visual_offset(sp)
		_stop_switch_animation()
		_sync_sprite_scale_to_grid(sp)
	else:
		sp.offset = Vector2.ZERO
		_stop_switch_animation()
		_sync_sprite_scale_to_grid(sp)
	_refresh_world_position()
	_stop_switch_animation()
	_refresh_interaction_glow_geometry()


func _apply_static_switch_texture(sp: Sprite2D, tex: Texture2D) -> void:
	sp.texture = tex
	sp.hframes = 1
	sp.vframes = 1
	sp.frame = 0


func _restore_legacy_idle_spritesheet(sp: Sprite2D) -> void:
	sp.texture = LEGACY_IDLE_SHEET
	sp.hframes = LEGACY_IDLE_HFRAMES
	sp.vframes = LEGACY_IDLE_VFRAMES
	sp.frame = LEGACY_IDLE_START_FRAME
	sp.offset = Vector2.ZERO
	sp.scale = Vector2.ONE


func _stop_switch_animation() -> void:
	var ap := _resolve_animation_player()
	if ap == null:
		return
	if ap.is_playing():
		ap.stop(true)
	ap.active = false


func _coords_from_pick_array(arr: Array[Vector2i]) -> Variant:
	if arr.is_empty():
		return null
	return arr[0]


func _dungeon_atlas_fragment(coords: Vector2i) -> Texture2D:
	var dg := _resolve_dungeon()
	if dg == null:
		return null
	var tls: TileMapLayer = dg.tile_map_layer
	if tls == null or tls.tile_set == null:
		return null
	var source_id: int = dg.get_effective_wall_switch_atlas_source_id()
	var ts := tls.tile_set
	var src_variant: Variant = ts.get_source(source_id)
	if src_variant == null:
		push_warning(
			"GridWallSwitch: TileSet source_id=%d 不存在，无法用选图 atlas 裁剪贴图。"
			% source_id
		)
		return null
	if not src_variant is TileSetAtlasSource:
		return null
	var atlas_src := src_variant as TileSetAtlasSource
	if not atlas_src.has_tile(coords):
		push_warning(
			"GridWallSwitch: atlas 中无坐标 (%d,%d)，请检查 marker_switch_visual_* 与 tile_source_id。"
			% [coords.x, coords.y]
		)
		return null
	var at := AtlasTexture.new()
	at.atlas = atlas_src.texture
	at.region = atlas_src.get_tile_texture_region(coords, 0)
	at.filter_clip = true
	return at


func _texture_from_pick_for_facing(face: int) -> Texture2D:
	var cv: Variant
	match face:
		Facing.UP_FROM_SOUTH:
			cv = _coords_from_pick_array(marker_switch_visual_attack_from_south_row_tiles)
		Facing.DOWN_FROM_NORTH:
			cv = _coords_from_pick_array(marker_switch_visual_attack_from_north_row_tiles)
		Facing.APPROACH_WEST_HIT_EAST:
			cv = _coords_from_pick_array(marker_switch_visual_floor_west_tiles)
		Facing.APPROACH_EAST_HIT_WEST:
			cv = _coords_from_pick_array(marker_switch_visual_floor_east_tiles)
		_:
			return null
	if cv == null or not (cv is Vector2i):
		return null
	return _dungeon_atlas_fragment(cv as Vector2i)


func _default_texture_for_facing(face: int) -> Texture2D:
	var tk := _texture_from_pick_for_facing(face)
	if tk != null:
		return tk
	match face:
		Facing.UP_FROM_SOUTH:
			return texture_fallback_attack_from_south_row
		Facing.DOWN_FROM_NORTH:
			return texture_fallback_attack_from_north_row
		Facing.APPROACH_WEST_HIT_EAST:
			return texture_floor_west_appr_to_east
		Facing.APPROACH_EAST_HIT_WEST:
			return texture_floor_east_appr_to_west
	return null


func _refresh_world_position() -> void:
	var half := Vector2.ONE * (float(tile_size) * 0.5)
	var dg := _resolve_dungeon()
	var sw_parent := get_parent() as Node2D
	if dg != null and dg.tile_map_layer != null and is_instance_valid(dg.tile_map_layer) and sw_parent != null:
		var layer := dg.tile_map_layer
		# Godot 4：map_to_local 已是格心，再加 half 会整体偏右下。
		var center_in_layer := layer.map_to_local(Vector2i(grid_pos))
		var world_pt := layer.to_global(center_in_layer)
		position = sw_parent.to_local(world_pt)
	else:
		position = Vector2(grid_pos) * float(tile_size) + half


func _apply_tile_visual_offset(sp: Sprite2D) -> void:
	sp.offset = _tile_texture_origin_for_visual()


func _tile_texture_origin_for_visual() -> Vector2:
	if _visual_atlas_coords.x < 0 or _visual_atlas_coords.y < 0:
		return Vector2.ZERO
	var dg := _resolve_dungeon()
	if dg == null or dg.tile_map_layer == null or dg.tile_map_layer.tile_set == null:
		return Vector2.ZERO
	var sid := dg.get_effective_wall_switch_atlas_source_id()
	var src_var: Variant = dg.tile_map_layer.tile_set.get_source(sid)
	if src_var == null or not src_var is TileSetAtlasSource:
		return Vector2.ZERO
	var td := (src_var as TileSetAtlasSource).get_tile_data(_visual_atlas_coords, 0)
	if td == null:
		return Vector2.ZERO
	return Vector2(td.texture_origin)


## 使用裁切区域尺寸：`AtlasTexture.get_size()` 在部分环境下会反映整张贴图，导致 scale 极小。
## 精灵表（hframes/vframes）须按单帧尺寸计算，否则会按整图缩放或误判为「过大整图」而保持 scale=1。
func _texture_drawn_pixel_size(tex: Texture2D, sp: Sprite2D = null) -> Vector2:
	if tex == null:
		return Vector2.ZERO
	if tex is AtlasTexture:
		var sz: Vector2 = (tex as AtlasTexture).region.size
		if not is_zero_approx(sz.x) and not is_zero_approx(sz.y):
			return sz
	if sp != null:
		var hf := maxi(sp.hframes, 1)
		var vf := maxi(sp.vframes, 1)
		if hf > 1 or vf > 1:
			var full: Vector2 = tex.get_size()
			return Vector2(full.x / float(hf), full.y / float(vf))
	return tex.get_size()


## 当裁切图素尺寸与 `tile_size`（一格世界单位边长）不一致时按格缩放；误拖整图集时不强行缩到一格。
func _sync_sprite_scale_to_grid(sp: Sprite2D) -> void:
	if sp == null:
		return
	var tex := sp.texture
	if tex == null:
		sp.scale = Vector2.ONE
		return
	var px: Vector2 = _texture_drawn_pixel_size(tex, sp)
	if is_zero_approx(px.x) or is_zero_approx(px.y):
		sp.scale = Vector2.ONE
		return
	var sf := float(tile_size)
	var ratio_x := sf / px.x
	var ratio_y := sf / px.y
	# 已与一格同大：保持 1，避免浮点误差抖动。
	if is_equal_approx(px.x, sf) and is_equal_approx(px.y, sf):
		sp.scale = Vector2.ONE
		return
	# 可能是整张图集当 Texture2D 用了；缩到一格会不可读，保持原样并提示。
	var max_dim := maxf(px.x, px.y)
	if max_dim > sf * 6.0 and not (tex is AtlasTexture):
		sp.scale = Vector2.ONE
		push_warning(
			"GridWallSwitch: Sprite 贴图像素 (%d×%d) 远大于一格 (%d)。请改用图集裁切或 DungeonGenerator 的开关 atlas 坐标。"
			% [int(px.x), int(px.y), tile_size]
		)
		return
	sp.scale = Vector2(ratio_x, ratio_y)


func play_idle_if_any() -> void:
	refresh_idle_animation_for_facing()


func _uses_legacy_idle_spritesheet(sp: Sprite2D) -> bool:
	if sp == null or sp.texture == null:
		return false
	if sp.texture is AtlasTexture:
		return false
	return sp.hframes > 1 or sp.vframes > 1


## 仅 `UP_FROM_SOUTH`（自下往上）且使用 Legacy 精灵表时播放 Idle。
func refresh_idle_animation_for_facing() -> void:
	var ap := _resolve_animation_player()
	if ap == null:
		return
	var sp := get_node_or_null("Sprite2D") as Sprite2D
	if facing != Facing.UP_FROM_SOUTH or not _uses_legacy_idle_spritesheet(sp):
		_stop_switch_animation()
		return
	if ap.has_animation(IDLE_ANIM):
		ap.active = true
		ap.play(IDLE_ANIM)
		call_deferred("_deferred_sync_wall_switch_sprite_scale")


func _deferred_sync_wall_switch_sprite_scale() -> void:
	var sp := get_node_or_null("Sprite2D") as Sprite2D
	if sp != null:
		_sync_sprite_scale_to_grid(sp)


func _resolve_animation_player() -> AnimationPlayer:
	if animation_player_path != NodePath("") and String(animation_player_path) != "":
		var by_path := get_node_or_null(animation_player_path)
		if by_path is AnimationPlayer:
			return by_path as AnimationPlayer
	var sp := get_node_or_null("Sprite2D")
	if sp != null:
		var nested := sp.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if nested != null:
			return nested
	return get_node_or_null("AnimationPlayer") as AnimationPlayer


func can_receive_melee() -> bool:
	return true


func get_attack_feedback_duration() -> float:
	return 0.06


## 用于占用格、近战目标格：上下开关即 `grid_pos`；东西开关为**依附的那面墙所在格**，锚点地板可走。
func get_occupancy_grid_pos() -> Vector2i:
	match facing:
		Facing.APPROACH_WEST_HIT_EAST:
			return grid_pos + Vector2i(1, 0)
		Facing.APPROACH_EAST_HIT_WEST:
			return grid_pos + Vector2i(-1, 0)
	return grid_pos


func get_toggle_anchor_grid_pos() -> Vector2i:
	return get_occupancy_grid_pos()


func _required_attack_source_cell() -> Vector2i:
	match facing:
		Facing.UP_FROM_SOUTH:
			return grid_pos + Vector2i(0, 1)
		Facing.DOWN_FROM_NORTH:
			return grid_pos + Vector2i(0, -1)
		Facing.APPROACH_WEST_HIT_EAST, Facing.APPROACH_EAST_HIT_WEST:
			return grid_pos
	return grid_pos


func accepts_directional_hit_from(attacker_grid: Vector2i) -> bool:
	var req: Vector2i = _required_attack_source_cell()
	match facing:
		Facing.UP_FROM_SOUTH:
			return attacker_grid.y == req.y \
					and attacker_grid.x >= req.x - 1 and attacker_grid.x <= req.x + 1
		Facing.DOWN_FROM_NORTH:
			return attacker_grid.y == req.y \
					and attacker_grid.x >= req.x - 1 and attacker_grid.x <= req.x + 1
		Facing.APPROACH_WEST_HIT_EAST, Facing.APPROACH_EAST_HIT_WEST:
			return attacker_grid.x == req.x \
					and attacker_grid.y >= req.y - 1 and attacker_grid.y <= req.y + 1
		_:
			return attacker_grid == req


func trigger_from_environment_damage(_amount: int = 1) -> void:
	_trigger_toggle(false)


func apply_damage(amount: int, source_grid: Vector2i = Vector2i.ZERO) -> bool:
	if not accepts_directional_hit_from(source_grid):
		return false
	_trigger_toggle()
	_try_play_toggle_sfx()
	return false


func apply_damage_from_ranged(amount: int, source_grid: Vector2i = Vector2i.ZERO) -> bool:
	if not accepts_directional_hit_from(source_grid):
		return false
	_trigger_toggle()
	_try_play_toggle_sfx()
	return false


func _try_play_toggle_sfx() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var wait := maxf(0.0, toggle_sfx_delay_seconds)
	if wait <= 0.001:
		_play_toggle_sfx_immediate()
		return
	var t := tree.create_timer(wait, false, true, false)
	t.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_play_toggle_sfx_immediate()
	, CONNECT_ONE_SHOT)


func _play_toggle_sfx_immediate() -> void:
	var am := _resolve_audio_manager_for_sfx()
	if am != null:
		am.call("play_sfx", "Switch")
		return
	if not _audio_manager_missing_warned:
		_audio_manager_missing_warned = true
		push_warning("GridWallSwitch: 未找到带 play_sfx 的 AudioManager（Autoload 或根节点子项）。")


func _resolve_audio_manager_for_sfx() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	var by_group: Node = tree.get_first_node_in_group("audio_manager_play_sfx")
	if by_group != null and by_group.has_method("play_sfx"):
		return by_group
	for nm in ["AudioManager", "audiomanager", "SfxManager"]:
		var n := tree.root.get_node_or_null(NodePath(nm))
		if n != null and n.has_method("play_sfx"):
			return n
	for ch in tree.root.get_children():
		if ch != null and ch.has_method("play_sfx"):
			return ch
	return null


func _ensure_interaction_glow_rect() -> ColorRect:
	if _glow_rect != null and is_instance_valid(_glow_rect):
		return _glow_rect
	var cr := ColorRect.new()
	cr.name = "InteractionGlow"
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.z_as_relative = true
	cr.z_index = 14
	cr.visible = false
	var sm := ShaderMaterial.new()
	sm.shader = INTERACTION_GLOW_SHADER
	cr.material = sm
	_glow_shader_mat = sm
	add_child(cr)
	_glow_rect = cr
	return cr


func _apply_interaction_glow_shader_params() -> void:
	var sm := _glow_shader_mat
	if sm == null:
		return
	sm.set_shader_parameter("inner_color", interaction_glow_inner_color)
	sm.set_shader_parameter("outer_color", interaction_glow_outer_color)
	sm.set_shader_parameter("quant_steps", interaction_glow_quant_steps)
	sm.set_shader_parameter("inner_radius", interaction_glow_inner_radius)
	sm.set_shader_parameter("mid_radius", interaction_glow_mid_radius)
	sm.set_shader_parameter("outer_radius", interaction_glow_outer_radius)
	sm.set_shader_parameter("inner_alpha_mul", interaction_glow_inner_alpha_mul)
	sm.set_shader_parameter("outer_alpha_mul", interaction_glow_outer_alpha_mul)
	sm.set_shader_parameter("flicker_speed", interaction_glow_flicker_speed)
	sm.set_shader_parameter("flicker_amount", interaction_glow_flicker_amount)


func _refresh_interaction_glow_geometry() -> void:
	var cr := _ensure_interaction_glow_rect()
	var d := maxf(8.0, float(tile_size) * interaction_glow_rect_scale)
	cr.size = Vector2(d, d)
	cr.position = Vector2(-d * 0.5, -d * 0.5)
	_apply_interaction_glow_shader_params()


func _update_interaction_glow_visual() -> void:
	var cr := _ensure_interaction_glow_rect()
	cr.visible = _interaction_glow_on
	set_process(_interaction_glow_on)
	if _interaction_glow_on:
		_refresh_interaction_glow_geometry()


func _process(_dt: float) -> void:
	if _interaction_glow_on and _glow_shader_mat != null:
		_apply_interaction_glow_shader_params()


func _trigger_toggle(with_interaction_glow: bool = true) -> void:
	var dg := _resolve_dungeon()
	if dg == null:
		return
	dg.toggle_doors_adjacent_to_wall_switch(get_toggle_anchor_grid_pos())
	if with_interaction_glow:
		_interaction_glow_on = not _interaction_glow_on
		_update_interaction_glow_visual()


func _resolve_dungeon() -> DungeonGenerator:
	if _dungeon_generator != null and is_instance_valid(_dungeon_generator):
		return _dungeon_generator
	if dungeon_generator_path != NodePath("") and String(dungeon_generator_path) != "":
		var n := get_node_or_null(dungeon_generator_path)
		if n is DungeonGenerator:
			_dungeon_generator = n
			return _dungeon_generator
	var by_group := get_tree().get_first_node_in_group("dungeon_generator")
	if by_group is DungeonGenerator:
		_dungeon_generator = by_group
		return _dungeon_generator
	return null
