class_name FogOfWar
extends Node2D
## Simple grid-based fog of war for the generated dungeon.

enum FogState { UNSEEN, EXPLORED, VISIBLE }

@export_group("References")
@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
@export var player_path: NodePath = NodePath("../Player")
@export var turn_controller_path: NodePath = NodePath("../TurnController")
@export var level_flow_path: NodePath = NodePath("../LevelFlowController")

@export_group("Vision")
@export_range(1, 20, 1) var vision_radius: int = 6
@export var doors_block_vision: bool = true
@export var enable_corner_peek: bool = true

@export_group("Rendering")
@export_range(0.0, 1.0, 0.05) var unseen_alpha: float = 1.0
@export_range(0.0, 1.0, 0.05) var explored_alpha: float = 0.55
@export var fog_z_index: int = 90

var dungeon_generator: DungeonGenerator = null
var player: Node = null
var turn_controller: Node = null
var level_flow_controller: Node = null

var _fog_state: Array = []
## 地城瓦片网格宽高（与 DungeonGenerator.map_* 一致，不含深渊外延）。
var _inner_w: int = 0
var _inner_h: int = 0
## 与 DungeonGenerator.background_margin_tiles 同步；仅用于在地图外绘制静态遮蔽条（不参与迷雾状态与贴图更新）。
var _margin: int = 0
## 迷雾逻辑与贴图仅覆盖地城格 0..map-1（与 dungeon 网格一致）；外延深渊用 _draw_abyss_margin 一次画完。
var _tile_size: int = 16
var _awaiting_spawn_reveal: bool = false
## 上一帧结束时仍处于 VISIBLE 的格（地城格坐标）；用于 EXPLORED 标记，避免全表扫描。
var _visible_last_frame: Array[Vector2i] = []
## 地城内网格尺寸的 CPU 小图，一次 draw_texture_rect 覆盖 playable 区域。
var _fog_image: Image
var _fog_texture: ImageTexture


func _ready() -> void:
	add_to_group("fog_of_war")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = fog_z_index
	_resolve_references()
	_connect_signals()
	call_deferred("reset_and_refresh")
	call_deferred("_force_initial_reveal")


func reset_and_refresh() -> void:
	_resolve_references()
	_connect_signals()
	_reset_fog()
	_awaiting_spawn_reveal = true
	_update_enemy_visibility()
	_rebuild_fog_texture()
	queue_redraw()


func refresh_visibility() -> void:
	if dungeon_generator == null or player == null or dungeon_generator.grid_map.is_empty():
		return
	_sync_map_settings()
	if _fog_state.is_empty() or _fog_state.size() != _inner_h \
			or _inner_w <= 0 or _inner_h <= 0 or (_fog_state[0] as Array).size() != _inner_w:
		_reset_fog()

	var player_grid: Vector2i = player.get("grid_pos")
	_mark_previous_visible_as_explored()

	var visible_floor_cells: Array[Vector2i] = []
	_reveal_from_origin(player_grid, player_grid, vision_radius, visible_floor_cells)
	if enable_corner_peek:
		for origin in _corner_peek_origins(player_grid):
			_reveal_from_origin(origin, player_grid, vision_radius, visible_floor_cells)

	_reveal_walls_next_to_visible_floors(visible_floor_cells)
	_update_enemy_visibility()

	_rebuild_fog_texture()
	queue_redraw()


func _draw() -> void:
	if _fog_texture == null or _fog_state.is_empty():
		return
	var ts := float(_tile_size)
	if _margin > 0:
		_draw_abyss_margin(ts)
	var inner_rect := Rect2(Vector2.ZERO, Vector2(float(_inner_w), float(_inner_h)) * ts)
	draw_texture_rect(_fog_texture, inner_rect, false)


func _resolve_references() -> void:
	if dungeon_generator == null and not dungeon_generator_path.is_empty():
		var dungeon_node := get_node_or_null(dungeon_generator_path)
		if dungeon_node is DungeonGenerator:
			dungeon_generator = dungeon_node
	if dungeon_generator == null:
		var found := get_tree().get_first_node_in_group("dungeon_generator")
		if found is DungeonGenerator:
			dungeon_generator = found

	if player == null and not player_path.is_empty():
		player = get_node_or_null(player_path)
	if player == null:
		player = get_tree().get_first_node_in_group("player")

	if turn_controller == null and not turn_controller_path.is_empty():
		turn_controller = get_node_or_null(turn_controller_path)
	if turn_controller == null:
		turn_controller = get_tree().get_first_node_in_group("turn_controller")

	if level_flow_controller == null and not level_flow_path.is_empty():
		level_flow_controller = get_node_or_null(level_flow_path)
	if level_flow_controller == null:
		level_flow_controller = get_tree().get_first_node_in_group("level_flow_controller")


func _connect_signals() -> void:
	if dungeon_generator != null:
		var dungeon_callable := Callable(self, "_on_dungeon_generated")
		if not dungeon_generator.generation_finished.is_connected(dungeon_callable):
			dungeon_generator.generation_finished.connect(dungeon_callable)

	if player != null and player.has_signal("grid_position_changed"):
		var player_callable := Callable(self, "_on_player_grid_position_changed")
		if not player.is_connected("grid_position_changed", player_callable):
			player.connect("grid_position_changed", player_callable)

	if turn_controller != null and turn_controller.has_signal("turn_resolved"):
		var turn_callable := Callable(self, "_on_turn_resolved")
		if not turn_controller.is_connected("turn_resolved", turn_callable):
			turn_controller.connect("turn_resolved", turn_callable)

	if level_flow_controller != null and level_flow_controller.has_signal("floor_changed"):
		var floor_callable := Callable(self, "_on_floor_changed")
		if not level_flow_controller.is_connected("floor_changed", floor_callable):
			level_flow_controller.connect("floor_changed", floor_callable)


func _on_dungeon_generated() -> void:
	reset_and_refresh()
	call_deferred("_ensure_post_regen_reveal")


func _on_floor_changed(_previous_floor: int, _current_floor: int) -> void:
	reset_and_refresh()
	call_deferred("_ensure_post_regen_reveal")


func _on_player_grid_position_changed(_grid_pos: Vector2i) -> void:
	if _awaiting_spawn_reveal:
		_awaiting_spawn_reveal = false
	refresh_visibility()


func _on_turn_resolved(_turn_index: int, _player_consumed_turn: bool, _had_attack: bool) -> void:
	if _awaiting_spawn_reveal:
		return
	refresh_visibility()


func _ensure_post_regen_reveal() -> void:
	# 若玩家重生信号先于迷雾重置到达，兜底在下一帧执行一次首次揭示。
	if not _awaiting_spawn_reveal:
		return
	if player == null:
		_resolve_references()
	if player == null or not player.has_method("get"):
		return
	_awaiting_spawn_reveal = false
	refresh_visibility()


func _force_initial_reveal() -> void:
	# 首次进入游戏时，确保玩家出生后至少执行一次可见性揭示。
	if player == null:
		_resolve_references()
	if player == null or not player.has_method("get"):
		return
	_awaiting_spawn_reveal = false
	refresh_visibility()


func _update_enemy_visibility() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("get"):
			continue
		var enemy_grid: Vector2i = enemy.get("grid_pos")
		enemy.visible = _is_cell_currently_visible(enemy_grid)
	for liquid in get_tree().get_nodes_in_group("flammable_liquid"):
		if liquid == null or not is_instance_valid(liquid):
			continue
		if not liquid.has_method("get"):
			continue
		var liquid_grid: Variant = liquid.get("grid_pos")
		if liquid_grid is Vector2i:
			liquid.visible = _is_cell_currently_visible(liquid_grid as Vector2i)
	# 可破坏柱子可见性由自身渲染层控制，不在此处强制隐藏，
	# 避免调试阶段出现“已生成但完全不可见”的误判。


func _is_cell_currently_visible(pos: Vector2i) -> bool:
	if not _is_in_bounds(pos):
		return false
	if _fog_state.is_empty():
		return false
	return _fog_state[pos.y][pos.x] == FogState.VISIBLE


func is_cell_visible(pos: Vector2i) -> bool:
	return _is_cell_currently_visible(pos)


func is_cell_unseen(pos: Vector2i) -> bool:
	if not _is_in_bounds(pos):
		return true
	if _fog_state.is_empty():
		return false
	return _fog_state[pos.y][pos.x] == FogState.UNSEEN




func _sync_map_settings() -> void:
	_inner_w = dungeon_generator.map_width
	_inner_h = dungeon_generator.map_height
	_margin = maxi(0, int(dungeon_generator.background_margin_tiles))
	_tile_size = dungeon_generator.tile_size


func _reset_fog() -> void:
	if dungeon_generator == null:
		return
	_sync_map_settings()
	_fog_state.clear()
	for _y in _inner_h:
		var row: Array = []
		row.resize(_inner_w)
		row.fill(FogState.UNSEEN)
		_fog_state.append(row)
	_visible_last_frame.clear()


func _rebuild_fog_texture() -> void:
	if _fog_state.is_empty() or _inner_w <= 0 or _inner_h <= 0:
		_fog_texture = null
		return
	if _fog_image == null or _fog_image.get_width() != _inner_w or _fog_image.get_height() != _inner_h:
		_fog_image = Image.create(_inner_w, _inner_h, false, Image.FORMAT_RGBA8)
	_visible_last_frame.clear()
	for fy in _inner_h:
		var row: Array = _fog_state[fy] as Array
		for fx in _inner_w:
			var st: FogState = row[fx] as FogState
			var a := 0.0
			if st == FogState.UNSEEN:
				a = unseen_alpha
			elif st == FogState.EXPLORED:
				a = explored_alpha
			if st == FogState.VISIBLE:
				_visible_last_frame.append(Vector2i(fx, fy))
			_fog_image.set_pixel(fx, fy, Color(0.0, 0.0, 0.0, a))
	if _fog_texture == null:
		_fog_texture = ImageTexture.create_from_image(_fog_image)
	else:
		_fog_texture.set_image(_fog_image)


func _mark_previous_visible_as_explored() -> void:
	for cell in _visible_last_frame:
		var fx := cell.x
		var fy := cell.y
		if fx < 0 or fy < 0 or fx >= _inner_w or fy >= _inner_h:
			continue
		if _fog_state[fy][fx] == FogState.VISIBLE:
			_fog_state[fy][fx] = FogState.EXPLORED


func _set_fog_state(pos: Vector2i, state: FogState) -> void:
	if not _is_in_bounds(pos):
		return
	_fog_state[pos.y][pos.x] = state


func _reveal_from_origin(
	origin: Vector2i,
	radius_center: Vector2i,
	radius: int,
	visible_floor_cells: Array[Vector2i]
) -> void:
	var radius_sq := radius * radius
	var min_x := maxi(radius_center.x - radius, 0)
	var max_x := mini(radius_center.x + radius, _inner_w - 1)
	var min_y := maxi(radius_center.y - radius, 0)
	var max_y := mini(radius_center.y + radius, _inner_h - 1)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if radius_center.distance_squared_to(cell) > radius_sq:
				continue
			if _has_line_of_sight(origin, cell):
				_set_fog_state(cell, FogState.VISIBLE)
				if dungeon_generator.get_tile(cell) == DungeonGenerator.TileType.FLOOR:
					visible_floor_cells.append(cell)


func _corner_peek_origins(player_grid: Vector2i) -> Array[Vector2i]:
	var origins: Array[Vector2i] = []
	for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var origin: Vector2i = player_grid + direction
		if _is_walkable_for_vision(origin) and _has_perpendicular_blocker(player_grid, direction):
			_add_unique_origin(origins, origin)

	for dx in [-1, 1]:
		for dy in [-1, 1]:
			var diagonal := player_grid + Vector2i(dx, dy)
			var horizontal := player_grid + Vector2i(dx, 0)
			var vertical := player_grid + Vector2i(0, dy)
			if not _is_walkable_for_vision(diagonal):
				continue
			var horizontal_open := _is_walkable_for_vision(horizontal)
			var vertical_open := _is_walkable_for_vision(vertical)
			if horizontal_open == vertical_open:
				continue
			if not _can_reach_diagonal_peek_origin(horizontal, vertical):
				continue
			_add_unique_origin(origins, diagonal)
	return origins


func _add_unique_origin(origins: Array[Vector2i], origin: Vector2i) -> void:
	if not origins.has(origin):
		origins.append(origin)


func _has_perpendicular_blocker(pos: Vector2i, direction: Vector2i) -> bool:
	if direction.x != 0:
		return _blocks_vision(pos + Vector2i(0, -1)) or _blocks_vision(pos + Vector2i(0, 1))
	return _blocks_vision(pos + Vector2i(-1, 0)) or _blocks_vision(pos + Vector2i(1, 0))


func _is_walkable_for_vision(pos: Vector2i) -> bool:
	return _is_in_bounds(pos) \
		and dungeon_generator.get_tile(pos) == DungeonGenerator.TileType.FLOOR \
		and not _is_closed_door(pos)


func _can_reach_diagonal_peek_origin(horizontal: Vector2i, vertical: Vector2i) -> bool:
	return _is_walkable_for_vision(horizontal) or _is_walkable_for_vision(vertical)


func _reveal_walls_next_to_visible_floors(visible_floor_cells: Array[Vector2i]) -> void:
	for floor_cell in visible_floor_cells:
		for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = floor_cell + direction
			if not _is_in_bounds(neighbor):
				continue
			var neighbor_tile: DungeonGenerator.TileType = (
				dungeon_generator.get_tile(neighbor) as DungeonGenerator.TileType
			)
			if DungeonGenerator.tile_blocks_movement(neighbor_tile):
				_set_fog_state(neighbor, FogState.VISIBLE)


func _has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var line := _grid_line(from, to)
	for i in line.size():
		var cell: Vector2i = line[i]
		if i == 0:
			continue
		if _blocks_vision(cell):
			return cell == to
	return true


func _blocks_vision(pos: Vector2i) -> bool:
	if not _is_in_bounds(pos):
		return true
	if doors_block_vision and _is_closed_door(pos):
		return true
	return DungeonGenerator.tile_blocks_vision(dungeon_generator.get_tile(pos) as DungeonGenerator.TileType)


func _is_closed_door(pos: Vector2i) -> bool:
	return dungeon_generator._door_set.has(pos) \
		and not bool(dungeon_generator._door_states.get(pos, false))


func _grid_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0 := from.x
	var y0 := from.y
	var x1 := to.x
	var y1 := to.y
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy

	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return points


func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < _inner_w and pos.y < _inner_h


## 深渊外延：固定「未探索」遮罩，不参与 _fog_state / 贴图逐格更新。
func _draw_abyss_margin(ts: float) -> void:
	var m := float(_margin)
	if m <= 0.0:
		return
	var cover := Color(0.0, 0.0, 0.0, unseen_alpha)
	var iw := float(_inner_w) * ts
	var ih := float(_inner_h) * ts
	var w_full := iw + 2.0 * m * ts
	# 上、下整条（含左右角）
	draw_rect(Rect2(Vector2(-m * ts, -m * ts), Vector2(w_full, m * ts)), cover, true)
	draw_rect(Rect2(Vector2(-m * ts, ih), Vector2(w_full, m * ts)), cover, true)
	# 左、右中部（避免与上下条重复绘制中间带）
	draw_rect(Rect2(Vector2(-m * ts, 0.0), Vector2(m * ts, ih)), cover, true)
	draw_rect(Rect2(Vector2(iw, 0.0), Vector2(m * ts, ih)), cover, true)
