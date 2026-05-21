class_name DungeonMarkerSemanticsConfig
extends Resource
## `PresetFloorLayout` 可选挂载：改一份资源可同时影响所有使用该资源的预设关卡。


@export_subgroup("语义图块（与 marker_source_id / marker_door_source_id 配对使用）")
## 「门 + 墙上/地板开关」图块须放在**门源**（effective door source = `marker_door_source_id`，-1 时用 `marker_source_id`）同一 atlas 里；开关不再使用独立 source。
@export var marker_wall_tiles: Array[Vector2i] = []
@export var marker_transparent_wall_tiles: Array[Vector2i] = []
@export var marker_ricochet_wall_tiles: Array[Vector2i] = []
## 「face_up-*」占位墙格：**烘焙 `Facing.DOWN_FROM_NORTH`**（玩家在开关**北侧**可走格往南打）。
@export var marker_wall_switch_face_up_tiles: Array[Vector2i] = []
## 「face_down-*」→ **`Facing.UP_FROM_SOUTH`**（**南侧**走近往北打）。
@export var marker_wall_switch_face_down_tiles: Array[Vector2i] = []
## 「左」：占地板格，东面须为墙，须从西邻格往东攻击触发。
@export var marker_wall_switch_floor_west_appr_tiles: Array[Vector2i] = []
## 「右」：占地板格，西面须为墙，须从东邻格往西攻击触发。
@export var marker_wall_switch_floor_east_appr_tiles: Array[Vector2i] = []
## 后备：**烘焙 `UP_FROM_SOUTH`**（与 face_down-* 近战逻辑）；若仅用本数组则全部按该语义。
@export var marker_wall_switch_tiles: Array[Vector2i] = []
@export var marker_floor_tiles: Array[Vector2i] = []
@export var marker_door_tiles: Array[Vector2i] = []
## 与同组门图块同源（`marker_door_source_id`）；格子在地图中为墙，不产生可开关门实体。
@export var marker_inactive_door_tiles: Array[Vector2i] = []
@export var marker_exit_tiles: Array[Vector2i] = []
@export var marker_player_spawn_tiles: Array[Vector2i] = []
@export var marker_enemy_tiles: Array[Vector2i] = []
@export var marker_pillar_tiles: Array[Vector2i] = []
## 桶占位（烘焙 `preset_barrel_cells`）。
@export var marker_barrel_tiles: Array[Vector2i] = []
## 可燃液罐占位（地图烘焙 `preset_liquid_cells`，楼层生成后由 TurnController 实例化）。
@export var marker_liquid_tiles: Array[Vector2i] = []
## 深渊：不可行走的「坑」图层格；运行时映射为 `DungeonGenerator.TileType.ABYSS`。
@export var marker_abyss_tiles: Array[Vector2i] = []
