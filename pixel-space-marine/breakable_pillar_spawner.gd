class_name BreakablePillarSpawner
extends Node

@export_group("References")
@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
## 为空时使用父节点（主场景根）作为柱子父级。
@export var world_path: NodePath = NodePath("")
@export var turn_controller_path: NodePath = NodePath("../TurnController")
@export var level_flow_path: NodePath = NodePath("../LevelFlowController")

@export_group("Pillar")
@export var pillar_scene: PackedScene
@export_range(0, 80, 1) var pillar_count: int = 8
@export_range(1, 400, 1) var placement_attempts: int = 200
@export_range(0, 20, 1) var min_distance_to_player_spawn: int = 4
## 距房间边缘的最小格数（0 = 不限制）
@export_range(0, 8, 1) var min_room_edge_distance: int = 1

var dungeon_generator: DungeonGenerator = null
var world: Node2D = null
var turn_controller: TurnController = null
var level_flow_controller: LevelFlowController = null
var _spawned: Array[BreakablePillar] = []


func _ready() -> void:
	_resolve_references()
	_connect_signals()
	call_deferred("_spawn_after_ready")


func clear_pillars() -> void:
	for pillar in _spawned:
		if pillar != null and is_instance_valid(pillar):
			pillar.queue_free()
	_spawned.clear()
	if turn_controller != null:
		turn_controller.request_occupancy_refresh()


func spawn_for_floor() -> void:
	_resolve_references()
	if dungeon_generator == null or world == null:
		return
	clear_pillars()

	## 指示层 `preset_pillar_cells`：**不**应用 `min_room_edge_distance` / `min_distance_to_player_spawn`（仅用于下方随机柱）。
	if dungeon_generator.has_preset_pillar_layout():
		for gp in dungeon_generator.get_preset_pillar_cells():
			if dungeon_generator.exit_pos == gp:
				continue
			if dungeon_generator._door_set.has(gp):
				continue
			if dungeon_generator.get_tile(gp) != DungeonGenerator.TileType.FLOOR:
				continue
			if turn_controller != null and turn_controller.is_cell_occupied(gp):
				continue
			var pillar_a := _instantiate_pillar()
			if pillar_a == null:
				continue
			world.add_child(pillar_a)
			pillar_a.bind_grid_position(gp)
			_spawned.append(pillar_a)
	elif not dungeon_generator.layout_suppresses_procedural_breakable_pillars():
		var player_grid := _player_grid()
		var used: Dictionary = {}
		var placed := 0
		var attempts := 0
		while placed < pillar_count and attempts < placement_attempts:
			attempts += 1
			var gp := dungeon_generator.get_random_floor_cell()
			if used.has(gp):
				continue
			if gp == dungeon_generator.exit_pos:
				continue
			if dungeon_generator._door_set.has(gp):
				continue
			if dungeon_generator._corridor_floor_set.has(gp):
				continue
			if not dungeon_generator._room_floor_set.has(gp):
				continue
			if not _is_far_enough_from_room_edge(gp):
				continue
			if gp == player_grid:
				continue
			if gp.distance_to(player_grid) < float(min_distance_to_player_spawn):
				continue
			if turn_controller != null and turn_controller.is_cell_occupied(gp):
				continue
			used[gp] = true
			var pillar_b := _instantiate_pillar()
			if pillar_b == null:
				continue
			world.add_child(pillar_b)
			pillar_b.bind_grid_position(gp)
			_spawned.append(pillar_b)
			placed += 1

	if not dungeon_generator.layout_suppresses_procedural_breakable_pillars():
		_spawn_four_way_wall_entity_pillars()

	if turn_controller != null:
		turn_controller.request_occupancy_refresh()


func _spawn_four_way_wall_entity_pillars() -> void:
	if dungeon_generator == null or world == null:
		return
	if not dungeon_generator.use_breakable_entities_for_four_way_wall_pillars:
		return
	var taken: Dictionary = {}
	for inst in _spawned:
		if inst != null and is_instance_valid(inst):
			taken[inst.grid_pos] = true
	for gp in dungeon_generator.get_four_way_entity_pillar_cells():
		if taken.has(gp):
			continue
		if gp == dungeon_generator.exit_pos:
			continue
		if dungeon_generator._door_set.has(gp):
			continue
		if dungeon_generator.get_tile(gp) != DungeonGenerator.TileType.FLOOR:
			continue
		if turn_controller != null and turn_controller.is_cell_occupied(gp):
			continue
		var pillar := _instantiate_pillar()
		if pillar == null:
			continue
		world.add_child(pillar)
		pillar.bind_grid_position(gp)
		_spawned.append(pillar)
		taken[gp] = true


func _spawn_after_ready() -> void:
	_resolve_references()
	_connect_signals()
	if dungeon_generator == null:
		return
	if dungeon_generator.grid_map.is_empty():
		return
	spawn_for_floor()


func _instantiate_pillar() -> BreakablePillar:
	if pillar_scene != null:
		var inst = pillar_scene.instantiate()
		if inst is BreakablePillar:
			return inst
		if inst != null:
			inst.queue_free()
	return BreakablePillar.new()


func _connect_signals() -> void:
	if dungeon_generator == null:
		return
	var callable := Callable(self, "_on_dungeon_generated")
	if not dungeon_generator.generation_finished.is_connected(callable):
		dungeon_generator.generation_finished.connect(callable)
	if level_flow_controller != null:
		if not level_flow_controller.floor_changed.is_connected(_on_floor_changed):
			level_flow_controller.floor_changed.connect(_on_floor_changed)


func _on_dungeon_generated() -> void:
	call_deferred("spawn_for_floor")


func _on_floor_changed(_previous_floor: int, _current_floor: int) -> void:
	call_deferred("spawn_for_floor")


func _resolve_references() -> void:
	if dungeon_generator == null and not dungeon_generator_path.is_empty():
		var dungeon_node := get_node_or_null(dungeon_generator_path)
		if dungeon_node is DungeonGenerator:
			dungeon_generator = dungeon_node
	if dungeon_generator == null:
		var found_dungeon := get_tree().get_first_node_in_group("dungeon_generator")
		if found_dungeon is DungeonGenerator:
			dungeon_generator = found_dungeon

	if world == null and not world_path.is_empty():
		var world_node := get_node_or_null(world_path)
		if world_node is Node2D:
			world = world_node
	if world == null:
		var wp := get_parent()
		if wp is Node2D:
			world = wp

	if turn_controller == null and not turn_controller_path.is_empty():
		var turn_node := get_node_or_null(turn_controller_path)
		if turn_node is TurnController:
			turn_controller = turn_node
	if turn_controller == null:
		var found_turn := get_tree().get_first_node_in_group("turn_controller")
		if found_turn is TurnController:
			turn_controller = found_turn

	if level_flow_controller == null and not level_flow_path.is_empty():
		var flow_node := get_node_or_null(level_flow_path)
		if flow_node is LevelFlowController:
			level_flow_controller = flow_node
	if level_flow_controller == null:
		var found_flow := get_tree().get_first_node_in_group("level_flow_controller")
		if found_flow is LevelFlowController:
			level_flow_controller = found_flow


func _is_far_enough_from_room_edge(gp: Vector2i) -> bool:
	if min_room_edge_distance <= 0:
		return true
	var room_index = dungeon_generator._room_cell_to_room_index.get(gp, -1)
	if room_index < 0 or room_index >= dungeon_generator.rooms.size():
		return false
	var room: Rect2i = dungeon_generator.rooms[room_index]
	var dist_to_edge := mini(
		mini(gp.x - room.position.x, room.end.x - 1 - gp.x),
		mini(gp.y - room.position.y, room.end.y - 1 - gp.y)
	)
	return dist_to_edge >= min_room_edge_distance


func _player_grid() -> Vector2i:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("get"):
		var gp = player.get("grid_pos")
		if gp is Vector2i:
			return gp
	return Vector2i(-9999, -9999)
