class_name DungeonGenerator
extends Node
## 像素地牢风格的随机楼层生成；可选将 grid_map 绘制到 TileMapLayer。

enum TileType { WALL, FLOOR, ABYSS, TRANSPARENT_WALL, RICOCHET_WALL }

const DEFAULT_ABYSS_BACKGROUND_SCENE: PackedScene = preload("res://AbyssBackground.tscn")
const DEFAULT_ABYSS_PARTICLE_SCENE: PackedScene = preload("res://AbyssParticles.tscn")
const DEFAULT_WALL_SWITCH_ENTITY_SCENE: PackedScene = preload("res://WallSwitchEntity.tscn")
const _WALL_SWITCH_NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

@export_group("Map")
@export_range(4, 128, 1) var tile_size: int = 16
@export var map_width: int = 50
@export var map_height: int = 50

@export_group("Rooms")
@export var min_room_size: int = 4
@export var max_room_size: int = 8
@export var room_count: int = 6
@export var room_padding: int = 1
@export var max_placement_attempts: int = 300

@export_group("Corridors")
@export var connect_all_pairs: bool = true
@export var use_astar_corridors: bool = false
@export var max_connection_attempts: int = 30

@export_group("Rendering")
## 指定后可在 Inspector 用「从图集选取」预览 TileSet 并点选填入下方数组（需启用插件 Dungeon Tile Picker）。
## 底层图块（先绘制）。
@export var tile_map_layer: TileMapLayer
## 上层图块（后绘制，用于双面墙 / T 墙 / 角落+直墙 叠层组合）。
@export var tile_map_layer_overlay: TileMapLayer
@export var use_layered_wall_composites: bool = true
## 叠层墙相对基础层的 z 步进；0 表示不抬高 z，仅靠层顺序叠加，避免压住玩家。
@export var wall_overlay_z_step: int = 0
@export var tile_source_id: int = 0
## 地板图块（多项时随机）。
@export var floor_tiles: Array[Vector2i] = [Vector2i(0, 0)]
## 深渊格图块（`TileType.ABYSS`；邻墙 bitmask 不按深渊当「地板」，故不会牵引墙贴图）。
@export var abyss_tiles: Array[Vector2i] = []
## 当本格为深渊且**正上方**一格也是深渊时使用的图块（多项随机），替代此时对 `abyss_tiles` 的采样。留空则不启用该规则（与仅配 `abyss_tiles` 一致；选图方式与同组 `abyss_tiles` 相同）。
@export var abyss_tiles_when_north_is_abyss: Array[Vector2i] = []

@export_subgroup("Wall tiles")
## 四面都没有相邻地板，且四角对角也不可通行的实心墙。
@export var solid_wall_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 四面皆不可通行，但东北对角可贴地板（斜向角落可通行）。
@export var solid_diagonal_ne_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 四面皆不可通行，但西北对角可贴地板。
@export var solid_diagonal_nw_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 四面皆不可通行，但东南对角可贴地板。
@export var solid_diagonal_se_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 四面皆不可通行，但西南对角可贴地板。
@export var solid_diagonal_sw_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 横向走廊墙（地板在东/西）。西侧邻地板时自动水平翻转。
@export var corridor_horizontal_wall_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 纵向走廊墙（地板在南/北，用于横向走廊的上下侧）。上下统一朝向，不翻转。
@export var corridor_vertical_wall_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 左上角（相邻地板在南 + 东）。
@export var corner_top_left_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 右上角（相邻地板在南 + 西）。
@export var corner_top_right_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 左下角（相邻地板在北 + 东）。
@export var corner_bottom_left_tiles: Array[Vector2i] = [Vector2i(13, 9)]
## 右下角（相邻地板在北 + 西）。
@export var corner_bottom_right_tiles: Array[Vector2i] = [Vector2i(13, 9)]

@export_group("Special Walls")
## 透明墙（玻璃）叠层：半透明显示；逻辑格不挡视野。勿绑定主 `tile_map_layer`。
@export var tile_map_layer_transparent_wall: TileMapLayer
@export var transparent_wall_layer_z_offset: int = 2
@export_range(0.05, 1.0, 0.01) var transparent_wall_alpha: float = 0.45
## 反弹墙本体叠层（墙贴图 + HSV；勿绑定主 `tile_map_layer`）。
@export var tile_map_layer_ricochet_wall: TileMapLayer
@export var ricochet_wall_layer_z_offset: int = 2
## 反弹墙叠层第二层（双面墙 / T 形墙上层；与 `tile_map_layer_overlay` 对应）。勿绑定主层。
@export var tile_map_layer_ricochet_overlay: TileMapLayer
## 相对主 `tile_map_layer` 的 z 增量；默认比本体层 +1。
@export var ricochet_wall_overlay_z_offset: int = 3
## 反弹墙装饰叠层（纵向走廊 vertical + 四面内凹角；原色，不受 HSV 影响）。勿绑定主 `tile_map_layer`。
@export var tile_map_layer_ricochet_decor: TileMapLayer
@export var ricochet_decor_layer_z_offset: int = 4
@export var use_ricochet_wall_hsv_adjust: bool = true
@export_range(-180.0, 180.0, 0.1) var ricochet_wall_hue_shift_degrees: float = 42.0
@export_range(0.0, 2.0, 0.01) var ricochet_wall_saturation: float = 1.12
@export_range(0.0, 2.0, 0.01) var ricochet_wall_value: float = 1.05
## 内凹角装饰（与 `corner_*` 朝向一致，勿与 `ricochet_decor_vertical` 混用）。
## L 角：两面正交邻地板且内侧对角为地板（沿拐角三格）；T 角：三面邻地板。
@export var ricochet_decor_corner_top_left_tiles: Array[Vector2i] = []
@export var ricochet_decor_corner_top_right_tiles: Array[Vector2i] = []
@export var ricochet_decor_corner_bottom_left_tiles: Array[Vector2i] = []
@export var ricochet_decor_corner_bottom_right_tiles: Array[Vector2i] = []
## 走廊墙装饰：与本体选用 `corridor_vertical_wall_tiles`（上下朝向墙）时叠加；`corridor_horizontal_wall_tiles` 不加装饰。
@export var ricochet_decor_vertical_tiles: Array[Vector2i] = []

@export_group("Abyss Background")
## 深渊背景占位/扩展根场景（与 `AbyssParticles` 等配套引用）。
@export var abyss_background_scene: PackedScene = DEFAULT_ABYSS_BACKGROUND_SCENE
## 背景专用层（可选，不设则自动创建；z_index 比 tile_map_layer 更低）。
@export var tile_map_layer_background: TileMapLayer
@export var background_layer_z_offset: int = -10
## 背景平铺图块（留空则不绘制）。
@export var background_tiles: Array[Vector2i] = []
## 额外向地图外平铺的边距格数，避免相机轻微越界时露底。
## 在地图四周多铺的瓦片圈数。数值越大越不易露底，但格子数按 (宽+2m)×(高+2m) 增长。
@export_range(0, 128, 1) var background_margin_tiles: int = 2
## 开启后对深渊背景层做 HSV 调整。
@export var use_background_hsv_adjust: bool = true
## 色相偏移（度）。正值偏向青/蓝，负值偏向红/紫。
@export_range(-180.0, 180.0, 0.1) var background_hue_shift_degrees: float = 0.0
## 饱和度倍率（1.0 不变）。
@export_range(0.0, 2.0, 0.01) var background_saturation: float = 0.3
## 明度倍率（1.0 不变）。
@export_range(0.0, 2.0, 0.01) var background_value: float = 0.4
## 背景粒子场景（默认 `AbyssParticles.tscn`）。
@export var background_particle_scene: PackedScene = DEFAULT_ABYSS_PARTICLE_SCENE
@export var use_background_particles: bool = true
@export var background_particle_z_offset: int = -9

@export_group("Pillar (四面通道孤立墙)")
## 柱子专用层（可选，不设则自动创建；z_index 比 tile_map_layer 高 20）。
@export var tile_map_layer_pillar: TileMapLayer
@export var pillar_layer_z_offset: int = 20
## 柱子顶部图块，绘制在孤立墙格子本身。
@export var pillar_top_tiles: Array[Vector2i] = []
## 柱子底部图块，绘制在孤立墙下方一格，与顶部合成两格高的视觉。
@export var pillar_bottom_tiles: Array[Vector2i] = []
## 柱子层使用的 TileSet source id；-1 表示复用 tile_source_id。
@export var pillar_tile_source_id: int = -1
## 如专用柱子层 TileSet/source/atlas 与基础层不一致，可临时开启复用基础层 TileSet 诊断。
@export var pillar_use_base_tileset: bool = false
@export var pillar_top_cell_offset: Vector2i = Vector2i(0, -1)
@export var pillar_bottom_cell_offset: Vector2i = Vector2i.ZERO
## 随机在房间内部生成的两格高柱子障碍数量；设为 0 可关闭。
@export var random_pillar_obstacle_count: int = 8
@export var random_pillar_placement_attempts: int = 200
@export var use_baked_random_pillar_obstacles: bool = false
## 四面邻地板的孤立墙（原先 pillar 图层）：改为地板并由 BreakablePillar 实体占位，便于液罐/击破逻辑。
@export var use_breakable_entities_for_four_way_wall_pillars: bool = true
@export_group("Barrel (preset)")
## 与 `BreakableBarrel` 调试/外观对齐：图集坐标；-1,-1 表示仅用桶实体默认帧。
@export var barrel_body_atlas_coords: Vector2i = Vector2i(-1, -1)
## 坠入深渊浮台外观；-1,-1 表示沿用桶场景内 `abyss_submerged_atlas_tiles` / `atlas_coords`。
@export var barrel_abyss_submerged_atlas_coords: Vector2i = Vector2i(-1, -1)
## 桶/柱实体裁图所用的 TileSet atlas source；-1 表示与 `_pillar_source_id()` 相同。
@export var barrel_tile_source_id: int = -1
@export_group("Door")
## 门专用叠层（可选，不设则自动创建；z_index 比 tile_map_layer 高 15）。
@export var tile_map_layer_door: TileMapLayer
@export var door_layer_z_offset: int = 5
## 门关闭时的图块。
@export var door_closed_tiles: Array[Vector2i] = []
## 门打开时的图块（玩家踏上后切换）。
@export var door_open_tiles: Array[Vector2i] = []
## 未激活门在**门图层**上使用的 atlas（与主地板层无关）；空则与普通关门相同使用 `door_closed_tiles`。激活后为普通关门外观。
@export var inactive_door_wall_tiles: Array[Vector2i] = []
@export_group("Exit")
## 出口专用叠层（可选，不设则自动创建；z_index 比 tile_map_layer 高 30）。
@export var tile_map_layer_exit: TileMapLayer
@export var exit_layer_z_offset: int = 6
## 出口图块（叠在地板上方）。留空则仅在地板上开口，不额外绘制。
@export var exit_tiles: Array[Vector2i] = []
@export_subgroup("场景实例（可选）")
## 若赋值，门用场景实例显示并可挂 AnimationPlayer；未赋值时仍用上方门图块画在 TileMap 上。
@export var door_entity_scene: PackedScene
## 若赋值，出口用场景实例；未赋值时仍用 exit_tiles。
@export var exit_entity_scene: PackedScene
## 墙上的开关：布局里 `switch_specs`／`switch_cells`；指示层上须与**门**使用同一 TileSet source（`PresetFloorLayout.marker_door_source_id`，-1 时即主 `marker_source_id`）。未赋值 scene 则用内建 `WallSwitchEntity.tscn`。
@export var wall_switch_scene: PackedScene
## Canvas z 对齐：偏移从 `tile_map_layer.z_index` 起算。
@export var wall_switch_layer_z_offset: int = 12
## 四类朝向各自一张贴图。**可选**：仅在布局里**没有**烘焙 `switch_specs["atlas"]` 时用作回退；Preset 指示层图块会写入 atlas，一般不必在 DG 重复拖贴图。
@export var wall_switch_texture_attack_from_south_row: Texture2D
@export var wall_switch_texture_attack_from_north_row: Texture2D
@export var wall_switch_texture_floor_west_appr_to_east: Texture2D
@export var wall_switch_texture_floor_east_appr_to_west: Texture2D
## 开关「选坐标裁图」与门上占位所用的 TileSet atlas source。-1：**优先使用 Preset 烘焙的门的 source**，再退回 `tile_source_id`。**若门与地表不同 atlas，必须设对或烘焙正确。**
@export var wall_switch_atlas_source_id_override: int = -1

@export_group("Debug")
@export var generate_on_ready: bool = true

var grid_map: Array = []
var rooms: Array[Rect2i] = []
var room_centers: Array[Vector2i] = []
var exit_pos: Vector2i = Vector2i(-1, -1)
var spawn_room_index: int = 0
var doors: Array[Vector2i] = []
var _door_states: Dictionary = {}   # Vector2i → bool (true = open)
var _door_set: Dictionary = {}      # Vector2i → true，快速判断是否为门
## 仍为 FLOOR+门逻辑；`_door_states` 为 false 时雾/弹射按关门处理；可走性由脚本单独阻挡直至 `activate_inactive_door_at`。
var _inactive_door_set: Dictionary = {}
var _door_entity_by_cell: Dictionary = {}  # Vector2i → 门场景实例
var _door_exit_container: Node2D = null
var _exit_entity_node: Node = null
var _connected_room_pairs: Dictionary = {}
var _room_corridor_counts: Array[int] = []
var _room_floor_set: Dictionary = {}
var _room_cell_to_room_index: Dictionary = {}
var _corridor_floor_set: Dictionary = {}
var _random_pillar_obstacle_set: Dictionary = {}
var _rendered_pillar_cells: Dictionary = {}
var _rendered_door_cells: Dictionary = {}
var _render_layers: Array[TileMapLayer] = []
var _created_overlay_layers: Array[TileMapLayer] = []
var _ricochet_render_layers: Array[TileMapLayer] = []
var _created_ricochet_overlay_layers: Array[TileMapLayer] = []
var _transparent_render_layers: Array[TileMapLayer] = []
var _created_transparent_overlay_layers: Array[TileMapLayer] = []
var _background_particle_instance: Node = null
var _fixed_spawn_pos: Vector2i = Vector2i(-1, -1)
## 程序化生成专用的地图宽高（ Inspector 初始值）；`load_floor_layout` 会改写 `map_*`，需在下次 `generate_dungeon` 时恢复。
var _procedural_map_size_valid: bool = false
## 门/出口场景与玩家/敌人的 `z_index`（均约 -10）排序对齐；偏移不足时保底画在 Actor 前方。
const ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING := -10

@export_group("Flammable Liquid")
## 易燃液体 Canvas 深度：相对主地板 `tile_map_layer.z_index` 的偏移（默认 1 → 地板 -20 时为 -19）。
@export var flammable_liquid_layer_z_offset: int = 1
var _procedural_map_width: int = 50
var _procedural_map_height: int = 50
## 预设关卡的敌人占位格（与 `preset_floor_layout.gd` 烘焙一致）；随机生成时清空。
var _preset_enemy_cells: Array[Vector2i] = []
var _preset_pillar_cells: Array[Vector2i] = []
var _preset_liquid_cells: Array[Vector2i] = []
var _preset_barrel_cells: Array[Vector2i] = []
## 坠入深渊后仍存活的木桶浮台：格坐标 → `BreakableBarrel`（ submerged ）。
var _abyss_barrel_platforms: Dictionary = {}
## `load_floor_layout` 载入的墙上的开关占位格（程序化生成清空）。
var _registered_wall_switch_cells: Array[Vector2i] = []
## Vector2i → `GridWallSwitch.Facing`，与四类贴图语义一致。
var _wall_switch_facing_by_cell: Dictionary = {}
## 开关格 → 指示层上该格的 atlas 坐标（Preset 烘焙）；用于裁切外观，免在 DG 再配四张贴图。
var _wall_switch_baked_visual_atlas_by_cell: Dictionary = {}
var _wall_switch_entity_by_cell: Dictionary = {}
var _wall_switch_container: Node2D = null
## Preset 烘焙的「门/开关占位」atlas source；-1：本关字典未提供时由 `get_effective_wall_switch_atlas_source_id()` 回退。
var _baked_wall_switch_atlas_source_id: int = -1
## 由 `_promote_four_way_isolated_walls_for_entity_pillars` 写入；渲染前已从墙改为地板。
var _four_way_entity_pillar_cells: Array[Vector2i] = []
## `load_floor_layout` 可由布局字典写入（如 PresetFloorLayout）；程序化生成时为 false。
## Preset：**仅抑制**程序化石柱（四面通墙升格 + 关卡随机 pillar_count）；不抑制 PresetFloorLayout 里画的柱占位。
var layout_suppress_procedural_breakable_pillars: bool = false
## Preset：无预制敌格子时，若为 true 则本关不散布随机敌人。
var layout_suppress_random_enemies: bool = false
## `load_floor_layout` 中 `camera_enable_control`；程序化生成为 true。
var layout_camera_enable_control: bool = true
## `load_floor_layout` 中 `camera_maintain_zoom`；程序化生成为 false。
var layout_camera_maintain_zoom: bool = false
const ABYSS_HSV_SHADER_PATH := "res://abyss_hsv.gdshader"

signal generation_finished

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _level_flow_initial_floor_uses_scene_layout() -> bool:
	## 与 LevelFlowController 同场景时：若开局楼层走预设 PackedScene，则不可再在 `_ready` 里程序化生成，
	## 否则会与 `LevelFlowController` 延迟载入的布局竞态——后跑的 `generate_dungeon()` 会清空 `preset_pillar_cells` 并盖住预设图。
	var tree := get_tree()
	if tree == null:
		return false
	var flow_node := tree.get_first_node_in_group("level_flow_controller")
	if flow_node == null:
		return false
	if not (flow_node is LevelFlowController):
		return false
	var flow: LevelFlowController = flow_node as LevelFlowController
	var spec := flow.get_current_floor_spec()
	return spec != null and spec.uses_scene_layout()


func _ready() -> void:
	add_to_group("dungeon_generator")
	_capture_procedural_map_size_if_needed()
	if generate_on_ready:
		if _level_flow_initial_floor_uses_scene_layout():
			return
		## 延后到所有节点 `_ready` 之后再生成，便于 BreakablePillarSpawner 等先连接 `generation_finished`。
		call_deferred("generate_dungeon")


func _capture_procedural_map_size_if_needed() -> void:
	if _procedural_map_size_valid:
		return
	_procedural_map_width = maxi(4, map_width)
	_procedural_map_height = maxi(4, map_height)
	_procedural_map_size_valid = true


func generate_dungeon() -> void:
	_capture_procedural_map_size_if_needed()
	map_width = _procedural_map_width
	map_height = _procedural_map_height
	_rng.randomize()
	rooms.clear()
	room_centers.clear()
	_connected_room_pairs.clear()
	_room_corridor_counts.clear()
	_room_floor_set.clear()
	_room_cell_to_room_index.clear()
	_corridor_floor_set.clear()
	_random_pillar_obstacle_set.clear()
	_rendered_pillar_cells.clear()
	_rendered_door_cells.clear()
	_fixed_spawn_pos = Vector2i(-1, -1)
	exit_pos = Vector2i(-1, -1)
	spawn_room_index = 0
	doors.clear()
	_door_states.clear()
	_door_set.clear()
	_inactive_door_set.clear()
	_preset_enemy_cells.clear()
	_preset_pillar_cells.clear()
	_preset_liquid_cells.clear()
	_preset_barrel_cells.clear()
	_abyss_barrel_platforms.clear()
	_registered_wall_switch_cells.clear()
	_wall_switch_facing_by_cell.clear()
	_wall_switch_baked_visual_atlas_by_cell.clear()
	_baked_wall_switch_atlas_source_id = -1
	_four_way_entity_pillar_cells.clear()
	layout_suppress_procedural_breakable_pillars = false
	layout_suppress_random_enemies = false
	layout_camera_enable_control = true
	layout_camera_maintain_zoom = false
	_init_grid()
	_place_rooms()
	_connect_room_centers()
	if use_baked_random_pillar_obstacles:
		_place_random_pillar_obstacles()
	spawn_room_index = _rng.randi_range(0, maxi(rooms.size() - 1, 0))
	_find_doors()
	_place_exit()
	print_debug_map()
	_promote_four_way_isolated_walls_for_entity_pillars()
	render_tilemap()
	generation_finished.emit()


func load_from_scene(layout_scene: PackedScene) -> void:
	if layout_scene == null:
		generate_dungeon()
		return
	var layout_node := layout_scene.instantiate()
	if layout_node == null:
		generate_dungeon()
		return
	var layout_data: Dictionary = {}
	if layout_node.has_method("build_layout_data"):
		layout_data = layout_node.call("build_layout_data") as Dictionary
	layout_node.queue_free()
	if layout_data.is_empty():
		generate_dungeon()
		return
	load_floor_layout(layout_data)


func load_floor_layout(layout_data: Dictionary) -> void:
	_capture_procedural_map_size_if_needed()
	var new_width: int = maxi(4, int(layout_data.get("map_width", map_width)))
	var new_height: int = maxi(4, int(layout_data.get("map_height", map_height)))
	map_width = new_width
	map_height = new_height
	grid_map.clear()
	grid_map.resize(map_height)
	for y in range(map_height):
		var row: Array = []
		row.resize(map_width)
		row.fill(TileType.WALL)
		grid_map[y] = row

	rooms.clear()
	room_centers.clear()
	_connected_room_pairs.clear()
	_room_corridor_counts.clear()
	_room_floor_set.clear()
	_room_cell_to_room_index.clear()
	_corridor_floor_set.clear()
	_random_pillar_obstacle_set.clear()
	_rendered_pillar_cells.clear()
	_rendered_door_cells.clear()
	doors.clear()
	_door_states.clear()
	_door_set.clear()
	_inactive_door_set.clear()
	spawn_room_index = 0
	exit_pos = Vector2i(-1, -1)
	_fixed_spawn_pos = Vector2i(-1, -1)
	_preset_enemy_cells.clear()
	_preset_pillar_cells.clear()
	_preset_liquid_cells.clear()
	_preset_barrel_cells.clear()
	_abyss_barrel_platforms.clear()
	_registered_wall_switch_cells.clear()
	_wall_switch_facing_by_cell.clear()
	_wall_switch_baked_visual_atlas_by_cell.clear()
	_baked_wall_switch_atlas_source_id = -1
	_four_way_entity_pillar_cells.clear()
	layout_suppress_procedural_breakable_pillars = bool(
		layout_data.get(
			"suppress_procedural_breakable_pillars",
			layout_data.get("disable_breakable_pillars", false),
		)
	)
	layout_suppress_random_enemies = bool(layout_data.get("suppress_random_enemy_spawns", false))
	layout_camera_enable_control = bool(layout_data.get("camera_enable_control", true))
	layout_camera_maintain_zoom = bool(layout_data.get("camera_maintain_zoom", false))

	var sw_atlas_sid: Variant = layout_data.get("wall_switch_marker_atlas_source_id", null)
	if sw_atlas_sid is int and int(sw_atlas_sid) >= 0:
		_baked_wall_switch_atlas_source_id = int(sw_atlas_sid)

	var floor_cells: Variant = layout_data.get("floor_cells", [])
	if floor_cells is Array:
		for cell_variant in floor_cells:
			if not (cell_variant is Vector2i):
				continue
			var cell: Vector2i = cell_variant
			if not _is_in_bounds(cell):
				continue
			grid_map[cell.y][cell.x] = TileType.FLOOR
			_room_floor_set[cell] = true
			_room_cell_to_room_index[cell] = 0

	var abyss_cells_var_early: Variant = layout_data.get("abyss_cells", [])
	if abyss_cells_var_early is Array:
		for ac in abyss_cells_var_early:
			if not (ac is Vector2i):
				continue
			var apose: Vector2i = ac
			if _is_in_bounds(apose):
				grid_map[apose.y][apose.x] = TileType.ABYSS
				_room_floor_set.erase(apose)
				_room_cell_to_room_index.erase(apose)

	if not _room_floor_set.is_empty():
		rooms.append(Rect2i(Vector2i.ZERO, Vector2i(map_width, map_height)))
		room_centers.append(Vector2i(map_width / 2, map_height / 2))

	var spawn_pos: Variant = layout_data.get("player_spawn_pos", null)
	if spawn_pos is Vector2i and _is_in_bounds(spawn_pos) and get_tile(spawn_pos) == TileType.FLOOR:
		_fixed_spawn_pos = spawn_pos

	var loaded_exit: Variant = layout_data.get("exit_pos", null)
	if loaded_exit is Vector2i and _is_in_bounds(loaded_exit):
		exit_pos = loaded_exit

	var door_cells: Variant = layout_data.get("door_cells", [])
	var inactive_door_cells: Variant = layout_data.get("inactive_door_cells", [])
	# 门占用格（暂不写 grid）：供墙开关先雕刻时避让，再在开关之后统一铺地板，避免开关写在门之后又把门改成墙导致邻墙贴片跳变。
	var door_geometry_cells := {}
	if door_cells is Array:
		for cell_variant in door_cells:
			if cell_variant is Vector2i:
				door_geometry_cells[cell_variant] = true
	if inactive_door_cells is Array:
		for cell_variant in inactive_door_cells:
			if cell_variant is Vector2i:
				door_geometry_cells[cell_variant] = true

	var switch_specs_parsed: Array = []
	var specs_var: Variant = layout_data.get("switch_specs", [])
	if specs_var is Array:
		for spec_item in specs_var:
			if spec_item is Dictionary:
				var spec_dict: Dictionary = spec_item as Dictionary
				var p_vari: Variant = spec_dict.get("pos", null)
				var sf: int = int(spec_dict.get("facing", GridWallSwitch.Facing.UP_FROM_SOUTH))
				if p_vari is Vector2i:
					var entry: Dictionary = {"pos": p_vari as Vector2i, "facing": sf}
					var av: Variant = spec_dict.get("atlas", null)
					if av is Vector2i:
						entry["atlas"] = av as Vector2i
					switch_specs_parsed.append(entry)
	if switch_specs_parsed.is_empty():
		var switch_cells_fallback: Variant = layout_data.get("switch_cells", [])
		if switch_cells_fallback is Array:
			for cv in switch_cells_fallback:
				if cv is Vector2i:
					switch_specs_parsed.append({
						"pos": cv as Vector2i,
						"facing": GridWallSwitch.Facing.UP_FROM_SOUTH,
					})

	var _switch_layout_count: int = switch_specs_parsed.size()
	var _switch_registered_count: int = 0
	var _switch_rejected_count: int = 0
	for spec_entry in switch_specs_parsed:
		var spec_ent: Dictionary = spec_entry as Dictionary
		var sw_cell: Vector2i = spec_ent["pos"] as Vector2i
		var fac: int = int(spec_ent["facing"])
		var before_n: int = _registered_wall_switch_cells.size()
		if _attempt_register_wall_switch(sw_cell, fac, door_geometry_cells):
			if _registered_wall_switch_cells.size() > before_n:
				_switch_registered_count += 1
				var atl_v: Variant = spec_ent.get("atlas", null)
				if atl_v is Vector2i:
					_wall_switch_baked_visual_atlas_by_cell[sw_cell] = atl_v as Vector2i
		else:
			_switch_rejected_count += 1
	if _switch_layout_count > 0 and _switch_registered_count == 0:
		push_warning(
			"DungeonGenerator: 布局里开关有 %d 项（switch_specs／switch_cells），但无一登记成功（%d 项因越界／几何不符／锚点为门／重复）。"
			% [_switch_layout_count, _switch_rejected_count]
		)

	for cell_key in door_geometry_cells.keys():
		_ensure_floor_for_layout_door_cell(cell_key)

	if door_cells is Array:
		for cell_variant in door_cells:
			if not (cell_variant is Vector2i):
				continue
			var cell: Vector2i = cell_variant
			if not _is_in_bounds(cell):
				continue
			if not doors.has(cell):
				doors.append(cell)
			_door_set[cell] = true
			_door_states[cell] = false

	var open_door_cells: Variant = layout_data.get("open_door_cells", [])
	if open_door_cells is Array:
		for cell_variant in open_door_cells:
			if not (cell_variant is Vector2i):
				continue
			var cell: Vector2i = cell_variant
			if _door_set.has(cell):
				_door_states[cell] = true

	if inactive_door_cells is Array:
		for cell_variant in inactive_door_cells:
			if not (cell_variant is Vector2i):
				continue
			var i_cell: Vector2i = cell_variant
			_register_inactive_door_cell_from_layout(i_cell)

	var pe: Variant = layout_data.get("preset_enemy_cells", [])
	if pe is Array:
		for cell_variant in pe:
			if not (cell_variant is Vector2i):
				continue
			var ce: Vector2i = cell_variant
			if _is_in_bounds(ce):
				_preset_enemy_cells.append(ce)
	for ce2 in _preset_enemy_cells:
		if not _is_in_bounds(ce2):
			continue
		if get_tile(ce2) as TileType == TileType.ABYSS:
			continue
		grid_map[ce2.y][ce2.x] = TileType.FLOOR
		_room_floor_set[ce2] = true
		if not _room_cell_to_room_index.has(ce2):
			_room_cell_to_room_index[ce2] = 0

	var pp: Variant = layout_data.get("preset_pillar_cells", [])
	if pp is Array:
		for cell_variant in pp:
			if not (cell_variant is Vector2i):
				continue
			var cp: Vector2i = cell_variant
			if _is_in_bounds(cp):
				_preset_pillar_cells.append(cp)
	## 指示层柱格必须可行走，`BreakablePillarSpawner` 仅在 `FLOOR` 上 instantiation。
	## 若烘焙/手写流程未把柱格写入 `floor_cells`（常见：图块未命中 `marker_pillar_tiles`、仅用墙笔画柱），此处补成地板以免「有 preset 列表却不生成实体柱」。
	for cp2 in _preset_pillar_cells:
		if not _is_in_bounds(cp2):
			continue
		var tpre := get_tile(cp2) as TileType
		if tpre == TileType.ABYSS:
			push_warning(
				"DungeonGenerator: preset_pillar_cells 与深渊重叠 (%d,%d)，保持深渊不铺柱。"
				% [cp2.x, cp2.y]
			)
			continue
		grid_map[cp2.y][cp2.x] = TileType.FLOOR
		_room_floor_set[cp2] = true
		if not _room_cell_to_room_index.has(cp2):
			_room_cell_to_room_index[cp2] = 0

	var pq: Variant = layout_data.get("preset_liquid_cells", [])
	if pq is Array:
		for cell_variant in pq:
			if not (cell_variant is Vector2i):
				continue
			var cq: Vector2i = cell_variant
			if _is_in_bounds(cq):
				_preset_liquid_cells.append(cq)

	var pbar: Variant = layout_data.get("preset_barrel_cells", [])
	if pbar is Array:
		for cell_variant in pbar:
			if not (cell_variant is Vector2i):
				continue
			var cba: Vector2i = cell_variant
			if _is_in_bounds(cba):
				_preset_barrel_cells.append(cba)
	for cb2 in _preset_barrel_cells:
		if not _is_in_bounds(cb2):
			continue
		if get_tile(cb2) as TileType == TileType.ABYSS:
			push_warning(
				"DungeonGenerator: preset_barrel_cells 与深渊重叠 (%d,%d)，保持深渊不铺桶。"
				% [cb2.x, cb2.y]
			)
			continue
		grid_map[cb2.y][cb2.x] = TileType.FLOOR
		_room_floor_set[cb2] = true
		if not _room_cell_to_room_index.has(cb2):
			_room_cell_to_room_index[cb2] = 0

	if exit_pos == Vector2i(-1, -1):
		_place_exit()
	if _fixed_spawn_pos == Vector2i(-1, -1):
		_fixed_spawn_pos = get_random_floor_cell()

	_apply_preset_special_wall_cells(layout_data)

	_promote_four_way_isolated_walls_for_entity_pillars()
	render_tilemap()
	generation_finished.emit()


func has_preset_enemy_layout() -> bool:
	return not _preset_enemy_cells.is_empty()


func get_preset_enemy_cells() -> Array[Vector2i]:
	return _preset_enemy_cells.duplicate()


func has_preset_pillar_layout() -> bool:
	return not _preset_pillar_cells.is_empty()


func get_preset_pillar_cells() -> Array[Vector2i]:
	return _preset_pillar_cells.duplicate()


func has_preset_liquid_layout() -> bool:
	return not _preset_liquid_cells.is_empty()


func get_preset_liquid_cells() -> Array[Vector2i]:
	return _preset_liquid_cells.duplicate()


func has_preset_barrels_layout() -> bool:
	return not _preset_barrel_cells.is_empty()


func get_preset_barrel_cells() -> Array[Vector2i]:
	return _preset_barrel_cells.duplicate()


func get_barrel_atlas_source_id() -> int:
	if barrel_tile_source_id >= 0:
		return barrel_tile_source_id
	return _pillar_source_id()


func register_abyss_barrel_platform(cell: Vector2i, barrel: BreakableBarrel) -> void:
	if barrel == null or not is_instance_valid(barrel):
		return
	_abyss_barrel_platforms[cell] = barrel


func unregister_abyss_barrel_platform(cell: Vector2i) -> void:
	_abyss_barrel_platforms.erase(cell)


func has_abyss_barrel_platform(cell: Vector2i) -> bool:
	var b: Variant = _abyss_barrel_platforms.get(cell, null)
	if b is BreakableBarrel:
		var barrel := b as BreakableBarrel
		return is_instance_valid(barrel) and barrel.is_submerged_in_abyss()
	return false


func get_abyss_barrel_platform(cell: Vector2i) -> BreakableBarrel:
	var b: Variant = _abyss_barrel_platforms.get(cell, null)
	if b is BreakableBarrel and is_instance_valid(b as BreakableBarrel):
		return b as BreakableBarrel
	return null


## 反查浮台桶注册格；`grid_pos` 与注册键不一致时用于承重检测。
func find_abyss_barrel_platform_cell(barrel: BreakableBarrel) -> Vector2i:
	if barrel == null or not is_instance_valid(barrel):
		return Vector2i(-1, -1)
	for cell: Vector2i in _abyss_barrel_platforms:
		var b: Variant = _abyss_barrel_platforms[cell]
		if b is BreakableBarrel and (b as BreakableBarrel) == barrel:
			return cell
	return Vector2i(-1, -1)


func get_four_way_entity_pillar_cells() -> Array[Vector2i]:
	return _four_way_entity_pillar_cells.duplicate()


func layout_suppresses_procedural_breakable_pillars() -> bool:
	return layout_suppress_procedural_breakable_pillars


func layout_suppresses_random_enemies() -> bool:
	return layout_suppress_random_enemies


## @deprecated 请改用 `layout_suppresses_procedural_breakable_pillars()`。
func layout_disables_breakable_pillars() -> bool:
	return layout_suppress_procedural_breakable_pillars


func get_tile(pos: Vector2i) -> TileType:
	if not _is_in_bounds(pos):
		return TileType.WALL
	return grid_map[pos.y][pos.x] as TileType


static func tile_blocks_movement(tile: TileType) -> bool:
	return tile == TileType.WALL or tile == TileType.TRANSPARENT_WALL or tile == TileType.RICOCHET_WALL


static func tile_blocks_vision(tile: TileType) -> bool:
	return tile == TileType.WALL or tile == TileType.RICOCHET_WALL


static func tile_blocks_projectile_solid(tile: TileType) -> bool:
	return tile == TileType.WALL or tile == TileType.TRANSPARENT_WALL


static func tile_reflects_projectiles(tile: TileType) -> bool:
	return tile == TileType.RICOCHET_WALL


## 桶击退/撞击时视为不可破坏的实心墙（含透明墙、反弹墙）。
static func tile_is_barrel_indestructible_wall(tile: TileType) -> bool:
	return tile == TileType.WALL or tile == TileType.TRANSPARENT_WALL or tile == TileType.RICOCHET_WALL


## 裁剪开关 Sprite 占位坐标时所用的 TileSet source：优先 Inspector 覆盖，其次预设烘焙的门源，最后 `tile_source_id`。
func get_effective_wall_switch_atlas_source_id() -> int:
	if wall_switch_atlas_source_id_override >= 0:
		return wall_switch_atlas_source_id_override
	if _baked_wall_switch_atlas_source_id >= 0:
		return _baked_wall_switch_atlas_source_id
	return tile_source_id


func get_wall_switch_baked_atlas_at(cell: Vector2i) -> Vector2i:
	var v: Variant = _wall_switch_baked_visual_atlas_by_cell.get(cell, null)
	if v is Vector2i:
		return v as Vector2i
	return Vector2i(-1, -1)


## 返回出生房间（spawn_room_index）内的随机地板格。
func get_random_room_floor_cell() -> Vector2i:
	if _fixed_spawn_pos != Vector2i(-1, -1) and _is_in_bounds(_fixed_spawn_pos):
		if get_tile(_fixed_spawn_pos) == TileType.FLOOR:
			return _fixed_spawn_pos
	if rooms.is_empty():
		return get_random_floor_cell()
	var room := rooms[spawn_room_index]
	var cells: Array[Vector2i] = []
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			if grid_map[y][x] == TileType.FLOOR:
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return get_random_floor_cell()
	return cells[_rng.randi_range(0, cells.size() - 1)]


func get_map_pixel_size() -> Vector2:
	return Vector2(map_width, map_height) * float(tile_size)


func get_map_center() -> Vector2:
	return get_map_pixel_size() * 0.5


func get_random_floor_cell() -> Vector2i:
	var floor_cells: Array[Vector2i] = []
	for y in map_height:
		for x in map_width:
			if grid_map[y][x] == TileType.FLOOR:
				floor_cells.append(Vector2i(x, y))
	if floor_cells.is_empty():
		return Vector2i(1, 1)
	return floor_cells[_rng.randi_range(0, floor_cells.size() - 1)]


func print_debug_map() -> void:
	var lines: PackedStringArray = []
	lines.append("--- Dungeon %dx%d | rooms: %d ---" % [map_width, map_height, rooms.size()])
	for y in map_height:
		var line := ""
		for x in map_width:
			var gm: TileType = grid_map[y][x]
			if gm == TileType.FLOOR:
				line += "."
			elif gm == TileType.ABYSS:
				line += "~"
			else:
				line += "#"
		lines.append(line)
	print("\n".join(lines))


func render_tilemap() -> void:
	if tile_map_layer == null:
		push_warning("DungeonGenerator: 未设置 tile_map_layer，跳过 TileMap 渲染。")
		return


	_prepare_tilemap_layers()
	# tile_size 同步放在 clear 之前，避免渲染时格子尺寸不对
	var base_ts := tile_map_layer.tile_set
	if base_ts != null:
		base_ts.tile_size = Vector2i(tile_size, tile_size)
	for layer in _render_layers:
		layer.clear()
	# 手动绑定的专用出口层也需随每次生成清空
	if tile_map_layer_exit != null and is_instance_valid(tile_map_layer_exit) \
			and tile_map_layer_exit != tile_map_layer:
		tile_map_layer_exit.clear()
	_clear_door_exit_entities_full()
	_render_background()

	for y in map_height:
		for x in map_width:
			var grid_pos := Vector2i(x, y)
			var tile: TileType = grid_map[y][x] as TileType
			for placement in _resolve_tile_placements(grid_pos, tile):
				_apply_placement(grid_pos, placement)

	_render_pillars()
	_render_special_wall_overlays()
	_render_wall_switches()
	_render_doors()
	_render_exit()   # 最后绘制，确保出口覆盖在一切之上
	_sync_background_particles()


func _resolve_tile_placements(grid_pos: Vector2i, tile: TileType) -> Array:
	if tile == TileType.FLOOR:
		return [_make_placement(_pick_random_tile(floor_tiles, Vector2i(0, 0)), 0, 0)]
	if tile == TileType.TRANSPARENT_WALL:
		return []
	if tile == TileType.RICOCHET_WALL:
		return []
	if tile == TileType.ABYSS:
		var pool: Array[Vector2i] = abyss_tiles if not abyss_tiles.is_empty() else floor_tiles
		var north := grid_pos + Vector2i(0, -1)
		if not abyss_tiles_when_north_is_abyss.is_empty() and get_tile(north) == TileType.ABYSS:
			pool = abyss_tiles_when_north_is_abyss
		return [_make_placement(_pick_random_tile(pool, Vector2i(0, 0)), 0, 0)]
	# 墙 bitmask 仅以邻格是否为 FLOOR（含门格）为准，不因「夹在两个门坐标之间」换装；
	# 否则会与未激活门（墙外观门图层）耦合，关门/激活时邻墙形态跟着变。
	return _resolve_wall_placements(grid_pos)


func _resolve_wall_placements(grid_pos: Vector2i, include_diagonal_fill: bool = true) -> Array:
	var north := _is_floor_at(grid_pos + Vector2i(0, -1))
	var south := _is_floor_at(grid_pos + Vector2i(0, 1))
	var west := _is_floor_at(grid_pos + Vector2i(-1, 0))
	var east := _is_floor_at(grid_pos + Vector2i(1, 0))
	var floor_count := int(north) + int(south) + int(west) + int(east)

	var placements: Array = []
	match floor_count:
		0:
			placements = [_solid_wall_placement()]
		1:
			placements = [_corridor_placement(north, south, west, east)]
		2:
			if north and south:
				placements = _double_sided_wall_placements(true)
			elif west and east:
				placements = _double_sided_wall_placements(false)
			if placements.is_empty():
				placements = [_corner_placement(north, south, west, east)]
		3:
			placements = _t_junction_composite_placements(north, south, west, east)
		4:
			# 四面邻地板：启用实体柱时该格会在渲染前改为地板并由 BreakablePillar 占位；否则仅用 pillar 图层贴图。
			if pillar_top_tiles.is_empty() and pillar_bottom_tiles.is_empty():
				placements = [_solid_wall_placement()]
		_:
			placements = [_solid_wall_placement()]

	if include_diagonal_fill:
		match floor_count:
			0:
				return _append_diagonal_fill_placements(grid_pos, placements, [])
			1:
				# 走廊墙：对面两个对角可能需要补全；与地板同侧的对角不补
				var covered: Array[String] = []
				if north:  covered = ["ne", "nw"]
				elif south: covered = ["se", "sw"]
				elif east:  covered = ["ne", "se"]
				elif west:  covered = ["nw", "sw"]
				return _append_diagonal_fill_placements(grid_pos, placements, covered)
	return placements


func _pick_primary_wall_placement(placements: Array) -> Dictionary:
	if placements.is_empty():
		return {}
	for placement in placements:
		if placement is Dictionary and int((placement as Dictionary).get("layer", 0)) == 0:
			return placement as Dictionary
	if placements[0] is Dictionary:
		return placements[0] as Dictionary
	return {}


func _corridor_placement(north: bool, south: bool, west: bool, east: bool) -> Dictionary:
	var horizontal := _pick_random_tile(corridor_horizontal_wall_tiles, Vector2i(13, 9))
	var vertical := _pick_random_tile(corridor_vertical_wall_tiles, Vector2i(13, 9))
	var rot := _tile_rotation_flags()

	# 横向走廊：地板在东 / 西（或两侧）
	if east and not west and not north and not south:
		return _make_placement(horizontal, rot.none, 0)
	if west and not east and not north and not south:
		return _make_placement(horizontal, rot.flip_h, 0)
	if west and east:
		return _make_placement(horizontal, rot.none, 0)

	# 纵向走廊上下侧墙：与上方（地板在南）同款，下方（地板在北）不翻转
	if south and not north and not east and not west:
		return _make_placement(vertical, rot.none, 0)
	if north and not south and not east and not west:
		return _make_placement(vertical, rot.none, 0)
	if north and south:
		return _make_placement(vertical, rot.none, 0)

	return _make_placement(horizontal, rot.none, 0)


func _solid_wall_placement() -> Dictionary:
	return _make_placement(_pick_random_tile(solid_wall_tiles, Vector2i(13, 9)), 0, 0)


func _append_diagonal_fill_placements(
	grid_pos: Vector2i,
	placements: Array,
	covered_diagonals: Array[String]
) -> Array:
	var diagonal_placements: Array = _diagonal_fill_placements(grid_pos, covered_diagonals)
	if diagonal_placements.is_empty():
		return placements
	if not _can_use_layered_composites():
		return diagonal_placements if placements.is_empty() else placements

	var result: Array = placements.duplicate()
	var next_layer: int = result.size()
	for placement in diagonal_placements:
		var extra: Dictionary = (placement as Dictionary).duplicate()
		extra["layer"] = next_layer
		result.append(extra)
		next_layer += 1
	return result


func _diagonal_fill_placements(grid_pos: Vector2i, covered_diagonals: Array[String]) -> Array:
	var ne := _is_floor_at(grid_pos + Vector2i(1, -1))
	var nw := _is_floor_at(grid_pos + Vector2i(-1, -1))
	var se := _is_floor_at(grid_pos + Vector2i(1, 1))
	var sw := _is_floor_at(grid_pos + Vector2i(-1, 1))
	var diagonal_floor_count := int(ne) + int(nw) + int(se) + int(sw)

	if diagonal_floor_count == 0:
		return []

	var placements: Array = []
	if ne and not covered_diagonals.has("ne"):
		placements.append(_make_placement(_pick_random_tile(solid_diagonal_ne_tiles, Vector2i(13, 9)), 0, 0))
	if nw and not covered_diagonals.has("nw"):
		placements.append(_make_placement(_pick_random_tile(solid_diagonal_nw_tiles, Vector2i(13, 9)), 0, 0))
	if se and not covered_diagonals.has("se"):
		placements.append(_make_placement(_pick_random_tile(solid_diagonal_se_tiles, Vector2i(13, 9)), 0, 0))
	if sw and not covered_diagonals.has("sw"):
		placements.append(_make_placement(_pick_random_tile(solid_diagonal_sw_tiles, Vector2i(13, 9)), 0, 0))
	return placements


func _tile_rotation_flags() -> Dictionary:
	return {
		"none": 0,
		"flip_h": TileSetAtlasSource.TRANSFORM_FLIP_H,
		"flip_v": TileSetAtlasSource.TRANSFORM_FLIP_V,
	}


func _corner_placement(north: bool, south: bool, west: bool, east: bool) -> Dictionary:
	if south and east:
		return _make_placement(_pick_random_tile(corner_top_left_tiles, Vector2i(13, 9)), 0, 0)
	if south and west:
		return _make_placement(_pick_random_tile(corner_top_right_tiles, Vector2i(13, 9)), 0, 0)
	if north and east:
		return _make_placement(_pick_random_tile(corner_bottom_left_tiles, Vector2i(13, 9)), 0, 0)
	if north and west:
		return _make_placement(_pick_random_tile(corner_bottom_right_tiles, Vector2i(13, 9)), 0, 0)
	return _make_placement(_pick_random_tile(corner_top_left_tiles, Vector2i(13, 9)), 0, 0)


func _double_sided_wall_placements(vertical_axis: bool) -> Array:
	var single := _corridor_placement(vertical_axis, vertical_axis, not vertical_axis, not vertical_axis)
	if not _can_use_layered_composites():
		return [single]

	var bottom: Dictionary
	var top: Dictionary
	if vertical_axis:
		bottom = _corridor_placement(false, true, false, false)
		top = _corridor_placement(true, false, false, false)
	else:
		bottom = _corridor_placement(false, false, false, true)
		top = _corridor_placement(false, false, true, false)
	bottom["layer"] = 0
	top["layer"] = 1
	return [bottom, top]


func _t_junction_composite_placements(north: bool, south: bool, west: bool, east: bool) -> Array:
	if not _can_use_layered_composites():
		return [_t_junction_fallback_corner(north, south, west, east)]

	# 缺南 T 墙特殊处理：右下角落 + 偏右（flip_h）纵向走廊墙弥补左侧视觉缺失
	if not south:
		return _t_junction_missing_south()

	var tiles0: Array[Vector2i] = []
	var tiles1: Array[Vector2i] = []
	if not north:
		tiles0 = corner_top_left_tiles
		tiles1 = corner_top_right_tiles
	elif not west:
		tiles0 = corner_bottom_left_tiles
		tiles1 = corner_top_left_tiles
	elif not east:
		tiles0 = corner_bottom_right_tiles
		tiles1 = corner_top_right_tiles
	else:
		return [_t_junction_fallback_corner(north, south, west, east)]

	var has0 := not tiles0.is_empty()
	var has1 := not tiles1.is_empty()
	if not has0 and not has1:
		return [_t_junction_fallback_corner(north, south, west, east)]

	var result: Array = []
	if has0:
		result.append(_make_placement(_pick_random_tile(tiles0, Vector2i(13, 9)), 0, 0))
	if has1:
		var layer := 1 if has0 else 0
		result.append(_make_placement(_pick_random_tile(tiles1, Vector2i(13, 9)), 0, layer))
	return result


func _t_junction_missing_south() -> Array:
	var has_corner := not corner_bottom_right_tiles.is_empty()
	var has_corridor := not corridor_horizontal_wall_tiles.is_empty()
	if not has_corner and not has_corridor:
		return [_t_junction_fallback_corner(true, false, true, true)]

	var result: Array = []
	if has_corner:
		result.append(_make_placement(
			_pick_random_tile(corner_bottom_right_tiles, Vector2i(13, 9)), 0, 0))
	if has_corridor:
		var layer := 1 if has_corner else 0
		# 朝右（东）的横向走廊墙：默认朝东，transform 为 0（无翻转）
		result.append(_make_placement(
			_pick_random_tile(corridor_horizontal_wall_tiles, Vector2i(13, 9)), 0, layer))
	return result


func _t_junction_fallback_corner(north: bool, south: bool, west: bool, east: bool) -> Dictionary:
	if not north:
		return _make_placement(_pick_random_tile(corner_top_left_tiles, Vector2i(13, 9)), 0, 0)
	if not south:
		return _make_placement(_pick_random_tile(corner_bottom_left_tiles, Vector2i(13, 9)), 0, 0)
	if not west:
		return _make_placement(_pick_random_tile(corner_top_left_tiles, Vector2i(13, 9)), 0, 0)
	if not east:
		return _make_placement(_pick_random_tile(corner_top_right_tiles, Vector2i(13, 9)), 0, 0)
	return _make_placement(_pick_random_tile(corner_top_left_tiles, Vector2i(13, 9)), 0, 0)


func _can_use_layered_composites() -> bool:
	return use_layered_wall_composites and _render_layers.size() >= 2


func _make_placement(atlas: Vector2i, transform: int, layer: int) -> Dictionary:
	return {"atlas": atlas, "transform": transform, "layer": layer}


func _apply_placement(grid_pos: Vector2i, placement: Dictionary) -> void:
	var layer_index: int = placement.get("layer", 0)
	if layer_index >= _render_layers.size():
		_ensure_layer_exists(layer_index)
	if layer_index >= _render_layers.size():
		return
	_render_layers[layer_index].set_cell(
		grid_pos, tile_source_id, placement.atlas, placement.get("transform", 0)
	)


func _prepare_tilemap_layers() -> void:
	_render_layers.clear()
	_render_layers.append(tile_map_layer)

	if not use_layered_wall_composites:
		return

	# 优先使用 Inspector 里手动绑定的 overlay；否则自动创建。
	if tile_map_layer_overlay == null \
			or tile_map_layer_overlay == tile_map_layer \
			or not is_instance_valid(tile_map_layer_overlay):
		tile_map_layer_overlay = _make_auto_overlay(tile_map_layer, 1)
	if tile_map_layer_overlay != null:
		_render_layers.append(tile_map_layer_overlay)

	# 已追踪的额外层（对角补块 layer 2+）
	for existing_layer in _created_overlay_layers:
		if is_instance_valid(existing_layer) and existing_layer not in _render_layers:
			_render_layers.append(existing_layer)

	_sync_layer_visuals()


func _sync_layer_visuals() -> void:
	var base := tile_map_layer
	for i in _render_layers.size():
		var layer := _render_layers[i]
		if layer == null or layer == base:
			continue
		layer.position = base.position
		layer.rotation = base.rotation
		layer.scale = base.scale
		layer.visible = base.visible
		layer.modulate = base.modulate
		layer.self_modulate = base.self_modulate
		layer.z_as_relative = base.z_as_relative
		layer.z_index = base.z_index + (i * wall_overlay_z_step)
		var ts := layer.tile_set
		if ts != null:
			ts.tile_size = Vector2i(tile_size, tile_size)


func _make_auto_overlay(base: TileMapLayer, layer_index: int) -> TileMapLayer:
	var parent := base.get_parent()
	if parent == null:
		push_warning("DungeonGenerator: tile_map_layer 没有父节点，无法自动创建叠层。")
		return null
	var layer := TileMapLayer.new()
	layer.name = "%sOverlay%d" % [base.name, layer_index]
	layer.tile_set = base.tile_set
	layer.z_index = base.z_index + (layer_index * wall_overlay_z_step)
	parent.add_child(layer)
	if layer not in _created_overlay_layers:
		_created_overlay_layers.append(layer)
	return layer


func _place_exit() -> void:
	exit_pos = Vector2i(-1, -1)
	if rooms.is_empty():
		return

	# BFS 计算各房间距出生房间的跳数
	var adj := _build_room_adjacency()
	var distances := _bfs_room_distances(spawn_room_index, adj)

	# 按距离降序收集候选房间，至少距离 2；不足则降级
	var candidate_rooms: Array = []
	for i in rooms.size():
		if distances[i] >= 2 and i != spawn_room_index:
			candidate_rooms.append(i)
	if candidate_rooms.is_empty():
		for i in rooms.size():
			if distances[i] >= 1 and i != spawn_room_index:
				candidate_rooms.append(i)
	if candidate_rooms.is_empty():
		for i in rooms.size():
			if i != spawn_room_index:
				candidate_rooms.append(i)

	# 出口放在房间内部（距边界至少 1 格的 FLOOR 格）。
	# 内部格距外壁门格至少 2 格，天然不相邻，无需额外过滤。
	# 优先选离房间中心更近的格子（即更靠内），通过"到最近边界的曼哈顿距离"排序。
	candidate_rooms.shuffle()
	for ri in candidate_rooms:
		var room: Rect2i = rooms[ri]
		var candidates: Array[Vector2i] = []
		for y in range(room.position.y + 1, room.end.y - 1):
			for x in range(room.position.x + 1, room.end.x - 1):
				var pos := Vector2i(x, y)
				if grid_map[pos.y][pos.x] == TileType.FLOOR:
					candidates.append(pos)
		if candidates.is_empty():
			continue
		# 按"到最近墙边的距离"降序，优先取最靠内的格子
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := mini(mini(a.x - room.position.x, room.end.x - 1 - a.x),
						   mini(a.y - room.position.y, room.end.y - 1 - a.y))
			var db := mini(mini(b.x - room.position.x, room.end.x - 1 - b.x),
						   mini(b.y - room.position.y, room.end.y - 1 - b.y))
			return da > db
		)
		# 从最靠内的一批格子中随机取一个（避免永远选正中心）
		var best_dist := mini(mini(candidates[0].x - room.position.x, room.end.x - 1 - candidates[0].x),
							  mini(candidates[0].y - room.position.y, room.end.y - 1 - candidates[0].y))
		var best_pool: Array[Vector2i] = []
		for c in candidates:
			var d := mini(mini(c.x - room.position.x, room.end.x - 1 - c.x),
						  mini(c.y - room.position.y, room.end.y - 1 - c.y))
			if d == best_dist:
				best_pool.append(c)
		exit_pos = best_pool[_rng.randi_range(0, best_pool.size() - 1)]
		# 确保出口不与出生点重合
		if exit_pos == get_random_room_floor_cell():
			exit_pos = best_pool[_rng.randi_range(0, best_pool.size() - 1)]
		return


func _build_room_adjacency() -> Array:
	var adj: Array = []
	adj.resize(rooms.size())
	for i in rooms.size():
		adj[i] = []
	for pair_key in _connected_room_pairs:
		var parts: PackedStringArray = (pair_key as String).split(":")
		if parts.size() < 2:
			continue
		var a := int(parts[0])
		var b := int(parts[1])
		if a < adj.size() and b < adj.size():
			(adj[a] as Array).append(b)
			(adj[b] as Array).append(a)
	return adj


func _bfs_room_distances(start: int, adj: Array) -> Array:
	var dist: Array = []
	dist.resize(adj.size())
	dist.fill(-1)
	if start < 0 or start >= adj.size():
		return dist
	dist[start] = 0
	var queue: Array = [start]
	while not queue.is_empty():
		var curr: int = queue.pop_front()
		for neighbor in (adj[curr] as Array):
			if dist[neighbor] == -1:
				dist[neighbor] = dist[curr] + 1
				queue.append(neighbor)
	return dist


func _find_doors() -> void:
	doors.clear()
	_door_set.clear()
	for room in rooms:
		# 北/南面：外侧格子 + 向外方向为北/南
		for x in range(room.position.x, room.end.x):
			_try_add_door(Vector2i(x, room.position.y - 1), Vector2i(0, -1))
			_try_add_door(Vector2i(x, room.end.y),           Vector2i(0,  1))
		# 西/东面
		for y in range(room.position.y, room.end.y):
			_try_add_door(Vector2i(room.position.x - 1, y), Vector2i(-1, 0))
			_try_add_door(Vector2i(room.end.x,           y), Vector2i( 1, 0))
	_remove_tightly_adjacent_doors()


## 仅当外侧格为 FLOOR 且其"向外方向"邻格也是 FLOOR（实际走廊入口）时才标记为门。
## 这样可以排除沿房间外壁平行行进的走廊段，避免产生多格宽的开口。
func _try_add_door(pos: Vector2i, outward: Vector2i) -> void:
	if _door_set.has(pos):
		return
	if not _is_in_bounds(pos) or grid_map[pos.y][pos.x] != TileType.FLOOR:
		return
	# 向外的邻格也必须是 FLOOR（即真正有走廊向内延伸）
	var out_pos := pos + outward
	if not _is_in_bounds(out_pos) or grid_map[out_pos.y][out_pos.x] != TileType.FLOOR:
		return
	doors.append(pos)
	_door_set[pos] = true


func _remove_tightly_adjacent_doors() -> void:
	var invalid_doors: Dictionary = {}
	for door in doors:
		if _is_direct_room_door(door):
			continue
		for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = door + direction
			if _door_set.has(neighbor) and not _is_direct_room_door(neighbor):
				invalid_doors[door] = true
				invalid_doors[neighbor] = true

	if invalid_doors.is_empty():
		return
	var filtered_doors: Array[Vector2i] = []
	for door in doors:
		if invalid_doors.has(door):
			_door_set.erase(door)
			_door_states.erase(door)
		else:
			filtered_doors.append(door)
	doors = filtered_doors


func _is_direct_room_door(pos: Vector2i) -> bool:
	return (_room_floor_set.has(pos + Vector2i(-1, 0)) and _room_floor_set.has(pos + Vector2i(1, 0))) \
		or (_room_floor_set.has(pos + Vector2i(0, -1)) and _room_floor_set.has(pos + Vector2i(0, 1)))


func toggle_door(pos: Vector2i) -> void:
	if not _door_set.has(pos):
		return
	if _inactive_door_set.has(pos):
		return
	var is_open: bool = not _door_states.get(pos, false)
	_door_states[pos] = is_open
	var inst: Variant = _door_entity_by_cell.get(pos, null)
	if inst != null and is_instance_valid(inst) and (inst as Node).has_method("set_open"):
		(inst as Node).call("set_open", is_open, true)
		return
	var layer := _get_or_create_door_layer()
	if layer == null:
		return
	_draw_door_cell(pos, is_open, layer)


## 将普通（非 inactive）门强制设为开启并刷新实体/图块表现（用于桶等击退落到门格时保持敞开）。
func ensure_door_open_at(pos: Vector2i, animate: bool = true) -> void:
	if not _door_set.has(pos):
		return
	if _inactive_door_set.has(pos):
		return
	if bool(_door_states.get(pos, false)):
		return
	_door_states[pos] = true
	var inst: Variant = _door_entity_by_cell.get(pos, null)
	if inst != null and is_instance_valid(inst) and (inst as Node).has_method("set_open"):
		(inst as Node).call("set_open", true, animate)
		return
	var layer := _get_or_create_door_layer()
	if layer == null:
		return
	_draw_door_cell(pos, true, layer)


func _draw_door_cell(pos: Vector2i, is_open: bool, layer: TileMapLayer) -> void:
	if is_open:
		if not door_open_tiles.is_empty():
			layer.set_cell(pos, tile_source_id,
				_pick_random_tile(door_open_tiles, Vector2i(0, 0)))
		else:
			layer.erase_cell(pos)
	else:
		var tiles_for_closed := door_closed_tiles
		if _inactive_door_set.has(pos) and not inactive_door_wall_tiles.is_empty():
			tiles_for_closed = inactive_door_wall_tiles
		if not tiles_for_closed.is_empty():
			layer.set_cell(pos, tile_source_id,
				_pick_random_tile(tiles_for_closed, Vector2i(0, 0)))
		else:
			layer.erase_cell(pos)


func _render_doors() -> void:
	if door_entity_scene != null:
		_remove_only_door_scene_instances()
		if doors.is_empty():
			return
		var parent := _get_or_create_door_exit_container()
		if parent == null:
			return
		for pos in doors:
			var inst := door_entity_scene.instantiate()
			parent.add_child(inst)
			_apply_door_entity_canvas_z(inst)
			if inst.has_method("bind_grid_position"):
				inst.call("bind_grid_position", pos, tile_size)
			elif inst is Node2D:
				(inst as Node2D).position = Vector2(pos) * float(tile_size) \
						+ Vector2.ONE * (float(tile_size) * 0.5)
			if inst.has_method("set_door_inactive"):
				(inst as Object).call("set_door_inactive", _inactive_door_set.has(pos), false)
			if inst.has_method("set_open"):
				inst.call("set_open", _door_states.get(pos, false), false)
			_door_entity_by_cell[pos] = inst
		return
	if door_closed_tiles.is_empty() \
			and door_open_tiles.is_empty() \
			and inactive_door_wall_tiles.is_empty():
		return
	var layer := _get_or_create_door_layer()
	if layer == null:
		return
	_clear_previous_door_cells(layer)
	for pos in doors:
		var is_open: bool = _door_states.get(pos, false)
		_draw_door_cell(pos, is_open, layer)
		_rendered_door_cells[pos] = true


func _clear_previous_door_cells(layer: TileMapLayer) -> void:
	for cell in _rendered_door_cells:
		layer.erase_cell(cell)
	_rendered_door_cells.clear()


func _apply_door_entity_canvas_z(node: Node) -> void:
	if tile_map_layer == null:
		return
	if node is CanvasItem:
		var zs := tile_map_layer.z_index + door_layer_z_offset
		zs = maxi(zs, ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING + 1)
		(node as CanvasItem).z_as_relative = false
		(node as CanvasItem).z_index = zs


## 与 `_apply_door_entity_canvas_z` / 自动门 TileMapLayer 使用的 z 一致，供玩家在「是否压过门」时对齐。
func get_door_canvas_z_index() -> int:
	if tile_map_layer == null:
		return ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING + 1
	var zs := tile_map_layer.z_index + door_layer_z_offset
	return maxi(zs, ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING + 1)


## 液体仅略高于地板、始终低于玩家/敌人（约 -10）。
func get_flammable_liquid_canvas_z_index() -> int:
	if tile_map_layer == null:
		return ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING - 1
	var floor_z: int = (tile_map_layer as CanvasItem).z_index
	var z: int = floor_z + flammable_liquid_layer_z_offset
	return mini(z, ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING - 1)


## 深渊浮台木桶：高于地板/深渊 TileMap，低于玩家与敌人（约 -10）。
func get_abyss_barrel_platform_canvas_z_index() -> int:
	if tile_map_layer == null:
		return ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING - 1
	var floor_z: int = (tile_map_layer as CanvasItem).z_index
	## 与易燃液体同档：floor + offset，且必须 **严格高于** floor_z（否则与深渊块同层被盖住）。
	var z: int = floor_z + maxi(2, flammable_liquid_layer_z_offset + 1)
	return mini(z, ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING - 1)


## 玩家是否与任意门占位格在同一网格纵轴（同行），用于决定是否画在门下。
func is_aligned_with_any_door_row(grid_pos: Vector2i) -> bool:
	for door_cell in doors:
		if door_cell.y == grid_pos.y:
			return true
	return false


func _apply_exit_entity_canvas_z(node: Node) -> void:
	if tile_map_layer == null:
		return
	if node is CanvasItem:
		# 向下的通道出入口：始终在玩家（约 -10）之下绘制。
		var zs := tile_map_layer.z_index + exit_layer_z_offset
		zs = mini(zs, ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING - 1)
		(node as CanvasItem).z_as_relative = false
		(node as CanvasItem).z_index = zs


func _remove_door_registration_at(cell: Vector2i) -> void:
	if not _door_set.has(cell):
		return
	_door_set.erase(cell)
	_door_states.erase(cell)
	_inactive_door_set.erase(cell)
	var ix := doors.find(cell)
	if ix >= 0:
		doors.remove_at(ix)


## 布局/渲染前先把门格的 grid 与房间地板集合对齐为可走地板「开口」，避免邻居墙 bitmask 把它当墙；
## 「未激活」仅由 `_inactive_door_set` + 门图层外观表达，不改变此处几何。
func _ensure_floor_for_layout_door_cell(cell: Vector2i) -> void:
	if not _is_in_bounds(cell):
		return
	grid_map[cell.y][cell.x] = TileType.FLOOR
	_room_floor_set[cell] = true
	if _room_cell_to_room_index.get(cell, -1) < 0:
		_room_cell_to_room_index[cell] = 0


func _register_inactive_door_cell_from_layout(cell: Vector2i) -> void:
	if not _is_in_bounds(cell):
		return
	_ensure_floor_for_layout_door_cell(cell)
	if not doors.has(cell):
		doors.append(cell)
	_door_set[cell] = true
	_door_states[cell] = false
	_inactive_door_set[cell] = true


## 将未激活门变为普通门关（可被玩家踩上后按原有逻辑撬开）。
func activate_inactive_door_at(pos: Vector2i) -> bool:
	if not _inactive_door_set.has(pos) or not _door_set.has(pos):
		return false
	_inactive_door_set.erase(pos)
	# 与布局注册未激活门时一致：逻辑格必须是地板，寻路/回合与雾区房间集合才能与普通门对齐。
	var need_base_refresh := false
	if _is_in_bounds(pos):
		if get_tile(pos) != TileType.FLOOR:
			_set_tile(pos, TileType.FLOOR)
			need_base_refresh = true
		if not _room_floor_set.has(pos):
			_room_floor_set[pos] = true
			need_base_refresh = true
		if _room_cell_to_room_index.get(pos, -1) < 0:
			_room_cell_to_room_index[pos] = 0
	_door_states[pos] = false
	var inst_ent: Variant = _door_entity_by_cell.get(pos, null)
	if inst_ent != null and is_instance_valid(inst_ent) and (inst_ent as Object).has_method("set_door_inactive"):
		(inst_ent as Object).call("set_door_inactive", false, true)
	else:
		var lyr := _get_or_create_door_layer()
		if lyr != null:
			_draw_door_cell(pos, bool(_door_states.get(pos, false)), lyr)
	if need_base_refresh:
		# 不重跑 _render_doors，避免瞬时销毁/重建全体门实体，冲掉上面的激活演出。
		_refresh_render_patch(pos, 1, false)
	return true


func is_inactive_door_at(pos: Vector2i) -> bool:
	return _inactive_door_set.has(pos)


## 运行时把已激活的普通门设为「未激活」假门；与布局烘焙的 `_inactive_door_set` 行为一致。
func deactivate_door_at(pos: Vector2i, animate_entity_visual: bool = true) -> bool:
	if not _door_set.has(pos):
		return false
	if _inactive_door_set.has(pos):
		return true
	_inactive_door_set[pos] = true
	_door_states[pos] = false
	var inst_ent: Variant = _door_entity_by_cell.get(pos, null)
	if inst_ent != null and is_instance_valid(inst_ent) \
			and (inst_ent as Object).has_method("set_door_inactive"):
		(inst_ent as Object).call("set_door_inactive", true, animate_entity_visual)
	else:
		var lyr := _get_or_create_door_layer()
		if lyr != null:
			_draw_door_cell(pos, bool(_door_states.get(pos, false)), lyr)
	return true


func toggle_doors_adjacent_to_wall_switch(center: Vector2i) -> void:
	for i in _WALL_SWITCH_NEIGHBOR_OFFSETS.size():
		var d: Vector2i = _WALL_SWITCH_NEIGHBOR_OFFSETS[i]
		var p: Vector2i = center + d
		if not _door_set.has(p):
			continue
		if _inactive_door_set.has(p):
			activate_inactive_door_at(p)
		else:
			deactivate_door_at(p, true)


func _clamp_wall_switch_facing(facing: int) -> int:
	if facing < GridWallSwitch.Facing.UP_FROM_SOUTH or facing > GridWallSwitch.Facing.APPROACH_EAST_HIT_WEST:
		return GridWallSwitch.Facing.UP_FROM_SOUTH
	return facing


## 「上」「下」贴墙闸：近战来源格必须为地板（若指示层没落笔到该格，`floor_cells` 里可能没有它）。
func _ensure_wall_switch_attack_stance_floor(sw_cell: Vector2i, facing: int) -> void:
	var f: int = _clamp_wall_switch_facing(facing)
	var stance := Vector2i.ZERO
	var need_floor := false
	match f:
		GridWallSwitch.Facing.UP_FROM_SOUTH:
			stance = sw_cell + Vector2i(0, 1)
			need_floor = true
		GridWallSwitch.Facing.DOWN_FROM_NORTH:
			stance = sw_cell + Vector2i(0, -1)
			need_floor = true
		_:
			pass
	if not need_floor:
		return
	if not _is_in_bounds(stance):
		push_warning(
			"DungeonGenerator: 开关 (%d,%d) 近战站位邻格 (%d,%d) 超出地图。"
			% [sw_cell.x, sw_cell.y, stance.x, stance.y])
		return
	grid_map[stance.y][stance.x] = TileType.FLOOR
	_room_floor_set[stance] = true
	_room_cell_to_room_index[stance] = 0


func _texture_from_baked_switch_atlas(atlas_coords: Vector2i) -> Texture2D:
	if tile_map_layer == null or tile_map_layer.tile_set == null:
		return null
	var ts: TileSet = tile_map_layer.tile_set
	var sid := get_effective_wall_switch_atlas_source_id()
	var src_var: Variant = ts.get_source(sid)
	if src_var == null or not src_var is TileSetAtlasSource:
		return null
	var asrc := src_var as TileSetAtlasSource
	if not asrc.has_tile(atlas_coords):
		return null
	var at := AtlasTexture.new()
	at.atlas = asrc.texture
	at.region = asrc.get_tile_texture_region(atlas_coords, 0)
	at.filter_clip = true
	return at


func _texture_for_wall_switch_facing(facing: int) -> Texture2D:
	match facing:
		GridWallSwitch.Facing.UP_FROM_SOUTH:
			return wall_switch_texture_attack_from_south_row
		GridWallSwitch.Facing.DOWN_FROM_NORTH:
			return wall_switch_texture_attack_from_north_row
		GridWallSwitch.Facing.APPROACH_WEST_HIT_EAST:
			return wall_switch_texture_floor_west_appr_to_east
		GridWallSwitch.Facing.APPROACH_EAST_HIT_WEST:
			return wall_switch_texture_floor_east_appr_to_west
	return null


func _finalize_wall_switch_layout_cell(cell: Vector2i, facing: int) -> void:
	if _registered_wall_switch_cells.find(cell) >= 0:
		return
	_registered_wall_switch_cells.append(cell)
	_wall_switch_facing_by_cell[cell] = facing


func _attempt_register_wall_switch(cell: Vector2i, facing: int, forbidden: Dictionary) -> bool:
	var f: int = _clamp_wall_switch_facing(facing)
	if _registered_wall_switch_cells.find(cell) >= 0:
		_ensure_wall_switch_attack_stance_floor(cell, f)
		return true
	var ok := false
	match f:
		GridWallSwitch.Facing.UP_FROM_SOUTH:
			ok = _carve_wall_switch_cover_up(cell, forbidden)
		GridWallSwitch.Facing.DOWN_FROM_NORTH:
			ok = _carve_wall_switch_cover_down(cell, forbidden)
		GridWallSwitch.Facing.APPROACH_WEST_HIT_EAST:
			ok = _validate_wall_switch_floor_anchor_west_approach(cell, forbidden)
		GridWallSwitch.Facing.APPROACH_EAST_HIT_WEST:
			ok = _validate_wall_switch_floor_anchor_east_approach(cell, forbidden)
		_:
			ok = _carve_wall_switch_cover_up(cell, forbidden)
	if not ok:
		return false
	_finalize_wall_switch_layout_cell(cell, f)
	_ensure_wall_switch_attack_stance_floor(cell, f)
	return true


func _carve_wall_switch_cover_up(cell: Vector2i, forbidden: Dictionary) -> bool:
	if not _is_in_bounds(cell):
		return false
	if forbidden.has(cell):
		return false
	## 仅占位墙格本体；对应朝向的近战站位邻格由 `_ensure_wall_switch_attack_stance_floor` 在登记后写成地板。
	grid_map[cell.y][cell.x] = TileType.WALL
	_room_floor_set.erase(cell)
	_room_cell_to_room_index.erase(cell)
	return true


func _carve_wall_switch_cover_down(cell: Vector2i, forbidden: Dictionary) -> bool:
	if not _is_in_bounds(cell):
		return false
	if forbidden.has(cell):
		return false
	## 同上；不向邻格强行刻墙。
	grid_map[cell.y][cell.x] = TileType.WALL
	_room_floor_set.erase(cell)
	_room_cell_to_room_index.erase(cell)
	return true


func _validate_wall_switch_floor_anchor_west_approach(cell: Vector2i, forbidden: Dictionary) -> bool:
	if not _is_in_bounds(cell) or forbidden.has(cell):
		return false
	if get_tile(cell) != TileType.FLOOR:
		push_warning(
			"DungeonGenerator: 左朝向（西向东打）墙面开关锚点须为可走地板格 (%d,%d)。" % [cell.x, cell.y])
		return false
	var east_n := cell + Vector2i(1, 0)
	if not _is_in_bounds(east_n) or get_tile(east_n) != TileType.WALL:
		push_warning(
			"DungeonGenerator: 左朝向开关要求东侧邻格为墙 (%d,%d)。" % [cell.x, cell.y])
		return false
	var below := cell + Vector2i(0, 1)
	if not _is_in_bounds(below) or get_tile(below) != TileType.FLOOR:
		push_warning(
			"DungeonGenerator: 左朝向开关要求其南邻格（「下」方）亦为地板 (%d,%d)。" % [cell.x, cell.y])
		return false
	return true


func _validate_wall_switch_floor_anchor_east_approach(cell: Vector2i, forbidden: Dictionary) -> bool:
	if not _is_in_bounds(cell) or forbidden.has(cell):
		return false
	if get_tile(cell) != TileType.FLOOR:
		push_warning(
			"DungeonGenerator: 右朝向（东向西打）墙面开关锚点须为可走地板格 (%d,%d)。" % [cell.x, cell.y])
		return false
	var west_n := cell + Vector2i(-1, 0)
	if not _is_in_bounds(west_n) or get_tile(west_n) != TileType.WALL:
		push_warning(
			"DungeonGenerator: 右朝向开关要求西侧邻格为墙 (%d,%d)。" % [cell.x, cell.y])
		return false
	var below2 := cell + Vector2i(0, 1)
	if not _is_in_bounds(below2) or get_tile(below2) != TileType.FLOOR:
		push_warning(
			"DungeonGenerator: 右朝向开关要求其南邻格（「下」方）亦为地板 (%d,%d)。" % [cell.x, cell.y])
		return false
	return true


func _clear_wall_switch_entities_only() -> void:
	_wall_switch_entity_by_cell.clear()
	if _wall_switch_container != null and is_instance_valid(_wall_switch_container):
		for sw_ch in _wall_switch_container.get_children():
			if is_instance_valid(sw_ch):
				sw_ch.free()


func _get_or_create_wall_switch_container() -> Node2D:
	if tile_map_layer == null:
		return null
	if _wall_switch_container != null and is_instance_valid(_wall_switch_container):
		return _wall_switch_container
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var n := Node2D.new()
	n.name = "WallSwitchEntities"
	parent.add_child(n)
	_wall_switch_container = n
	return _wall_switch_container


func _apply_wall_switch_canvas_z(node: Node) -> void:
	if tile_map_layer == null:
		return
	if node is CanvasItem:
		var zs := tile_map_layer.z_index + wall_switch_layer_z_offset
		zs = maxi(zs, ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING + 1)
		(node as CanvasItem).z_as_relative = false
		(node as CanvasItem).z_index = zs


func _get_wall_switch_scene_effective() -> PackedScene:
	return wall_switch_scene if wall_switch_scene != null else DEFAULT_WALL_SWITCH_ENTITY_SCENE


func _render_wall_switches() -> void:
	var scene: PackedScene = _get_wall_switch_scene_effective()
	if scene == null or _registered_wall_switch_cells.is_empty():
		return
	var parent := _get_or_create_wall_switch_container()
	if parent == null:
		return
	for cell in _registered_wall_switch_cells:
		var sw := scene.instantiate()
		parent.add_child(sw)
		_apply_wall_switch_canvas_z(sw)
		var facing_sw: int = int(_wall_switch_facing_by_cell.get(cell, GridWallSwitch.Facing.UP_FROM_SOUTH))
		var ov_tex: Texture2D = null
		var bakery_atlas := get_wall_switch_baked_atlas_at(cell)
		if bakery_atlas.x >= 0:
			ov_tex = _texture_from_baked_switch_atlas(bakery_atlas)
		if ov_tex == null:
			ov_tex = _texture_for_wall_switch_facing(facing_sw)
		if sw.has_method("bind_grid_position"):
			sw.call("bind_grid_position", cell, tile_size, self)
		elif sw is Node2D:
			(sw as Node2D).position = Vector2(cell) * float(tile_size) \
					+ Vector2.ONE * (float(tile_size) * 0.5)
		if sw.has_method("apply_facing_visual"):
			sw.call("apply_facing_visual", facing_sw, ov_tex, bakery_atlas)
		if sw.has_method("bind_dungeon"):
			sw.call("bind_dungeon", self)
		if sw.has_method("play_idle_if_any"):
			sw.call("play_idle_if_any")
		## 东西向开关的布局锚点在地板格，`try_apply_barrel_wall_strike_effects` 以**墙格**为 strike_cell；须用与 `GridWallSwitch.get_occupancy_grid_pos` 一致的键注册。
		var map_cell: Vector2i = cell
		if sw.has_method("get_toggle_anchor_grid_pos"):
			var ac: Variant = sw.call("get_toggle_anchor_grid_pos")
			if ac is Vector2i:
				map_cell = ac as Vector2i
		_wall_switch_entity_by_cell[map_cell] = sw


func _get_or_create_door_exit_container() -> Node2D:
	if tile_map_layer == null:
		return null
	if _door_exit_container != null and is_instance_valid(_door_exit_container):
		return _door_exit_container
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var n := Node2D.new()
	n.name = "DoorExitEntities"
	parent.add_child(n)
	_door_exit_container = n
	return n


func _clear_door_exit_entities_full() -> void:
	_clear_wall_switch_entities_only()
	_door_entity_by_cell.clear()
	if _exit_entity_node != null and is_instance_valid(_exit_entity_node):
		_exit_entity_node.free()
	_exit_entity_node = null
	if _door_exit_container != null and is_instance_valid(_door_exit_container):
		for ch in _door_exit_container.get_children():
			if is_instance_valid(ch):
				ch.free()


func _remove_only_door_scene_instances() -> void:
	for k in _door_entity_by_cell.keys():
		var n: Variant = _door_entity_by_cell[k]
		if n != null and is_instance_valid(n):
			(n as Node).free()
	_door_entity_by_cell.clear()


func _get_or_create_door_layer() -> TileMapLayer:
	if tile_map_layer_door != null \
			and is_instance_valid(tile_map_layer_door) \
			and tile_map_layer_door != tile_map_layer:
		_sync_extra_layer(tile_map_layer_door)
		return tile_map_layer_door
	if tile_map_layer == null:
		return null
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var layer := TileMapLayer.new()
	layer.name = "%sDoor" % tile_map_layer.name
	layer.tile_set = tile_map_layer.tile_set
	layer.z_index = tile_map_layer.z_index + door_layer_z_offset
	parent.add_child(layer)
	tile_map_layer_door = layer
	_sync_extra_layer(layer)
	return layer


func _render_exit() -> void:
	if exit_pos == Vector2i(-1, -1):
		return
	if exit_entity_scene != null:
		var gpv: Variant = null
		if _exit_entity_node != null and is_instance_valid(_exit_entity_node) \
				and _exit_entity_node.has_method("get"):
			gpv = _exit_entity_node.get("grid_pos")
		if gpv is Vector2i and (gpv as Vector2i) == exit_pos:
			return
		if _exit_entity_node != null and is_instance_valid(_exit_entity_node):
			_exit_entity_node.free()
		_exit_entity_node = null
		var parent := _get_or_create_door_exit_container()
		if parent == null:
			return
		var ex := exit_entity_scene.instantiate()
		parent.add_child(ex)
		_apply_exit_entity_canvas_z(ex)
		if ex.has_method("bind_grid_position"):
			ex.call("bind_grid_position", exit_pos, tile_size)
		elif ex is Node2D:
			(ex as Node2D).position = Vector2(exit_pos) * float(tile_size) \
					+ Vector2.ONE * (float(tile_size) * 0.5)
		_exit_entity_node = ex
		if ex.has_method("play_idle_if_any"):
			ex.call("play_idle_if_any")
		return
	if exit_tiles.is_empty():
		return

	# 优先使用 Inspector 手动绑定的专用层；
	# 否则复用 _render_layers[1]：出口格是 FLOOR，主循环只在第 0 层写地板，
	# 第 1 层在此格必然为空，可安全写入，且与其他图块同属一套已验证的渲染系统。
	if tile_map_layer_exit != null \
			and is_instance_valid(tile_map_layer_exit) \
			and tile_map_layer_exit != tile_map_layer:
		if tile_map_layer_exit.z_index > tile_map_layer.z_index + pillar_layer_z_offset:
			tile_map_layer_exit.z_index = tile_map_layer.z_index + exit_layer_z_offset
		_sync_extra_layer(tile_map_layer_exit)
		tile_map_layer_exit.set_cell(exit_pos, tile_source_id,
			_pick_random_tile(exit_tiles, Vector2i(0, 0)))
	else:
		_ensure_layer_exists(1)
		if _render_layers.size() > 1:
			_render_layers[1].set_cell(exit_pos, tile_source_id,
				_pick_random_tile(exit_tiles, Vector2i(0, 0)))


func _render_background() -> void:
	var layer := _get_or_create_background_layer()
	if layer == null:
		return
	_sync_background_layer_hsv(layer)
	layer.clear()
	if background_tiles.is_empty():
		return
	# 过大边距会在 load 时铺海量背景格导致长时间卡死（Inspector 仍可设大值，运行时封顶）。
	var margin := clampi(background_margin_tiles, 0, 48)
	for y in range(-margin, map_height + margin):
		for x in range(-margin, map_width + margin):
			layer.set_cell(Vector2i(x, y), tile_source_id,
				_pick_random_tile(background_tiles, background_tiles[0]))


func _get_or_create_background_layer() -> TileMapLayer:
	if tile_map_layer_background == tile_map_layer:
		push_warning(
			"DungeonGenerator: tile_map_layer_background 不能与 tile_map_layer 相同，将自动创建独立背景层。"
		)
		tile_map_layer_background = null
	if tile_map_layer_background != null \
			and is_instance_valid(tile_map_layer_background) \
			and tile_map_layer_background != tile_map_layer:
		if tile_map_layer_background.tile_set == null:
			tile_map_layer_background.tile_set = tile_map_layer.tile_set
		tile_map_layer_background.z_index = tile_map_layer.z_index + background_layer_z_offset
		_sync_extra_layer(tile_map_layer_background)
		return tile_map_layer_background
	if tile_map_layer == null:
		return null
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var layer := TileMapLayer.new()
	layer.name = "%sBackground" % tile_map_layer.name
	layer.tile_set = tile_map_layer.tile_set
	layer.z_index = tile_map_layer.z_index + background_layer_z_offset
	parent.add_child(layer)
	tile_map_layer_background = layer
	_sync_extra_layer(layer)
	return layer


func _sync_background_particles() -> void:
	if tile_map_layer == null:
		return
	if not use_background_particles or background_particle_scene == null:
		if _background_particle_instance != null and is_instance_valid(_background_particle_instance):
			_background_particle_instance.queue_free()
		_background_particle_instance = null
		return

	if _background_particle_instance == null or not is_instance_valid(_background_particle_instance):
		var parent := tile_map_layer.get_parent()
		if parent == null:
			return
		var instance := background_particle_scene.instantiate()
		if instance == null:
			return
		parent.add_child(instance)
		_background_particle_instance = instance

	if _background_particle_instance is Node2D:
		var n2d := _background_particle_instance as Node2D
		n2d.position = tile_map_layer.position + get_map_pixel_size() * 0.5
	if _background_particle_instance.has_method("set_emission_rect"):
		_background_particle_instance.call("set_emission_rect", get_map_pixel_size())
	var particles := _background_particle_instance.get_node_or_null("GPUParticles2D") as GPUParticles2D
	if particles != null and particles.process_material is ParticleProcessMaterial:
		var pm := particles.process_material as ParticleProcessMaterial
		pm.emission_box_extents = Vector3(
			get_map_pixel_size().x * 0.5,
			get_map_pixel_size().y * 0.5,
			1.0
		)
	if _background_particle_instance is CanvasItem:
		var ci := _background_particle_instance as CanvasItem
		ci.z_as_relative = tile_map_layer.z_as_relative
		ci.z_index = tile_map_layer.z_index + background_particle_z_offset


func _sync_background_layer_hsv(layer: TileMapLayer) -> void:
	if layer == null:
		return
	var existing_mat := layer.material as ShaderMaterial
	if not use_background_hsv_adjust:
		if _is_abyss_hsv_material(existing_mat):
			layer.material = null
		return

	var shader := load(ABYSS_HSV_SHADER_PATH) as Shader
	if shader == null:
		push_warning("DungeonGenerator: 未找到深渊 HSV 着色器 %s。" % ABYSS_HSV_SHADER_PATH)
		return

	var mat := existing_mat
	if mat == null or mat.shader != shader:
		mat = ShaderMaterial.new()
		mat.shader = shader
		layer.material = mat
	mat.set_shader_parameter("hue_shift", background_hue_shift_degrees / 360.0)
	mat.set_shader_parameter("saturation_mult", background_saturation)
	mat.set_shader_parameter("value_mult", background_value)


func _is_abyss_hsv_material(mat: ShaderMaterial) -> bool:
	if mat == null or mat.shader == null:
		return false
	return mat.shader.resource_path == ABYSS_HSV_SHADER_PATH


## 将额外叠层（门 / 出口 / 柱子）的位置 / 旋转 / 缩放与基础层同步。
func _sync_extra_layer(layer: TileMapLayer) -> void:
	if layer == null or tile_map_layer == null:
		return
	_sync_extra_layer_transform_only(layer)
	layer.modulate = tile_map_layer.modulate
	layer.self_modulate = tile_map_layer.self_modulate


func _sync_extra_layer_transform_only(layer: TileMapLayer) -> void:
	if layer == null or tile_map_layer == null:
		return
	layer.position = tile_map_layer.position
	layer.rotation = tile_map_layer.rotation
	layer.scale = tile_map_layer.scale
	layer.visible = tile_map_layer.visible
	layer.z_as_relative = tile_map_layer.z_as_relative
	if layer.tile_set != null:
		layer.tile_set.tile_size = Vector2i(tile_size, tile_size)


func _render_pillars() -> void:
	if pillar_top_tiles.is_empty() and pillar_bottom_tiles.is_empty():
		push_warning("DungeonGenerator: pillar_top_tiles 和 pillar_bottom_tiles 都为空。请在 Inspector 里填入柱子图块坐标，而不只是给图层分配 Texture/TileSet。")
		return
	var layer := _get_or_create_pillar_layer()
	if layer == null:
		return
	_prepare_pillar_layer_tileset(layer)
	if layer.tile_set == null:
		push_warning("DungeonGenerator: 柱子层没有 TileSet，无法绘制 pillar。")
		return
	var source_id := _pillar_source_id()
	if layer.tile_set.get_source(source_id) == null:
		source_id = tile_source_id
	if layer.tile_set.get_source(source_id) == null:
		push_warning("DungeonGenerator: 柱子层 TileSet 找不到可用 source（pillar_tile_source_id=%d, tile_source_id=%d）。" % [pillar_tile_source_id, tile_source_id])
		return
	_clear_previous_pillar_cells(layer)
	var pillar_cells: Dictionary = {}
	for y in map_height:
		for x in map_width:
			var gp := Vector2i(x, y)
			if _is_isolated_wall(gp):
				pillar_cells[gp] = true
	for gp in _random_pillar_obstacle_set:
		if use_baked_random_pillar_obstacles and get_tile(gp) == TileType.WALL:
			pillar_cells[gp] = true
	for gp in pillar_cells:
		_render_pillar_cell(gp, layer, source_id)


func _clear_previous_pillar_cells(layer: TileMapLayer) -> void:
	for cell in _rendered_pillar_cells:
		layer.erase_cell(cell)
	_rendered_pillar_cells.clear()


func _render_pillar_cell(gp: Vector2i, layer: TileMapLayer, source_id: int) -> void:
	# 在基础层补一块地板，让柱子脚下不露空
	tile_map_layer.set_cell(gp, tile_source_id,
		_pick_random_tile(floor_tiles, Vector2i(0, 0)))
	# 默认底部在碰撞格，上半部分在其上方；可通过 offset 适配不同素材。
	if not pillar_bottom_tiles.is_empty():
		var bottom_tile := _pick_valid_pillar_tile(layer, source_id, pillar_bottom_tiles)
		if bottom_tile != Vector2i(-1, -1):
			var bottom_cell := gp + pillar_bottom_cell_offset
			layer.set_cell(bottom_cell, source_id, bottom_tile)
			_rendered_pillar_cells[bottom_cell] = true
		elif gp == _first_pillar_debug_cell():
			push_warning("DungeonGenerator: pillar_bottom_tiles 在 source_id=%d 中均无效。" % source_id)
	if not pillar_top_tiles.is_empty():
		var top_tile := _pick_valid_pillar_tile(layer, source_id, pillar_top_tiles)
		if top_tile != Vector2i(-1, -1):
			var top_cell := gp + pillar_top_cell_offset
			layer.set_cell(top_cell, source_id, top_tile)
			_rendered_pillar_cells[top_cell] = true
		elif gp == _first_pillar_debug_cell():
			push_warning("DungeonGenerator: pillar_top_tiles 在 source_id=%d 中均无效。" % source_id)


func _pillar_source_id() -> int:
	if pillar_use_base_tileset:
		return tile_source_id
	return tile_source_id if pillar_tile_source_id < 0 else pillar_tile_source_id


func _pick_valid_pillar_tile(layer: TileMapLayer, source_id: int, candidates: Array[Vector2i]) -> Vector2i:
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var source := layer.tile_set.get_source(source_id)
	if not source is TileSetAtlasSource:
		return _pick_random_tile(candidates, candidates[0])
	var atlas := source as TileSetAtlasSource
	var valid_tiles: Array[Vector2i] = []
	for tile in candidates:
		if atlas.has_tile(tile):
			valid_tiles.append(tile)
	if valid_tiles.is_empty():
		return Vector2i(-1, -1)
	return _pick_random_tile(valid_tiles, valid_tiles[0])


func _first_pillar_debug_cell() -> Vector2i:
	for gp in _random_pillar_obstacle_set:
		return gp
	return Vector2i(-9999, -9999)


func _prepare_pillar_layer_tileset(layer: TileMapLayer) -> void:
	if pillar_use_base_tileset:
		layer.tile_set = tile_map_layer.tile_set
	elif layer.tile_set == null:
		layer.tile_set = tile_map_layer.tile_set
	if layer.tile_set != null:
		layer.tile_set.tile_size = Vector2i(tile_size, tile_size)


func _is_isolated_wall(gp: Vector2i) -> bool:
	return get_tile(gp) == TileType.WALL \
		and _is_floor_at(gp + Vector2i(0, -1)) \
		and _is_floor_at(gp + Vector2i(0, 1)) \
		and _is_floor_at(gp + Vector2i(-1, 0)) \
		and _is_floor_at(gp + Vector2i(1, 0))


func _promote_four_way_isolated_walls_for_entity_pillars() -> void:
	_four_way_entity_pillar_cells.clear()
	if layout_suppress_procedural_breakable_pillars:
		return
	if not use_breakable_entities_for_four_way_wall_pillars:
		return
	for y in map_height:
		for x in map_width:
			var gp := Vector2i(x, y)
			if not _is_isolated_wall(gp):
				continue
			_four_way_entity_pillar_cells.append(gp)
			_random_pillar_obstacle_set.erase(gp)
			_set_tile(gp, TileType.FLOOR)


func _get_or_create_pillar_layer() -> TileMapLayer:
	if tile_map_layer_pillar != null \
			and is_instance_valid(tile_map_layer_pillar) \
			and tile_map_layer_pillar != tile_map_layer:
		_prepare_pillar_layer_tileset(tile_map_layer_pillar)
		if tile_map_layer_pillar.z_index <= tile_map_layer.z_index + door_layer_z_offset:
			tile_map_layer_pillar.z_index = tile_map_layer.z_index + pillar_layer_z_offset
		_sync_extra_layer(tile_map_layer_pillar)
		return tile_map_layer_pillar
	if tile_map_layer == null:
		return null
	var parent := tile_map_layer.get_parent()
	if parent == null:
		push_warning("DungeonGenerator: 无法自动创建柱子层（tile_map_layer 无父节点）。")
		return null
	var layer := TileMapLayer.new()
	layer.name = "%sPillar" % tile_map_layer.name
	layer.tile_set = tile_map_layer.tile_set
	layer.z_index = tile_map_layer.z_index + pillar_layer_z_offset
	parent.add_child(layer)
	tile_map_layer_pillar = layer
	_sync_extra_layer(layer)
	return layer


func _ensure_layer_exists(layer_index: int) -> void:
	while _render_layers.size() <= layer_index:
		var new_layer := _make_auto_overlay(tile_map_layer, _render_layers.size())
		if new_layer == null:
			return
		_render_layers.append(new_layer)
		new_layer.clear()


func _pick_random_tile(tiles: Array[Vector2i], fallback: Vector2i) -> Vector2i:
	if tiles.is_empty():
		return fallback
	return tiles[_rng.randi_range(0, tiles.size() - 1)]


func _apply_preset_special_wall_cells(layout_data: Dictionary) -> void:
	var transp_var: Variant = layout_data.get("transparent_wall_cells", [])
	if transp_var is Array:
		for cv in transp_var:
			if cv is Vector2i and _is_in_bounds(cv):
				grid_map[(cv as Vector2i).y][(cv as Vector2i).x] = TileType.TRANSPARENT_WALL
				_room_floor_set.erase(cv)
				_room_cell_to_room_index.erase(cv)
	var ric_var: Variant = layout_data.get("ricochet_wall_cells", [])
	if ric_var is Array:
		for cv2 in ric_var:
			if cv2 is Vector2i and _is_in_bounds(cv2):
				grid_map[(cv2 as Vector2i).y][(cv2 as Vector2i).x] = TileType.RICOCHET_WALL
				_room_floor_set.erase(cv2)
				_room_cell_to_room_index.erase(cv2)


func is_ricochet_corner_cell(pos: Vector2i) -> bool:
	if get_tile(pos) != TileType.RICOCHET_WALL:
		return false
	var north := _is_floor_at(pos + Vector2i(0, -1))
	var south := _is_floor_at(pos + Vector2i(0, 1))
	var west := _is_floor_at(pos + Vector2i(-1, 0))
	var east := _is_floor_at(pos + Vector2i(1, 0))
	var floor_count := int(north) + int(south) + int(west) + int(east)
	if floor_count != 2:
		return false
	return not ((north and south) or (west and east))


## 邻接地板方向（墙格 → 开放侧），与 `_resolve_ricochet_decor_placement` 朝向一致。
func get_ricochet_open_floor_directions(wall_cell: Vector2i) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = []
	if _is_floor_at(wall_cell + Vector2i(0, -1)):
		dirs.append(Vector2i(0, -1))
	if _is_floor_at(wall_cell + Vector2i(0, 1)):
		dirs.append(Vector2i(0, 1))
	if _is_floor_at(wall_cell + Vector2i(-1, 0)):
		dirs.append(Vector2i(-1, 0))
	if _is_floor_at(wall_cell + Vector2i(1, 0)):
		dirs.append(Vector2i(1, 0))
	return dirs


## 按墙面开放朝向作镜面反射（等价于以墙面为轴镜像射手侧速度），`incident` 为入射步进方向。
func get_ricochet_reflect_dir(wall_cell: Vector2i, incident: Vector2i) -> Vector2i:
	if incident == Vector2i.ZERO:
		return Vector2i.ZERO
	var open_dirs := get_ricochet_open_floor_directions(wall_cell)
	if open_dirs.is_empty():
		return -incident

	var inc_v := Vector2(incident)
	if open_dirs.size() == 1:
		return _quantize_ricochet_reflect(inc_v, Vector2(open_dirs[0]).normalized())

	var primary: Vector2i = open_dirs[0]
	var best_align: float = inc_v.dot(Vector2(primary))
	for d: Vector2i in open_dirs:
		var align: float = inc_v.dot(Vector2(d))
		if align < best_align:
			best_align = align
			primary = d

	if absi(incident.x) > 0 and absi(incident.y) > 0 and is_ricochet_corner_cell(wall_cell):
		var secondary: Vector2i = primary
		for d: Vector2i in open_dirs:
			if d != primary:
				secondary = d
				break
		var n_bi := (Vector2(primary) + Vector2(secondary)).normalized()
		if n_bi.length_squared() > 1e-8:
			return _quantize_ricochet_reflect(inc_v, n_bi)

	return _quantize_ricochet_reflect(inc_v, Vector2(primary).normalized())


func _quantize_ricochet_reflect(inc_v: Vector2, n_hat: Vector2) -> Vector2i:
	if n_hat.length_squared() <= 1e-8:
		return Vector2i.ZERO
	var reflected := inc_v - 2.0 * inc_v.dot(n_hat) * n_hat
	if absf(inc_v.x) <= 1e-5:
		return Vector2i(0, _ricochet_signi(reflected.y))
	if absf(inc_v.y) <= 1e-5:
		return Vector2i(_ricochet_signi(reflected.x), 0)
	return Vector2i(_ricochet_signi(reflected.x), _ricochet_signi(reflected.y))


func _ricochet_signi(v: float) -> int:
	if v > 0.25:
		return 1
	if v < -0.25:
		return -1
	return 0


func _layer_is_safe_special_wall_overlay(layer: TileMapLayer) -> bool:
	if layer == null or not is_instance_valid(layer):
		return false
	# 仅禁止写入主地图与其常规叠层/背景；专用透明墙、反弹墙叠层正是合法绘制目标。
	if layer == tile_map_layer:
		return false
	if tile_map_layer_overlay != null and layer == tile_map_layer_overlay:
		return false
	if tile_map_layer_background != null and layer == tile_map_layer_background:
		return false
	return true


func _render_special_wall_overlays() -> void:
	if tile_map_layer == null:
		return
	_prepare_transparent_wall_layers_for_render()
	_prepare_ricochet_wall_layers_for_render()
	var ric_decor_layer := _get_or_create_ricochet_decor_layer()
	if _layer_is_safe_special_wall_overlay(ric_decor_layer):
		ric_decor_layer.clear()
		ric_decor_layer.modulate = Color.WHITE
		ric_decor_layer.self_modulate = Color.WHITE
	elif ric_decor_layer == tile_map_layer:
		push_warning(
			"DungeonGenerator: tile_map_layer_ricochet_decor 不能指向主 tile_map_layer，已跳过以免清空地图。"
		)
	for y in map_height:
		for x in map_width:
			_render_special_wall_cell(Vector2i(x, y), ric_decor_layer)


func _render_special_wall_cell(gp: Vector2i, ric_decor_layer: TileMapLayer) -> void:
	var tile: TileType = get_tile(gp) as TileType
	if tile == TileType.TRANSPARENT_WALL:
		var transp_placements := _resolve_wall_placements(gp, true)
		_apply_transparent_wall_placements(gp, transp_placements)
	elif tile == TileType.RICOCHET_WALL:
		var wall_placements := _resolve_wall_placements(gp, true)
		_apply_ricochet_wall_placements(gp, wall_placements)
		var decor := _resolve_ricochet_decor_placement(gp, wall_placements)
		if not decor.is_empty() and _layer_is_safe_special_wall_overlay(ric_decor_layer):
			_apply_placement_on_layer(ric_decor_layer, gp, decor)


func _sync_transparent_layer_alpha(layer: TileMapLayer) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	var ta := clampf(transparent_wall_alpha, 0.05, 1.0)
	layer.modulate = Color(1.0, 1.0, 1.0, ta)
	layer.self_modulate = Color(1.0, 1.0, 1.0, ta)


func _prepare_transparent_wall_layers_for_render() -> void:
	_transparent_render_layers.clear()
	var max_layer_idx := 1 if _can_use_layered_composites() else 0
	for i in range(max_layer_idx + 1):
		_ensure_transparent_layer_exists(i)
	for layer in _transparent_render_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		if not _layer_is_safe_special_wall_overlay(layer):
			continue
		layer.clear()
		_sync_transparent_layer_alpha(layer)


func _ensure_transparent_render_layers_registered() -> void:
	if not _transparent_render_layers.is_empty():
		if _can_use_layered_composites():
			_ensure_transparent_layer_exists(1)
		return
	var base := _get_or_create_transparent_wall_overlay_layer()
	if base != null and _layer_is_safe_special_wall_overlay(base):
		if base not in _transparent_render_layers:
			_transparent_render_layers.append(base)
		_sync_transparent_layer_alpha(base)
	for layer in _created_transparent_overlay_layers:
		if layer != null and is_instance_valid(layer) and layer not in _transparent_render_layers:
			_transparent_render_layers.append(layer)
			_sync_transparent_layer_alpha(layer)
	if _can_use_layered_composites():
		_ensure_transparent_layer_exists(1)


func _ensure_transparent_layer_exists(layer_index: int) -> void:
	layer_index = maxi(0, layer_index)
	while _transparent_render_layers.size() <= layer_index:
		var prev_size := _transparent_render_layers.size()
		var idx := _transparent_render_layers.size()
		var layer: TileMapLayer = null
		if idx == 0:
			layer = _get_or_create_transparent_wall_overlay_layer()
		else:
			layer = _make_transparent_auto_overlay(idx)
		if layer == null:
			push_warning("DungeonGenerator: 无法创建透明墙叠层 index=%d。" % idx)
			break
		if layer in _transparent_render_layers:
			push_warning(
				"DungeonGenerator: 透明墙叠层 index=%d 引用重复，中止以免死循环。" % idx
			)
			break
		_transparent_render_layers.append(layer)
		_sync_transparent_layer_alpha(layer)
		if _transparent_render_layers.size() <= prev_size:
			break


func _make_transparent_auto_overlay(overlay_index: int) -> TileMapLayer:
	if tile_map_layer == null:
		return null
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var z_step := maxi(1, wall_overlay_z_step)
	var layer := TileMapLayer.new()
	layer.name = "%sTransparentWallOverlay%d" % [tile_map_layer.name, overlay_index]
	layer.tile_set = tile_map_layer.tile_set
	layer.z_index = tile_map_layer.z_index + transparent_wall_layer_z_offset + (overlay_index - 1) * z_step
	parent.add_child(layer)
	_sync_extra_layer(layer)
	_sync_transparent_layer_alpha(layer)
	if layer not in _created_transparent_overlay_layers:
		_created_transparent_overlay_layers.append(layer)
	return layer


func _apply_transparent_wall_placements(grid_pos: Vector2i, placements: Array) -> void:
	if placements.is_empty():
		return
	for item in placements:
		if not item is Dictionary:
			continue
		var placement: Dictionary = item as Dictionary
		var layer_index: int = int(placement.get("layer", 0))
		_ensure_transparent_layer_exists(layer_index)
		if layer_index < 0 or layer_index >= _transparent_render_layers.size():
			continue
		var target: TileMapLayer = _transparent_render_layers[layer_index] as TileMapLayer
		if target == null or not _layer_is_safe_special_wall_overlay(target):
			continue
		_apply_placement_on_layer(target, grid_pos, placement)


func _ensure_ricochet_render_layers_registered() -> void:
	if not _ricochet_render_layers.is_empty():
		if _can_use_layered_composites():
			_ensure_ricochet_layer_exists(1)
		return
	var base := _get_or_create_ricochet_wall_layer()
	if base != null and base not in _ricochet_render_layers:
		_ricochet_render_layers.append(base)
	for layer in _created_ricochet_overlay_layers:
		if layer != null and is_instance_valid(layer) and layer not in _ricochet_render_layers:
			_ricochet_render_layers.append(layer)
	if _can_use_layered_composites():
		_ensure_ricochet_layer_exists(1)


func _apply_placement_on_layer(layer: TileMapLayer, grid_pos: Vector2i, placement: Dictionary) -> void:
	if layer == null:
		return
	layer.set_cell(
		grid_pos,
		tile_source_id,
		placement.get("atlas", Vector2i.ZERO),
		placement.get("transform", 0)
	)


func _apply_ricochet_wall_placements(grid_pos: Vector2i, placements: Array) -> void:
	if placements.is_empty():
		return
	for item in placements:
		if not item is Dictionary:
			continue
		var placement: Dictionary = item as Dictionary
		var layer_index: int = int(placement.get("layer", 0))
		_ensure_ricochet_layer_exists(layer_index)
		if layer_index < 0 or layer_index >= _ricochet_render_layers.size():
			continue
		var target: TileMapLayer = _ricochet_render_layers[layer_index] as TileMapLayer
		if target == null:
			continue
		_apply_placement_on_layer(target, grid_pos, placement)


func _prepare_ricochet_wall_layers_for_render() -> void:
	_ricochet_render_layers.clear()
	var base := _get_or_create_ricochet_wall_layer()
	if base != null:
		_ricochet_render_layers.append(base)
		base.clear()
		_sync_ricochet_wall_layer_hsv(base)
	for layer in _created_ricochet_overlay_layers:
		if layer != null and is_instance_valid(layer) and layer not in _ricochet_render_layers:
			_ricochet_render_layers.append(layer)
			layer.clear()
			_sync_ricochet_wall_layer_hsv(layer)
	if _can_use_layered_composites():
		_ensure_ricochet_layer_exists(1)


func _ensure_ricochet_layer_exists(layer_index: int) -> void:
	layer_index = maxi(0, layer_index)
	while _ricochet_render_layers.size() <= layer_index:
		var prev_size := _ricochet_render_layers.size()
		var idx := _ricochet_render_layers.size()
		var layer: TileMapLayer = null
		if idx == 0:
			layer = _get_or_create_ricochet_wall_layer()
		elif not _can_use_layered_composites():
			break
		elif idx == 1:
			layer = _get_or_create_ricochet_wall_overlay_layer()
		else:
			layer = _make_ricochet_auto_overlay(idx)
		if layer == null:
			push_warning("DungeonGenerator: 无法创建反弹墙叠层 index=%d。" % idx)
			break
		if layer in _ricochet_render_layers:
			push_warning(
				"DungeonGenerator: 反弹墙叠层 index=%d 引用重复，中止以免死循环。" % idx
			)
			break
		_ricochet_render_layers.append(layer)
		_sync_ricochet_wall_layer_hsv(layer)
		if _ricochet_render_layers.size() <= prev_size:
			break


func _make_ricochet_auto_overlay(overlay_index: int) -> TileMapLayer:
	if tile_map_layer == null:
		return null
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var z_step := maxi(1, wall_overlay_z_step)
	var layer := TileMapLayer.new()
	layer.name = "%sRicochetWallOverlay%d" % [tile_map_layer.name, overlay_index]
	layer.tile_set = tile_map_layer.tile_set
	layer.z_index = tile_map_layer.z_index + ricochet_wall_layer_z_offset + (overlay_index - 1) * z_step
	parent.add_child(layer)
	_sync_extra_layer(layer)
	_sync_ricochet_wall_layer_hsv(layer)
	if layer not in _created_ricochet_overlay_layers:
		_created_ricochet_overlay_layers.append(layer)
	return layer


func _resolve_ricochet_decor_placement(grid_pos: Vector2i, wall_placements: Array) -> Dictionary:
	var north := _is_floor_at(grid_pos + Vector2i(0, -1))
	var south := _is_floor_at(grid_pos + Vector2i(0, 1))
	var west := _is_floor_at(grid_pos + Vector2i(-1, 0))
	var east := _is_floor_at(grid_pos + Vector2i(1, 0))
	var corner_decor := _resolve_ricochet_inner_corner_decor(grid_pos, north, south, west, east)
	if not corner_decor.is_empty():
		return corner_decor

	# 平面墙：仅当本体 `_corridor_placement` 会选 `corridor_vertical_wall_tiles`（上下朝向）时叠加装饰。
	if ricochet_decor_vertical_tiles.is_empty():
		return {}
	if not _wall_mask_uses_corridor_vertical(north, south, west, east):
		return {}
	if not _ricochet_body_uses_corridor_vertical(wall_placements):
		return {}
	var primary := _pick_primary_wall_placement(wall_placements)
	var rot := _tile_rotation_flags()
	var body_xf: int = int(primary.get("transform", rot.none)) if not primary.is_empty() else rot.none
	return {
		"atlas": _pick_random_tile(ricochet_decor_vertical_tiles, Vector2i.ZERO),
		"transform": body_xf,
	}


## 内凹角：L 形（两面正交邻地板 + 内侧对角地板，沿拐角三格）或 T 形（三面邻地板）。
func _resolve_ricochet_inner_corner_decor(
	grid_pos: Vector2i,
	north: bool,
	south: bool,
	west: bool,
	east: bool
) -> Dictionary:
	var floor_count := int(north) + int(south) + int(west) + int(east)
	var rot := _tile_rotation_flags()

	# T 形内凹：三面邻地板，缺的一侧为墙脊。
	if floor_count == 3:
		if not north:
			return _make_ricochet_decor_corner_pick(ricochet_decor_corner_top_left_tiles, rot.none)
		if not south:
			return _make_ricochet_decor_corner_pick(ricochet_decor_corner_bottom_left_tiles, rot.none)
		if not west:
			return _make_ricochet_decor_corner_pick(ricochet_decor_corner_top_right_tiles, rot.none)
		if not east:
			return _make_ricochet_decor_corner_pick(ricochet_decor_corner_bottom_right_tiles, rot.none)
		return {}

	# L 形内凹：两面正交邻地板，且内侧对角格为地板（拐角共三格相邻）。
	if floor_count != 2 or (north and south) or (west and east):
		return {}

	# 内侧对角格须为地板（两面正交邻地板 + 该对角 = 沿拐角三格）。
	if south and east and _is_floor_at(grid_pos + Vector2i(1, 1)):
		return _make_ricochet_decor_corner_pick(ricochet_decor_corner_top_left_tiles, rot.none)
	if south and west and _is_floor_at(grid_pos + Vector2i(-1, 1)):
		return _make_ricochet_decor_corner_pick(ricochet_decor_corner_top_right_tiles, rot.none)
	if north and east and _is_floor_at(grid_pos + Vector2i(1, -1)):
		return _make_ricochet_decor_corner_pick(ricochet_decor_corner_bottom_left_tiles, rot.none)
	if north and west and _is_floor_at(grid_pos + Vector2i(-1, -1)):
		return _make_ricochet_decor_corner_pick(ricochet_decor_corner_bottom_right_tiles, rot.none)
	return {}


func _make_ricochet_decor_corner_pick(tiles: Array[Vector2i], transform: int) -> Dictionary:
	if tiles.is_empty():
		return {}
	return {
		"atlas": _pick_random_tile(tiles, Vector2i.ZERO),
		"transform": transform,
	}


## 与 `_corridor_placement` 选用 `corridor_vertical_wall_tiles` 的分支一致（上下朝向墙，非 horizontal）。
func _wall_mask_uses_corridor_vertical(north: bool, south: bool, west: bool, east: bool) -> bool:
	if east and not west and not north and not south:
		return false
	if west and not east and not north and not south:
		return false
	if west and east:
		return false
	if south and not north and not east and not west:
		return true
	if north and not south and not east and not west:
		return true
	if north and south:
		return true
	return false


func _ricochet_body_uses_corridor_vertical(wall_placements: Array) -> bool:
	if corridor_vertical_wall_tiles.is_empty():
		return false
	for item in wall_placements:
		if not item is Dictionary:
			continue
		var atlas: Vector2i = (item as Dictionary).get("atlas", Vector2i(-1, -1))
		for ref in corridor_vertical_wall_tiles:
			if atlas == ref:
				return true
	return false


func _sync_ricochet_wall_layer_hsv(layer: TileMapLayer) -> void:
	if layer == null:
		return
	if not use_ricochet_wall_hsv_adjust:
		layer.modulate = Color.WHITE
		return
	var base := Color.from_hsv(
		fposmod(ricochet_wall_hue_shift_degrees / 360.0, 1.0),
		clampf(ricochet_wall_saturation, 0.0, 2.0),
		clampf(ricochet_wall_value, 0.0, 2.0),
		1.0
	)
	layer.modulate = base


func _get_or_create_transparent_wall_overlay_layer() -> TileMapLayer:
	if _layer_is_safe_special_wall_overlay(tile_map_layer_transparent_wall):
		_sync_extra_layer(tile_map_layer_transparent_wall)
		return tile_map_layer_transparent_wall
	if tile_map_layer_transparent_wall != null and tile_map_layer_transparent_wall == tile_map_layer:
		push_warning(
			"DungeonGenerator: 已忽略 tile_map_layer_transparent_wall 与主层相同引用，将自动创建独立叠层。"
		)
		tile_map_layer_transparent_wall = null
	if tile_map_layer == null:
		return null
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var layer := TileMapLayer.new()
	layer.name = "%sTransparentWall" % tile_map_layer.name
	layer.tile_set = tile_map_layer.tile_set
	layer.z_index = tile_map_layer.z_index + transparent_wall_layer_z_offset
	parent.add_child(layer)
	tile_map_layer_transparent_wall = layer
	_sync_extra_layer(layer)
	return layer


func _get_or_create_ricochet_wall_layer() -> TileMapLayer:
	if _layer_is_safe_special_wall_overlay(tile_map_layer_ricochet_wall):
		_sync_extra_layer(tile_map_layer_ricochet_wall)
		return tile_map_layer_ricochet_wall
	if tile_map_layer_ricochet_wall != null and tile_map_layer_ricochet_wall == tile_map_layer:
		push_warning(
			"DungeonGenerator: 已忽略 tile_map_layer_ricochet_wall 与主层相同引用，将自动创建独立叠层。"
		)
		tile_map_layer_ricochet_wall = null
	if tile_map_layer == null:
		return null
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var layer := TileMapLayer.new()
	layer.name = "%sRicochetWall" % tile_map_layer.name
	layer.tile_set = tile_map_layer.tile_set
	layer.z_index = tile_map_layer.z_index + ricochet_wall_layer_z_offset
	parent.add_child(layer)
	tile_map_layer_ricochet_wall = layer
	_sync_extra_layer(layer)
	_sync_ricochet_wall_layer_hsv(layer)
	return layer


func _get_or_create_ricochet_wall_overlay_layer() -> TileMapLayer:
	if not _can_use_layered_composites():
		return null
	if _layer_is_safe_special_wall_overlay(tile_map_layer_ricochet_overlay):
		_sync_extra_layer(tile_map_layer_ricochet_overlay)
		_sync_ricochet_wall_layer_hsv(tile_map_layer_ricochet_overlay)
		return tile_map_layer_ricochet_overlay
	if tile_map_layer_ricochet_overlay != null and tile_map_layer_ricochet_overlay == tile_map_layer:
		push_warning(
			"DungeonGenerator: 已忽略 tile_map_layer_ricochet_overlay 与主层相同引用，将自动创建独立叠层。"
		)
		tile_map_layer_ricochet_overlay = null
	if tile_map_layer == null:
		return null
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var layer := TileMapLayer.new()
	layer.name = "%sRicochetWallOverlay" % tile_map_layer.name
	layer.tile_set = tile_map_layer.tile_set
	layer.z_index = tile_map_layer.z_index + ricochet_wall_overlay_z_offset
	parent.add_child(layer)
	tile_map_layer_ricochet_overlay = layer
	_sync_extra_layer(layer)
	_sync_ricochet_wall_layer_hsv(layer)
	return layer


func _get_or_create_ricochet_decor_layer() -> TileMapLayer:
	if _layer_is_safe_special_wall_overlay(tile_map_layer_ricochet_decor):
		_sync_extra_layer_transform_only(tile_map_layer_ricochet_decor)
		tile_map_layer_ricochet_decor.modulate = Color.WHITE
		tile_map_layer_ricochet_decor.self_modulate = Color.WHITE
		return tile_map_layer_ricochet_decor
	if tile_map_layer_ricochet_decor != null and tile_map_layer_ricochet_decor == tile_map_layer:
		push_warning(
			"DungeonGenerator: 已忽略 tile_map_layer_ricochet_decor 与主层相同引用，将自动创建独立叠层。"
		)
		tile_map_layer_ricochet_decor = null
	if tile_map_layer == null:
		return null
	var parent := tile_map_layer.get_parent()
	if parent == null:
		return null
	var layer := TileMapLayer.new()
	layer.name = "%sRicochetDecor" % tile_map_layer.name
	layer.tile_set = tile_map_layer.tile_set
	layer.z_as_relative = false
	layer.z_index = tile_map_layer.z_index + ricochet_decor_layer_z_offset
	layer.modulate = Color.WHITE
	layer.self_modulate = Color.WHITE
	parent.add_child(layer)
	_sync_extra_layer_transform_only(layer)
	tile_map_layer_ricochet_decor = layer
	_sync_extra_layer(layer)
	tile_map_layer_ricochet_decor.modulate = Color.WHITE
	tile_map_layer_ricochet_decor.self_modulate = Color.WHITE
	return layer


func _is_floor_at(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.FLOOR


func _init_grid() -> void:
	grid_map.clear()
	for _y in map_height:
		var row: Array = []
		row.resize(map_width)
		row.fill(TileType.WALL)
		grid_map.append(row)


func _place_rooms() -> void:
	var attempts := 0
	while rooms.size() < room_count and attempts < max_placement_attempts:
		attempts += 1
		var candidate := _random_room_rect()
		if _overlaps_any_room(candidate):
			continue
		var room_index := rooms.size()
		rooms.append(candidate)
		_carve_rect(candidate, TileType.FLOOR, room_index)
		room_centers.append(_room_center(candidate))


func _random_room_rect() -> Rect2i:
	var w := _rng.randi_range(min_room_size, max_room_size)
	var h := _rng.randi_range(min_room_size, max_room_size)
	var max_x := map_width - w - 2
	var max_y := map_height - h - 2
	if max_x < 1 or max_y < 1:
		return Rect2i()
	var x := _rng.randi_range(1, max_x)
	var y := _rng.randi_range(1, max_y)
	return Rect2i(x, y, w, h)


func _overlaps_any_room(rect: Rect2i) -> bool:
	var padded := Rect2i(
		rect.position - Vector2i(room_padding + 1, room_padding + 1),
		rect.size + Vector2i((room_padding + 1) * 2, (room_padding + 1) * 2)
	)
	for existing in rooms:
		if padded.intersects(existing):
			return true
	return false


func _room_center(rect: Rect2i) -> Vector2i:
	return rect.position + Vector2i(rect.size.x / 2.0, rect.size.y / 2.0)


func _carve_rect(rect: Rect2i, tile: TileType, room_index: int = -1) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			_set_tile(pos, tile)
			if tile == TileType.FLOOR:
				_room_floor_set[pos] = true
				if room_index >= 0:
					_room_cell_to_room_index[pos] = room_index


func _place_random_pillar_obstacles() -> void:
	if random_pillar_obstacle_count <= 0:
		return
	if pillar_top_tiles.is_empty() and pillar_bottom_tiles.is_empty():
		return

	var placed := 0
	var attempts := 0
	while placed < random_pillar_obstacle_count and attempts < random_pillar_placement_attempts:
		attempts += 1
		if rooms.is_empty():
			return
		var room_index := _rng.randi_range(0, rooms.size() - 1)
		var room: Rect2i = rooms[room_index]
		if room.size.x < 3 or room.size.y < 3:
			continue
		var pos := Vector2i(
			_rng.randi_range(room.position.x + 1, room.end.x - 2),
			_rng.randi_range(room.position.y + 1, room.end.y - 2)
		)
		if not _can_try_place_pillar_obstacle(pos):
			continue
		_set_pillar_obstacle(pos, room_index)
		if _floor_cells_remain_connected():
			placed += 1
		else:
			_unset_pillar_obstacle(pos, room_index)


func _can_try_place_pillar_obstacle(pos: Vector2i) -> bool:
	if not _is_in_bounds(pos) or grid_map[pos.y][pos.x] != TileType.FLOOR:
		return false
	for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor: Vector2i = pos + direction
		if not _is_in_bounds(neighbor) or grid_map[neighbor.y][neighbor.x] != TileType.FLOOR:
			return false
	return true


func _set_pillar_obstacle(pos: Vector2i, _room_index: int) -> void:
	_set_tile(pos, TileType.WALL)
	_room_floor_set.erase(pos)
	_room_cell_to_room_index.erase(pos)
	_random_pillar_obstacle_set[pos] = true


func _unset_pillar_obstacle(pos: Vector2i, room_index: int) -> void:
	_set_tile(pos, TileType.FLOOR)
	_room_floor_set[pos] = true
	_room_cell_to_room_index[pos] = room_index
	_random_pillar_obstacle_set.erase(pos)


func get_random_pillar_obstacle_positions() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pos in _random_pillar_obstacle_set:
		result.append(pos as Vector2i)
	return result


func is_breakable_pillar_at(pos: Vector2i) -> bool:
	return _random_pillar_obstacle_set.has(pos)


func break_pillar_obstacle(pos: Vector2i) -> bool:
	if not use_baked_random_pillar_obstacles:
		return false
	if not _random_pillar_obstacle_set.has(pos):
		return false
	_set_tile(pos, TileType.FLOOR)
	_random_pillar_obstacle_set.erase(pos)
	_room_floor_set[pos] = true
	_refresh_render_patch(pos, 1)
	return true


## 桶击退撞击墙格：不挖穿地形；若有墙面开关则 `apply_damage` 尝试触发。
func try_apply_barrel_wall_strike_effects(strike_cell: Vector2i, damage: int, attacker_cell: Vector2i) -> bool:
	if damage <= 0 or not _is_in_bounds(strike_cell):
		return false
	if get_tile(strike_cell) != TileType.WALL:
		return false
	var sw: Variant = _wall_switch_entity_by_cell.get(strike_cell, null)
	if sw == null or not is_instance_valid(sw):
		return false
	if (sw as Object).has_method("apply_damage"):
		(sw as Object).call("apply_damage", damage, attacker_cell)
		return true
	if (sw as Object).has_method("trigger_from_environment_damage"):
		(sw as Object).call("trigger_from_environment_damage", damage)
		return true
	return false


## redraw_overlays：为 false 时只刷新墙/地板等主层叠块，不重绘门实体、立柱、出口（避免门实体被整图重建）。
func _refresh_render_patch(center: Vector2i, radius: int = 1, redraw_overlays: bool = true) -> void:
	if tile_map_layer == null:
		return
	_prepare_tilemap_layers()
	var min_x := maxi(center.x - radius, 0)
	var max_x := mini(center.x + radius, map_width - 1)
	var min_y := maxi(center.y - radius, 0)
	var max_y := mini(center.y + radius, map_height - 1)

	# 先清理补丁区域，避免旧叠层残留。
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var gp := Vector2i(x, y)
			for layer in _render_layers:
				layer.erase_cell(gp)

	# 仅重算补丁区域主层/叠层图块，不重绘全图。
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var gp := Vector2i(x, y)
			var tile: TileType = grid_map[y][x] as TileType
			for placement in _resolve_tile_placements(gp, tile):
				_apply_placement(gp, placement)

	if redraw_overlays:
		_render_pillars()
		_render_doors()
		_render_exit()
	_refresh_special_wall_patch(center, radius)


func _refresh_special_wall_patch(center: Vector2i, radius: int) -> void:
	if tile_map_layer == null:
		return
	var min_x := maxi(center.x - radius, 0)
	var max_x := mini(center.x + radius, map_width - 1)
	var min_y := maxi(center.y - radius, 0)
	var max_y := mini(center.y + radius, map_height - 1)
	_ensure_transparent_render_layers_registered()
	_ensure_ricochet_render_layers_registered()
	var ric_decor_layer := _get_or_create_ricochet_decor_layer()
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var gp := Vector2i(x, y)
			for tl in _transparent_render_layers:
				if tl != null and is_instance_valid(tl) and _layer_is_safe_special_wall_overlay(tl):
					tl.erase_cell(gp)
			for rl in _ricochet_render_layers:
				if rl != null and is_instance_valid(rl) and _layer_is_safe_special_wall_overlay(rl):
					rl.erase_cell(gp)
			if _layer_is_safe_special_wall_overlay(ric_decor_layer):
				ric_decor_layer.erase_cell(gp)
			_render_special_wall_cell(gp, ric_decor_layer)


func _floor_cells_remain_connected() -> bool:
	var start := Vector2i(-1, -1)
	var total_floor := 0
	for y in map_height:
		for x in map_width:
			if grid_map[y][x] != TileType.FLOOR:
				continue
			total_floor += 1
			if start == Vector2i(-1, -1):
				start = Vector2i(x, y)
	if total_floor <= 1:
		return true

	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + direction
			if visited.has(next) or not _is_in_bounds(next):
				continue
			if grid_map[next.y][next.x] != TileType.FLOOR:
				continue
			visited[next] = true
			queue.append(next)
	return visited.size() == total_floor


func _connect_room_centers() -> void:
	if room_centers.size() < 2:
		return

	var attempts := maxi(max_connection_attempts, 1)
	for attempt in attempts:
		_reset_to_rooms_only()
		_init_room_corridor_counts()
		var start_room := _rng.randi_range(0, rooms.size() - 1)
		if _connect_required_room_tree(start_room):
			if connect_all_pairs:
				_connect_extra_room_pairs()
			return
	push_warning("DungeonGenerator: 无法在一格走廊约束下连通所有房间，保留最后一次连接结果。")


func _init_room_corridor_counts() -> void:
	_room_corridor_counts.clear()
	_room_corridor_counts.resize(rooms.size())
	_room_corridor_counts.fill(0)


func _reset_to_rooms_only() -> void:
	_connected_room_pairs.clear()
	_corridor_floor_set.clear()
	_init_grid()
	_room_floor_set.clear()
	_room_cell_to_room_index.clear()
	for i in rooms.size():
		_carve_rect(rooms[i], TileType.FLOOR, i)


func _connect_required_room_tree(start_room: int) -> bool:
	var connected: Dictionary = {start_room: true}
	while connected.size() < rooms.size():
		var candidates := _room_connection_candidates(connected, true)
		var connected_new_room := false
		for pair in candidates:
			if _connect_room_pair(pair.x, pair.y):
				connected[pair.x] = true
				connected[pair.y] = true
				connected_new_room = true
				break
		if not connected_new_room:
			return false
	return true


func _connect_extra_room_pairs() -> void:
	var all_rooms: Dictionary = {}
	for i in rooms.size():
		all_rooms[i] = true
	var candidates := _room_connection_candidates(all_rooms, false)
	for pair in candidates:
		_connect_room_pair(pair.x, pair.y)


func _room_connection_candidates(connected: Dictionary, require_new_room: bool) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for i in room_centers.size():
		for j in range(i + 1, room_centers.size()):
			var i_connected := connected.has(i)
			var j_connected := connected.has(j)
			if require_new_room and i_connected == j_connected:
				continue
			candidates.append(Vector2i(i, j))
	candidates.shuffle()
	return candidates


func _connect_room_pair(room_a: int, room_b: int) -> bool:
	var a := mini(room_a, room_b)
	var b := maxi(room_a, room_b)
	var pair_key := "%d:%d" % [a, b]
	if _connected_room_pairs.has(pair_key):
		return false
	if _room_corridor_counts[a] >= 4 or _room_corridor_counts[b] >= 4:
		return false
	if _carve_corridor(room_centers[a], room_centers[b], a, b):
		_connected_room_pairs[pair_key] = true
		_room_corridor_counts[a] += 1
		_room_corridor_counts[b] += 1
		return true
	return false


func _carve_corridor(from: Vector2i, to: Vector2i, room_a: int, room_b: int) -> bool:
	if use_astar_corridors:
		return _carve_corridor_astar(from, to, room_a, room_b)
	return _carve_corridor_l_shape(from, to, room_a, room_b)


func _carve_corridor_l_shape(from: Vector2i, to: Vector2i, room_a: int, room_b: int) -> bool:
	var allowed_rooms: Array[int] = [room_a, room_b]
	if _rng.randf() > 0.5:
		if _try_carve_corridor_path(_corridor_l_shape_path(from, to, true), allowed_rooms):
			return true
		if _try_carve_corridor_path(_corridor_l_shape_path(from, to, false), allowed_rooms):
			return true
	else:
		if _try_carve_corridor_path(_corridor_l_shape_path(from, to, false), allowed_rooms):
			return true
		if _try_carve_corridor_path(_corridor_l_shape_path(from, to, true), allowed_rooms):
			return true
	var fallback_path := _find_one_tile_corridor_path(from, to, allowed_rooms)
	if not fallback_path.is_empty():
		return _try_carve_corridor_path(fallback_path, allowed_rooms)
	return false


func _corridor_l_shape_path(from: Vector2i, to: Vector2i, horizontal_first: bool) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if horizontal_first:
		_append_horizontal_path(path, from.x, to.x, from.y)
		_append_vertical_path(path, from.y, to.y, to.x)
	else:
		_append_vertical_path(path, from.y, to.y, from.x)
		_append_horizontal_path(path, from.x, to.x, to.y)
	return path


func _append_horizontal_path(path: Array[Vector2i], x0: int, x1: int, y: int) -> void:
	var step := 1 if x0 <= x1 else -1
	for x in range(x0, x1 + step, step):
		_append_unique_path_cell(path, Vector2i(x, y))


func _append_vertical_path(path: Array[Vector2i], y0: int, y1: int, x: int) -> void:
	var step := 1 if y0 <= y1 else -1
	for y in range(y0, y1 + step, step):
		_append_unique_path_cell(path, Vector2i(x, y))


func _append_unique_path_cell(path: Array[Vector2i], pos: Vector2i) -> void:
	if path.is_empty() or path[path.size() - 1] != pos:
		path.append(pos)


func _try_carve_corridor_path(path: Array[Vector2i], allowed_rooms: Array[int]) -> bool:
	if path.is_empty() or not _path_keeps_corridor_one_tile(path, allowed_rooms):
		return false
	for pos in path:
		_set_tile(pos, TileType.FLOOR)
		if not _room_floor_set.has(pos):
			_corridor_floor_set[pos] = true
	return true


func _path_keeps_corridor_one_tile(path: Array[Vector2i], allowed_rooms: Array[int]) -> bool:
	if not _path_stays_in_allowed_rooms(path, allowed_rooms):
		return false
	if not _path_keeps_room_connection_length(path):
		return false
	if not _path_avoids_unintended_room_diagonal_contacts(path, allowed_rooms):
		return false

	var path_index: Dictionary = {}
	for i in path.size():
		var pos: Vector2i = path[i]
		if not _is_in_bounds(pos):
			return false
		path_index[pos] = i

	for i in path.size():
		var pos: Vector2i = path[i]
		if _room_floor_set.has(pos):
			continue
		if _corridor_floor_set.has(pos):
			continue
		for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = pos + direction
			if _room_floor_set.has(neighbor):
				# 允许真正穿出房间的门口；不允许走廊贴着房间外墙横向延伸。
				if not path_index.has(neighbor):
					return false
				continue
			if _corridor_floor_set.has(neighbor):
				if not path_index.has(neighbor):
					return false
				continue
			if path_index.has(neighbor) and abs(int(path_index[neighbor]) - i) > 1:
				return false
	return true


func _path_avoids_unintended_room_diagonal_contacts(path: Array[Vector2i], allowed_rooms: Array[int]) -> bool:
	var path_set: Dictionary = {}
	for pos in path:
		path_set[pos] = true

	for pos in path:
		# 房间内部格子不参与“走廊贴房间斜角”判定
		if _room_floor_set.has(pos):
			continue
		var diagonals: Array[Vector2i] = [
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
		]
		for diag in diagonals:
			var diagonal_neighbor: Vector2i = pos + diag
			if not _room_floor_set.has(diagonal_neighbor):
				continue
			# 仅约束“非目标房间”的意外斜角接触；目标两房间保留正常开门/连接可能。
			if _room_cell_to_room_index.has(diagonal_neighbor):
				var room_index: int = _room_cell_to_room_index[diagonal_neighbor]
				if allowed_rooms.has(room_index):
					continue

			# 如果该对角接触同时也有正交接触，就不算“纯对角贴角”。
			var side_a := pos + Vector2i(diag.x, 0)
			var side_b := pos + Vector2i(0, diag.y)
			if _room_floor_set.has(side_a) or _room_floor_set.has(side_b):
				continue

			# 仅对角贴到非目标房间，判为非法。
			return false
	return true


func _path_stays_in_allowed_rooms(path: Array[Vector2i], allowed_rooms: Array[int]) -> bool:
	for pos in path:
		if not _room_cell_to_room_index.has(pos):
			continue
		var room_index: int = _room_cell_to_room_index[pos]
		if not allowed_rooms.has(room_index):
			return false
	return true


func _path_keeps_room_connection_length(path: Array[Vector2i]) -> bool:
	var corridor_len := -1
	for pos in path:
		if _room_floor_set.has(pos):
			if corridor_len == 2:
				return false
			corridor_len = 0
		elif corridor_len >= 0:
			corridor_len += 1
	return true


func _find_one_tile_corridor_path(
	from: Vector2i,
	to: Vector2i,
	allowed_rooms: Array[int]
) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary = {from: from}
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to:
			return _reconstruct_corridor_path(came_from, from, to, allowed_rooms)
		for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + direction
			if came_from.has(next) or not _can_step_one_tile_corridor(next, current, allowed_rooms):
				continue
			came_from[next] = current
			queue.append(next)
	return []


func _can_step_one_tile_corridor(
	pos: Vector2i,
	previous: Vector2i,
	allowed_rooms: Array[int]
) -> bool:
	if not _is_in_bounds(pos):
		return false
	if _room_cell_to_room_index.has(pos):
		var room_index: int = _room_cell_to_room_index[pos]
		return allowed_rooms.has(room_index)
	if _corridor_floor_set.has(pos):
		return true
	for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor: Vector2i = pos + direction
		if _corridor_floor_set.has(neighbor) and neighbor != previous:
			return false
		if _room_floor_set.has(neighbor) and neighbor != previous:
			return false
	return true


func _reconstruct_corridor_path(
	came_from: Dictionary,
	from: Vector2i,
	to: Vector2i,
	allowed_rooms: Array[int]
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current := to
	while current != from:
		path.push_front(current)
		current = came_from[current]
	path.push_front(from)
	if _path_keeps_corridor_one_tile(path, allowed_rooms):
		return path
	return []


func _carve_horizontal_line(x0: int, x1: int, y: int) -> void:
	var start_x := mini(x0, x1)
	var end_x := maxi(x0, x1)
	for x in range(start_x, end_x + 1):
		var pos := Vector2i(x, y)
		_set_tile(pos, TileType.FLOOR)
		if not _room_floor_set.has(pos):
			_corridor_floor_set[pos] = true


func _carve_vertical_line(y0: int, y1: int, x: int) -> void:
	var start_y := mini(y0, y1)
	var end_y := maxi(y0, y1)
	for y in range(start_y, end_y + 1):
		var pos := Vector2i(x, y)
		_set_tile(pos, TileType.FLOOR)
		if not _room_floor_set.has(pos):
			_corridor_floor_set[pos] = true


func _carve_corridor_astar(from: Vector2i, to: Vector2i, room_a: int, room_b: int) -> bool:
	var allowed_rooms: Array[int] = [room_a, room_b]
	var astar := AStar2D.new()
	var point_ids: Dictionary = {}

	for y in map_height:
		for x in map_width:
			var pos := Vector2i(x, y)
			var id := astar.get_available_point_id()
			astar.add_point(id, Vector2(x, y))
			point_ids[pos] = id

	for y in map_height:
		for x in map_width:
			var pos := Vector2i(x, y)
			var id: int = point_ids[pos]
			if x + 1 < map_width:
				astar.connect_points(id, point_ids[Vector2i(x + 1, y)])
			if y + 1 < map_height:
				astar.connect_points(id, point_ids[Vector2i(x, y + 1)])

	var path: PackedVector2Array = astar.get_point_path(point_ids[from], point_ids[to])
	var corridor_path: Array[Vector2i] = []
	for point in path:
		corridor_path.append(Vector2i(int(point.x), int(point.y)))
	if _try_carve_corridor_path(corridor_path, allowed_rooms):
		return true
	var fallback_path := _find_one_tile_corridor_path(from, to, allowed_rooms)
	if not fallback_path.is_empty():
		return _try_carve_corridor_path(fallback_path, allowed_rooms)
	return false


func _set_tile(pos: Vector2i, tile: TileType) -> void:
	if not _is_in_bounds(pos):
		return
	grid_map[pos.y][pos.x] = tile


func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < map_width and pos.y < map_height
