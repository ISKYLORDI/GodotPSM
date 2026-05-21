class_name LevelFlowConfig
extends Resource

@export_range(1, 999, 1) var total_floors: int = 10
@export var restart_after_final: bool = true
@export var floor_specs: Array[FloorSpec] = []


func get_floor_spec_for_index(floor_index_1_based: int) -> FloorSpec:
	if floor_index_1_based <= 0:
		return null
	var idx: int = floor_index_1_based - 1
	if idx < 0 or idx >= floor_specs.size():
		return null
	return floor_specs[idx]
