class_name BreakablePillar
extends Sprite2D

const GRID_EXPLOSION_SCRIPT: GDScript = preload("res://grid_explosion.gd")

signal pillar_broken(grid_pos: Vector2i)

@export_group("References")
@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
@export var turn_controller_path: NodePath = NodePath("../TurnController")

@export_group("Combat")
@export var max_hp: int = 1
@export var break_flash_duration: float = 0.08
@export var explosive_damage: int = 2
@export var explosion_radius_tiles: int = 1
## 被邻格燃烧液体连锁点燃时，每回合受到的火焰伤害（等同远程引爆的单次攻击力的一部分，默认 1 即引爆）。
@export var fire_tick_damage: int = 1
## （远程爆炸击破）散落在柱周邻格的随机样本数。
@export var liquid_neighbor_count: int = 4
@export var burning_turns_on_ignite: int = 8
## 近战击破液罐：泼溅前沿相对「击打射线」的最大格子距离（欧氏）。
@export_range(0.5, 24.0, 0.25) var melee_splash_max_distance_tiles: float = 4.5
## 近战击破液罐：泼溅格子总数上限（含罐格本身）。
@export_range(1, 80, 1) var melee_splash_max_puddle_cells: int = 14
## 近战击破液罐：楔形半角（度）。
@export_range(5.0, 75.0, 1.0) var melee_splash_half_angle_degrees: float = 30.0

@export_group("Debug")
## 在场景中以红圈显示 `explosion_radius_tiles`（世界单位：柱格中心 ± 半径格）。仅调试。
@export var debug_draw_explosion_radius: bool = false

@export_group("Visual")
@export var top_atlas_coords: Vector2i = Vector2i(0, 8)
@export var bottom_atlas_coords: Vector2i = Vector2i(0, 9)

var grid_pos: Vector2i = Vector2i.ZERO
var tile_size: int = 16
var dungeon_generator: DungeonGenerator = null
var turn_controller: TurnController = null
var _hp: int = 1
var _dead: bool = false
var _top_sprite: Sprite2D = null
var _ui_pixel_texture: Texture2D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _burning_turns_left: int = 0
## 通用 `ignite()` 时跳过首次火焰结算（对齐液体）；`ignite_from_liquid_spread` **不**挂起，便于同相位先点后爆。
var _pending_chain_fire_tick: bool = false


func _ready() -> void:
	add_to_group("breakable")
	add_to_group("ignitable_breakable")
	_rng.randomize()
	_resolve_references()
	_apply_atlas_from_dungeon()
	_hp = maxi(1, max_hp)
	_setup_sprites()
	_snap_to_grid_center()


func _process(_delta: float) -> void:
	if debug_draw_explosion_radius:
		queue_redraw()


func _draw() -> void:
	if not debug_draw_explosion_radius:
		return
	var rpx: float = (float(tile_size) * float(explosion_radius_tiles)) + float(tile_size) * 0.5
	draw_arc(Vector2.ZERO, rpx, 0.0, TAU, 48, Color(1.0, 0.35, 0.15, 0.85), 2.0, true)
	var label := "R=%d" % explosion_radius_tiles
	draw_string(ThemeDB.fallback_font, Vector2(-18, -rpx - 6.0), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(1.0, 0.85, 0.4))


func bind_grid_position(pos: Vector2i) -> void:
	grid_pos = pos
	_snap_to_grid_center()


func can_receive_melee() -> bool:
	return not _dead


func get_attack_feedback_duration() -> float:
	return break_flash_duration


func apply_damage(amount: int, melee_attacker_grid: Variant = null) -> bool:
	return _apply_damage_internal(amount, false, melee_attacker_grid)


func apply_damage_from_ranged(amount: int, _hit_context_grid: Vector2i = Vector2i.ZERO) -> bool:
	return _apply_damage_internal(amount, true, null)


func _apply_damage_internal(amount: int, from_ranged: bool, melee_attacker_grid: Variant) -> bool:
	if _dead:
		return true
	_hp -= maxi(0, amount)
	_play_hit_flash()
	if _hp > 0:
		return false
	_dead = true
	if from_ranged:
		_explode_by_shot()
	else:
		_break_into_flammable_directional_cone(melee_attacker_grid)
	if dungeon_generator != null:
		dungeon_generator.break_pillar_obstacle(grid_pos)
	pillar_broken.emit(grid_pos)
	queue_free()
	return true


func is_dead() -> bool:
	return _dead


func is_burning() -> bool:
	return _burning_turns_left > 0


## 任意来源点燃；**新**点燃时首帧不结算 `apply_fire_chain_tick`，与 `FlammableLiquid.should_resolve` 对齐。
func ignite(turns: int = 8, refresh_existing: bool = true) -> void:
	if _dead:
		return
	var was_burning := is_burning()
	var dur: int = turns if turns > 0 else burning_turns_on_ignite
	if refresh_existing:
		_burning_turns_left = dur
	else:
		_burning_turns_left = maxi(_burning_turns_left, dur)
	if not was_burning and is_burning():
		_pending_chain_fire_tick = true
		FireAttachmentVisual.spawn_ignite_burst(global_position, tile_size, 5.0)


## 仅自燃烧液体「蔓延」邻格点燃：同一 `_process_liquid_turn_effects` 内紧接着的 `apply_fire_chain_tick` 即结算。
func ignite_from_liquid_spread(turns: int = 8, refresh_existing: bool = true) -> void:
	if _dead:
		return
	var was_burning := is_burning()
	var dur: int = turns if turns > 0 else burning_turns_on_ignite
	if refresh_existing:
		_burning_turns_left = dur
	else:
		_burning_turns_left = maxi(_burning_turns_left, dur)
	_pending_chain_fire_tick = false
	if not was_burning and is_burning():
		FireAttachmentVisual.spawn_ignite_burst(global_position, tile_size, 5.0)


func apply_fire_chain_tick() -> void:
	if _dead or not is_burning():
		return
	if _pending_chain_fire_tick:
		_pending_chain_fire_tick = false
		return
	_apply_damage_internal(maxi(1, fire_tick_damage), true, null)
	if not _dead:
		_burning_turns_left = maxi(0, _burning_turns_left - 1)


func _play_hit_flash() -> void:
	modulate = Color(1.0, 0.75, 0.75, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, break_flash_duration)


func _explode_by_shot() -> void:
	_play_pixel_blast(Color(1.0, 0.65, 0.25, 0.95))
	if turn_controller != null:
		turn_controller.apply_explosion_damage(grid_pos, explosive_damage, true)
		turn_controller.spawn_flammable_liquid_cluster(grid_pos, liquid_neighbor_count)
		var center_liquid: Node = turn_controller.get_liquid_at(grid_pos)
		if center_liquid != null and center_liquid.has_method("ignite"):
			center_liquid.call("ignite", burning_turns_on_ignite, false)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var gp := grid_pos + Vector2i(dx, dy)
				var liq: Node = turn_controller.get_liquid_at(gp)
				if liq != null and liq.has_method("ignite"):
					liq.call("ignite", burning_turns_on_ignite, false)


func _break_into_flammable_directional_cone(attacker_origin: Variant = null) -> void:
	_play_sfx_if_available("GlassBreak")
	if turn_controller == null:
		return
	if turn_controller.has_method("spawn_melee_break_pillar_flammable_spray"):
		turn_controller.call(
			"spawn_melee_break_pillar_flammable_spray",
			grid_pos,
			attacker_origin,
			melee_splash_max_distance_tiles,
			melee_splash_max_puddle_cells,
			melee_splash_half_angle_degrees,
		)


func _play_pixel_blast(color: Color) -> void:
	var parent_node := get_parent()
	if parent_node == null:
		parent_node = self
	if GRID_EXPLOSION_SCRIPT == null:
		return
	var explosion: Node2D = GRID_EXPLOSION_SCRIPT.new() as Node2D
	if explosion == null:
		return
	parent_node.add_child(explosion)
	var target_radius := (float(tile_size) * float(explosion_radius_tiles) + 6.0) * 1.35
	if explosion.has_method("play"):
		explosion.call("play", global_position, color, target_radius, 0.165, float(tile_size), explosion_radius_tiles)
	_play_random_explosion_sfx()
	_request_explosion_shake()


func _play_random_explosion_sfx() -> void:
	var sfx_name := "Explosion1" if _rng.randi_range(0, 1) == 0 else "Explosion2"
	_play_sfx_if_available(sfx_name)


func _request_explosion_shake() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.has_method("request_shake"):
		camera.call("request_shake", 9.5, 0.16)


func _play_sfx_if_available(sfx_name: String) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	for autoload_name in ["AudioManager", "audiomanager", "SfxManager"]:
		var node := tree.root.get_node_or_null(NodePath(autoload_name))
		if node != null and node.has_method("play_sfx"):
			node.call("play_sfx", sfx_name)
			return


func _resolve_references() -> void:
	if dungeon_generator == null and not dungeon_generator_path.is_empty():
		var node := get_node_or_null(dungeon_generator_path)
		if node is DungeonGenerator:
			dungeon_generator = node
	if dungeon_generator == null:
		var found := get_tree().get_first_node_in_group("dungeon_generator")
		if found is DungeonGenerator:
			dungeon_generator = found

	if turn_controller == null and not turn_controller_path.is_empty():
		var node := get_node_or_null(turn_controller_path)
		if node is TurnController:
			turn_controller = node
	if turn_controller == null:
		var found := get_tree().get_first_node_in_group("turn_controller")
		if found is TurnController:
			turn_controller = found

	if dungeon_generator != null:
		tile_size = dungeon_generator.tile_size


func _apply_atlas_from_dungeon() -> void:
	if dungeon_generator == null:
		return
	if not dungeon_generator.pillar_top_tiles.is_empty():
		top_atlas_coords = dungeon_generator.pillar_top_tiles[0]
	if not dungeon_generator.pillar_bottom_tiles.is_empty():
		bottom_atlas_coords = dungeon_generator.pillar_bottom_tiles[0]
	if texture != null:
		return
	var layer: TileMapLayer = dungeon_generator.tile_map_layer_pillar
	if layer == null:
		layer = dungeon_generator.tile_map_layer
	if layer == null or layer.tile_set == null:
		return
	var source_id := dungeon_generator.tile_source_id
	if dungeon_generator.pillar_tile_source_id >= 0:
		source_id = dungeon_generator.pillar_tile_source_id
	var source := layer.tile_set.get_source(source_id)
	if not source is TileSetAtlasSource:
		return
	var atlas := source as TileSetAtlasSource
	texture = atlas.texture
	var cell := atlas.texture_region_size
	hframes = int(atlas.texture.get_width()) / cell.x
	vframes = int(atlas.texture.get_height()) / cell.y


func _setup_sprites() -> void:
	centered = true
	if texture != null and hframes > 0 and vframes > 0:
		frame_coords = bottom_atlas_coords
	elif texture != null:
		_apply_region(self, bottom_atlas_coords)
	else:
		_apply_fallback(self, Color(0.45, 0.35, 0.25, 1.0))

	_top_sprite = get_node_or_null("Top")
	if _top_sprite == null:
		_top_sprite = Sprite2D.new()
		_top_sprite.name = "Top"
		add_child(_top_sprite)

	_top_sprite.centered = true
	_top_sprite.position = Vector2(0.0, -float(tile_size))
	_top_sprite.z_index = 1

	if texture != null and hframes > 0 and vframes > 0:
		_top_sprite.texture = texture
		_top_sprite.hframes = hframes
		_top_sprite.vframes = vframes
		_top_sprite.frame_coords = top_atlas_coords
	elif texture != null:
		_apply_region(_top_sprite, top_atlas_coords)
	else:
		_apply_fallback(_top_sprite, Color(0.55, 0.45, 0.30, 1.0))


func _apply_region(sprite: Sprite2D, coords: Vector2i) -> void:
	sprite.texture = texture
	sprite.region_enabled = true
	var cell_w := int(texture.get_width()) / maxi(hframes, 1)
	var cell_h := int(texture.get_height()) / maxi(vframes, 1)
	sprite.region_rect = Rect2(
		Vector2(coords.x * cell_w, coords.y * cell_h),
		Vector2(cell_w, cell_h)
	)


func _apply_fallback(sprite: Sprite2D, color: Color) -> void:
	var img := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.region_enabled = false


func _snap_to_grid_center() -> void:
	position = Vector2(grid_pos) * float(tile_size) + Vector2.ONE * (tile_size * 0.5)
