class_name PresetFloorLayout
extends Node2D
## 预设关卡布局：一个或多个 TileMapLayer 仅作编辑器「指示」，运行时不进入正式关卡；
## `build_layout_data()` 遍历指示层读出语义后用 `DungeonGenerator.load_floor_layout` 重生地图。
## 同格可在不同图层各摆一种语义（如底层地板 + 上层敌人）；同格冲突时按语义优先级，相同则后读图层覆盖。
## 敌人生成／程序化石柱等开关均在 **PresetFloorLayout**「生成抑制」导出项与本节点烘焙字段中配置（不使用 LevelFlow / FloorSpec 上的 override）。
## 「门柱敌玩家出生出口」等处底层强制铺地板（与随机生成占位规则一致）。

@export_group("Design TileMap (指示层)")
## 主指示层（最先烘焙）；同格多图层时优先级相同则后读图层覆盖。
@export var design_tile_map_layer: TileMapLayer
## 额外指示层（在主层之后、自动收集子节点图层之前按顺序烘焙）。
@export var design_tile_map_layers_extra: Array[TileMapLayer] = []
## 自动收集本 Preset 节点下所有子级 `TileMapLayer` 并套用相同语义规则。
@export var auto_discover_design_tile_map_layers: bool = true
## 图块所属的 TileSet atlas source id（与同工程 DungeonGenerator 主层一致）。
@export var marker_source_id: int = 0
## 编辑器选图器：在 `design_tile_map_layer` 的 TileSet 上预览/点选另一 atlas source（如门图块 source 1）；不参与烘焙逻辑。
@export var marker_alt_source_id: int = 0
## 若门图块在**同一 TileMap** 但使用**另一 atlas source**（与主层 source 不同），在此填写该 source id。
## 为 -1 时表示门与 `marker_source_id` 使用同一 source（仅通过 atlas 坐标区分）。
@export var marker_door_source_id: int = -1
## **柱占位**（`marker_pillar_tiles`）所在的 TileSet **source id**。
## 为 -1 时与 `marker_source_id` 相同。若柱图块在独立 source（例如主语义用 0、柱用 **1**），必须在此填柱的 source，否则烘焙时在白名单检查阶段整格丢弃，永不会匹配柱语义。
@export var marker_pillar_source_id: int = -1
## **桶占位**（`marker_barrel_tiles`）atlas source；规则同柱独立 source。
@export var marker_barrel_source_id: int = -1

@export_group("语义 Bundle（可选）")
## 若赋值：烘焙时仅用资源内的图块语义数组（见同一 Resource 导出项），本体下方各 `marker_*_tiles` **不再生效**；
## 「门 atlas 所用的 source」仍以本节点的 `marker_door_source_id` / `marker_source_id` 为准；
## 「柱 / 桶 atlas 所用的 source」以本节点的 `marker_pillar_source_id` / `marker_barrel_source_id` 为准（-1 等同 `marker_source_id`）。
@export var marker_bundle: DungeonMarkerSemanticsConfig = null

@export_group("语义图块 (= 选取器配置)")
## 单层墙占位（整块区域除地板与实体外可不画，留空亦为墙）。
@export var marker_wall_tiles: Array[Vector2i] = []
## 透明墙：有碰撞、不挡玩家/敌人视野（`TileType.TRANSPARENT_WALL`）。
@export var marker_transparent_wall_tiles: Array[Vector2i] = []
## 反弹墙：阻挡移动并反射玩家子弹（`TileType.RICOCHET_WALL`）。
@export var marker_ricochet_wall_tiles: Array[Vector2i] = []
## 四类墙上/地板开关占位：**须与门共用同一 TileSet source**（effective = `marker_door_source_id`，为 -1 时等于 `marker_source_id`）；不可再单独画在另一套 source 上。
## `marker_wall_switch_face_up_*`：**烘焙为面向 `Facing.DOWN_FROM_NORTH`**——玩家在开关格**北面**可走格往南打。
@export var marker_wall_switch_face_up_tiles: Array[Vector2i] = []
## `marker_wall_switch_face_down_*`：**烘焙为 `Facing.UP_FROM_SOUTH`**——玩家在开关格**南面**可走格往北打。
@export var marker_wall_switch_face_down_tiles: Array[Vector2i] = []
## 「左」：占地板格，东面须为墙，须从西邻格往东打。
@export var marker_wall_switch_floor_west_appr_tiles: Array[Vector2i] = []
## 「右」：占地板格，西面须为墙，须从东邻格往西打。
@export var marker_wall_switch_floor_east_appr_tiles: Array[Vector2i] = []
## 后备语义：烘焙为 `UP_FROM_SOUTH`（与同组 `face_down` 近战逻辑相同）；可与上面四种混用。
@export var marker_wall_switch_tiles: Array[Vector2i] = []
## 可走地板。
@export var marker_floor_tiles: Array[Vector2i] = []
## 与同组门图块同源（`marker_door_source_id`）；可走、可回合内开关的活门。
@export var marker_door_tiles: Array[Vector2i] = []
## 与同组门图块同源：`marker_door_source_id`。**未激活门**：仍为可走格（地板），运行时登记为门并叠门图层，`DungeonGenerator.activate_inactive_door_at` 后可当普通门关使用。
##（当 `marker_bundle` 赋值时请以资源内同名数组为准）
@export var marker_inactive_door_tiles: Array[Vector2i] = []
## 可多格；仅用首格逻辑中心作出口占位。
@export var marker_exit_tiles: Array[Vector2i] = []
## 可多格；仅用首格作出生。
@export var marker_player_spawn_tiles: Array[Vector2i] = []
## 可多格。
@export var marker_enemy_tiles: Array[Vector2i] = []
## 可多格。
@export var marker_pillar_tiles: Array[Vector2i] = []
## 可多格：可燃桶占位（烘焙 `preset_barrel_cells`，运行时生成 `BreakableBarrel`）。
@export var marker_barrel_tiles: Array[Vector2i] = []
## 可多格：可燃液体占位（烘焙 `preset_liquid_cells`，运行时生成液体格）。
@export var marker_liquid_tiles: Array[Vector2i] = []
## 可多格：`DungeonMarkerSemanticsConfig.marker_abyss_tiles`。**深渊**占位；玩家与默认地面敌人难以通行，且不当作邻墙Bitmask的「地板」。
@export var marker_abyss_tiles: Array[Vector2i] = []
## 若为 true：**不生成**程序化石柱（关卡随机 pillar_count、`DungeonGenerator` 四面通孤立墙升格为可击破柱）。
## 「指示层预制柱」（`preset_pillar_cells`）**仍会生成**，不受此项影响。
@export var suppress_procedural_breakable_pillars: bool = false
## 若为 true，且关卡**没有**烘焙 `preset_enemy_cells`：**不散布随机敌人**。有预制敌方占位时不受影响。
@export var suppress_random_enemy_spawns: bool = false

@export_group("Camera（本 Preset 载入时生效）")
## 为 false 时：摄像机固定在关卡中心、不跟随玩家，且本关禁用鼠标平移与滚轮缩放（仍可用 R 以外的逻辑，但会拦截跟随切换与平移缩放）。
@export var camera_enable_control: bool = true
## 为 true 时：换层后沿用上一关已应用的缩放值，不再按新图尺寸重新计算「整图刚好入镜」的 zoom 下限（可能与大地图不同步，请自行把控关卡尺寸）。
@export var camera_maintain_zoom: bool = false

@export_group("备选：无 TileMap 时手写")
@export_range(4, 512, 1) var map_width: int = 50
@export_range(4, 512, 1) var map_height: int = 50
@export var floor_cells: Array[Vector2i] = []
@export var door_cells: Array[Vector2i] = []
## 与同组语义一致：占位为**地板上未激活的门**（与 `marker_inactive_door_tiles` 对应）。
@export var inactive_door_cells: Array[Vector2i] = []
@export var abyss_cells: Array[Vector2i] = []
## 备选手写：预设可燃液体格（与 `marker_liquid_tiles` 烘焙字段同源）。
@export var liquid_cells: Array[Vector2i] = []
## 备选手写：预制敌占位（与烘焙 `preset_enemy_cells` 同源）；也会并入 `floor_cells`（若尚不在地板上且非深渊）。
@export var enemy_cells: Array[Vector2i] = []
## 备选手写：预制可击破柱占位（与烘焙 `preset_pillar_cells` 同源）；也会并入 `floor_cells`（若尚不在地板上且非深渊）。
@export var pillar_cells: Array[Vector2i] = []
## 备选手写：预制桶占位（与烘焙 `preset_barrel_cells` 同源）。
@export var barrel_cells: Array[Vector2i] = []
@export var switch_cells: Array[Vector2i] = []
## 与 `switch_cells` 逐项对应；值为 `GridWallSwitch.Facing`（0=`UP_FROM_SOUTH`… 1=`DOWN_FROM_NORTH`… 2=`APPROACH_WEST_HIT_EAST` 3=`APPROACH_EAST_HIT_WEST`）。留空或越界项视为 0。东西向开关格会自动写入 `floor_cells`。
@export var switch_cell_facings: Array[int] = []
@export var open_door_cells: Array[Vector2i] = []
@export var player_spawn_pos: Vector2i = Vector2i(-1, -1)
@export var exit_pos: Vector2i = Vector2i(-1, -1)


func build_layout_data() -> Dictionary:
	var design_layers := _collect_design_tile_map_layers()
	if not design_layers.is_empty():
		var baked := _bake_from_design_tile_maps(design_layers)
		if not baked.is_empty():
			_merge_manual_switch_cells_into_layout(baked)
			_merge_manual_abyss_cells_into_layout(baked)
			_merge_manual_liquid_cells_into_layout(baked)
			_merge_manual_preset_actors_into_layout(baked)
			return baked
	return _legacy_manual_dictionary()


func _merge_manual_preset_actors_into_layout(baked: Dictionary) -> void:
	## 有 TileMap 时仍可合并「备选手写」的敌/柱列表（与 _legacy 行为一致）。
	_append_preset_cells_and_floors(baked, "preset_enemy_cells", enemy_cells)
	_append_preset_cells_and_floors(baked, "preset_pillar_cells", pillar_cells)
	_append_preset_cells_and_floors(baked, "preset_barrel_cells", barrel_cells)


func _append_preset_cells_and_floors(baked: Dictionary, key: String, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var arr_var: Variant = baked.get(key)
	if arr_var is not Array:
		baked[key] = []
		arr_var = baked[key]
	var out_arr: Array = arr_var
	var floor_var: Variant = baked.get("floor_cells")
	if floor_var is not Array:
		baked["floor_cells"] = []
		floor_var = baked["floor_cells"]
	var floor_out: Array = floor_var as Array
	var abyss_var: Variant = baked.get("abyss_cells", [])
	var abyss_arr: Array = abyss_var if abyss_var is Array else []
	for item in cells:
		if not (item is Vector2i):
			continue
		var v: Vector2i = item as Vector2i
		if out_arr.find(v) < 0:
			out_arr.append(v)
		if abyss_arr.find(v) >= 0:
			continue
		if floor_out.find(v) < 0:
			floor_out.append(v)


func _merge_manual_liquid_cells_into_layout(baked: Dictionary) -> void:
	if liquid_cells.is_empty():
		return
	var arr_var: Variant = baked.get("preset_liquid_cells")
	if arr_var is not Array:
		baked["preset_liquid_cells"] = []
		arr_var = baked["preset_liquid_cells"]
	var out_arr: Array = arr_var
	for item in liquid_cells:
		if item is Vector2i:
			var lc: Vector2i = item as Vector2i
			if out_arr.find(lc) < 0:
				out_arr.append(lc)


func _merge_manual_abyss_cells_into_layout(baked: Dictionary) -> void:
	if abyss_cells.is_empty():
		return
	var arr_var: Variant = baked.get("abyss_cells")
	if arr_var is not Array:
		baked["abyss_cells"] = []
		arr_var = baked["abyss_cells"]
	var out_arr: Array = arr_var
	for item in abyss_cells:
		if item is Vector2i:
			var ac: Vector2i = item as Vector2i
			if out_arr.find(ac) < 0:
				out_arr.append(ac)
	var floor_var: Variant = baked.get("floor_cells")
	if not floor_var is Array:
		return
	var floor_arr: Array = floor_var as Array
	for item2 in abyss_cells:
		if not (item2 is Vector2i):
			continue
		var erase_pos: Vector2i = item2 as Vector2i
		var ix := floor_arr.find(erase_pos)
		if ix >= 0:
			floor_arr.remove_at(ix)


func _merge_manual_switch_cells_into_layout(baked: Dictionary) -> void:
	## 指示层烘焙后仍合并「备选：手写」里的 switch_cells……图块坐标须与门同属**门源** TileSet（参见 `PresetFloorLayout`）。
	if switch_cells.is_empty():
		return
	var arr_var: Variant = baked.get("switch_cells")
	if not arr_var is Array:
		baked["switch_cells"] = []
		arr_var = baked["switch_cells"]
	var out_arr: Array = arr_var
	var floor_var: Variant = baked.get("floor_cells")
	if not floor_var is Array:
		baked["floor_cells"] = []
		floor_var = baked["floor_cells"]
	var floor_out: Array = floor_var
	for item in switch_cells:
		if item is Vector2i:
			var c: Vector2i = item as Vector2i
			if out_arr.find(c) < 0:
				out_arr.append(c)
	var specs_var: Variant = baked.get("switch_specs")
	if not specs_var is Array:
		baked["switch_specs"] = []
		specs_var = baked["switch_specs"]
	var specs_out: Array = specs_var
	var has_pos := {}
	for dict_item in specs_out:
		if dict_item is Dictionary:
			var p: Variant = (dict_item as Dictionary).get("pos", null)
			if p is Vector2i:
				has_pos[p as Vector2i] = true
	for idx in range(switch_cells.size()):
		var item2: Variant = switch_cells[idx]
		if not (item2 is Vector2i):
			continue
		var c2: Vector2i = item2 as Vector2i
		var f_def: int = GridWallSwitch.Facing.UP_FROM_SOUTH
		if idx < switch_cell_facings.size():
			f_def = int(switch_cell_facings[idx])
		if not has_pos.has(c2):
			specs_out.append({"pos": c2, "facing": f_def})
			has_pos[c2] = true
		if f_def == GridWallSwitch.Facing.APPROACH_WEST_HIT_EAST \
				or f_def == GridWallSwitch.Facing.APPROACH_EAST_HIT_WEST:
			if floor_out.find(c2) < 0:
				floor_out.append(c2)


func _legacy_manual_dictionary() -> Dictionary:
	var manual_specs: Array = []
	var floor_dup: Array[Vector2i] = floor_cells.duplicate()
	for i in range(switch_cells.size()):
		var sv: Variant = switch_cells[i]
		if not (sv is Vector2i):
			continue
		var cc: Vector2i = sv as Vector2i
		var f_manual: int = GridWallSwitch.Facing.UP_FROM_SOUTH
		if i < switch_cell_facings.size():
			f_manual = int(switch_cell_facings[i])
		manual_specs.append({"pos": cc, "facing": f_manual})
		if f_manual == GridWallSwitch.Facing.APPROACH_WEST_HIT_EAST \
				or f_manual == GridWallSwitch.Facing.APPROACH_EAST_HIT_WEST:
			if floor_dup.find(cc) < 0:
				floor_dup.append(cc)
	for apreset in enemy_cells:
		if not (apreset is Vector2i):
			continue
		var ae: Vector2i = apreset as Vector2i
		if abyss_cells.find(ae) >= 0:
			continue
		if floor_dup.find(ae) < 0:
			floor_dup.append(ae)
	for apillar in pillar_cells:
		if not (apillar is Vector2i):
			continue
		var ap: Vector2i = apillar as Vector2i
		if abyss_cells.find(ap) >= 0:
			continue
		if floor_dup.find(ap) < 0:
			floor_dup.append(ap)
	for abarrel in barrel_cells:
		if not (abarrel is Vector2i):
			continue
		var ab: Vector2i = abarrel as Vector2i
		if abyss_cells.find(ab) >= 0:
			continue
		if floor_dup.find(ab) < 0:
			floor_dup.append(ab)
	return {
		"map_width": map_width,
		"map_height": map_height,
		"floor_cells": floor_dup,
		"door_cells": door_cells.duplicate(),
		"inactive_door_cells": inactive_door_cells.duplicate(),
		"switch_cells": switch_cells.duplicate(),
		"switch_specs": manual_specs,
		"open_door_cells": open_door_cells.duplicate(),
		"wall_switch_marker_atlas_source_id": marker_door_source_id if marker_door_source_id >= 0 else marker_source_id,
		"player_spawn_pos": player_spawn_pos,
		"exit_pos": exit_pos,
		"preset_enemy_cells": enemy_cells.duplicate(),
		"preset_pillar_cells": pillar_cells.duplicate(),
		"preset_barrel_cells": barrel_cells.duplicate(),
		"suppress_procedural_breakable_pillars": suppress_procedural_breakable_pillars,
		"suppress_random_enemy_spawns": suppress_random_enemy_spawns,
		"camera_enable_control": camera_enable_control,
		"camera_maintain_zoom": camera_maintain_zoom,
		"abyss_cells": abyss_cells.duplicate(),
		"preset_liquid_cells": liquid_cells.duplicate(),
	}


func _marker_has(markers: Array[Vector2i], atlas: Vector2i) -> bool:
	for item in markers:
		if item is Vector2i and item == atlas:
			return true
	return false


func _sem_wall() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_wall_tiles
	return marker_wall_tiles


func _sem_transparent_wall() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_transparent_wall_tiles
	return marker_transparent_wall_tiles


func _sem_ricochet_wall() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_ricochet_wall_tiles
	return marker_ricochet_wall_tiles


func _sem_floor() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_floor_tiles
	return marker_floor_tiles


func _sem_door() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_door_tiles
	return marker_door_tiles


func _sem_inactive_door() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_inactive_door_tiles
	return marker_inactive_door_tiles


func _sem_exit() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_exit_tiles
	return marker_exit_tiles


func _sem_spawn() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_player_spawn_tiles
	return marker_player_spawn_tiles


func _sem_enemy() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_enemy_tiles
	return marker_enemy_tiles


func _sem_pillar() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_pillar_tiles
	return marker_pillar_tiles


func _sem_barrel() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_barrel_tiles
	return marker_barrel_tiles


func _sem_liquid() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_liquid_tiles
	return marker_liquid_tiles


func _sem_abyss() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_abyss_tiles
	return marker_abyss_tiles


func _sem_wall_switch_face_up() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_wall_switch_face_up_tiles
	return marker_wall_switch_face_up_tiles


func _sem_wall_switch_face_down() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_wall_switch_face_down_tiles
	return marker_wall_switch_face_down_tiles


func _sem_wall_switch_floor_west_appr() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_wall_switch_floor_west_appr_tiles
	return marker_wall_switch_floor_west_appr_tiles


func _sem_wall_switch_floor_east_appr() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_wall_switch_floor_east_appr_tiles
	return marker_wall_switch_floor_east_appr_tiles


func _sem_wall_switch_legacy_fallback() -> Array[Vector2i]:
	if marker_bundle != null:
		return marker_bundle.marker_wall_switch_tiles
	return marker_wall_switch_tiles


func _wall_switch_facing_for_atlas(source_id: int, atlas: Vector2i) -> int:
	var door_src: int = marker_door_source_id if marker_door_source_id >= 0 else marker_source_id
	## 与活门 / 未激活门一致：开关图块必须放在**门所用**的 TileSet source 上（不再接受主 `marker_source_id` 上分置一套开关图）。
	if source_id != door_src:
		return -1
	if _marker_has(_sem_wall_switch_face_up(), atlas):
		## 「face_up」图块组映射为北侧走近（`DOWN_FROM_NORTH`），与墙顶/南边开关常用摆法一致；勿与美术文字「朝上」死记挂钩。
		return GridWallSwitch.Facing.DOWN_FROM_NORTH
	if _marker_has(_sem_wall_switch_face_down(), atlas):
		## 「face_down」组 → `UP_FROM_SOUTH`（南侧走近）。
		return GridWallSwitch.Facing.UP_FROM_SOUTH
	if _marker_has(_sem_wall_switch_floor_west_appr(), atlas):
		return GridWallSwitch.Facing.APPROACH_WEST_HIT_EAST
	if _marker_has(_sem_wall_switch_floor_east_appr(), atlas):
		return GridWallSwitch.Facing.APPROACH_EAST_HIT_WEST
	if _marker_has(_sem_wall_switch_legacy_fallback(), atlas):
		return GridWallSwitch.Facing.UP_FROM_SOUTH
	return -1


func _classify_cell(source_id: int, atlas: Vector2i) -> int:
	## 返回值越大优先越高（重合时）。
	var door_src: int = marker_door_source_id if marker_door_source_id >= 0 else marker_source_id
	var pillar_src: int = marker_pillar_source_id if marker_pillar_source_id >= 0 else marker_source_id
	var barrel_src: int = marker_barrel_source_id if marker_barrel_source_id >= 0 else marker_source_id
	## 柱单独占一个 atlas source 时，不能走下方「仅 marker + 门源」白名单：否则会先被判无效，轮不到 `_sem_pillar()`。
	if pillar_src != marker_source_id and pillar_src != door_src:
		if source_id == pillar_src:
			if _marker_has(_sem_pillar(), atlas):
				return 50
			return 0
	## 桶独立 source（与柱同理）。
	if barrel_src != marker_source_id and barrel_src != door_src:
		if source_id == barrel_src:
			if _marker_has(_sem_barrel(), atlas):
				return 47
			return 0
	if source_id != marker_source_id and source_id != door_src:
		return 0
	if _marker_has(_sem_spawn(), atlas):
		return 70
	if _marker_has(_sem_enemy(), atlas):
		return 60
	if _marker_has(_sem_pillar(), atlas):
		return 50
	if _marker_has(_sem_liquid(), atlas):
		return 49
	if _marker_has(_sem_barrel(), atlas):
		return 47
	if _marker_has(_sem_exit(), atlas):
		return 40
	if _wall_switch_facing_for_atlas(source_id, atlas) >= 0:
		return 39
	if source_id == door_src and _marker_has(_sem_inactive_door(), atlas):
		return 35
	if source_id == door_src and _marker_has(_sem_door(), atlas):
		return 30
	if source_id == marker_source_id and _marker_has(_sem_ricochet_wall(), atlas):
		return 22
	if source_id == marker_source_id and _marker_has(_sem_transparent_wall(), atlas):
		return 21
	if source_id == marker_source_id and _marker_has(_sem_wall(), atlas):
		return 20
	if source_id == marker_source_id and _marker_has(_sem_abyss(), atlas):
		return 15
	if source_id == marker_source_id and _marker_has(_sem_floor(), atlas):
		return 10
	return 0


func _collect_design_tile_map_layers() -> Array[TileMapLayer]:
	var out: Array[TileMapLayer] = []
	var seen: Dictionary = {}

	var add_layer := func(layer: TileMapLayer) -> void:
		if layer == null or not is_instance_valid(layer):
			return
		var layer_id: int = layer.get_instance_id()
		if seen.has(layer_id):
			return
		seen[layer_id] = true
		out.append(layer)

	if design_tile_map_layer != null and is_instance_valid(design_tile_map_layer):
		add_layer.call(design_tile_map_layer)
	for extra in design_tile_map_layers_extra:
		if extra is TileMapLayer:
			add_layer.call(extra)
	if auto_discover_design_tile_map_layers:
		for discovered in _discover_tile_map_layers_under_self():
			add_layer.call(discovered)
	return out


func _discover_tile_map_layers_under_self() -> Array[TileMapLayer]:
	var found: Array[TileMapLayer] = []
	_gather_tile_map_layers_recursive(self, found)
	return found


func _gather_tile_map_layers_recursive(node: Node, out: Array[TileMapLayer]) -> void:
	for child in node.get_children():
		if child is TileMapLayer:
			out.append(child as TileMapLayer)
		_gather_tile_map_layers_recursive(child, out)


func _bake_from_design_tile_maps(layers: Array[TileMapLayer]) -> Dictionary:
	var any_used := false
	for layer in layers:
		if not layer.get_used_cells().is_empty():
			any_used = true
			break
	if not any_used:
		push_warning(
			"PresetFloorLayout: 所有指示 TileMapLayer 均无图块（共 %d 层），回退手写数据。"
			% layers.size()
		)
		return {}

	var bounds := {
		"min_x": 2147483647,
		"max_x": -2147483648,
		"min_y": 2147483647,
		"max_y": -2147483648,
	}
	var cells_by_kind: Dictionary = {}  ## Vector2i → int priority kind
	var switch_faces_global: Dictionary = {}  ## Vector2i（全局格）→ int Facing
	var switch_atlas_global: Dictionary = {}  ## Vector2i（全局格）→ Vector2i atlas

	for layer in layers:
		_accumulate_cells_from_design_layer(
			layer,
			cells_by_kind,
			switch_faces_global,
			switch_atlas_global,
			bounds
		)

	if cells_by_kind.is_empty():
		return {}

	var min_x: int = int(bounds["min_x"])
	var max_x: int = int(bounds["max_x"])
	var min_y: int = int(bounds["min_y"])
	var max_y: int = int(bounds["max_y"])
	var origin := Vector2i(min_x, min_y)
	var w: int = maxi(4, max_x - min_x + 1)
	var h: int = maxi(4, max_y - min_y + 1)

	var floor_accum: Dictionary = {}
	var doors_out: Array[Vector2i] = []
	var inactive_out: Array[Vector2i] = []
	var switch_out: Array[Vector2i] = []
	var open_doors_out: Array[Vector2i] = []
	var enemies_out: Array[Vector2i] = []
	var pillars_out: Array[Vector2i] = []
	var barrels_out: Array[Vector2i] = []
	var liquids_out: Array[Vector2i] = []
	var abyss_out: Array[Vector2i] = []
	var transparent_walls_out: Array[Vector2i] = []
	var ricochet_walls_out: Array[Vector2i] = []

	var spawn_norm := Vector2i(-1, -1)
	var exit_norm := Vector2i(-1, -1)

	for cell_key in cells_by_kind.keys():
		var cell_global: Vector2i = cell_key as Vector2i
		var n: Vector2i = cell_global - origin
		var prio_val: int = int(cells_by_kind[cell_global])
		match prio_val:
			20:
				pass
			21:
				if not transparent_walls_out.has(n):
					transparent_walls_out.append(n)
				floor_accum.erase(n)
			22:
				if not ricochet_walls_out.has(n):
					ricochet_walls_out.append(n)
				floor_accum.erase(n)
			15:
				if not abyss_out.has(n):
					abyss_out.append(n)
			39:
				if not switch_out.has(n):
					switch_out.append(n)
				var sface_sw: int = int(switch_faces_global.get(cell_global, GridWallSwitch.Facing.UP_FROM_SOUTH))
				if sface_sw == GridWallSwitch.Facing.APPROACH_WEST_HIT_EAST \
						or sface_sw == GridWallSwitch.Facing.APPROACH_EAST_HIT_WEST:
					floor_accum[n] = true
			35:
				if not inactive_out.has(n):
					inactive_out.append(n)
				floor_accum[n] = true
			10:
				floor_accum[n] = true
			30:
				floor_accum[n] = true
				doors_out.append(n)
			40:
				floor_accum[n] = true
				if exit_norm == Vector2i(-1, -1):
					exit_norm = n
			70:
				floor_accum[n] = true
				if spawn_norm == Vector2i(-1, -1):
					spawn_norm = n
			60:
				floor_accum[n] = true
				if not enemies_out.has(n):
					enemies_out.append(n)
			50:
				floor_accum[n] = true
				if not pillars_out.has(n):
					pillars_out.append(n)
			49:
				floor_accum[n] = true
				if not liquids_out.has(n):
					liquids_out.append(n)
			47:
				floor_accum[n] = true
				if not barrels_out.has(n):
					barrels_out.append(n)
			_:
				pass

	if spawn_norm != Vector2i(-1, -1):
		floor_accum[spawn_norm] = true
	if exit_norm != Vector2i(-1, -1):
		floor_accum[exit_norm] = true
	for d in doors_out:
		floor_accum[d] = true
	for e in enemies_out:
		floor_accum[e] = true
	for p in pillars_out:
		floor_accum[p] = true
	for liq in liquids_out:
		floor_accum[liq] = true
	for br in barrels_out:
		floor_accum[br] = true

	var floor_arr: Array[Vector2i] = []
	for k in floor_accum.keys():
		floor_arr.append(k as Vector2i)

	var switch_specs: Array = []
	for n_sw in switch_out:
		var n_norm: Vector2i = n_sw as Vector2i
		var cell_glob: Vector2i = n_norm + origin
		switch_specs.append({
			"pos": n_norm,
			"facing": int(switch_faces_global.get(cell_glob, 0)),
			"atlas": switch_atlas_global.get(cell_glob, Vector2i.ZERO),
		})

	var door_marker_atlas_eff: int = marker_door_source_id if marker_door_source_id >= 0 else marker_source_id

	if not abyss_out.is_empty():
		for abyss_local in abyss_out:
			var aa: Vector2i = abyss_local
			floor_accum.erase(aa)

	var out_dict := {
		"map_width": w,
		"map_height": h,
		"floor_cells": floor_arr,
		"door_cells": doors_out.duplicate(),
		"inactive_door_cells": inactive_out.duplicate(),
		"switch_cells": switch_out.duplicate(),
		"switch_specs": switch_specs,
		"open_door_cells": open_doors_out.duplicate(),
		"wall_switch_marker_atlas_source_id": door_marker_atlas_eff,
		"player_spawn_pos": spawn_norm,
		"exit_pos": exit_norm,
		"preset_enemy_cells": enemies_out.duplicate(),
		"preset_pillar_cells": pillars_out.duplicate(),
		"preset_liquid_cells": liquids_out.duplicate(),
		"preset_barrel_cells": barrels_out.duplicate(),
		"suppress_procedural_breakable_pillars": suppress_procedural_breakable_pillars,
		"suppress_random_enemy_spawns": suppress_random_enemy_spawns,
		"camera_enable_control": camera_enable_control,
		"camera_maintain_zoom": camera_maintain_zoom,
		"abyss_cells": abyss_out.duplicate(),
		"transparent_wall_cells": transparent_walls_out.duplicate(),
		"ricochet_wall_cells": ricochet_walls_out.duplicate(),
	}
	return out_dict


func _accumulate_cells_from_design_layer(
	layer: TileMapLayer,
	cells_by_kind: Dictionary,
	switch_faces_global: Dictionary,
	switch_atlas_global: Dictionary,
	bounds: Dictionary
) -> void:
	var used: Array[Vector2i] = layer.get_used_cells()
	for cell in used:
		var sid := layer.get_cell_source_id(cell)
		if sid < 0:
			continue
		var atlas: Vector2i = layer.get_cell_atlas_coords(cell)
		var prio := _classify_cell(sid, atlas)
		if prio == 0:
			var door_src: int = marker_door_source_id if marker_door_source_id >= 0 else marker_source_id
			push_warning(
				"PresetFloorLayout [%s]: (%d,%d) source_id=%d（主=%d 门源=%d）atlas (%d,%d) 未匹配语义，已忽略。"
				% [layer.name, cell.x, cell.y, sid, marker_source_id, door_src, atlas.x, atlas.y]
			)
			continue

		bounds["min_x"] = mini(int(bounds["min_x"]), cell.x)
		bounds["max_x"] = maxi(int(bounds["max_x"]), cell.x)
		bounds["min_y"] = mini(int(bounds["min_y"]), cell.y)
		bounds["max_y"] = maxi(int(bounds["max_y"]), cell.y)

		var prev_prio: int = int(cells_by_kind.get(cell, 0))
		if prio >= prev_prio:
			cells_by_kind[cell] = prio
			if prio == 39:
				switch_faces_global[cell] = _wall_switch_facing_for_atlas(sid, atlas)
				switch_atlas_global[cell] = atlas
