class_name TurnController
extends Node

signal turn_resolved(turn_index: int, player_consumed_turn: bool, had_attack: bool)

@export_group("References")
@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
@export var player_path: NodePath = NodePath("../Player")
## 为空时父节点作为液体等运行时实体的父级（与无 World 的扁平主场景兼容）。
@export var world_path: NodePath = NodePath("")

@export_group("Turn")
@export_range(0.0, 0.2, 0.01) var base_turn_interval: float = 0.02
@export_range(0.0, 0.3, 0.01) var combat_pause_duration: float = 0.1
@export_group("Projectile Visual")
## 弹体世界坐标飞行速度（像素/秒）；命中结算在飞行结束后触发。
@export_range(200.0, 2400.0, 50.0) var projectile_travel_speed: float = 1100.0
@export_range(0.03, 0.25, 0.01) var projectile_travel_min_duration: float = 0.07
@export_range(0.08, 3.0, 0.01) var projectile_travel_max_duration: float = 0.20
@export var block_bump_consumes_turn: bool = false

@export_group("Movement Rules")
@export var allow_diagonal_movement: bool = true
@export var forbid_diagonal_corner_cutting: bool = true
@export var allow_diagonal_pillar_gap: bool = true

@export_group("Flammable Liquid")
@export var flammable_liquid_scene: PackedScene = preload("res://FlammableLiquid.tscn")
## 单位踏上燃烧液、附着燃烧的默认持续回合（及多数 `ignite(...)` 传参）；可在 Inspector 调整以调试关卡节奏。
@export_range(1, 64, 1) var default_fire_duration_turns: int = 8
## 每回合结束时在 Output 打出玩家与敌人的燃烧剩余回合（调试用）。
@export var debug_log_fire_attachment_remaining: bool = false

var dungeon_generator: DungeonGenerator = null
var player: Node = null
var world: Node2D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
const PLAYER_IMPACT_SFX_NAMES: PackedStringArray = ["Impact1", "Impact2", "Impact3", "Impact4", "Impact5", "Impact6"]
const ENEMY_HIT_SFX_NAMES: PackedStringArray = ["Hit1", "Hit2", "Hit3", "Hit4", "Hit5"]
const AUDIO_MANAGER_CANDIDATE_NAMES: PackedStringArray = ["AudioManager", "audiomanager", "SfxManager"]
const GRID_PROJECTILE_SCRIPT: GDScript = preload("res://grid_projectile.gd")
var _audio_manager_missing_logged: bool = false
## 当前 `_resolve_turn_async` 内是否出现过火焰蔓延（液体/桶/附着者邻格点燃等）；用于回合末至多播一次 Ignite。
var _fire_spread_occurred_this_resolve: bool = false

var occupancy: Dictionary = {}  # Vector2i -> Node
var enemies: Array[EnemyGridController] = []
var liquids: Array[Node] = []
var _fog_of_war: Node = null

var _queued_player_direction: Vector2i = Vector2i.ZERO
var _queued_player_wait: bool = false
var _queued_player_shot_target: Vector2i = Vector2i(-9999, -9999)
var _is_resolving_turn: bool = false
var _combat_pause_remaining: float = 0.0
var _turn_index: int = 0


func _ready() -> void:
	add_to_group("turn_controller")
	_rng.randomize()
	_resolve_references()
	_resolve_fog_of_war()
	_connect_signals()
	call_deferred("_refresh_runtime_state")


func _process(delta: float) -> void:
	if _combat_pause_remaining > 0.0:
		_combat_pause_remaining = maxf(0.0, _combat_pause_remaining - delta)
		return
	if not _is_resolving_turn and (_queued_player_direction != Vector2i.ZERO or _queued_player_wait or _has_queued_player_shot()) and _can_begin_next_turn():
		_start_resolve_turn()


func queue_player_direction(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return
	_queued_player_direction = direction
	_queued_player_wait = false
	if not _is_resolving_turn and _combat_pause_remaining <= 0.0 and _can_begin_next_turn():
		_start_resolve_turn()


func queue_player_wait() -> void:
	_queued_player_wait = true
	_queued_player_direction = Vector2i.ZERO
	_queued_player_shot_target = Vector2i(-9999, -9999)
	if not _is_resolving_turn and _combat_pause_remaining <= 0.0 and _can_begin_next_turn():
		_start_resolve_turn()


func queue_player_shot(target_grid: Vector2i) -> void:
	_queued_player_shot_target = target_grid
	_queued_player_direction = Vector2i.ZERO
	_queued_player_wait = false
	if not _is_resolving_turn and _combat_pause_remaining <= 0.0 and _can_begin_next_turn():
		_start_resolve_turn()


func clear_queued_actions() -> void:
	_queued_player_direction = Vector2i.ZERO
	_queued_player_wait = false
	_queued_player_shot_target = Vector2i(-9999, -9999)


func register_enemy(enemy: EnemyGridController) -> void:
	if enemy == null:
		return
	if enemies.has(enemy):
		return
	enemies.append(enemy)
	_refresh_runtime_state()


func unregister_enemy(enemy: EnemyGridController) -> void:
	if enemy == null:
		return
	enemies.erase(enemy)
	_refresh_runtime_state()


func request_occupancy_refresh() -> void:
	_refresh_runtime_state()
	_notify_submerged_abyss_barrel_platforms()


func get_debug_default_fire_duration_turns() -> int:
	return default_fire_duration_turns


func is_cell_occupied(pos: Vector2i) -> bool:
	return occupancy.has(pos)


## 深渊木桶浮台承重：同格且非浮空的玩家/敌人/未入水桶，不含浮台桶自身。
func count_non_floating_weight_on_abyss_platform(
		cell: Vector2i, platform_barrel: BreakableBarrel = null
) -> int:
	return int(debug_abyss_platform_weight(cell, platform_barrel).get("weight", 0))


func debug_abyss_platform_weight(
		cell: Vector2i, platform_barrel: BreakableBarrel = null
) -> Dictionary:
	_resolve_references()
	var result := {
		"cell": cell,
		"weight": 0,
		"platform_registered": false,
		"player_grid": Vector2i(-1, -1),
		"occupant_at_cell": "",
		"actor_names": PackedStringArray(),
	}
	if dungeon_generator == null:
		return result
	var platform_ok := false
	if platform_barrel != null and is_instance_valid(platform_barrel) \
			and platform_barrel.is_submerged_in_abyss():
		platform_ok = true
		result["platform_registered"] = (
			dungeon_generator.has_abyss_barrel_platform(cell)
			or dungeon_generator.find_abyss_barrel_platform_cell(platform_barrel) == cell
		)
	else:
		result["platform_registered"] = dungeon_generator.has_abyss_barrel_platform(cell)
		platform_ok = bool(result["platform_registered"])
	if not platform_ok:
		return result
	if player != null and is_instance_valid(player):
		var pg: Variant = player.get("grid_pos")
		if pg is Vector2i:
			result["player_grid"] = pg as Vector2i
	var occ: Variant = occupancy.get(cell, null)
	if occ != null and is_instance_valid(occ):
		result["occupant_at_cell"] = String(occ.name)
	var weight := 0
	var seen: Dictionary = {}
	var actor_names: PackedStringArray = []
	var consider := func(node: Node) -> void:
		if node == null or not is_instance_valid(node):
			return
		if platform_barrel != null and node == platform_barrel:
			return
		var id: int = node.get_instance_id()
		if seen.has(id):
			return
		if not _actor_on_abyss_platform(node, cell):
			return
		var w := _actor_weight_on_abyss_platform(node)
		if w <= 0:
			return
		seen[id] = true
		weight += w
		actor_names.append("%s@%s" % [node.name, _read_actor_grid_pos_for_platform(node)])
	var direct: Node = occ as Node
	if direct != null and is_instance_valid(direct):
		consider.call(direct)
	for occ_node in occupancy.values():
		consider.call(occ_node as Node)
	if player != null and is_instance_valid(player):
		consider.call(player)
	for enemy in enemies:
		if enemy != null and is_instance_valid(enemy):
			consider.call(enemy)
	result["weight"] = weight
	result["actor_names"] = actor_names
	return result


func _actor_on_abyss_platform(actor: Node, platform_cell: Vector2i) -> bool:
	return _read_actor_grid_pos_for_platform(actor) == platform_cell


func _is_abyss_platform_cell_valid(cell: Vector2i, platform_barrel: BreakableBarrel) -> bool:
	if dungeon_generator == null:
		return false
	if dungeon_generator.has_abyss_barrel_platform(cell):
		return true
	if platform_barrel == null or not is_instance_valid(platform_barrel):
		return false
	if not platform_barrel.is_submerged_in_abyss():
		return false
	return dungeon_generator.find_abyss_barrel_platform_cell(platform_barrel) == cell


func _read_actor_grid_pos_for_platform(actor: Node) -> Vector2i:
	if actor == null or not is_instance_valid(actor):
		return Vector2i(-999999, -999999)
	if actor is EnemyGridController:
		return (actor as EnemyGridController).grid_pos
	if actor is BreakableBarrel:
		return (actor as BreakableBarrel).grid_pos
	var gp: Variant = actor.get("grid_pos")
	if gp is Vector2i:
		return gp as Vector2i
	return Vector2i(-999999, -999999)


func _actor_weight_on_abyss_platform(actor: Node) -> int:
	if actor is BreakableBarrel:
		return 0 if (actor as BreakableBarrel).is_submerged_in_abyss() else 1
	if actor is EnemyGridController:
		return 0 if (actor as EnemyGridController).floating else 1
	if player != null and actor == player:
		return 1
	if actor.is_in_group("player"):
		return 1
	var scr: Variant = actor.get_script()
	if scr is Script and String((scr as Script).resource_path).ends_with("player_grid_controller.gd"):
		return 1
	return 0


func get_enemy_at(pos: Vector2i) -> EnemyGridController:
	var node = occupancy.get(pos, null)
	if node == null or not is_instance_valid(node):
		return null
	if node is EnemyGridController:
		return node
	return null


func get_melee_target_at(pos: Vector2i) -> Node:
	var node = occupancy.get(pos, null)
	if node == null or not is_instance_valid(node):
		return null
	if node.has_method("can_receive_melee") and bool(node.call("can_receive_melee")):
		return node
	if node is EnemyGridController:
		return node
	return null


func _player_directional_attack_ok(actor_node: Node, from_grid: Vector2i) -> bool:
	if actor_node == null or not is_instance_valid(actor_node):
		return false
	if actor_node.has_method("accepts_directional_hit_from"):
		return bool(actor_node.call("accepts_directional_hit_from", from_grid))
	return true


func get_liquid_at(pos: Vector2i) -> Node:
	for liquid in liquids:
		if liquid == null or not is_instance_valid(liquid):
			continue
		if not liquid.has_method("get"):
			continue
		var gp = liquid.get("grid_pos")
		if gp is Vector2i and gp == pos:
			return liquid
	return null


func spawn_flammable_liquid(pos: Vector2i, volatile_for_floor_reset: bool = true) -> Node:
	if flammable_liquid_scene == null or world == null:
		return null
	if get_liquid_at(pos) != null:
		return get_liquid_at(pos)
	var liquid: Node2D = flammable_liquid_scene.instantiate() as Node2D
	if liquid == null:
		return null
	if dungeon_generator != null and liquid.has_method("set"):
		liquid.set("tile_size", dungeon_generator.tile_size)
	world.add_child(liquid)
	if liquid is FlammableLiquid:
		(liquid as FlammableLiquid).apply_canvas_depth(dungeon_generator)
	if volatile_for_floor_reset:
		liquid.set_meta("volatile_liquid", true)
	elif liquid.has_meta("volatile_liquid"):
		liquid.remove_meta("volatile_liquid")
	if liquid.has_method("bind_grid_position"):
		liquid.call("bind_grid_position", pos)
	liquids.append(liquid)
	return liquid


func spawn_flammable_liquid_cluster(center: Vector2i, random_neighbors_count: int = 4) -> void:
	var candidates: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var gp := center + Vector2i(dx, dy)
			if not _is_walkable_tile(gp):
				continue
			candidates.append(gp)
	spawn_flammable_liquid(center)
	candidates.shuffle()
	var limit := mini(random_neighbors_count, candidates.size())
	for i in range(limit):
		spawn_flammable_liquid(candidates[i])


func spawn_melee_break_pillar_flammable_spray(
	origin: Vector2i,
	melee_attacker_cell = null,
	max_distance_tiles: float = 4.5,
	max_puddle_cells: int = 14,
	half_angle_degrees: float = 30.0
) -> void:
	## 近战击破液罐：沿「攻击者→罐子」射线越过罐子前方张开有限楔形；线段遮挡参照 `_splash_segment_blocks_propagation`（墙、深渊、关门挡；开门可通过）。
	var atk_grid: Vector2i
	if melee_attacker_cell is Vector2i:
		atk_grid = melee_attacker_cell as Vector2i
	else:
		atk_grid = origin + Vector2i(0, -1)

	var fwd_vec: Vector2 = Vector2(origin - atk_grid)
	if fwd_vec.length_squared() < 1e-10:
		fwd_vec = Vector2(0.0, 1.0)
	else:
		fwd_vec = fwd_vec.normalized()

	var half_rad: float = deg_to_rad(maxf(0.0, half_angle_degrees))
	var max_dist: float = maxf(0.05, max_distance_tiles)
	var budget: int = maxi(1, max_puddle_cells)

	var placed: Dictionary = {}
	var spawned_count: int = 0
	if _try_place_melee_splash_liquid(origin, placed):
		spawned_count += 1

	var ri: int = int(ceili(max_dist)) + 1
	var scored: Array = []
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var cand: Vector2i = origin + Vector2i(dx, dy)
			if cand == origin:
				continue
			var rel: Vector2 = Vector2(cand - origin)
			var dist_len: float = rel.length()
			if dist_len > max_dist + 1e-5:
				continue
			if rel.dot(fwd_vec) <= 1e-5:
				continue
			var cos_th: float = clampf(rel.normalized().dot(fwd_vec), -1.0, 1.0)
			var ang: float = absf(acos(cos_th))
			if ang > half_rad + 1e-5:
				continue
			if not _splash_can_place_liquid_at(cand):
				continue
			if not _splash_propagation_line_clear(origin, cand):
				continue
			scored.append({"cell": cand, "dist_sq": dist_len * dist_len, "ang": ang})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = float(a["dist_sq"])
		var db: float = float(b["dist_sq"])
		if da != db:
			return da < db
		return float(a["ang"]) < float(b["ang"])
	)

	var remaining: int = budget - spawned_count
	var idx: int = 0
	while remaining > 0 and idx < scored.size():
		var row: Dictionary = scored[idx] as Dictionary
		var picked: Vector2i = row["cell"] as Vector2i
		idx += 1
		if _try_place_melee_splash_liquid(picked, placed):
			remaining -= 1


func _try_place_melee_splash_liquid(gp: Vector2i, dedup_placed: Dictionary) -> bool:
	if dedup_placed.has(gp):
		return false
	if not _splash_can_place_liquid_at(gp):
		dedup_placed[gp] = true
		return false
	if get_liquid_at(gp) != null:
		dedup_placed[gp] = true
		return false
	spawn_flammable_liquid(gp)
	dedup_placed[gp] = true
	return true


func apply_explosion_damage(center: Vector2i, damage: int, include_diagonals: bool = true) -> void:
	var offsets: Array[Vector2i] = []
	if include_diagonals:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				offsets.append(Vector2i(dx, dy))
	else:
		offsets = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var player_was_hit: bool = false
	for offset in offsets:
		var gp := center + offset
		var target: Node = occupancy.get(gp, null) as Node
		if target == null:
			continue
		if target.has_method("trigger_from_environment_damage"):
			target.call("trigger_from_environment_damage", damage)
			continue
		if target.has_method("apply_damage_from_ranged"):
			target.call("apply_damage_from_ranged", damage, center)
			continue
		if not target.has_method("apply_damage"):
			continue
		var is_dead: bool = target.call("apply_damage", damage, center) == true
		if target == player:
			player_was_hit = true
		if is_dead:
			occupancy.erase(gp)
			if is_instance_valid(target) and target is EnemyGridController:
				enemies.erase(target)
	if player_was_hit and not _is_player_dead():
		_apply_player_explosion_knockback(center, 2)


func _apply_player_explosion_knockback(center: Vector2i, max_steps: int) -> void:
	if player == null or _is_player_dead():
		return
	if not player.has_method("get"):
		return
	var start: Vector2i = player.get("grid_pos") as Vector2i
	var delta := start - center
	var step := Vector2i(signi(delta.x), signi(delta.y))
	if step == Vector2i.ZERO:
		return
	var current := start
	var moved := false
	for _i in range(max_steps):
		var next := current + step
		if not can_actor_step(player, current, next, true):
			break
		_handle_door_transition(current, next, player)
		occupancy.erase(current)
		occupancy[next] = player
		current = next
		moved = true
	if moved and player.has_method("execute_turn_move"):
		player.call("execute_turn_move", current)
		_notify_submerged_abyss_barrel_platforms()


func can_actor_step(actor: Node, from: Vector2i, to: Vector2i, explosion_knockback: bool = false) -> bool:
	var delta := to - from
	if delta == Vector2i.ZERO:
		return false
	if absi(delta.x) > 1 or absi(delta.y) > 1:
		return false
	if not allow_diagonal_movement and delta.x != 0 and delta.y != 0:
		return false
	if not _actor_can_enter_cell(actor, to, explosion_knockback):
		return false

	var blocker = occupancy.get(to, null)
	if blocker != null and blocker != actor:
		if actor is EnemyGridController:
			var eg: EnemyGridController = actor as EnemyGridController
			## 仅飞行单位可「越过」木桶占位；石柱对飞行与地面单位均照常阻挡。
			if eg.floating and blocker is BreakableBarrel:
				pass
			else:
				return false
		else:
			return false

	if delta.x != 0 and delta.y != 0 and forbid_diagonal_corner_cutting:
		var side_a := from + Vector2i(delta.x, 0)
		var side_b := from + Vector2i(0, delta.y)
		var side_a_walkable := _is_walkable_for_actor(actor, side_a)
		var side_b_walkable := _is_walkable_for_actor(actor, side_b)
		if not side_a_walkable and not side_b_walkable:
			if allow_diagonal_pillar_gap and _is_diagonal_pillar_gap(from, to):
				return true
			if _is_diagonal_abyss_platform_crossing(from, to):
				return true
			return false
	return true


## 桶撞击占用者：沿 `push_step` 将演员从 `from_cell` 推一格（`from_cell` 一般为被挡格、即该演员当前格）。
func try_push_actor_from_cell_along_step(actor: Node, from_cell: Vector2i, push_step: Vector2i) -> bool:
	if actor == null or not is_instance_valid(actor) or push_step == Vector2i.ZERO:
		return false
	var dest := from_cell + push_step
	if not can_actor_step(actor, from_cell, dest):
		return false
	var push_lock := 0.12
	if actor.has_method("get_turn_move_duration"):
		push_lock = float(actor.call("get_turn_move_duration"))
	if actor.is_in_group("player") and actor.has_method("prepare_for_forced_grid_push"):
		actor.call("prepare_for_forced_grid_push", push_lock)
	_handle_door_transition(from_cell, dest, actor)
	occupancy.erase(from_cell)
	occupancy[dest] = actor
	if actor.has_method("execute_turn_move"):
		if actor.is_in_group("player"):
			actor.call("execute_turn_move", dest, false)
		else:
			actor.call("execute_turn_move", dest)
		request_occupancy_refresh()
		_notify_submerged_abyss_barrel_platforms()
		return true
	if actor.has_method("bind_grid_position"):
		actor.call("bind_grid_position", dest)
	request_occupancy_refresh()
	return true


func pick_enemy_step(enemy: EnemyGridController, target_grid: Vector2i) -> Vector2i:
	if enemy == null:
		return target_grid
	return _pick_step_by_bfs(enemy, enemy.grid_pos, target_grid)


func pick_wander_step(enemy: EnemyGridController) -> Vector2i:
	if enemy == null:
		return Vector2i.ZERO
	var start := enemy.grid_pos
	var candidates: Array[Vector2i] = []
	for offset in _neighbor_offsets():
		var next_grid := start + offset
		if can_actor_step(enemy, start, next_grid):
			candidates.append(next_grid)
	if candidates.is_empty():
		return start
	var index := _rng.randi_range(0, candidates.size() - 1)
	return candidates[index]


func pick_random_wander_target(actor: Node, origin: Vector2i, min_distance: int = 4, attempts: int = 24) -> Vector2i:
	if dungeon_generator == null:
		return origin
	for _i in attempts:
		var candidate := dungeon_generator.get_random_floor_cell()
		if candidate.distance_squared_to(origin) < min_distance * min_distance:
			continue
		if not _is_walkable_for_actor(actor, candidate):
			continue
		return candidate
	return origin


func has_line_of_sight(from: Vector2i, to: Vector2i, max_range: int = -1) -> bool:
	if max_range >= 0 and maxi(absi(to.x - from.x), absi(to.y - from.y)) > max_range:
		return false
	var line := _grid_line(from, to)
	for i in line.size():
		var cell: Vector2i = line[i]
		if i == 0:
			continue
		if _blocks_vision(cell):
			return cell == to
	return true


func _start_resolve_turn() -> void:
	if _is_resolving_turn:
		return
	if not _can_begin_next_turn():
		return
	_resolve_references()
	if dungeon_generator == null or player == null:
		return
	if _queued_player_direction == Vector2i.ZERO and not _queued_player_wait and not _has_queued_player_shot():
		return

	var direction := _queued_player_direction
	var is_wait := _queued_player_wait
	var shot_target := _queued_player_shot_target
	var is_shot := _has_queued_player_shot()
	_queued_player_direction = Vector2i.ZERO
	_queued_player_wait = false
	_queued_player_shot_target = Vector2i(-9999, -9999)
	_is_resolving_turn = true
	_resolve_turn_async(direction, is_wait, shot_target, is_shot)


func _resolve_turn_async(player_direction: Vector2i, is_wait_action: bool, shot_target: Vector2i, is_shot_action: bool) -> void:
	_refresh_runtime_state()
	_fire_spread_occurred_this_resolve = false

	var visual_duration := 0.0
	var had_attack := false
	var enemy_attack_serial_waited := false
	var waited_player_phase := false
	var player_result: Dictionary
	if is_shot_action:
		player_result = await _resolve_player_shot_action(shot_target)
	else:
		player_result = _resolve_player_action(player_direction, is_wait_action)
	## 木桶击退在 `apply_damage` 内 deferred+await，须先等链式击退结束再继续液体结算与敌人阶段。
	await get_tree().process_frame
	await _await_all_barrel_knockbacks_finished()
	var player_visual_duration := float(player_result.get("visual_duration", 0.0))
	visual_duration = maxf(visual_duration, player_visual_duration)
	had_attack = had_attack or bool(player_result.get("had_attack", false))
	var player_consumed_turn := bool(player_result.get("consumed_turn", false))
	var player_had_attack := bool(player_result.get("had_attack", false))
	var force_wait_before_enemy := bool(player_result.get("force_wait_before_enemy", false))
	var did_grid_move := bool(player_result.get("did_grid_move", false))
	# 仅在「走位进入燃烧格子且本回合马上要结算灼伤」时，等移动Tween结束再打伤害，其余移动不慢半拍。
	if (
		player_consumed_turn
		and did_grid_move
		and _player_would_take_imminent_liquid_burn_damage()
		and player_visual_duration > 0.0
		and not _is_player_dead()
	):
		waited_player_phase = true
		await get_tree().create_timer(player_visual_duration).timeout
	if player_consumed_turn:
		_process_liquid_turn_effects()

	if player_consumed_turn and not _is_player_dead():
		var ordered_enemies := _alive_enemies_ordered()
		var attack_queue: Array[EnemyGridController] = []
		var move_queue: Array[EnemyGridController] = []
		for enemy in ordered_enemies:
			if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
				continue
			var player_grid := player.get("grid_pos") as Vector2i
			var action := enemy.decide_turn_action(player_grid, self)
			var action_type := String(action.get("type", "wait"))
			if action_type == "attack":
				attack_queue.append(enemy)
			else:
				move_queue.append(enemy)

		var ordered_execution: Array[EnemyGridController] = []
		ordered_execution.append_array(attack_queue)
		ordered_execution.append_array(move_queue)

		# 仅在本回合存在战斗时，等待玩家动作先完整结算（含近战/近战阻档表现），再执行敌人。
		# 若上面已为「走位踩火灼伤」耽搁过同一时间窗，则不重复等待。
		var has_enemy_attack_this_turn := not attack_queue.is_empty()
		if (player_had_attack or has_enemy_attack_this_turn or force_wait_before_enemy) \
				and player_visual_duration > 0.0 and not _is_player_dead() \
				and not waited_player_phase:
			waited_player_phase = true
			await get_tree().create_timer(player_visual_duration).timeout

		for enemy in ordered_execution:
			if _is_player_dead():
				break
			_refresh_runtime_state()
			if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
				continue
			var enemy_result := _resolve_enemy_action(enemy)
			var enemy_visual_duration := float(enemy_result.get("visual_duration", 0.0))
			var enemy_had_attack := bool(enemy_result.get("had_attack", false))
			visual_duration = maxf(visual_duration, enemy_visual_duration)
			had_attack = had_attack or enemy_had_attack
			if _is_player_dead():
				break
			if enemy_had_attack and enemy_visual_duration > 0.0:
				enemy_attack_serial_waited = true
				await get_tree().create_timer(enemy_visual_duration).timeout

	var turn_delay := maxf(base_turn_interval, visual_duration)
	if enemy_attack_serial_waited:
		# 敌人攻击动画已在循环中按顺序逐个等待，回合末只保留基础间隔。
		turn_delay = base_turn_interval
	elif waited_player_phase and player_visual_duration > 0.0:
		# 玩家阶段已经等待过一次，避免回合末重复等待造成“额外停顿”。
		turn_delay = base_turn_interval
	_play_ignite_sfx_if_fire_spread_this_resolve()
	_turn_index += 1
	turn_resolved.emit(_turn_index, player_consumed_turn, had_attack)
	if turn_delay > 0.0:
		await get_tree().create_timer(turn_delay).timeout

	_is_resolving_turn = false
	if had_attack:
		_combat_pause_remaining = maxf(_combat_pause_remaining, combat_pause_duration)
	_refresh_runtime_state()

	if _queued_player_direction != Vector2i.ZERO and _combat_pause_remaining <= 0.0:
		_start_resolve_turn()


func _resolve_player_shot_action(shot_target: Vector2i) -> Dictionary:
	var result := {
		"consumed_turn": false,
		"had_attack": false,
		"visual_duration": 0.0,
		"force_wait_before_enemy": false,
		"did_grid_move": false,
	}
	if player == null or not player.has_method("get"):
		return result
	if player.has_method("begin_ranged_attack"):
		var started := bool(player.call("begin_ranged_attack", shot_target))
		if not started:
			return result

	var from_grid := player.get("grid_pos") as Vector2i
	var shot_goal := _remap_shot_target_for_wall_switch_floor_anchor(from_grid, shot_target)
	var shot_trace := _trace_projectile_hit(player, from_grid, shot_goal, true)
	var hit_grid := shot_trace.get("hit_grid", shot_target) as Vector2i
	var target_node: Node = shot_trace.get("target_node", null) as Node
	var hit_prev: Vector2i = shot_trace.get("hit_prev_cell", from_grid) as Vector2i
	if target_node != null and not _player_directional_attack_ok(target_node, hit_prev):
		target_node = null
	var anim_duration: float = _call_duration(player, "get_ranged_attack_feedback_duration")

	_play_sfx_if_available("Playershot")
	var total_visual: float = _spawn_projectile_visual_path(
		player,
		shot_trace.get("path_cells", [from_grid, hit_grid])
	)
	if total_visual > 0.0:
		await get_tree().create_timer(total_visual).timeout

	_apply_player_shot_hit(hit_grid, target_node, hit_prev)

	var phase_budget: float = maxf(anim_duration, total_visual)
	result["consumed_turn"] = true
	result["had_attack"] = true
	result["visual_duration"] = maxf(0.0, phase_budget - total_visual)
	return result


func _apply_player_shot_hit(hit_grid: Vector2i, target_node: Node, hit_prev: Vector2i) -> float:
	if player == null:
		return 0.0
	if player.has_method("play_ranged_impact_feedback"):
		player.call("play_ranged_impact_feedback", hit_grid)
	_play_random_impact_sfx()
	var hit_liquid := get_liquid_at(hit_grid)
	if hit_liquid != null and hit_liquid.has_method("ignite"):
		hit_liquid.call("ignite", default_fire_duration_turns)
	if target_node == null or not is_instance_valid(target_node) or not target_node.has_method("apply_damage"):
		return 0.0
	var damage := _call_int(player, "get_ranged_attack_damage", _call_int(player, "get_attack_damage", 1))
	var is_dead: bool = false
	if target_node.has_method("apply_damage_from_ranged"):
		is_dead = bool(target_node.call("apply_damage_from_ranged", damage, hit_prev))
	else:
		is_dead = bool(target_node.apply_damage(damage, hit_prev))
	if is_dead:
		occupancy.erase(hit_grid)
		if target_node is EnemyGridController:
			enemies.erase(target_node)
		return 0.0
	return _call_duration(target_node, "get_attack_feedback_duration")


func _resolve_player_action(direction: Vector2i, is_wait_action: bool = false) -> Dictionary:
	var result := {
		"consumed_turn": false,
		"had_attack": false,
		"visual_duration": 0.0,
		"force_wait_before_enemy": false,
		"did_grid_move": false,
	}
	if player == null:
		return result
	if not player.has_method("get"):
		return result
	if is_wait_action:
		if player.has_method("play_wait_feedback"):
			player.play_wait_feedback()
		result["consumed_turn"] = true
		result["visual_duration"] = 0.0
		result["force_wait_before_enemy"] = false
		return result
	if direction == Vector2i.ZERO:
		return result

	var from := player.get("grid_pos") as Vector2i
	var target := from + direction
	var melee_target := get_melee_target_at(target)
	if melee_target != null and not _player_directional_attack_ok(melee_target, from):
		melee_target = null
	if melee_target != null:
		if player.has_method("play_attack_feedback"):
			player.play_attack_feedback(target)
		var player_impact_sfx := PLAYER_IMPACT_SFX_NAMES[_rng.randi_range(0, PLAYER_IMPACT_SFX_NAMES.size() - 1)]
		_play_sfx_if_available(player_impact_sfx)
		result["consumed_turn"] = true
		result["had_attack"] = true
		var player_dur := _call_duration(player, "get_attack_feedback_duration")
		var target_feedback_dur := 0.0
		if melee_target.has_method("apply_damage"):
			var damage := _call_int(player, "get_attack_damage", 1)
			var is_dead: bool = bool(melee_target.apply_damage(damage, from))
			if is_dead:
				occupancy.erase(target)
				if is_instance_valid(melee_target) and melee_target is EnemyGridController:
					enemies.erase(melee_target)
			else:
				target_feedback_dur = _call_duration(melee_target, "get_attack_feedback_duration")
		result["visual_duration"] = maxf(player_dur, target_feedback_dur)
		return result

	if can_actor_step(player, from, target):
		_handle_door_transition(from, target, player)
		occupancy.erase(from)
		occupancy[target] = player
		if player.has_method("execute_turn_move"):
			player.execute_turn_move(target)
		_post_actor_moved_for_fire(player)
		_notify_submerged_abyss_barrel_platforms()
		result["consumed_turn"] = true
		result["visual_duration"] = _call_duration(player, "get_turn_move_duration")
		result["did_grid_move"] = true
		return result

	if player.has_method("play_blocked_feedback"):
		player.play_blocked_feedback(direction)
	if block_bump_consumes_turn:
		result["consumed_turn"] = true
		result["visual_duration"] = _call_duration(player, "get_block_feedback_duration")
	return result


func _resolve_enemy_action(enemy: EnemyGridController) -> Dictionary:
	var result := {
		"consumed_turn": true,
		"had_attack": false,
		"visual_duration": 0.0,
	}
	if enemy == null or not is_instance_valid(enemy):
		return result
	if player == null:
		return result

	var player_grid := player.get("grid_pos") as Vector2i
	var action := enemy.decide_turn_action(player_grid, self)
	var action_type := String(action.get("type", "wait"))

	if action_type == "attack":
		enemy.play_attack_feedback(player_grid)
		var enemy_sfx_name := ENEMY_HIT_SFX_NAMES[_rng.randi_range(0, ENEMY_HIT_SFX_NAMES.size() - 1)]
		_play_sfx_if_available(enemy_sfx_name)
		var player_dur := 0.0
		if player.has_method("apply_damage"):
			player.apply_damage(enemy.get_attack_damage(), enemy.grid_pos)
			player_dur = _call_duration(player, "get_damage_feedback_duration")
		result["had_attack"] = true
		result["visual_duration"] = maxf(enemy.get_attack_feedback_duration(), player_dur)
		return result

	if action_type == "move":
		var from := enemy.grid_pos
		var to := action.get("target_grid", from) as Vector2i
		if can_actor_step(enemy, from, to):
			_handle_door_transition(from, to, enemy)
			occupancy.erase(from)
			occupancy[to] = enemy
			enemy.execute_turn_move(to)
			_notify_submerged_abyss_barrel_platforms()
			_post_actor_moved_for_fire(enemy)
			result["visual_duration"] = enemy.get_turn_move_duration()
		return result

	return result


func _play_sfx_if_available(sfx_name: String) -> void:
	var audio_manager := _get_audio_manager()
	if audio_manager != null:
		audio_manager.call("play_sfx", sfx_name)
		return
	if not _audio_manager_missing_logged:
		_audio_manager_missing_logged = true
		push_warning("TurnController: 未找到可用的 AudioManager Autoload（需包含 play_sfx 方法）。")


func _note_fire_spread_this_resolve() -> void:
	_fire_spread_occurred_this_resolve = true


func _play_ignite_sfx_if_fire_spread_this_resolve() -> void:
	if not _fire_spread_occurred_this_resolve:
		return
	_fire_spread_occurred_this_resolve = false
	_play_sfx_if_available("Ignite")


func _get_audio_manager() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	var by_group: Node = tree.get_first_node_in_group("audio_manager_play_sfx")
	if by_group != null and by_group.has_method("play_sfx"):
		return by_group
	for autoload_name in AUDIO_MANAGER_CANDIDATE_NAMES:
		var node := tree.root.get_node_or_null(NodePath(autoload_name))
		if node != null and node.has_method("play_sfx"):
			return node
	for child in tree.root.get_children():
		if child != null and child.has_method("play_sfx"):
			return child
	return null


func _alive_enemies_ordered() -> Array[EnemyGridController]:
	var result: Array[EnemyGridController] = []
	for enemy in enemies:
		if enemy != null and is_instance_valid(enemy) and enemy.is_inside_tree() and not enemy.is_dead():
			result.append(enemy)
	result.sort_custom(func(a: EnemyGridController, b: EnemyGridController) -> bool:
		if a.turn_order != b.turn_order:
			return a.turn_order < b.turn_order
		return a.get_instance_id() < b.get_instance_id()
	)
	return result


func _refresh_runtime_state() -> void:
	_resolve_references()
	occupancy.clear()
	## 基底：可破坏柱/桶占格；飞行敌人可落脚于其上，故随后由敌人占用覆盖本格。
	for node in get_tree().get_nodes_in_group("breakable"):
		if node == null or not is_instance_valid(node):
			continue
		if node.is_queued_for_deletion():
			continue
		if not node.has_method("is_dead") or bool(node.call("is_dead")):
			continue
		if node.has_method("is_submerged_in_abyss") and bool(node.call("is_submerged_in_abyss")):
			continue
		if node.has_method("get"):
			var gp = node.get("grid_pos")
			if gp is Vector2i:
				occupancy[gp] = node

	var alive: Array[EnemyGridController] = []
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		if enemy.is_queued_for_deletion():
			continue
		if enemy.is_dead():
			continue
		alive.append(enemy)
		occupancy[enemy.grid_pos] = enemy
	enemies = alive

	if player != null and not _is_player_dead():
		var pg := _read_actor_grid_pos_for_platform(player)
		if pg.x > -999999:
			occupancy[pg] = player

	for node in get_tree().get_nodes_in_group("wall_switch"):
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var gps: Vector2i
		if node.has_method("get_occupancy_grid_pos"):
			var gpv: Variant = node.call("get_occupancy_grid_pos")
			if not (gpv is Vector2i):
				continue
			gps = gpv as Vector2i
		elif node.has_method("get"):
			var gpx = node.get("grid_pos")
			if not (gpx is Vector2i):
				continue
			gps = gpx as Vector2i
		else:
			continue
		occupancy[gps] = node

	_rebuild_liquids_registry_from_world_group()


func _connect_signals() -> void:
	if dungeon_generator == null:
		return
	var callable := Callable(self, "_on_dungeon_generated")
	if not dungeon_generator.generation_finished.is_connected(callable):
		dungeon_generator.generation_finished.connect(callable)


func _on_dungeon_generated() -> void:
	_resolve_references()
	clear_queued_actions()
	_is_resolving_turn = false
	_combat_pause_remaining = 0.0
	_purge_volatile_flammable_under_world()
	_rebuild_liquids_registry_from_world_group()
	_spawn_preset_flammable_liquids_from_dungeon()
	call_deferred("_refresh_runtime_state")


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


func _neighbor_offsets() -> Array[Vector2i]:
	if allow_diagonal_movement:
		return [
			Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
		]
	return [
		Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1),
	]


func _pick_step_by_bfs(actor: Node, start: Vector2i, target: Vector2i) -> Vector2i:
	if actor == null:
		return start
	if start == target:
		return start

	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var came_from: Dictionary = {}
	var best_node: Vector2i = start
	var best_score := start.distance_squared_to(target)
	var best_depth := 0
	var depth_by_node: Dictionary = {start: 0}

	while not queue.is_empty():
		var current := queue.pop_front() as Vector2i
		var depth := int(depth_by_node.get(current, 0))
		var score := current.distance_squared_to(target)
		if score < best_score or (score == best_score and depth < best_depth):
			best_score = score
			best_node = current
			best_depth = depth
			if best_score == 0:
				break

		for offset in _neighbor_offsets():
			var next := current + offset
			if visited.has(next):
				continue
			if not can_actor_step(actor, current, next):
				continue
			visited[next] = true
			came_from[next] = current
			depth_by_node[next] = depth + 1
			queue.append(next)

	if best_node == start:
		return start

	var step := best_node
	while came_from.has(step):
		var parent := came_from[step] as Vector2i
		if parent == start:
			return step
		step = parent
	return start


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


func _blocks_vision(pos: Vector2i) -> bool:
	if dungeon_generator == null:
		return true
	if pos.x < 0 or pos.y < 0 or pos.x >= dungeon_generator.map_width or pos.y >= dungeon_generator.map_height:
		return true
	if dungeon_generator._door_set.has(pos) and not bool(dungeon_generator._door_states.get(pos, false)):
		return true
	return DungeonGenerator.tile_blocks_vision(dungeon_generator.get_tile(pos) as DungeonGenerator.TileType)


func _splash_segment_blocks_propagation(cell: Vector2i) -> bool:
	if dungeon_generator == null:
		return true
	if cell.x < 0 or cell.y < 0 or cell.x >= dungeon_generator.map_width or cell.y >= dungeon_generator.map_height:
		return true
	var t: DungeonGenerator.TileType = dungeon_generator.get_tile(cell) as DungeonGenerator.TileType
	if DungeonGenerator.tile_blocks_projectile_solid(t):
		return true
	## 深渊不承载液体，但不应阻断泼溅射线。
	if dungeon_generator.is_inactive_door_at(cell):
		return true
	if dungeon_generator._door_set.has(cell):
		return not bool(dungeon_generator._door_states.get(cell, false))
	return false


func _splash_can_place_liquid_at(pos: Vector2i) -> bool:
	if dungeon_generator == null:
		return false
	if pos.x < 0 or pos.y < 0 or pos.x >= dungeon_generator.map_width or pos.y >= dungeon_generator.map_height:
		return false
	var t: DungeonGenerator.TileType = dungeon_generator.get_tile(pos) as DungeonGenerator.TileType
	if t != DungeonGenerator.TileType.FLOOR:
		return false
	if dungeon_generator.is_inactive_door_at(pos):
		return false
	if dungeon_generator._door_set.has(pos):
		return bool(dungeon_generator._door_states.get(pos, false))
	return true


func _splash_propagation_line_clear(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var line := _grid_line(from_cell, to_cell)
	if line.size() <= 1:
		return true
	for i in range(1, line.size()):
		var c: Vector2i = line[i]
		if _splash_segment_blocks_propagation(c):
			return false
	return true


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	if node == null or ancestor == null:
		return false
	var p: Node = node
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false


func _purge_volatile_flammable_under_world() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var to_drop: Array[Node] = []
	var volatile_grp: Array = tree.get_nodes_in_group("flammable_liquid")
	for i in range(volatile_grp.size()):
		var node: Node = volatile_grp[i] as Node
		if node == null or not is_instance_valid(node):
			continue
		if world != null and not _is_descendant_of(node, world):
			continue
		if node.has_meta("volatile_liquid") and node.get_meta("volatile_liquid") == true:
			to_drop.append(node)
	for q in to_drop:
		if q != null and is_instance_valid(q):
			q.free()


func _rebuild_liquids_registry_from_world_group() -> void:
	var rebuilt: Array[Node] = []
	var tree := get_tree()
	if tree != null:
		var liq_grp: Array = tree.get_nodes_in_group("flammable_liquid")
		for i in range(liq_grp.size()):
			var node: Node = liq_grp[i] as Node
			if node == null or not is_instance_valid(node) or not node.is_inside_tree():
				continue
			if world != null and not _is_descendant_of(node, world):
				continue
			rebuilt.append(node)
	liquids = rebuilt


func _spawn_preset_flammable_liquids_from_dungeon() -> void:
	if dungeon_generator == null or world == null:
		return
	if flammable_liquid_scene == null:
		return
	var preset_liquid_cells: Array[Vector2i] = dungeon_generator.get_preset_liquid_cells()
	for pi in range(preset_liquid_cells.size()):
		var c: Vector2i = preset_liquid_cells[pi]
		if not _splash_can_place_liquid_at(c):
			push_warning(
				"TurnController: preset_liquid_cells 格 (%d,%d) 当前不可铺液体（墙/深渊/门关等），已跳过。"
				% [c.x, c.y]
			)
			continue
		spawn_flammable_liquid(c)


## 东西向开关的「可走锚点格」与墙面占用格不同：鼠标点在锚点上时，将弹道目标改到墙面格以便与敌人/柱子同款判定。
func _remap_shot_target_for_wall_switch_floor_anchor(from_g: Vector2i, intended: Vector2i) -> Vector2i:
	for n in get_tree().get_nodes_in_group("wall_switch"):
		if not n is GridWallSwitch:
			continue
		var sw: GridWallSwitch = n as GridWallSwitch
		if sw.grid_pos != intended:
			continue
		match sw.facing:
			GridWallSwitch.Facing.APPROACH_WEST_HIT_EAST:
				var occ_w: Vector2i = sw.get_occupancy_grid_pos()
				if from_g.x < occ_w.x:
					return occ_w
			GridWallSwitch.Facing.APPROACH_EAST_HIT_WEST:
				var occ_e: Vector2i = sw.get_occupancy_grid_pos()
				if from_g.x > occ_e.x:
					return occ_e
			_:
				pass
	return intended


func _trace_projectile_hit(
	shooter: Node,
	from: Vector2i,
	intended_target: Vector2i,
	allow_ricochet: bool = false
) -> Dictionary:
	var result := {
		"hit_grid": intended_target,
		"target_node": null,
		"hit_prev_cell": from,
		"path_cells": PackedVector2Array([from]),
	}
	if from == intended_target:
		return result

	var max_range := _projectile_max_range_cells(shooter)
	var aim_line := _grid_line(from, intended_target)
	var path: Array[Vector2i] = [from]
	var pos := from
	var travelled := 0
	var bounce_count := 0
	var fly_dir := Vector2i.ZERO
	var on_aim_line := true
	var aim_idx := 1
	const MAX_BOUNCES := 12

	# 瞄准段沿 Bresenham；反弹后沿反射方向直线飞行，直至阻挡或射程上限（不再在瞄准点中途停下）。
	while travelled < max_range and bounce_count <= MAX_BOUNCES:
		var next: Vector2i
		if on_aim_line:
			if aim_idx >= aim_line.size():
				break
			next = aim_line[aim_idx] as Vector2i
			aim_idx += 1
		elif fly_dir != Vector2i.ZERO:
			next = pos + fly_dir
		else:
			break

		if next == pos:
			break

		var step_dir := next - pos
		var cell_hit := _evaluate_projectile_cell(shooter, pos, next, allow_ricochet)
		travelled += 1

		if cell_hit.is_empty():
			pos = next
			if on_aim_line and aim_idx >= aim_line.size():
				result["hit_grid"] = intended_target
				result["hit_prev_cell"] = aim_line[aim_line.size() - 2] as Vector2i if aim_line.size() >= 2 else from
				_append_unique_path_cell(path, intended_target)
				result["path_cells"] = PackedVector2Array(path)
				return result
			continue

		var stop_cell: Vector2i = cell_hit.get("stop_cell", next) as Vector2i
		var prev_cell: Vector2i = cell_hit.get("prev_cell", pos) as Vector2i
		_append_unique_path_cell(path, stop_cell)
		result["hit_grid"] = stop_cell
		result["hit_prev_cell"] = prev_cell
		var hit_target: Node = cell_hit.get("target_node", null) as Node
		if hit_target != null:
			result["target_node"] = hit_target
			result["path_cells"] = PackedVector2Array(path)
			return result

		var reason: String = String(cell_hit.get("reason", "stop"))
		if reason == "ricochet" and allow_ricochet:
			bounce_count += 1
			pos = stop_cell
			fly_dir = _compute_projectile_ricochet_dir(stop_cell, step_dir)
			on_aim_line = false
			if fly_dir == Vector2i.ZERO:
				result["path_cells"] = PackedVector2Array(path)
				return result
			continue

		result["path_cells"] = PackedVector2Array(path)
		return result

	_append_unique_path_cell(path, pos)
	result["hit_grid"] = pos
	result["hit_prev_cell"] = path[path.size() - 2] if path.size() >= 2 else from
	result["path_cells"] = PackedVector2Array(path)
	return result


func _evaluate_projectile_cell(
	shooter: Node,
	prev: Vector2i,
	next: Vector2i,
	allow_ricochet: bool
) -> Dictionary:
	if dungeon_generator == null \
			or next.x < 0 or next.y < 0 \
			or next.x >= dungeon_generator.map_width \
			or next.y >= dungeon_generator.map_height:
		return {
			"reason": "bounds",
			"stop_cell": prev,
			"prev_cell": prev,
			"target_node": null,
		}

	var blocker: Node = occupancy.get(next, null) as Node
	if blocker != null and blocker != shooter:
		if blocker is EnemyGridController and not _is_cell_currently_visible(next):
			return {}
		return {
			"reason": "occupancy",
			"stop_cell": next,
			"prev_cell": prev,
			"target_node": blocker if _can_be_hit_by_projectile(blocker) else null,
		}

	var tile: DungeonGenerator.TileType = dungeon_generator.get_tile(next) as DungeonGenerator.TileType
	if DungeonGenerator.tile_reflects_projectiles(tile):
		if not allow_ricochet:
			return {
				"reason": "wall",
				"stop_cell": next,
				"prev_cell": prev,
				"target_node": null,
			}
		var reflect_dir := _compute_projectile_ricochet_dir(next, next - prev)
		return {
			"reason": "ricochet",
			"stop_cell": next,
			"prev_cell": prev,
			"target_node": null,
			"reflect_dir": reflect_dir,
		}

	if _blocks_projectile_cell(next):
		return {
			"reason": "wall",
			"stop_cell": next,
			"prev_cell": prev,
			"target_node": null,
		}

	return {}


func _trace_projectile_segment(
	shooter: Node,
	start: Vector2i,
	dir: Vector2i,
	max_steps: int,
	allow_ricochet: bool
) -> Dictionary:
	var pos := start
	var prev := start
	var crossed: Array[Vector2i] = []
	for _step in range(maxi(0, max_steps)):
		var next := pos + dir
		if dungeon_generator == null \
				or next.x < 0 or next.y < 0 \
				or next.x >= dungeon_generator.map_width \
				or next.y >= dungeon_generator.map_height:
			return {
				"reason": "bounds",
				"stop_cell": pos,
				"prev_cell": prev,
				"steps": _step,
				"target_node": null,
				"crossed_cells": crossed,
			}
		var blocker: Node = occupancy.get(next, null) as Node
		if blocker != null and blocker != shooter:
			if blocker is EnemyGridController and not _is_cell_currently_visible(next):
				prev = pos
				pos = next
				crossed.append(next)
				continue
			crossed.append(next)
			return {
				"reason": "occupancy",
				"stop_cell": next,
				"prev_cell": pos,
				"steps": _step + 1,
				"target_node": blocker if _can_be_hit_by_projectile(blocker) else null,
				"crossed_cells": crossed,
			}
		var tile: DungeonGenerator.TileType = dungeon_generator.get_tile(next) as DungeonGenerator.TileType
		if DungeonGenerator.tile_reflects_projectiles(tile):
			crossed.append(next)
			if not allow_ricochet:
				return {
					"reason": "wall",
					"stop_cell": next,
					"prev_cell": pos,
					"steps": _step + 1,
					"target_node": null,
					"crossed_cells": crossed,
				}
			var reflect_dir := _compute_projectile_ricochet_dir(next, dir)
			return {
				"reason": "ricochet",
				"stop_cell": next,
				"prev_cell": pos,
				"steps": _step + 1,
				"target_node": null,
				"reflect_dir": reflect_dir,
				"crossed_cells": crossed,
			}
		if _blocks_projectile_cell(next):
			crossed.append(next)
			return {
				"reason": "wall",
				"stop_cell": next,
				"prev_cell": pos,
				"steps": _step + 1,
				"target_node": null,
				"crossed_cells": crossed,
			}
		prev = pos
		pos = next
		crossed.append(next)
	return {
		"reason": "range",
		"stop_cell": pos,
		"prev_cell": prev,
		"steps": max_steps,
		"target_node": null,
		"crossed_cells": crossed,
	}


## 按反弹墙贴图朝向（邻接地板）作法线，对入射步进 `incident` 做镜面反射。
func _compute_projectile_ricochet_dir(wall_cell: Vector2i, incident: Vector2i) -> Vector2i:
	if incident == Vector2i.ZERO:
		return Vector2i.ZERO
	if dungeon_generator != null:
		return dungeon_generator.get_ricochet_reflect_dir(wall_cell, incident)
	return -incident


func _signi_nonzero(v: float) -> int:
	if v > 0.25:
		return 1
	if v < -0.25:
		return -1
	return 0


func _projectile_initial_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	var line := _grid_line(from, to)
	if line.size() >= 2:
		var delta := (line[1] as Vector2i) - (line[0] as Vector2i)
		return Vector2i(signi(delta.x), signi(delta.y))
	return Vector2i.ZERO


func _projectile_max_range_cells(shooter: Node) -> int:
	if shooter != null and shooter.has_method("get"):
		var dist_v: Variant = shooter.get("ranged_max_distance")
		if dist_v is int or dist_v is float:
			return maxi(1, int(dist_v))
	return 24


func _play_random_impact_sfx() -> void:
	if PLAYER_IMPACT_SFX_NAMES.is_empty():
		return
	var pick := PLAYER_IMPACT_SFX_NAMES[_rng.randi_range(0, PLAYER_IMPACT_SFX_NAMES.size() - 1)]
	_play_sfx_if_available(pick)


## 反弹拐点：与远程命中相同的击中粒子 + 随机 Impact 音效。
func _play_projectile_bounce_feedback(bounce_grid: Vector2i) -> void:
	if player != null and player.has_method("play_ranged_impact_feedback"):
		player.call("play_ranged_impact_feedback", bounce_grid)
	_play_random_impact_sfx()


func preview_player_shot_trace(target_grid: Vector2i, from_grid_override = null) -> Dictionary:
	_refresh_runtime_state()
	_resolve_fog_of_war()
	if player == null or not player.has_method("get"):
		return {"hit_grid": target_grid, "target_node": null, "hit_prev_cell": target_grid}
	var from_grid: Vector2i
	if typeof(from_grid_override) == TYPE_VECTOR2I:
		from_grid = from_grid_override as Vector2i
	else:
		from_grid = player.get("grid_pos") as Vector2i
	var shot_goal := _remap_shot_target_for_wall_switch_floor_anchor(from_grid, target_grid)
	var trace := _trace_projectile_hit(player, from_grid, shot_goal, false)
	var tn: Node = trace.get("target_node", null) as Node
	if tn != null:
		var prev: Vector2i = trace.get("hit_prev_cell", from_grid) as Vector2i
		if not _player_directional_attack_ok(tn, prev):
			trace["target_node"] = null
	return trace


func _resolve_fog_of_war() -> void:
	if _fog_of_war != null and is_instance_valid(_fog_of_war):
		return
	var found := get_tree().get_first_node_in_group("fog_of_war")
	if found != null and is_instance_valid(found):
		_fog_of_war = found


func _is_cell_currently_visible(pos: Vector2i) -> bool:
	_resolve_fog_of_war()
	if _fog_of_war == null or not is_instance_valid(_fog_of_war):
		return true
	if _fog_of_war.has_method("is_cell_visible"):
		return _fog_of_war.call("is_cell_visible", pos) == true
	return true


func _can_be_hit_by_projectile(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node is EnemyGridController:
		return true
	if node.has_method("can_receive_melee") and bool(node.call("can_receive_melee")):
		return true
	return false


func _blocks_projectile_cell(pos: Vector2i) -> bool:
	if dungeon_generator == null:
		return true
	if pos.x < 0 or pos.y < 0 or pos.x >= dungeon_generator.map_width or pos.y >= dungeon_generator.map_height:
		return true
	if dungeon_generator._door_set.has(pos) and not bool(dungeon_generator._door_states.get(pos, false)):
		return true
	var tile: DungeonGenerator.TileType = dungeon_generator.get_tile(pos) as DungeonGenerator.TileType
	if DungeonGenerator.tile_reflects_projectiles(tile):
		return false
	return DungeonGenerator.tile_blocks_projectile_solid(tile)


## 与 `_process_liquid_turn_effects` 中「对占据者 apply_damage」的判断一致，预测本阶段即将造成的燃烧液伤害。
func _player_would_take_imminent_liquid_burn_damage() -> bool:
	if player == null or _is_player_dead():
		return false
	if not player.has_method("get"):
		return false
	if player.has_method("get_fire_attachment_turns"):
		var ft: Variant = player.call("get_fire_attachment_turns")
		if ft is int and int(ft) > 0:
			return true
	var gp: Variant = player.get("grid_pos")
	if not (gp is Vector2i):
		return false
	var cell := gp as Vector2i
	if occupancy.get(cell, null) != player:
		return false
	for liquid in liquids:
		if liquid == null or not is_instance_valid(liquid):
			continue
		var should_resolve := true
		if liquid.has_method("should_resolve_this_turn"):
			should_resolve = liquid.call("should_resolve_this_turn") == true
		if not should_resolve:
			continue
		if not liquid.has_method("is_burning") or liquid.call("is_burning") != true:
			continue
		if not liquid.has_method("get"):
			continue
		var lgp = liquid.get("grid_pos")
		if lgp is Vector2i and (lgp as Vector2i) == cell:
			return true
	return false


## 悬浮/同格单位与桶叠放时 `occupancy` 为上方单位，仅烧液体时才会对其结算；无液体仅有燃烧桶时需补上与燃烧液同格等价的着火与环境伤。
func _append_actors_on_burning_barrels_to_cell_fire_hits(cell_fire_hits: Array[Dictionary]) -> void:
	var liquid_fire_cells: Dictionary = {}
	for hit in cell_fire_hits:
		var pv: Variant = hit.get("pos", null)
		if pv is Vector2i:
			liquid_fire_cells[pv as Vector2i] = true
	for n in get_tree().get_nodes_in_group("ignitable_breakable"):
		if n == null or not is_instance_valid(n):
			continue
		if not (n is BreakableBarrel):
			continue
		var b := n as BreakableBarrel
		if b.is_dead() or b.is_submerged_in_abyss() or not b.is_burning():
			continue
		var gp := b.grid_pos
		if liquid_fire_cells.has(gp):
			continue
		var occ: Node = occupancy.get(gp, null) as Node
		if occ == null or occ == b:
			continue
		if occ is BreakableBarrel:
			continue
		if occ.has_method("set_fire_attachment_turns"):
			occ.call("set_fire_attachment_turns", default_fire_duration_turns, true)
		cell_fire_hits.append({"pos": gp, "target": occ})


func _process_liquid_turn_effects() -> void:
	var cell_fire_hits: Array[Dictionary] = []
	var burning_liquid_positions: Array[Vector2i] = []
	for liquid in liquids:
		if liquid == null or not is_instance_valid(liquid):
			continue
		var should_resolve := true
		if liquid.has_method("should_resolve_this_turn"):
			should_resolve = liquid.call("should_resolve_this_turn") == true
		if liquid.has_method("is_burning") and liquid.call("is_burning") == true and should_resolve and liquid.has_method("get"):
			var bp = liquid.get("grid_pos")
			if bp is Vector2i:
				burning_liquid_positions.append(bp as Vector2i)
		if should_resolve and liquid.has_method("advance_turn"):
			liquid.call("advance_turn")
		if not should_resolve:
			continue
		if not liquid.has_method("is_burning") or liquid.call("is_burning") != true:
			continue
		if not liquid.has_method("get"):
			continue
		var gp_l = liquid.get("grid_pos")
		if not (gp_l is Vector2i):
			continue
		var pos := gp_l as Vector2i
		var target: Node = occupancy.get(pos, null) as Node
		if target == null:
			continue
		cell_fire_hits.append({"pos": pos, "target": target})

	_append_actors_on_burning_barrels_to_cell_fire_hits(cell_fire_hits)

	var cell_fire_actor_ids: Dictionary = {}
	for hit in cell_fire_hits:
		var t_hit: Node = hit.get("target") as Node
		var pos_hit: Vector2i = hit.get("pos") as Vector2i
		cell_fire_actor_ids[t_hit.get_instance_id()] = true
		if t_hit is BreakableBarrel:
			## 已在燃烧时不再用脚下液体刷新剩余燃烧回合，否则桶火与液体不同步会永远烧不完。
			if t_hit.has_method("is_burning") and t_hit.call("is_burning") == true:
				continue
			if t_hit.has_method("ignite_from_liquid_spread"):
				t_hit.call("ignite_from_liquid_spread", default_fire_duration_turns, true)
			if t_hit.has_method("is_burning") and t_hit.call("is_burning") == true:
				_note_fire_spread_this_resolve()
			continue
		if t_hit.has_method("trigger_from_environment_damage"):
			t_hit.call("trigger_from_environment_damage", 1)
			continue
		if not t_hit.has_method("apply_damage"):
			continue
		var dmg_res: Variant = t_hit.call("apply_damage", 1, pos_hit)
		var is_dead_c: bool = dmg_res is bool and bool(dmg_res as bool)
		if not is_dead_c and t_hit.has_method("is_dead"):
			is_dead_c = bool(t_hit.call("is_dead"))
		if is_dead_c:
			occupancy.erase(pos_hit)
			if is_instance_valid(t_hit) and t_hit is EnemyGridController and t_hit.has_method("play_death_animation"):
				t_hit.call("play_death_animation")

	_apply_ignite_attachment_burn_damage(cell_fire_actor_ids)

	_spread_liquid_fire(burning_liquid_positions)

	_ignite_breakables_adjacent_to_burning_liquids()

	_process_barrel_environment_fire_spread()

	_apply_fire_chain_ticks_to_ignited_breakables()

	_tick_actor_fire_attachment_durations()

	_cleanup_burned_out_liquids()


func _apply_ignite_attachment_burn_damage(cell_fire_actor_ids: Dictionary) -> void:
	if player != null and not _is_player_dead():
		if not cell_fire_actor_ids.has(player.get_instance_id()) \
				and player.has_method("get_fire_attachment_turns") \
				and int(player.call("get_fire_attachment_turns")) > 0 \
				and player.has_method("apply_damage"):
			var pg: Vector2i = player.get("grid_pos") as Vector2i
			var dead_p: bool = player.call("apply_damage", 1, pg) == true
			if dead_p:
				occupancy.erase(pg)
	for enemy in _alive_enemies_ordered():
		if cell_fire_actor_ids.has(enemy.get_instance_id()):
			continue
		if not enemy.has_method("get_fire_attachment_turns") or int(enemy.call("get_fire_attachment_turns")) <= 0:
			continue
		if not enemy.has_method("apply_damage"):
			continue
		var egp := enemy.grid_pos
		var dead_e: bool = enemy.call("apply_damage", 1, egp) == true
		if dead_e:
			occupancy.erase(egp)
			if is_instance_valid(enemy) and enemy.has_method("play_death_animation"):
				enemy.call("play_death_animation")


func _collect_all_burning_liquid_cell_positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for liquid in liquids:
		if liquid == null or not is_instance_valid(liquid):
			continue
		if liquid.has_method("is_burning") and liquid.call("is_burning") != true:
			continue
		if not liquid.has_method("get"):
			continue
		var gpv = liquid.get("grid_pos")
		if gpv is Vector2i:
			var v := gpv as Vector2i
			if not out.has(v):
				out.append(v)
	return out


func _ignite_breakables_adjacent_to_burning_liquids() -> void:
	var cells := _collect_all_burning_liquid_cell_positions()
	var seen: Dictionary = {}
	for gp in cells:
		for off in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]:
			var t: Vector2i = gp + off
			if seen.has(t):
				continue
			var node := _find_ignitable_breakable_at(t)
			if node == null:
				continue
			seen[t] = true
			if node is BreakableBarrel and node.has_method("is_burning") and node.call("is_burning") == true:
				continue
			var was_burning := false
			if node.has_method("is_burning"):
				was_burning = node.call("is_burning") == true
			if node.has_method("ignite_from_liquid_spread"):
				node.call("ignite_from_liquid_spread", default_fire_duration_turns, true)
			if node.has_method("is_burning") and node.call("is_burning") == true and not was_burning:
				_note_fire_spread_this_resolve()


## 站立燃烧桶的环境传火：每个液体阶段、每桶**至多**向八邻格成功点燃**一格**（液体或另一桶）；
## 新点燃的桶当阶段不播散；成功播散后隔一液体阶段才能再播（见 `BreakableBarrel.tick_env_fire_spread_eligible`）。
func _process_barrel_environment_fire_spread() -> void:
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var barrels: Array[BreakableBarrel] = []
	for n in get_tree().get_nodes_in_group("ignitable_breakable"):
		if n == null or not is_instance_valid(n):
			continue
		if not (n is BreakableBarrel):
			continue
		var b := n as BreakableBarrel
		if b.is_dead() or b.is_submerged_in_abyss() or not b.is_burning():
			continue
		barrels.append(b)
	barrels.sort_custom(func(a: BreakableBarrel, b: BreakableBarrel) -> bool:
		return a.get_instance_id() < b.get_instance_id()
	)
	for barrel in barrels:
		if not barrel.tick_env_fire_spread_eligible():
			continue
		var gp: Vector2i = barrel.grid_pos
		var spread_done := false
		for off in OFFSETS:
			var t: Vector2i = gp + off
			var liq := get_liquid_at(t)
			if liq != null:
				if _try_ignite_flammable_liquid_fresh_only(liq, default_fire_duration_turns):
					spread_done = true
					_note_fire_spread_this_resolve()
					break
			var other := _find_ignitable_breakable_at(t)
			if other != null and other is BreakableBarrel and other != barrel:
				var ob := other as BreakableBarrel
				if ob.is_dead() or ob.is_burning():
					continue
				ob.ignite_from_liquid_spread(default_fire_duration_turns, true)
				if ob.is_burning():
					spread_done = true
					_note_fire_spread_this_resolve()
					break
		if spread_done:
			barrel.mark_env_fire_spread_consumed()


func _find_ignitable_breakable_at(pos: Vector2i) -> Node:
	for n in get_tree().get_nodes_in_group("ignitable_breakable"):
		if n == null or not is_instance_valid(n):
			continue
		if n.has_method("is_dead") and bool(n.call("is_dead")):
			continue
		if n.has_method("is_submerged_in_abyss") and bool(n.call("is_submerged_in_abyss")):
			continue
		if not n.has_method("get"):
			continue
		var gpv = n.get("grid_pos")
		if gpv is Vector2i and (gpv as Vector2i) == pos:
			return n
	return null


func _apply_fire_chain_ticks_to_ignited_breakables() -> void:
	for n in get_tree().get_nodes_in_group("ignitable_breakable"):
		if n == null or not is_instance_valid(n):
			continue
		if n.has_method("is_dead") and bool(n.call("is_dead")):
			continue
		if not n.has_method("is_burning") or n.call("is_burning") != true:
			continue
		if n.has_method("apply_fire_chain_tick"):
			n.call("apply_fire_chain_tick")


func _tick_actor_fire_attachment_durations() -> void:
	if player != null and player.has_method("advance_fire_attachment_turn"):
		player.call("advance_fire_attachment_turn")
	for enemy in enemies:
		if enemy != null and is_instance_valid(enemy) and enemy.has_method("advance_fire_attachment_turn"):
			enemy.call("advance_fire_attachment_turn")

	if debug_log_fire_attachment_remaining:
		if player != null and player.has_method("get_fire_attachment_turns"):
			var pr: Variant = player.call("get_fire_attachment_turns")
			print(
				"TurnController(debug): cfg_fire_turns=", default_fire_duration_turns,
				" player_attachment_remaining=", pr
			)
		var ei := 0
		for e in enemies:
			if e == null:
				continue
			if not e.has_method("get_fire_attachment_turns"):
				continue
			var rv: Variant = e.call("get_fire_attachment_turns")
			print("TurnController(debug): enemy[", ei, "] attachment_remaining=", rv)
			ei += 1


func _post_actor_moved_for_fire(actor: Node) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if not actor.has_method("get"):
		return
	var gpv = actor.get("grid_pos")
	if not (gpv is Vector2i):
		return
	var gp: Vector2i = gpv as Vector2i
	var liq := get_liquid_at(gp)
	if liq != null and liq.has_method("is_burning") and bool(liq.call("is_burning")):
		if actor.has_method("set_fire_attachment_turns"):
			## refresh_existing=true：重新踏入火焰刷新满持续时间
			actor.call("set_fire_attachment_turns", default_fire_duration_turns, true)
	_ignite_adjacent_liquids_from_burning_walker(actor, gp)


func _ignite_adjacent_liquids_from_burning_walker(_actor: Node, gp: Vector2i) -> void:
	if _actor.has_method("get_fire_attachment_turns") and int(_actor.call("get_fire_attachment_turns")) <= 0:
		return
	for off in [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]:
		var t: Vector2i = gp + off
		var liq2 := get_liquid_at(t)
		if liq2 != null:
			if _try_ignite_flammable_liquid_fresh_only(liq2, default_fire_duration_turns):
				_note_fire_spread_this_resolve()


func _spread_liquid_fire(origins: Array[Vector2i]) -> void:
	var origin_set: Dictionary = {}
	for gp in origins:
		origin_set[gp] = true
	for origin_var in origins:
		var origin: Vector2i = origin_var
		for offset_var in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]:
			var offset: Vector2i = offset_var
			var next_pos: Vector2i = origin + offset
			if origin_set.has(next_pos):
				continue
			var target_liquid := get_liquid_at(next_pos)
			if target_liquid == null:
				continue
			if target_liquid.has_method("is_burning") and target_liquid.call("is_burning") == true:
				continue
			if target_liquid.has_method("ignite"):
				target_liquid.call("ignite", default_fire_duration_turns, false)
				if target_liquid.has_method("is_burning") and target_liquid.call("is_burning") == true:
					_note_fire_spread_this_resolve()


func _cleanup_burned_out_liquids() -> void:
	var alive_liquids: Array[Node] = []
	for liquid in liquids:
		if liquid == null or not is_instance_valid(liquid) or not liquid.is_inside_tree():
			continue
		if liquid.has_method("is_burned_out") and liquid.call("is_burned_out") == true:
			liquid.queue_free()
			continue
		alive_liquids.append(liquid)
	liquids = alive_liquids


func _spawn_projectile_visual(shooter: Node, from: Vector2i, to: Vector2i) -> void:
	_spawn_projectile_visual_path(shooter, [from, to])


func _append_unique_path_cell(path: Array[Vector2i], cell: Vector2i) -> void:
	if path.is_empty() or path[path.size() - 1] != cell:
		path.append(cell)


func _spawn_projectile_visual_path(shooter: Node, path_cells: Variant) -> float:
	if GRID_PROJECTILE_SCRIPT == null:
		return 0.0
	var cells: Array[Vector2i] = []
	if path_cells is PackedVector2Array:
		for pv in path_cells as PackedVector2Array:
			cells.append(pv)
	elif path_cells is Array:
		for item in path_cells:
			if item is Vector2i:
				cells.append(item)
	cells = _dedupe_consecutive_path_cells(cells)
	if cells.is_empty():
		return 0.0

	var world_points := _dedupe_consecutive_world_points(
		_projectile_visual_world_points(shooter, cells)
	)
	if world_points.size() < 2:
		return 0.0
	if cells.size() >= 3 and world_points.size() < 3:
		push_warning(
			"TurnController: 反弹弹道缺少拐点（path_cells 仅 %d 格），弹体将按直线飞行。"
			% cells.size()
		)

	var total_visual := _projectile_visual_timeline_duration(
		world_points,
		projectile_travel_speed,
		0.0
	)
	if cells.size() >= 3 and world_points.size() >= 3:
		_schedule_visual_ricochet_bounce_feedback(
			world_points,
			cells,
			projectile_travel_speed
		)

	var projectile: Node2D = GRID_PROJECTILE_SCRIPT.new() as Node2D
	if projectile == null:
		return total_visual
	var parent_node: Node = world if world != null else self
	parent_node.add_child(projectile)
	# 反弹与直线均走 fire_path + 恒定段速，避免两点时 chord 或 bind+tween_method 导致“瞬移”。
	if projectile.has_method("fire_path"):
		projectile.call("fire_path", world_points, -1.0, projectile_travel_speed, 0.0)
	elif projectile.has_method("fire"):
		projectile.call("fire", world_points[0], world_points[world_points.size() - 1], total_visual)
	return total_visual


func _dedupe_consecutive_path_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= 1:
		return cells.duplicate()
	var out: Array[Vector2i] = [cells[0]]
	for i in range(1, cells.size()):
		if cells[i] != out[out.size() - 1]:
			out.append(cells[i])
	return out


## 直线段：枪口 → 各反弹格 → 落点（`path_cells` 仅含拐点，不沿 Bresenham 逐格）。
func _projectile_visual_world_points(shooter: Node, cells: Array[Vector2i]) -> PackedVector2Array:
	if cells.is_empty():
		return PackedVector2Array()

	var points := PackedVector2Array()
	if shooter is Node2D:
		points.append((shooter as Node2D).global_position)
	else:
		points.append(_grid_cell_global_for_actor(shooter, cells[0]))

	for i in range(1, cells.size()):
		points.append(_grid_cell_global_for_actor(shooter, cells[i]))

	if points.size() == 1:
		points.append(points[0])
	return points


func _projectile_visual_travel_duration(world_points: PackedVector2Array) -> float:
	return _projectile_visual_timeline_duration(world_points, projectile_travel_speed, 0.0)


## 与 `GridProjectile._build_path_timeline` 一致：段速恒定 + 拐点停顿。
func _projectile_visual_timeline_duration(
	world_points: PackedVector2Array,
	move_speed: float,
	corner_pause: float
) -> float:
	if world_points.size() < 2:
		return projectile_travel_min_duration
	var speed := maxf(move_speed, 1.0)
	var total := 0.0
	for seg_i in range(1, world_points.size()):
		var seg_len := world_points[seg_i - 1].distance_to(world_points[seg_i])
		if seg_len <= 1e-5:
			continue
		total += maxf(0.02, seg_len / speed)
		if seg_i < world_points.size() - 1 and corner_pause > 0.0:
			total += corner_pause
	return maxf(projectile_travel_min_duration, total)


func _dedupe_consecutive_world_points(
	points: PackedVector2Array,
	min_dist: float = 4.0
) -> PackedVector2Array:
	if points.size() <= 1:
		return points
	var out := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		if points[i].distance_to(out[out.size() - 1]) > min_dist:
			out.append(points[i])
	if out.size() == 1:
		out.append(points[points.size() - 1])
	return out


func _schedule_visual_ricochet_bounce_feedback(
	world_points: PackedVector2Array,
	cells: Array[Vector2i],
	move_speed: float
) -> void:
	var speed := maxf(move_speed, 1.0)
	var elapsed := 0.0
	for bend_i in range(1, world_points.size() - 1):
		var seg_len := world_points[bend_i - 1].distance_to(world_points[bend_i])
		if seg_len <= 1e-5:
			continue
		elapsed += maxf(0.02, seg_len / speed)
		var bounce_at := elapsed
		if bend_i < cells.size():
			var bounce_grid := cells[bend_i]
			var timer := get_tree().create_timer(bounce_at)
			timer.timeout.connect(
				_play_projectile_bounce_feedback.bind(bounce_grid),
				CONNECT_ONE_SHOT
			)


func _grid_to_world_for_actor(actor: Node, grid: Vector2i) -> Vector2:
	if actor != null and actor.has_method("grid_to_world"):
		return actor.call("grid_to_world", grid) as Vector2
	if dungeon_generator != null:
		var ts := float(dungeon_generator.tile_size)
		return Vector2(grid) * ts + Vector2.ONE * (ts * 0.5)
	return Vector2(grid)


## `grid_to_world` 与同层演员 `position` 一致（上层 Node2D 局部坐标）；不能用 `actor.to_global(lp)`。
func _grid_cell_global_for_actor(actor: Node, grid: Vector2i) -> Vector2:
	var lp: Vector2 = _grid_to_world_for_actor(actor, grid)
	if actor == null:
		return lp
	var n: Node = actor.get_parent()
	while n != null:
		if n is Node2D:
			return (n as Node2D).to_global(lp)
		n = n.get_parent()
	push_warning("TurnController: 未找到 Node2D 祖先，grid→world 退回局部 lp。")
	return lp


func _is_diagonal_pillar_gap(from: Vector2i, to: Vector2i) -> bool:
	if dungeon_generator == null:
		return false
	var from_is_floor := dungeon_generator.get_tile(from) == DungeonGenerator.TileType.FLOOR
	var to_is_floor := dungeon_generator.get_tile(to) == DungeonGenerator.TileType.FLOOR
	if not from_is_floor or not to_is_floor:
		return false
	# 当对角两端均为地板，且仅正交侧格阻挡时，允许穿过“柱子夹缝”。
	return true


## 地板 ↔ 深渊木桶浮台：允许斜向进出（两侧切角格可为无浮台的深渊）。
func _is_diagonal_abyss_platform_crossing(from: Vector2i, to: Vector2i) -> bool:
	if dungeon_generator == null:
		return false
	var from_is_floor := dungeon_generator.get_tile(from) == DungeonGenerator.TileType.FLOOR
	var to_is_floor := dungeon_generator.get_tile(to) == DungeonGenerator.TileType.FLOOR
	var from_is_platform := (
		dungeon_generator.get_tile(from) == DungeonGenerator.TileType.ABYSS
		and dungeon_generator.has_abyss_barrel_platform(from)
	)
	var to_is_platform := (
		dungeon_generator.get_tile(to) == DungeonGenerator.TileType.ABYSS
		and dungeon_generator.has_abyss_barrel_platform(to)
	)
	return (from_is_floor and to_is_platform) or (from_is_platform and to_is_floor)


func _is_walkable_tile(pos: Vector2i) -> bool:
	if dungeon_generator == null:
		return false
	if pos.x < 0 or pos.y < 0 or pos.x >= dungeon_generator.map_width or pos.y >= dungeon_generator.map_height:
		return false
	if dungeon_generator.get_tile(pos) != DungeonGenerator.TileType.FLOOR:
		return false
	return true


func _is_walkable_for_actor(actor: Node, pos: Vector2i) -> bool:
	return _actor_can_enter_cell(actor, pos, false)


func _actor_can_enter_cell(actor: Node, pos: Vector2i, explosion_knockback: bool) -> bool:
	if dungeon_generator == null:
		return false
	if pos.x < 0 or pos.y < 0 or pos.x >= dungeon_generator.map_width or pos.y >= dungeon_generator.map_height:
		return false
	var t: DungeonGenerator.TileType = dungeon_generator.get_tile(pos) as DungeonGenerator.TileType
	if DungeonGenerator.tile_blocks_movement(t):
		return false
	if t == DungeonGenerator.TileType.ABYSS:
		var allow_abyss := false
		if explosion_knockback and actor != null and actor.is_in_group("player"):
			allow_abyss = true
		else:
			var floater: EnemyGridController = actor as EnemyGridController
			if floater != null and floater.floating:
				allow_abyss = true
			elif dungeon_generator.has_abyss_barrel_platform(pos):
				allow_abyss = true
		if not allow_abyss:
			return false
	elif t != DungeonGenerator.TileType.FLOOR:
		return false

	if dungeon_generator.is_inactive_door_at(pos):
		return false

	## 木桶：只要门已激活（非未激活假门），门格均视为可跌入；击退落地时 `DungeonGenerator.ensure_door_open_at` 会保持敞开。
	if actor is BreakableBarrel and dungeon_generator._door_set.has(pos):
		return true

	if not dungeon_generator._door_set.has(pos):
		return true

	var is_open := bool(dungeon_generator._door_states.get(pos, false))
	if is_open:
		return true

	# 玩家允许踩到门格，由原有逻辑在到达后切换门状态。
	if actor != null and actor.is_in_group("player"):
		return true
	# 敌人可选开门：能踩到门格，并在到达后触发开门逻辑。
	if actor != null and actor.is_in_group("enemy"):
		if actor.has_method("can_open_doors") and bool(actor.call("can_open_doors")):
			return true
	return false


func _call_duration(target: Node, method_name: String) -> float:
	if target != null and target.has_method(method_name):
		return float(target.call(method_name))
	return 0.0


func _call_int(target: Node, method_name: String, fallback: int) -> int:
	if target != null and target.has_method(method_name):
		return int(target.call(method_name))
	return fallback


func _is_player_dead() -> bool:
	if player == null:
		return false
	if player.has_method("is_dead"):
		return bool(player.call("is_dead"))
	return false


func _can_begin_next_turn() -> bool:
	if _any_barrel_knockback_busy():
		return false
	if player == null:
		return true
	if player.has_method("is_busy_for_turn"):
		return not bool(player.call("is_busy_for_turn"))
	return true


func _has_queued_player_shot() -> bool:
	return _queued_player_shot_target != Vector2i(-9999, -9999)


func is_any_burning_liquid_visible_to_player() -> bool:
	for liquid in liquids:
		if liquid == null or not is_instance_valid(liquid) or not liquid.is_inside_tree():
			continue
		if liquid.has_method("is_burning") and liquid.call("is_burning") != true:
			continue
		if not liquid.has_method("get"):
			continue
		var gp_variant = liquid.get("grid_pos")
		if gp_variant is Vector2i:
			if _is_cell_currently_visible(gp_variant as Vector2i):
				return true
	return false


## 仅对**从未点燃过**的液体有效；已点燃/烧尽过的格由 `FlammableLiquid.ignite` 内部拒绝（第二参数已废弃）。
## 返回本次调用是否使该格**新进入**燃烧状态（用于蔓延音效等）。
func _try_ignite_flammable_liquid_fresh_only(liq: Node, turns: int) -> bool:
	if liq == null or not is_instance_valid(liq) or not liq.has_method("ignite"):
		return false
	var was_burning := false
	if liq.has_method("is_burning"):
		was_burning = liq.call("is_burning") == true
	liq.call("ignite", turns, false)
	if liq.has_method("is_burning") and liq.call("is_burning") == true and not was_burning:
		return true
	return false


func _any_barrel_knockback_busy() -> bool:
	for n in get_tree().get_nodes_in_group("breakable"):
		if n == null or not is_instance_valid(n):
			continue
		if n is BreakableBarrel and n.has_method("is_knockback_busy") \
				and bool(n.call("is_knockback_busy")):
			return true
	return false


func _await_all_barrel_knockbacks_finished() -> void:
	var guard := 0
	while _any_barrel_knockback_busy():
		await get_tree().process_frame
		guard += 1
		if guard > 7200:
			push_warning("TurnController: barrel knockback wait exceeded safety frames.")
			break


func _notify_submerged_abyss_barrel_platforms() -> void:
	for n in get_tree().get_nodes_in_group("breakable"):
		if not (n is BreakableBarrel):
			continue
		var b := n as BreakableBarrel
		if b.is_submerged_in_abyss():
			b.sync_abyss_platform_visual()


func _door_cell_has_live_barrel_occupant(cell: Vector2i) -> bool:
	for n in get_tree().get_nodes_in_group("breakable"):
		if not (n is BreakableBarrel):
			continue
		if n == null or not is_instance_valid(n):
			continue
		if n.has_method("is_dead") and bool(n.call("is_dead")):
			continue
		if n.has_method("is_submerged_in_abyss") and bool(n.call("is_submerged_in_abyss")):
			continue
		if not n.has_method("get"):
			continue
		var gpv = n.get("grid_pos")
		if gpv is Vector2i and (gpv as Vector2i) == cell:
			return true
	return false


func _handle_door_transition(from: Vector2i, to: Vector2i, opener: Node = null) -> void:
	if dungeon_generator == null or from == to:
		return
	if dungeon_generator._door_set.has(from):
		var from_open := bool(dungeon_generator._door_states.get(from, false))
		## 门格内仍占位木桶时保持敞开，避免他格单位路过把门带上误关。
		if from_open and not _door_cell_has_live_barrel_occupant(from):
			dungeon_generator.toggle_door(from)
	if dungeon_generator._door_set.has(to):
		var to_open := bool(dungeon_generator._door_states.get(to, false))
		if not to_open:
			dungeon_generator.toggle_door(to)
			if opener != null and opener.is_in_group("player"):
				_play_sfx_if_available("DoorOpen")
