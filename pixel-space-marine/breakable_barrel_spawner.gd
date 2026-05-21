class_name BreakableBarrelSpawner
extends Node

@export_group("References")
@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
@export var world_path: NodePath = NodePath("")
@export var turn_controller_path: NodePath = NodePath("../TurnController")
@export var level_flow_path: NodePath = NodePath("../LevelFlowController")

@export_group("Barrel")
@export var barrel_scene: PackedScene

var dungeon_generator: DungeonGenerator = null
var world: Node2D = null
var turn_controller: TurnController = null
var level_flow_controller: LevelFlowController = null
var _spawned: Array[BreakableBarrel] = []
## 上一楼层经出口「掉下去」的木桶数；在下一层 `spawn_for_floor` 时于玩家周围一圈最多生成 8 个。
var _pending_exit_carryover_barrels: int = 0

const _EXIT_CARRYOVER_RING_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]


func _ready() -> void:
	add_to_group("breakable_barrel_spawner")
	_resolve_references()
	_connect_signals()
	call_deferred("_spawn_after_ready")


func clear_barrels() -> void:
	for b in _spawned:
		if b != null and is_instance_valid(b):
			b.queue_free()
	_spawned.clear()
	if turn_controller != null:
		turn_controller.request_occupancy_refresh()


func spawn_for_floor() -> void:
	_resolve_references()
	if dungeon_generator == null or world == null:
		return
	clear_barrels()
	if dungeon_generator.has_preset_barrels_layout():
		for gp in dungeon_generator.get_preset_barrel_cells():
			if dungeon_generator.exit_pos == gp:
				continue
			if dungeon_generator._door_set.has(gp):
				continue
			if dungeon_generator.get_tile(gp) != DungeonGenerator.TileType.FLOOR:
				continue
			if turn_controller != null and turn_controller.is_cell_occupied(gp):
				continue
			var barrel := _instantiate_barrel()
			if barrel == null:
				continue
			world.add_child(barrel)
			barrel.bind_grid_position(gp)
			_spawned.append(barrel)
	if turn_controller != null:
		turn_controller.request_occupancy_refresh()
	_spawn_exit_carryover_ring_around_player()


func register_barrel_sent_through_exit() -> void:
	_pending_exit_carryover_barrels += 1


func _cell_ok_for_spawned_barrel(gp: Vector2i) -> bool:
	if dungeon_generator == null:
		return false
	if dungeon_generator.exit_pos != Vector2i(-1, -1) and gp == dungeon_generator.exit_pos:
		return false
	if dungeon_generator._door_set.has(gp):
		return false
	if dungeon_generator.get_tile(gp) != DungeonGenerator.TileType.FLOOR:
		return false
	if turn_controller != null and turn_controller.is_cell_occupied(gp):
		return false
	return true


func _spawn_exit_carryover_ring_around_player() -> void:
	if dungeon_generator == null or world == null or turn_controller == null:
		return
	var want: int = mini(_pending_exit_carryover_barrels, 8)
	_pending_exit_carryover_barrels = 0
	if want <= 0:
		return
	var p: Node = turn_controller.player
	if p == null or not p.has_method("get"):
		return
	var pg_var: Variant = p.get("grid_pos")
	if not (pg_var is Vector2i):
		return
	var center: Vector2i = pg_var as Vector2i
	var offs: Array[Vector2i] = _EXIT_CARRYOVER_RING_OFFSETS.duplicate()
	offs.shuffle()
	var placed: int = 0
	for d: Vector2i in offs:
		if placed >= want:
			break
		var c: Vector2i = center + d
		if not _cell_ok_for_spawned_barrel(c):
			continue
		var barrel := _instantiate_barrel()
		if barrel == null:
			continue
		world.add_child(barrel)
		barrel.bind_grid_position(c)
		_spawned.append(barrel)
		placed += 1
	if turn_controller != null:
		turn_controller.request_occupancy_refresh()


func _instantiate_barrel() -> BreakableBarrel:
	if barrel_scene != null:
		var inst = barrel_scene.instantiate()
		if inst is BreakableBarrel:
			return inst
		if inst != null:
			inst.queue_free()
	return BreakableBarrel.new()


func _spawn_after_ready() -> void:
	_resolve_references()
	if dungeon_generator == null or dungeon_generator.grid_map.is_empty():
		return
	spawn_for_floor()


func _on_dungeon_generated() -> void:
	call_deferred("spawn_for_floor")


func _connect_signals() -> void:
	if dungeon_generator == null:
		return
	if not dungeon_generator.generation_finished.is_connected(_on_dungeon_generated):
		dungeon_generator.generation_finished.connect(_on_dungeon_generated)
	## 不可再连接 `LevelFlowController.floor_changed`：`advance_floor()` 在 `generation_finished`
	## 之后又 emit `floor_changed`，会导致本帧 deferred **两次** `spawn_for_floor`；
	## 第二次会 `clear_barrels()` 清空刚生成的携带桶，并把已清零的 pending 再跑一遍。


func _resolve_references() -> void:
	if dungeon_generator == null and not dungeon_generator_path.is_empty():
		var d := get_node_or_null(dungeon_generator_path)
		if d is DungeonGenerator:
			dungeon_generator = d
	if dungeon_generator == null:
		var fd := get_tree().get_first_node_in_group("dungeon_generator")
		if fd is DungeonGenerator:
			dungeon_generator = fd
	if world == null and not world_path.is_empty():
		var w := get_node_or_null(world_path)
		if w is Node2D:
			world = w
	if world == null:
		var p := get_parent()
		if p is Node2D:
			world = p
	if turn_controller == null and not turn_controller_path.is_empty():
		var t := get_node_or_null(turn_controller_path)
		if t is TurnController:
			turn_controller = t
	if turn_controller == null:
		var ft := get_tree().get_first_node_in_group("turn_controller")
		if ft is TurnController:
			turn_controller = ft
	if level_flow_controller == null and not level_flow_path.is_empty():
		var lf := get_node_or_null(level_flow_path)
		if lf is LevelFlowController:
			level_flow_controller = lf
	if level_flow_controller == null:
		var lff := get_tree().get_first_node_in_group("level_flow_controller")
		if lff is LevelFlowController:
			level_flow_controller = lff
