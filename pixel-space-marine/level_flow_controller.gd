class_name LevelFlowController
extends Node

signal floor_changed(previous_floor: int, current_floor: int)

@export_group("References")
@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
@export_group("Flow")
@export var config: LevelFlowConfig
@export_range(1, 999, 1) var current_floor_index: int = 1

var dungeon_generator: DungeonGenerator = null


func _ready() -> void:
	add_to_group("level_flow_controller")
	_resolve_references()
	_normalize_floor_index()
	# 延迟一帧：确保 DungeonGenerator 已入树/入组，所有子系统 _ready 顺序差异下也能稳定解析。
	call_deferred("_run_initial_floor_layout")


func _run_initial_floor_layout() -> void:
	_resolve_references()
	if dungeon_generator == null:
		push_warning("LevelFlowController: 未解析到 DungeonGenerator（检查 GameSystem 上 dungeon_generator_path）。")
		return
	## 必须从「当前楼层索引」载入布局：`DungeonGenerator.generate_on_ready` 会先填满网格，
	## 若此处仅在 grid 非空时跳过，则从第 N 关开局时会永远停在程序化迷宫而非 FloorSpec 指定关卡。
	_apply_current_floor_layout()


func advance_floor() -> void:
	_resolve_references()
	if dungeon_generator == null:
		return
	var previous_floor := current_floor_index
	current_floor_index += 1
	_apply_final_floor_policy()
	_apply_current_floor_layout()
	floor_changed.emit(previous_floor, current_floor_index)


## 玩家死亡等：不增加楼层索引，仅按当前 `FloorSpec` 重载本关（与 `advance_floor` 区分）。
func reload_current_floor() -> void:
	_resolve_references()
	if dungeon_generator == null:
		return
	var previous_floor := current_floor_index
	_apply_current_floor_layout()
	floor_changed.emit(previous_floor, current_floor_index)


func restart_flow() -> void:
	var previous_floor := current_floor_index
	current_floor_index = 1
	_apply_current_floor_layout()
	floor_changed.emit(previous_floor, current_floor_index)


func apply_current_floor() -> void:
	_apply_current_floor_layout()


func get_current_floor_spec() -> FloorSpec:
	if config == null:
		return null
	return config.get_floor_spec_for_index(current_floor_index)


func _apply_current_floor_layout() -> void:
	if dungeon_generator == null:
		return
	var spec := get_current_floor_spec()
	if spec != null and spec.uses_scene_layout():
		if dungeon_generator.has_method("load_from_scene"):
			dungeon_generator.call("load_from_scene", spec.layout_scene)
			return
	dungeon_generator.generate_dungeon()


func _apply_final_floor_policy() -> void:
	if config == null:
		return
	var total := maxi(1, config.total_floors)
	if current_floor_index <= total:
		return
	if config.restart_after_final:
		current_floor_index = 1
	else:
		current_floor_index = total


func _normalize_floor_index() -> void:
	if config == null:
		current_floor_index = maxi(1, current_floor_index)
		return
	var total := maxi(1, config.total_floors)
	current_floor_index = clampi(current_floor_index, 1, total)


func _resolve_references() -> void:
	if dungeon_generator == null and not dungeon_generator_path.is_empty():
		var dg_node := get_node_or_null(dungeon_generator_path)
		if dg_node is DungeonGenerator:
			dungeon_generator = dg_node
	if dungeon_generator == null:
		var found := get_tree().get_first_node_in_group("dungeon_generator")
		if found is DungeonGenerator:
			dungeon_generator = found
