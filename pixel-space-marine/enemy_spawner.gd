class_name EnemySpawner
extends Node

@export_group("References")
@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
@export var player_path: NodePath = NodePath("../Player")
## 为空时使用本节点的父节点（一般为 `GameSystem` / 场景根 `Node2D`）作为敌人生成的父级。
@export var world_path: NodePath = NodePath("")
@export var turn_controller_path: NodePath = NodePath("../TurnController")
@export var level_flow_path: NodePath = NodePath("../LevelFlowController")

@export_group("Enemy")
@export var enemy_scene: PackedScene
@export_range(1, 50, 1) var min_enemies_per_floor: int = 3
@export_range(1, 50, 1) var max_enemies_per_floor: int = 8
@export_range(0, 50, 1) var min_distance_to_player_spawn: int = 6
@export var spawn_attempt_limit: int = 300

var dungeon_generator: DungeonGenerator = null
var player: Node = null
var world: Node2D = null
var turn_controller: TurnController = null
var level_flow_controller: LevelFlowController = null
var _rng := RandomNumberGenerator.new()
var _spawned: Array[EnemyGridController] = []


func _ready() -> void:
	_rng.randomize()
	_resolve_references()
	_connect_signals()
	call_deferred("_spawn_after_ready")


func clear_enemies() -> void:
	for enemy in _spawned:
		if enemy != null and is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()
	if turn_controller != null:
		turn_controller.request_occupancy_refresh()


func spawn_for_floor() -> void:
	_resolve_references()
	if dungeon_generator == null or world == null or player == null:
		return
	clear_enemies()
	var reserved_for_pillars: Dictionary = {}
	if dungeon_generator.has_preset_pillar_layout():
		for gv in dungeon_generator.get_preset_pillar_cells():
			reserved_for_pillars[gv] = true
	if dungeon_generator.has_preset_barrels_layout():
		for bv in dungeon_generator.get_preset_barrel_cells():
			reserved_for_pillars[bv] = true

	if dungeon_generator.has_preset_enemy_layout():
		var slots: Array[Vector2i] = dungeon_generator.get_preset_enemy_cells()
		var order_idx := 0
		for pos in slots:
			if dungeon_generator.get_tile(pos) != DungeonGenerator.TileType.FLOOR:
				continue
			if pos == dungeon_generator.exit_pos:
				continue
			if dungeon_generator._door_set.has(pos):
				continue
			if _has_enemy_at(pos):
				continue
			var enemy_inst := _instantiate_enemy()
			world.add_child(enemy_inst)
			enemy_inst.turn_order = order_idx
			order_idx += 1
			enemy_inst.bind_grid_position(pos)
			_spawned.append(enemy_inst)
		if turn_controller != null:
			turn_controller.request_occupancy_refresh()
		return

	if dungeon_generator.layout_suppresses_random_enemies():
		if turn_controller != null:
			turn_controller.request_occupancy_refresh()
		return

	var low := mini(min_enemies_per_floor, max_enemies_per_floor)
	var high := maxi(min_enemies_per_floor, max_enemies_per_floor)
	var target_count := _rng.randi_range(low, high)
	var player_grid := player.get("grid_pos") as Vector2i

	var attempts := 0
	while _spawned.size() < target_count and attempts < spawn_attempt_limit:
		attempts += 1
		var candidate := dungeon_generator.get_random_floor_cell()
		if candidate == dungeon_generator.exit_pos:
			continue
		if dungeon_generator._door_set.has(candidate):
			continue
		if reserved_for_pillars.has(candidate):
			continue
		if _is_in_player_spawn_room(candidate):
			continue
		if candidate.distance_to(player_grid) < float(min_distance_to_player_spawn):
			continue
		if _has_enemy_at(candidate):
			continue
		_spawn_enemy(candidate)

	if turn_controller != null:
		turn_controller.request_occupancy_refresh()


func _spawn_after_ready() -> void:
	_resolve_references()
	_connect_signals()
	if dungeon_generator == null:
		return
	if dungeon_generator.grid_map.is_empty():
		return
	spawn_for_floor()


func _spawn_enemy(grid_pos: Vector2i) -> void:
	var enemy := _instantiate_enemy()
	if enemy == null:
		return
	world.add_child(enemy)
	enemy.turn_order = _spawned.size()
	enemy.bind_grid_position(grid_pos)
	_spawned.append(enemy)


func _instantiate_enemy() -> EnemyGridController:
	if enemy_scene != null:
		var inst = enemy_scene.instantiate()
		if inst is EnemyGridController:
			return inst
		if inst != null:
			inst.queue_free()
	var fallback := EnemyGridController.new()
	return fallback


func _has_enemy_at(pos: Vector2i) -> bool:
	for enemy in _spawned:
		if enemy != null and is_instance_valid(enemy) and enemy.grid_pos == pos:
			return true
	return false


func _is_in_player_spawn_room(pos: Vector2i) -> bool:
	var spawn_idx := dungeon_generator.spawn_room_index
	var room_idx = dungeon_generator._room_cell_to_room_index.get(pos, -1)
	return room_idx == spawn_idx


func _connect_signals() -> void:
	if dungeon_generator == null:
		return
	var callable := Callable(self, "_on_dungeon_generated")
	if not dungeon_generator.generation_finished.is_connected(callable):
		dungeon_generator.generation_finished.connect(callable)


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

	if player == null and not player_path.is_empty():
		player = get_node_or_null(player_path)
	if player == null:
		player = get_tree().get_first_node_in_group("player")

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
