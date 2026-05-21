@tool
class_name BreakableBarrel
extends Sprite2D
## 不可通行占位（地面单位）；飞行敌人可占位同格（见 TurnController）。
## 受击可被击退若干格（不含燃烧伤害）；击退入深渊时转为浮台：格可行走、桶失能并缓慢浮沉。
## 火焰仅视觉/蔓延参与，每秒回合计数扣燃尽倒计时，不伤 HP。

signal barrel_destroyed(grid_pos: Vector2i, from_fire_chain: bool)

@export_group("References")
@export var dungeon_generator_path: NodePath = NodePath("../DungeonGenerator")
@export var turn_controller_path: NodePath = NodePath("../TurnController")

@export_group("Combat")
@export var max_hp: int = 1
@export var break_flash_duration: float = 0.08
@export var burning_turns_on_ignite: int = 8

@export_group("Knockback（受血量伤害时触发，爆炸/远程的第二参数为受力参考格）")
@export_range(0, 8, 1) var knockback_distance_cells_on_damage: int = 1
@export var knockback_tween_duration: float = 0.12
@export var knockback_arc_height_px: float = 9.0
@export_range(0, 99, 1) var knockback_collision_damage: int = 1
## 击退撞到玩家时造成的伤害（可与 knockback_collision_damage 分开调）。
@export_range(0, 99, 1) var barrel_player_knock_damage: int = 1
## 击退被阻挡时：沿受力方向短促前后位移（相对格子中心），类似玩家近战冲撞，**不改 grid_pos**。
@export_range(0.05, 0.5, 0.01) var knockback_bump_lunge_ratio: float = 0.28
@export_range(0.04, 0.3, 0.01) var knockback_bump_lunge_duration: float = 0.06
@export_range(0, 32, 1) var knockback_bump_impact_particle_count: int = 12

@export_group("Knockback chain / timing / audio")
@export_range(1, 64, 1) var knockback_chain_max_transfers: int = 10
@export_range(0.0, 0.5, 0.005) var knockback_strike_delay_sec: float = 0.05
@export_range(0.0, 0.5, 0.005) var knockback_between_chain_delay_sec: float = 0.04
@export_range(0.0, 0.6, 0.02) var abyss_splash_effect_delay_sec: float = 0.1

@export_group("Abyss submerge（坠入深渊浮台）")
@export_range(0.0, 0.35, 0.01) var abyss_submerge_visual_offset_ratio: float = 0.14
@export var abyss_float_animation_name: StringName = &"Floats"
@export var abyss_sink_animation_name: StringName = &"Sink"
@export var abyss_float_animation_player_path: NodePath = NodePath("AnimationPlayer")

@export_range(1, 99, 1) var barrel_wall_strike_damage: int = 1
## 为 true 时：撞**实体墙**后先尝试沿墙面切向滑入邻格（与 `step` 正交的两向）；均不可行再反向回弹。
@export var knockback_wall_try_slide_along_face_first: bool = true
## 留空则击退/撞击不播音效；默认与 TurnController 近战 Impact 一致。
@export var barrel_impact_sfx_names: PackedStringArray = PackedStringArray(["Impact1", "Impact2", "Impact3", "Impact4", "Impact5", "Impact6"])
@export var barrel_splash_sfx_name: String = "Splash"

@export_group("Exit pit（推入出口下落）")
@export_range(0.05, 0.8, 0.01) var exit_plunge_shrink_duration_sec: float = 0.2
@export_range(0.0, 1.5, 0.02) var exit_plunge_pipe_delay_after_shrink_sec: float = 0.42
@export var exit_plunge_fall_sfx_name: String = "MetalPipe"

@export_group("Burn FX（与液体/角色附着火对齐，可在场景中调强度）")
@export var burn_visual_emit_interval_sec: float = 0.045
@export_range(2.0, 10.0, 0.1) var burn_visual_particle_scale: float = 5.5
@export_range(2.0, 12.0, 0.1) var ignite_burst_particle_scale: float = 6.5

@export_group("Debug")
@export var debug_show_hp: bool = false
## 入水浮台：显示承重检测（wt/cell/player格/模式）；用于确认是检测还是动画问题。
@export var debug_show_abyss_weight: bool = false

@export_group("选图预览（Tile Picker Inspector）", "editor_atlas_pick_")
## 任选其一：**直接拖入 TileSet**；或绑定下方 TileMapLayer 借其 `.tile_set` 预览。
@export var editor_atlas_pick_tile_set: TileSet
@export var editor_atlas_pick_layer: TileMapLayer
## 与桶/柱占位 atlas source 对齐；编辑器内为 **-1** 时预览用 source **0**。
@export var editor_atlas_pick_source_id: int = -1

@export_group("Visual")
var _atlas_coords: Vector2i = Vector2i(2, 9)
@export var atlas_coords: Vector2i = Vector2i(2, 9):
	get:
		return _atlas_coords
	set(value):
		_atlas_coords = value
		_queue_editor_atlas_preview()
var _abyss_submerged_atlas_coords: Vector2i = Vector2i(-1, -1)
@export var abyss_submerged_atlas_coords: Vector2i = Vector2i(-1, -1):
	get:
		return _abyss_submerged_atlas_coords
	set(value):
		_abyss_submerged_atlas_coords = value
		_queue_editor_atlas_preview()
var _abyss_submerged_atlas_tiles: Array[Vector2i] = []
## 坠入深渊浮台专用图块（Tile Picker 写入；与 `abyss_submerged_atlas_coords` 同步）。
@export var abyss_submerged_atlas_tiles: Array[Vector2i] = []:
	get:
		return _abyss_submerged_atlas_tiles
	set(value):
		_abyss_submerged_atlas_tiles = value
		if not value.is_empty() and value[0] is Vector2i:
			_abyss_submerged_atlas_coords = value[0]
		_queue_editor_atlas_preview()
var _editor_preview_submerged_visual: bool = false
## 编辑器预览：勾选后在场景里显示深渊浮台贴图（仅编辑器有效）。
@export var editor_preview_submerged_visual: bool = false:
	get:
		return _editor_preview_submerged_visual
	set(value):
		_editor_preview_submerged_visual = value
		_queue_editor_atlas_preview()

var grid_pos: Vector2i = Vector2i.ZERO
var tile_size: int = 16
var dungeon_generator: DungeonGenerator = null
var turn_controller: TurnController = null
var _hp: int = 1
var _dead: bool = false
var _burning_turns_left: int = 0
var _pending_chain_fire_tick: bool = false
var _knockback_tween: Tween = null
var _bump_fx_tween: Tween = null
var _knockback_arc_from: Vector2 = Vector2.ZERO
var _knockback_arc_to: Vector2 = Vector2.ZERO
var _knockback_busy: bool = false
var _barrel_sfx_rng := RandomNumberGenerator.new()
var _burn_vfx_accum: float = 0.0
## 环境传火（站立燃烧）：>0 时每经过一次液体阶段递减，期间不向外播火；新点燃时至少插 1 阶段冷却。
var _env_fire_spread_blocks_remaining: int = 0
var _submerged_in_abyss: bool = false
var _abyss_anim_player: AnimationPlayer = null
var _abyss_anim_mode: int = _AbyssAnimMode.NONE
var _abyss_platform_has_weight: bool = false
var _abyss_anim_listener_connected: bool = false
var _rest_scale: Vector2 = Vector2.ONE

enum _AbyssAnimMode {
	NONE,
	FLOAT,
	SINK,
	SUNK,
}
var _scene_atlas_sheet: Texture2D = null
var _scene_hframes: int = 1
var _scene_vframes: int = 1
var _editor_preview_queued: bool = false
var _platform_actor_grid_listener: Callable = Callable()
var _platform_turn_resolved_listener: Callable = Callable()


func _ready() -> void:
	_cache_scene_atlas_layout()
	if Engine.is_editor_hint():
		_run_editor_atlas_preview()
		return
	_barrel_sfx_rng.randomize()
	add_to_group("breakable")
	add_to_group("ignitable_breakable")
	_resolve_references()
	_hp = maxi(1, max_hp)
	_rest_scale = scale
	_apply_visual_from_dungeon()
	_snap_to_grid_center()


func _cache_scene_atlas_layout() -> void:
	if texture is AtlasTexture:
		var at := texture as AtlasTexture
		_scene_atlas_sheet = at.atlas
	elif texture != null:
		_scene_atlas_sheet = texture
	_scene_hframes = maxi(1, hframes)
	_scene_vframes = maxi(1, vframes)


func _queue_editor_atlas_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if _editor_preview_queued:
		return
	_editor_preview_queued = true
	call_deferred("_run_editor_atlas_preview")


func _run_editor_atlas_preview() -> void:
	_editor_preview_queued = false
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _scene_atlas_sheet == null:
		_cache_scene_atlas_layout()
	var coords := _resolve_active_atlas_coords_for_display()
	_apply_coords_on_scene_atlas_sheet(coords)


func _process(delta: float) -> void:
	if debug_show_hp or debug_show_abyss_weight:
		queue_redraw()
	if _submerged_in_abyss:
		_sync_submerged_platform_layout()
		_poll_abyss_platform_weight()
		return
	if not _dead and _burning_turns_left > 0:
		_burn_vfx_accum += delta
		var intvl := maxf(0.02, burn_visual_emit_interval_sec)
		while _burn_vfx_accum >= intvl:
			_burn_vfx_accum -= intvl
			FireAttachmentVisual.spawn_burn_tick_match_liquid(
				global_position, tile_size, burn_visual_particle_scale
			)
	elif _burn_vfx_accum != 0.0:
		_burn_vfx_accum = 0.0


func _draw() -> void:
	if not debug_show_hp and not debug_show_abyss_weight:
		return
	var lbl := ""
	if debug_show_hp:
		lbl = "HP %d/%d  kb:%d" % [_hp, max_hp, knockback_distance_cells_on_damage]
		if _burning_turns_left > 0:
			lbl += " FIRE:%d" % [_burning_turns_left]
	if _submerged_in_abyss and debug_show_abyss_weight:
		var dbg := _query_abyss_weight_debug()
		var wt: int = int(dbg.get("weight", 0))
		var mode := _abyss_anim_mode_label()
		var player_gp: Vector2i = dbg.get("player_grid", Vector2i(-1, -1))
		var cell: Vector2i = dbg.get("cell", grid_pos)
		var onp: int = 1 if bool(dbg.get("player_on_platform", false)) else 0
		var tcw: int = int(dbg.get("tc_weight", -1))
		var pw: int = int(dbg.get("player_weight", 0))
		var extra := (
			" wt:%d onp:%d pw:%d reg:%d tc:%d dg:%d cell:%s ply:%s tcw:%d mode:%s"
			% [
				wt, onp, pw,
				1 if bool(dbg.get("platform_registered", false)) else 0,
				1 if bool(dbg.get("tc_ok", false)) else 0,
				1 if bool(dbg.get("dg_ok", false)) else 0,
				cell, player_gp, tcw, mode
			]
		)
		if not lbl.is_empty():
			lbl += extra
		else:
			lbl = extra.strip_edges()
	if lbl.is_empty():
		return
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-32, -tile_size * 0.65),
		lbl,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		9,
		Color(1.0, 0.85, 0.35)
	)


func bind_grid_position(pos: Vector2i) -> void:
	grid_pos = pos
	if _submerged_in_abyss:
		_snap_abyss_platform_position()
	else:
		_snap_to_grid_center()


func can_receive_melee() -> bool:
	return not _dead and not _submerged_in_abyss


func get_attack_feedback_duration() -> float:
	return break_flash_duration


func ignite(turns: int = 8, refresh_existing: bool = true) -> void:
	if _dead or _submerged_in_abyss:
		return
	var was_burning := is_burning()
	var dur := turns if turns > 0 else burning_turns_on_ignite
	if refresh_existing:
		_burning_turns_left = dur
	else:
		_burning_turns_left = maxi(_burning_turns_left, dur)
	if not was_burning and is_burning():
		_pending_chain_fire_tick = true
		_env_fire_spread_blocks_remaining = maxi(_env_fire_spread_blocks_remaining, 1)
		FireAttachmentVisual.spawn_ignite_burst_intense(global_position, tile_size, ignite_burst_particle_scale)
		FireAttachmentVisual.spawn_burn_tick_match_liquid(global_position, tile_size, burn_visual_particle_scale)


func ignite_from_liquid_spread(turns: int = 8, refresh_existing: bool = true) -> void:
	if _dead or _submerged_in_abyss:
		return
	var was_burning := is_burning()
	var dur := turns if turns > 0 else burning_turns_on_ignite
	if refresh_existing:
		_burning_turns_left = dur
	else:
		_burning_turns_left = maxi(_burning_turns_left, dur)
	## 与 `BreakablePillar` / 燃烧液一致：蔓延点燃在本相位内照常 `apply_fire_chain_tick`（不挂 `_pending_chain_fire_tick`），
	## 避免首帧被跳过导致“只亮粒子、倒计时未跑”的错觉。
	_pending_chain_fire_tick = false
	if not was_burning and is_burning():
		_env_fire_spread_blocks_remaining = maxi(_env_fire_spread_blocks_remaining, 1)
		FireAttachmentVisual.spawn_ignite_burst_intense(global_position, tile_size, ignite_burst_particle_scale)
		FireAttachmentVisual.spawn_burn_tick_match_liquid(global_position, tile_size, burn_visual_particle_scale)


func is_burning() -> bool:
	return _burning_turns_left > 0


func should_resolve_fire_this_turn() -> bool:
	if not is_burning() or _dead:
		return false
	if _pending_chain_fire_tick:
		_pending_chain_fire_tick = false
		return false
	return true


func apply_damage(amount: int, melee_attacker_cell: Variant = null) -> bool:
	var impulse: Variant = melee_attacker_cell if melee_attacker_cell is Vector2i else null
	return _resolve_damage_impulse_then_hp(amount, impulse)


func apply_damage_from_ranged(amount: int, impulse_origin: Variant = null) -> bool:
	return _resolve_damage_impulse_then_hp(amount, impulse_origin)


func _resolve_damage_impulse_then_hp(amount: int, impulse_origin: Variant) -> bool:
	if _dead or _submerged_in_abyss:
		return true
	_hp -= maxi(0, amount)
	_play_hit_flash()

	var hp_dead_after := _hp <= 0
	if not hp_dead_after and impulse_origin is Vector2i and knockback_distance_cells_on_damage > 0:
		if _try_knockback_from_damage_origin(impulse_origin as Vector2i):
			return true

	if hp_dead_after:
		_die_normal()
		return true
	if turn_controller != null:
		turn_controller.request_occupancy_refresh()
	return false


func _die_normal() -> void:
	if _dead:
		return
	_dead = true
	if turn_controller != null:
		turn_controller.occupancy.erase(grid_pos)
		turn_controller.request_occupancy_refresh()
	barrel_destroyed.emit(grid_pos, false)
	queue_free()


func _try_knockback_from_damage_origin(origin_cell: Vector2i) -> bool:
	if dungeon_generator == null or _knockback_busy:
		return false
	var ux := grid_pos.x - origin_cell.x
	var uy := grid_pos.y - origin_cell.y
	var step := _approximate_knock_step(ux, uy)
	if step == Vector2i.ZERO:
		return false
	## 第一步即坠入深渊：播放击退/落水后转为浮台，不再销毁。
	var probe := grid_pos + step
	if _classify_roll_destination(probe) == 2:
		_knockback_busy = true
		call_deferred("_deferred_abyss_submerge_main", grid_pos, probe)
		return true
	if _classify_roll_destination(probe) == 1 and _is_dungeon_exit_cell(probe):
		_knockback_busy = true
		call_deferred("_deferred_exit_plunge_main", grid_pos, probe)
		return true
	## 先于 deferred 置位，便于同帧内 `TurnController` 阻塞后续玩家输入直至击退协程结束。
	_knockback_busy = true
	call_deferred("_deferred_knockback_main", origin_cell)
	return false


func _deferred_exit_plunge_main(from_cell: Vector2i, exit_cell: Vector2i) -> void:
	await _exit_plunge_async(from_cell, exit_cell)


func _deferred_abyss_submerge_main(from_cell: Vector2i, abyss_cell: Vector2i) -> void:
	await _abyss_submerge_async(from_cell, abyss_cell)


func _deferred_knockback_main(origin_cell: Vector2i) -> void:
	await _knockback_main_async(origin_cell)


func _knockback_main_async(origin_cell: Vector2i) -> void:
	if _dead or dungeon_generator == null:
		_knockback_busy = false
		return
	_knockback_busy = true
	var step := _approximate_knock_step(grid_pos.x - origin_cell.x, grid_pos.y - origin_cell.y)
	if step == Vector2i.ZERO:
		_knockback_busy = false
		return
	var landing := grid_pos
	var slides_left := maxi(1, knockback_distance_cells_on_damage)
	var transfer_idx := 0
	while slides_left > 0 and transfer_idx < knockback_chain_max_transfers and not _dead:
		if knockback_strike_delay_sec > 0.0:
			await get_tree().create_timer(knockback_strike_delay_sec).timeout
		var next_cell := landing + step
		var kind := _classify_roll_destination(next_cell)
		if kind == 2:
			await _abyss_submerge_async(landing, next_cell)
			_knockback_busy = false
			return
		if kind == 1 and _is_dungeon_exit_cell(next_cell):
			await _exit_plunge_async(landing, next_cell)
			return
		if kind != 1:
			var rem: int = knockback_chain_max_transfers - transfer_idx
			transfer_idx += await _knockback_resolve_blocked(
				next_cell, landing, step, rem
			)
			slides_left = 0
			break
		_play_random_barrel_impact_sfx()
		await _knockback_execute_roll(landing, next_cell)
		landing = next_cell
		slides_left -= 1
	if turn_controller != null:
		turn_controller.request_occupancy_refresh()
	_knockback_busy = false


func _knockback_resolve_blocked(
	blocked_cell: Vector2i,
	landing: Vector2i,
	step: Vector2i,
	transfers_left: int
) -> int:
	var used := 0
	if transfers_left <= 0 or _dead or dungeon_generator == null:
		return 0

	var blocked_tile: DungeonGenerator.TileType = dungeon_generator.get_tile(
		blocked_cell
	) as DungeonGenerator.TileType
	var is_wall_tile := DungeonGenerator.tile_is_barrel_indestructible_wall(blocked_tile)
	## 门关着或未激活门：格子上仍是 FLOOR，但不可进入 → 反弹处理（不凿墙）
	var door_like_block := dungeon_generator._door_set.has(blocked_cell) \
		and not bool(dungeon_generator._door_states.get(blocked_cell, false))

	if is_wall_tile:
		if knockback_strike_delay_sec > 0.0:
			await get_tree().create_timer(knockback_strike_delay_sec).timeout
		_play_random_barrel_impact_sfx()
		if barrel_wall_strike_damage > 0 and blocked_tile == DungeonGenerator.TileType.WALL:
			dungeon_generator.try_apply_barrel_wall_strike_effects(
				blocked_cell, barrel_wall_strike_damage, landing
			)
		used += 1
		if transfers_left - used <= 0:
			return used
		if knockback_between_chain_delay_sec > 0.0:
			await get_tree().create_timer(knockback_between_chain_delay_sec).timeout
		if knockback_wall_try_slide_along_face_first:
			used += await _knockback_try_slide_along_wall_then_bounce(
				landing, step, transfers_left - used
			)
		else:
			used += await _knockback_try_bounce_after_block(landing, step, transfers_left - used)
		return used

	if door_like_block:
		if knockback_strike_delay_sec > 0.0:
			await get_tree().create_timer(knockback_strike_delay_sec).timeout
		_play_random_barrel_impact_sfx()
		used += 1
		if transfers_left - used <= 0:
			return used
		if knockback_between_chain_delay_sec > 0.0:
			await get_tree().create_timer(knockback_between_chain_delay_sec).timeout
		used += await _knockback_try_bounce_after_block(landing, step, transfers_left - used)
		return used

	if knockback_strike_delay_sec > 0.0:
		await get_tree().create_timer(knockback_strike_delay_sec).timeout
	_play_random_barrel_impact_sfx()
	_apply_knockback_collision_at_blocked_cell(blocked_cell, landing)
	used += 1
	return used


## 沿墙面法线所对应的切向（与 `step` 正交）尝试滑移一格；均失败则回退为 `_knockback_try_bounce_after_block`。
func _knockback_try_slide_along_wall_then_bounce(
		landing: Vector2i, step: Vector2i, transfers_left: int
) -> int:
	if transfers_left <= 0 or _dead:
		return 0
	var t1 := Vector2i(-step.y, step.x)
	var t2 := Vector2i(step.y, -step.x)
	for delta in [t1, t2]:
		if delta == Vector2i.ZERO:
			continue
		var cand: Vector2i = landing + delta
		if _classify_roll_destination(cand) == 1:
			if transfers_left <= 0:
				return 0
			_play_random_barrel_impact_sfx()
			if _is_dungeon_exit_cell(cand):
				await _exit_plunge_async(landing, cand)
			else:
				await _knockback_execute_roll(landing, cand)
			return 1
	return await _knockback_try_bounce_after_block(landing, step, transfers_left)


func _knockback_try_bounce_after_block(landing: Vector2i, step: Vector2i, transfers_left: int) -> int:
	if transfers_left <= 0 or _dead:
		return 0
	var bounce_cell := landing - step
	var bounce_kind := _classify_roll_destination(bounce_cell)
	if bounce_kind == 2:
		await _abyss_submerge_async(landing, bounce_cell)
		return 1
	if bounce_kind == 1:
		if transfers_left <= 0:
			return 0
		_play_random_barrel_impact_sfx()
		if _is_dungeon_exit_cell(bounce_cell):
			await _exit_plunge_async(landing, bounce_cell)
		else:
			await _knockback_execute_roll(landing, bounce_cell)
		return 1
	if knockback_strike_delay_sec > 0.0:
		await get_tree().create_timer(knockback_strike_delay_sec).timeout
	_play_random_barrel_impact_sfx()
	_apply_knockback_collision_at_blocked_cell(bounce_cell, landing)
	return 1


func _is_dungeon_exit_cell(cell: Vector2i) -> bool:
	if dungeon_generator == null:
		return false
	var ep: Vector2i = dungeon_generator.exit_pos
	return ep != Vector2i(-1, -1) and cell == ep


func _notify_barrel_carryover_next_floor() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("breakable_barrel_spawner"):
		if n != null and (n as Object).has_method("register_barrel_sent_through_exit"):
			(n as Object).call("register_barrel_sent_through_exit")


## 推入出口：缩放到洞口 → 延迟 → MetalPipe；期间保持 `_knockback_busy` 直至序列结束（含音效）。
func _exit_plunge_async(from_cell: Vector2i, exit_cell: Vector2i) -> void:
	if dungeon_generator == null or not _is_dungeon_exit_cell(exit_cell):
		_knockback_busy = false
		return
	if _dead:
		_knockback_busy = false
		return
	_dead = true
	## 在动画/音效开始前记入携带数，避免换层 `clear_barrels` 中断协程后永远未累加。
	_notify_barrel_carryover_next_floor()
	if turn_controller != null:
		turn_controller.occupancy.erase(from_cell)
		grid_pos = exit_cell
		turn_controller.occupancy[exit_cell] = self
		turn_controller.request_occupancy_refresh()
	else:
		grid_pos = exit_cell

	var shrink_t: float = maxf(0.04, exit_plunge_shrink_duration_sec)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_EXPO)
	tw.set_ease(Tween.EASE_IN)
	var from_p: Vector2 = _grid_center_local(from_cell)
	var to_p: Vector2 = _grid_center_local(exit_cell)
	position = from_p
	var s0: Vector2 = scale
	tw.tween_property(self, "position", to_p, shrink_t)
	tw.tween_property(self, "scale", s0 * 0.05, shrink_t)
	await tw.finished

	if exit_plunge_pipe_delay_after_shrink_sec > 0.0:
		var tree := get_tree()
		if tree != null:
			await tree.create_timer(exit_plunge_pipe_delay_after_shrink_sec).timeout

	if not is_instance_valid(self):
		return

	if not exit_plunge_fall_sfx_name.is_empty():
		_play_barrel_sfx(exit_plunge_fall_sfx_name)

	if turn_controller != null and is_instance_valid(turn_controller):
		turn_controller.occupancy.erase(exit_cell)
		turn_controller.request_occupancy_refresh()
	barrel_destroyed.emit(exit_cell, false)
	_knockback_busy = false
	queue_free()


func _knockback_execute_roll(from_gp: Vector2i, to_gp: Vector2i) -> void:
	grid_pos = to_gp
	if turn_controller != null:
		turn_controller.occupancy.erase(from_gp)
		turn_controller.occupancy[to_gp] = self
		turn_controller.request_occupancy_refresh()
	if dungeon_generator != null and dungeon_generator._door_set.has(to_gp):
		dungeon_generator.ensure_door_open_at(to_gp, true)
	await _await_knockback_arc_tween(
		_grid_center_local(from_gp),
		_grid_center_local(to_gp)
	)


func _abyss_submerge_async(from_cell: Vector2i, abyss_cell: Vector2i) -> void:
	if _dead or _submerged_in_abyss or dungeon_generator == null:
		_knockback_busy = false
		return
	_knockback_busy = true
	if from_cell != abyss_cell:
		await _knockback_execute_roll(from_cell, abyss_cell)
	else:
		grid_pos = abyss_cell
		position = _grid_center_local(abyss_cell)
	if _dead or _submerged_in_abyss:
		_knockback_busy = false
		return
	if abyss_splash_effect_delay_sec > 0.0:
		await get_tree().create_timer(abyss_splash_effect_delay_sec).timeout
	if not is_instance_valid(self) or _dead or _submerged_in_abyss:
		_knockback_busy = false
		return
	_finalize_abyss_submerge(abyss_cell)
	_knockback_busy = false


func _finalize_abyss_submerge(abyss_cell: Vector2i) -> void:
	_submerged_in_abyss = true
	_burning_turns_left = 0
	_pending_chain_fire_tick = false
	_env_fire_spread_blocks_remaining = 0
	_resolve_references()
	grid_pos = abyss_cell
	_register_self_as_abyss_platform(abyss_cell)
	if turn_controller != null:
		turn_controller.occupancy.erase(abyss_cell)
	_play_splash_sfx()
	var w := _fx_world_parent()
	BarrelAbyssSplashEffect.play(w, abyss_cell, tile_size)
	_apply_abyss_submerged_visual()
	_apply_abyss_platform_canvas_depth()
	visible = true
	show()
	_abyss_platform_has_weight = false
	_abyss_anim_mode = _AbyssAnimMode.NONE
	_snap_abyss_platform_position()
	_connect_abyss_platform_actor_listeners()
	set_process(true)
	process_mode = Node.PROCESS_MODE_INHERIT
	var ap := _resolve_abyss_anim_player()
	if ap != null:
		ap.process_mode = Node.PROCESS_MODE_INHERIT
	_begin_abyss_float_animation()
	if turn_controller != null:
		turn_controller.request_occupancy_refresh()
	modulate = Color(0.88, 0.92, 1.0, 1.0)


func _apply_abyss_platform_canvas_depth() -> void:
	z_as_relative = false
	y_sort_enabled = false
	if dungeon_generator != null:
		z_index = dungeon_generator.get_abyss_barrel_platform_canvas_z_index()
	else:
		z_index = DungeonGenerator.ACTOR_APPROXIMATE_Z_INDEX_FOR_SORTING - 1


func _apply_abyss_submerged_visual() -> void:
	var coords := _resolve_abyss_submerged_atlas_coords()
	if _scene_atlas_sheet != null and _apply_coords_on_scene_atlas_sheet(coords, true):
		return
	if _apply_sprite_from_dungeon_atlas_coords(coords, true):
		return
	push_warning(
		"BreakableBarrel: 深渊浮台贴图 atlas (%d,%d) 未能应用，请检查图集坐标。"
		% [coords.x, coords.y]
	)


func _resolve_active_atlas_coords_for_display() -> Vector2i:
	if Engine.is_editor_hint() and _editor_preview_submerged_visual:
		return _resolve_abyss_submerged_atlas_coords()
	if _submerged_in_abyss:
		return _resolve_abyss_submerged_atlas_coords()
	return _atlas_coords


func _resolve_abyss_submerged_atlas_coords() -> Vector2i:
	if _abyss_submerged_atlas_coords != Vector2i(-1, -1):
		return _abyss_submerged_atlas_coords
	if not _abyss_submerged_atlas_tiles.is_empty():
		return _abyss_submerged_atlas_tiles[0]
	if dungeon_generator != null:
		var dg_coords: Vector2i = dungeon_generator.barrel_abyss_submerged_atlas_coords
		if dg_coords != Vector2i(-1, -1):
			return dg_coords
	return _atlas_coords


func sync_abyss_platform_visual() -> void:
	if not _submerged_in_abyss:
		return
	_sync_submerged_platform_layout()
	_snap_abyss_platform_position()
	_poll_abyss_platform_weight()


func _connect_abyss_platform_actor_listeners() -> void:
	_resolve_references()
	if turn_controller == null:
		return
	if _platform_actor_grid_listener.is_null() or not _platform_actor_grid_listener.is_valid():
		_platform_actor_grid_listener = Callable(self, "_on_platform_actor_grid_changed")
	if _platform_turn_resolved_listener.is_null() or not _platform_turn_resolved_listener.is_valid():
		_platform_turn_resolved_listener = Callable(self, "_on_platform_turn_resolved")
	if not turn_controller.turn_resolved.is_connected(_platform_turn_resolved_listener):
		turn_controller.turn_resolved.connect(_platform_turn_resolved_listener)
	var player := turn_controller.player
	if player != null and player.has_signal("grid_position_changed"):
		if not player.grid_position_changed.is_connected(_platform_actor_grid_listener):
			player.grid_position_changed.connect(_platform_actor_grid_listener)
	for enemy in turn_controller.enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.has_signal("grid_position_changed"):
			continue
		if not enemy.grid_position_changed.is_connected(_platform_actor_grid_listener):
			enemy.grid_position_changed.connect(_platform_actor_grid_listener)


func _disconnect_abyss_platform_actor_listeners() -> void:
	if turn_controller == null:
		return
	if _platform_turn_resolved_listener.is_valid() \
			and turn_controller.turn_resolved.is_connected(_platform_turn_resolved_listener):
		turn_controller.turn_resolved.disconnect(_platform_turn_resolved_listener)
	var player := turn_controller.player
	if player != null and player.has_signal("grid_position_changed") \
			and _platform_actor_grid_listener.is_valid() \
			and player.grid_position_changed.is_connected(_platform_actor_grid_listener):
		player.grid_position_changed.disconnect(_platform_actor_grid_listener)
	for enemy in turn_controller.enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_signal("grid_position_changed") \
				and _platform_actor_grid_listener.is_valid() \
				and enemy.grid_position_changed.is_connected(_platform_actor_grid_listener):
			enemy.grid_position_changed.disconnect(_platform_actor_grid_listener)


func _on_platform_actor_grid_changed(_new_grid: Vector2i) -> void:
	if not _submerged_in_abyss:
		return
	_resolve_references()
	_poll_abyss_platform_weight()


func _on_platform_turn_resolved(
		_turn_index: int, _player_consumed_turn: bool, _had_attack: bool
) -> void:
	if not _submerged_in_abyss:
		return
	_connect_abyss_platform_actor_listeners()


func is_submerged_in_abyss() -> bool:
	return _submerged_in_abyss


func get_abyss_platform_cell() -> Vector2i:
	return _resolve_abyss_platform_cell()


func _resolve_abyss_anim_player() -> AnimationPlayer:
	if _abyss_anim_player != null and is_instance_valid(_abyss_anim_player):
		return _abyss_anim_player
	if not abyss_float_animation_player_path.is_empty():
		var n := get_node_or_null(abyss_float_animation_player_path)
		if n is AnimationPlayer:
			_abyss_anim_player = n as AnimationPlayer
			return _abyss_anim_player
	var direct := get_node_or_null("AnimationPlayer") as AnimationPlayer
	_abyss_anim_player = direct
	return _abyss_anim_player


func _has_abyss_anim(ap: AnimationPlayer, anim_name: StringName) -> bool:
	return ap != null and not anim_name.is_empty() and ap.has_animation(anim_name)


func _ensure_abyss_anim_listener() -> void:
	var ap := _resolve_abyss_anim_player()
	if ap == null or _abyss_anim_listener_connected:
		return
	if not ap.animation_finished.is_connected(_on_abyss_platform_animation_finished):
		ap.animation_finished.connect(_on_abyss_platform_animation_finished)
	_abyss_anim_listener_connected = true


func _disconnect_abyss_anim_listener() -> void:
	var ap := _resolve_abyss_anim_player()
	if ap != null and _abyss_anim_listener_connected \
			and ap.animation_finished.is_connected(_on_abyss_platform_animation_finished):
		ap.animation_finished.disconnect(_on_abyss_platform_animation_finished)
	_abyss_anim_listener_connected = false


func _stop_abyss_platform_animation() -> void:
	var ap := _resolve_abyss_anim_player()
	if ap != null:
		ap.stop()
	_abyss_anim_mode = _AbyssAnimMode.NONE


func _snap_abyss_platform_position() -> void:
	var center := _grid_center_local(grid_pos)
	position = Vector2(
		center.x,
		center.y + float(tile_size) * abyss_submerge_visual_offset_ratio
	)
	scale = _rest_scale


func _set_abyss_anim_loop(ap: AnimationPlayer, anim_name: StringName, loop_mode: Animation.LoopMode) -> void:
	if not _has_abyss_anim(ap, anim_name):
		return
	var anim := ap.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = loop_mode


func _begin_abyss_float_animation() -> void:
	_abyss_platform_has_weight = false
	_abyss_anim_mode = _AbyssAnimMode.NONE
	var ap := _resolve_abyss_anim_player()
	if not _has_abyss_anim(ap, abyss_float_animation_name):
		if not Engine.is_editor_hint():
			push_warning(
				"BreakableBarrel: 未找到 AnimationPlayer 或动画 '%s'，深渊浮沉不会播放。"
				% String(abyss_float_animation_name)
			)
		return
	_play_abyss_float_pingpong()


func _play_abyss_float_pingpong() -> void:
	var ap := _resolve_abyss_anim_player()
	if not _has_abyss_anim(ap, abyss_float_animation_name):
		return
	_ensure_abyss_anim_listener()
	ap.active = true
	_abyss_anim_mode = _AbyssAnimMode.FLOAT
	_set_abyss_anim_loop(ap, abyss_float_animation_name, Animation.LOOP_PINGPONG)
	ap.play(abyss_float_animation_name)
	ap.speed_scale = 1.0


func _play_abyss_sink_once() -> void:
	var ap := _resolve_abyss_anim_player()
	if ap == null:
		return
	if not _has_abyss_anim(ap, abyss_sink_animation_name):
		push_warning(
			"BreakableBarrel @%s: 缺少承重动画 '%s'（AnimationPlayer 中不存在），无法播放 Sink。"
			% [grid_pos, String(abyss_sink_animation_name)]
		)
		return
	_ensure_abyss_anim_listener()
	ap.active = true
	_abyss_anim_mode = _AbyssAnimMode.SINK
	_set_abyss_anim_loop(ap, abyss_sink_animation_name, Animation.LOOP_NONE)
	ap.play(abyss_sink_animation_name)
	ap.speed_scale = 1.0


func _hold_abyss_sunk_pose() -> void:
	var ap := _resolve_abyss_anim_player()
	if not _has_abyss_anim(ap, abyss_sink_animation_name):
		return
	_abyss_anim_mode = _AbyssAnimMode.SUNK
	var anim := ap.get_animation(abyss_sink_animation_name)
	if anim != null:
		ap.seek(anim.length, true)
	ap.pause()


func _on_abyss_platform_animation_finished(anim_name: StringName) -> void:
	if not _submerged_in_abyss or anim_name != abyss_sink_animation_name:
		return
	if _has_abyss_platform_weight():
		_hold_abyss_sunk_pose()
	else:
		_play_abyss_float_pingpong()


func _poll_abyss_platform_weight() -> void:
	var has_weight := _has_abyss_platform_weight()
	if has_weight and not _abyss_platform_has_weight:
		_on_abyss_weight_applied()
	elif not has_weight and _abyss_platform_has_weight:
		_on_abyss_weight_removed()
	_abyss_platform_has_weight = has_weight


func _on_abyss_weight_applied() -> void:
	match _abyss_anim_mode:
		_AbyssAnimMode.SINK, _AbyssAnimMode.SUNK:
			return
		_:
			_play_abyss_sink_once()


func _on_abyss_weight_removed() -> void:
	match _abyss_anim_mode:
		_AbyssAnimMode.FLOAT:
			return
		_:
			_play_abyss_float_pingpong()


func _abyss_anim_mode_label() -> String:
	match _abyss_anim_mode:
		_AbyssAnimMode.FLOAT:
			return "Float"
		_AbyssAnimMode.SINK:
			return "Sink"
		_AbyssAnimMode.SUNK:
			return "Sunk"
		_:
			return "-"


func _sync_abyss_platform_grid_pos_with_registry() -> void:
	if dungeon_generator == null:
		_resolve_references()
	if dungeon_generator == null:
		return
	if dungeon_generator.get_abyss_barrel_platform(grid_pos) == self:
		return
	var registered_cell := dungeon_generator.find_abyss_barrel_platform_cell(self)
	if registered_cell != Vector2i(-1, -1) and registered_cell != grid_pos:
		grid_pos = registered_cell


func _resolve_abyss_platform_cell() -> Vector2i:
	_sync_abyss_platform_grid_pos_with_registry()
	return grid_pos


func _register_self_as_abyss_platform(abyss_cell: Vector2i) -> void:
	_resolve_references()
	if dungeon_generator != null:
		tile_size = dungeon_generator.tile_size
		dungeon_generator.register_abyss_barrel_platform(abyss_cell, self)


func _dungeon_tile_size() -> int:
	if dungeon_generator != null:
		return dungeon_generator.tile_size
	if turn_controller != null and turn_controller.dungeon_generator != null:
		return turn_controller.dungeon_generator.tile_size
	return tile_size


func _sync_submerged_platform_layout() -> void:
	if not _submerged_in_abyss:
		return
	_resolve_references()
	var ts := _dungeon_tile_size()
	if ts != tile_size:
		tile_size = ts
		_snap_abyss_platform_position()


func _read_actor_grid_pos_local(actor: Node) -> Vector2i:
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


## 仅同逻辑格算站上浮台。
func _local_actor_on_platform(actor: Node, platform_cell: Vector2i) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	return _read_actor_grid_pos_local(actor) == platform_cell


func _local_actor_weight(actor: Node) -> int:
	if actor == null or not is_instance_valid(actor) or actor == self:
		return 0
	if actor is BreakableBarrel:
		return 0 if (actor as BreakableBarrel).is_submerged_in_abyss() else 1
	if actor is EnemyGridController:
		return 0 if (actor as EnemyGridController).floating else 1
	_resolve_references()
	if turn_controller != null and actor == turn_controller.player:
		return 1
	if actor.is_in_group("player"):
		return 1
	var scr: Variant = actor.get_script()
	if scr is Script and String((scr as Script).resource_path).ends_with("player_grid_controller.gd"):
		return 1
	return 0


func _platform_weight_actors_at_cell(cell: Vector2i) -> Array[Node]:
	var out: Array[Node] = []
	var seen: Dictionary = {}
	var add := func(actor: Node) -> void:
		if actor == null or not is_instance_valid(actor) or actor == self:
			return
		if not _local_actor_on_platform(actor, cell):
			return
		var id: int = actor.get_instance_id()
		if seen.has(id):
			return
		seen[id] = true
		out.append(actor)
	_resolve_references()
	if turn_controller != null:
		add.call(turn_controller.occupancy.get(cell, null) as Node)
		add.call(turn_controller.player)
		for enemy in turn_controller.enemies:
			if enemy != null and is_instance_valid(enemy):
				add.call(enemy)
	var tree := get_tree()
	if tree != null:
		for n in tree.get_nodes_in_group("player"):
			add.call(n as Node)
	return out


func _measure_abyss_platform_weight() -> int:
	_sync_submerged_platform_layout()
	if not _submerged_in_abyss:
		return 0
	var cell := _resolve_abyss_platform_cell()
	_resolve_references()
	var weight := 0
	for actor in _platform_weight_actors_at_cell(cell):
		weight += _local_actor_weight(actor)
	if weight > 0:
		return weight
	if turn_controller != null and turn_controller.player != null:
		var pl := turn_controller.player
		if _local_actor_on_platform(pl, cell):
			return maxi(0, _local_actor_weight(pl))
	return 0


func _query_abyss_weight_debug() -> Dictionary:
	_resolve_references()
	var cell := _resolve_abyss_platform_cell()
	var wt := _measure_abyss_platform_weight()
	var result := {
		"cell": cell,
		"weight": wt,
		"platform_registered": dungeon_generator != null \
			and dungeon_generator.has_abyss_barrel_platform(cell),
		"player_grid": Vector2i(-1, -1),
		"player_on_platform": false,
		"player_weight": 0,
		"tc_ok": turn_controller != null,
		"dg_ok": dungeon_generator != null,
		"tc_weight": wt,
	}
	if turn_controller != null and turn_controller.player != null:
		var pl := turn_controller.player
		var pg := _read_actor_grid_pos_local(pl)
		if pg.x > -999999:
			result["player_grid"] = pg
		result["player_on_platform"] = _local_actor_on_platform(pl, cell)
		result["player_weight"] = _local_actor_weight(pl)
	if turn_controller != null:
		result["tc_weight"] = turn_controller.count_non_floating_weight_on_abyss_platform(
			cell, self
		)
	return result


func _has_abyss_platform_weight() -> bool:
	return _measure_abyss_platform_weight() > 0


func _play_random_barrel_impact_sfx() -> void:
	if barrel_impact_sfx_names.is_empty():
		return
	var n: String = String(barrel_impact_sfx_names[
		_barrel_sfx_rng.randi_range(0, barrel_impact_sfx_names.size() - 1)
	])
	_play_barrel_sfx(n)


func _play_splash_sfx() -> void:
	if barrel_splash_sfx_name.is_empty():
		return
	_play_barrel_sfx(barrel_splash_sfx_name)


func _play_barrel_sfx(sfx_name: String) -> void:
	if sfx_name.is_empty():
		return
	var tree := get_tree()
	if tree == null:
		return
	var am := tree.get_first_node_in_group("audio_manager_play_sfx")
	if am != null and (am as Object).has_method("play_sfx"):
		(am as Object).call("play_sfx", sfx_name)


## -1=out or hard block, 1=floor roll ok, 2=abyss (submerge into platform)
## 与 `TurnController._actor_can_enter_cell` 对齐可走性（含**已开门的门格**、关门阻挡、未激活门等）。
func _classify_roll_destination(cell: Vector2i) -> int:
	if dungeon_generator == null:
		return -1
	var t: DungeonGenerator.TileType = dungeon_generator.get_tile(cell) as DungeonGenerator.TileType
	if t == DungeonGenerator.TileType.ABYSS:
		if dungeon_generator.has_abyss_barrel_platform(cell):
			pass
		else:
			return 2
	if turn_controller != null:
		if not turn_controller._actor_can_enter_cell(self, cell, false):
			return -1
	else:
		if t != DungeonGenerator.TileType.FLOOR:
			return -1
		if dungeon_generator.is_inactive_door_at(cell):
			return -1
		if dungeon_generator._door_set.has(cell) \
				and not bool(dungeon_generator._door_states.get(cell, false)):
			return -1
	if turn_controller != null:
		var occ: Variant = turn_controller.occupancy.get(cell, null)
		if occ != null and occ != self and is_instance_valid(occ):
			return -1
	return 1


func _approximate_knock_step(dx: int, dy: int) -> Vector2i:
	if dx == 0 and dy == 0:
		return Vector2i.ZERO
	var ax := absi(dx)
	var ay := absi(dy)
	if ax >= ay * 2:
		return Vector2i(signi(dx), 0)
	if ay >= ax * 2:
		return Vector2i(0, signi(dy))
	return Vector2i(signi(dx), signi(dy))


## 击退路径被墙/关门/占用等挡住时：对目标格尝试近战伤害；若桶自身在燃烧则在伤害后对液体/可点燃物以 `ignite` 补点燃。
func _apply_knockback_collision_at_blocked_cell(blocked_cell: Vector2i, from_cell: Vector2i) -> void:
	if _dead or turn_controller == null:
		return
	var strike_dir := blocked_cell - from_cell
	_play_knockback_bump_melee_visual(strike_dir)
	_play_knockback_bump_impact_particles(strike_dir, blocked_cell)

	var target: Node = turn_controller.occupancy.get(blocked_cell, null)
	if target != null and target != self and is_instance_valid(target) \
			and _knockback_strike_direction_ok(target, from_cell):
		if target.is_in_group("player"):
			var pdmg := maxi(0, barrel_player_knock_damage)
			if pdmg > 0 and target.has_method("apply_damage"):
				target.call("apply_damage", pdmg, from_cell)
			if target.has_method("is_dead") and bool(target.call("is_dead")):
				return
			## 沿桶前进方向再推一格（无伤害时仍可推开）
			if strike_dir != Vector2i.ZERO:
				turn_controller.try_push_actor_from_cell_along_step(target, blocked_cell, strike_dir)
		else:
			var dmg := maxi(0, knockback_collision_damage)
			if dmg > 0 and target.has_method("apply_damage"):
				var dead := _apply_melee_damage_and_query_dead(target, dmg, from_cell)
				if dead:
					turn_controller.occupancy.erase(blocked_cell)
					if is_instance_valid(target) and target is EnemyGridController:
						turn_controller.enemies.erase(target as EnemyGridController)
				turn_controller.request_occupancy_refresh()

	if not is_burning():
		return
	var fd: int = turn_controller.default_fire_duration_turns
	var liq: Node = turn_controller.get_liquid_at(blocked_cell)
	if liq != null and liq.has_method("ignite"):
		liq.call("ignite", fd, false)
	var occ_after: Node = turn_controller.occupancy.get(blocked_cell, null)
	if occ_after != null and occ_after != self and is_instance_valid(occ_after) \
			and _knockback_strike_direction_ok(occ_after, from_cell):
		if occ_after.has_method("ignite"):
			if not occ_after.has_method("is_burning") or occ_after.call("is_burning") != true:
				occ_after.call("ignite", fd, true)


func _apply_melee_damage_and_query_dead(target: Node, dmg: int, from_cell: Vector2i) -> bool:
	if not target.has_method("apply_damage"):
		return false
	var r: Variant = target.call("apply_damage", dmg, from_cell)
	if r is bool:
		return bool(r as bool)
	if target.has_method("is_dead"):
		return bool(target.call("is_dead"))
	return false


func _knockback_strike_direction_ok(actor: Node, from_cell: Vector2i) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if actor.has_method("accepts_directional_hit_from"):
		return bool(actor.call("accepts_directional_hit_from", from_cell))
	return true


func _play_knockback_bump_melee_visual(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return
	if _bump_fx_tween != null and is_instance_valid(_bump_fx_tween):
		_bump_fx_tween.kill()
	var home := _grid_center_local(grid_pos)
	position = home
	var lunge_vec := Vector2(direction).normalized() * float(tile_size) * knockback_bump_lunge_ratio
	_bump_fx_tween = create_tween()
	_bump_fx_tween.set_trans(Tween.TRANS_SINE)
	_bump_fx_tween.set_ease(Tween.EASE_OUT)
	_bump_fx_tween.tween_property(self, "position", home + lunge_vec, knockback_bump_lunge_duration)
	_bump_fx_tween.tween_property(self, "position", home, knockback_bump_lunge_duration)


func _play_knockback_bump_impact_particles(direction: Vector2i, blocked_cell: Vector2i) -> void:
	if knockback_bump_impact_particle_count <= 0:
		return
	var dir := Vector2(direction)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var particle_parent: Node = get_parent()
	if particle_parent == null:
		particle_parent = self
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.82, 0.45, 0.95))
	var tex: Texture2D = ImageTexture.create_from_image(img)
	var spawn_glob: Vector2 = to_global(_grid_center_local(blocked_cell))
	for _i in knockback_bump_impact_particle_count:
		var p := Sprite2D.new()
		p.texture = tex
		p.centered = true
		p.modulate = Color(1.0, 0.9, 0.65, 0.92)
		p.top_level = true
		particle_parent.add_child(p)
		p.global_position = spawn_glob + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		var spread := dir.rotated(randf_range(-0.75, 0.75))
		var speed := randf_range(10.0, 26.0)
		var life := randf_range(0.09, 0.22)
		var tgt := p.global_position + spread * speed
		var tw := create_tween()
		tw.tween_property(p, "global_position", tgt, life)
		tw.parallel().tween_property(p, "modulate:a", 0.0, life)
		tw.finished.connect(func() -> void:
			if is_instance_valid(p):
				p.queue_free()
		, CONNECT_ONE_SHOT)


func _fx_world_parent() -> Node:
	if turn_controller != null and turn_controller.world != null \
			and is_instance_valid(turn_controller.world):
		return turn_controller.world
	var parent := get_parent()
	return parent if parent != null else self


func apply_fire_chain_tick() -> void:
	if _dead or _submerged_in_abyss:
		return
	if not should_resolve_fire_this_turn():
		return
	## 火焰连锁：仅扣倒计时，不改变 HP。
	_burning_turns_left = maxi(0, _burning_turns_left - 1)


func is_knockback_busy() -> bool:
	return _knockback_busy


## `TurnController` 环境传火：每液体阶段至多传一格；返回 true 表示本阶段允许尝试向外点燃一格邻格。
func tick_env_fire_spread_eligible() -> bool:
	if _dead or _submerged_in_abyss or not is_burning():
		return false
	if _env_fire_spread_blocks_remaining > 0:
		_env_fire_spread_blocks_remaining -= 1
		return false
	return true


func mark_env_fire_spread_consumed() -> void:
	## 本次液体阶段已成功点着邻格，下一液体阶段前不再播散。
	_env_fire_spread_blocks_remaining = maxi(_env_fire_spread_blocks_remaining, 1)


func is_dead() -> bool:
	return _dead


func _play_hit_flash() -> void:
	modulate = Color(1.0, 0.75, 0.55, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, break_flash_duration)


func _snap_to_grid_center() -> void:
	position = _grid_center_local(grid_pos)


func _grid_center_local(gp: Vector2i) -> Vector2:
	var ts := float(tile_size)
	return Vector2(gp) * ts + Vector2.ONE * (ts * 0.5)


func _await_knockback_arc_tween(from_center: Vector2, to_center: Vector2) -> void:
	if _knockback_tween != null and is_instance_valid(_knockback_tween):
		_knockback_tween.kill()
	_knockback_arc_from = from_center
	_knockback_arc_to = to_center
	position = from_center
	_knockback_tween = create_tween()
	_knockback_tween.tween_method(
		_apply_knockback_arc_visual_step,
		0.0,
		1.0,
		maxf(0.02, knockback_tween_duration)
	)
	await _knockback_tween.finished
	position = to_center
	_knockback_tween = null


## Godot 4：`tween_method` 仅传入插值 t；起止点存在成员变量中，避免多行 lambda 触发解析缩进问题。
func _apply_knockback_arc_visual_step(t: float) -> void:
	var base := _knockback_arc_from.lerp(_knockback_arc_to, t)
	## Godot 2D：y 向下为正，sin 峰在 mid：负号表示向上跳起
	var arc := -knockback_arc_height_px * sin(PI * t)
	position = base + Vector2(0.0, arc)


func _exit_tree() -> void:
	_disconnect_abyss_platform_actor_listeners()
	_disconnect_abyss_anim_listener()
	_stop_abyss_platform_animation()
	if _submerged_in_abyss and dungeon_generator != null:
		dungeon_generator.unregister_abyss_barrel_platform(grid_pos)
	if _knockback_tween != null and is_instance_valid(_knockback_tween):
		_knockback_tween.kill()
		_knockback_tween = null
	if _bump_fx_tween != null and is_instance_valid(_bump_fx_tween):
		_bump_fx_tween.kill()
		_bump_fx_tween = null


func _apply_visual_from_dungeon() -> void:
	if dungeon_generator != null:
		tile_size = dungeon_generator.tile_size
		var bc: Vector2i = dungeon_generator.barrel_body_atlas_coords
		if bc != Vector2i(-1, -1):
			_atlas_coords = bc
	if _submerged_in_abyss:
		## 入水后 frame 由 AnimationPlayer 驱动，勿再改 atlas 帧。
		return
	if not _apply_barrel_atlas_coords(_atlas_coords):
		_apply_fallback(Color(0.55, 0.35, 0.2, 1.0))


func _apply_barrel_atlas_coords(coords: Vector2i, keep_frame: bool = false) -> bool:
	if _apply_coords_on_scene_atlas_sheet(coords, keep_frame):
		return true
	return _apply_sprite_from_dungeon_atlas_coords(coords, keep_frame)


func _apply_coords_on_scene_atlas_sheet(coords: Vector2i, keep_frame: bool = false) -> bool:
	if _scene_atlas_sheet == null:
		return false
	if _scene_hframes <= 0 or _scene_vframes <= 0:
		return false
	texture = _scene_atlas_sheet
	hframes = _scene_hframes
	vframes = _scene_vframes
	region_enabled = false
	frame_coords = coords
	if not keep_frame:
		frame = coords.x + coords.y * _scene_hframes
	return true


func _resolve_barrel_atlas_source() -> TileSetAtlasSource:
	if dungeon_generator == null:
		return null
	var layer: TileMapLayer = dungeon_generator.tile_map_layer_pillar
	if layer == null:
		layer = dungeon_generator.tile_map_layer
	if layer == null or layer.tile_set == null:
		return null
	var source_id: int = dungeon_generator.get_barrel_atlas_source_id()
	var src: Variant = layer.tile_set.get_source(source_id)
	if src is TileSetAtlasSource:
		return src as TileSetAtlasSource
	return null


func _apply_sprite_from_dungeon_atlas_coords(coords: Vector2i, keep_frame: bool = false) -> bool:
	var asrc := _resolve_barrel_atlas_source()
	if asrc == null or asrc.texture == null:
		return false
	var region: Rect2
	if asrc.has_tile(coords):
		region = asrc.get_tile_texture_region(coords, 0)
	else:
		var cell := asrc.texture_region_size
		if cell.x <= 0 or cell.y <= 0:
			return false
		region = Rect2(Vector2(coords) * Vector2(cell), Vector2(cell))
	var cut := AtlasTexture.new()
	cut.atlas = asrc.texture
	cut.region = region
	cut.filter_clip = true
	texture = cut
	region_enabled = false
	if not keep_frame:
		hframes = 1
		vframes = 1
		frame = 0
		frame_coords = Vector2i.ZERO
	return true


func _apply_fallback(color: Color) -> void:
	var img := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	texture = ImageTexture.create_from_image(img)
	region_enabled = false
	hframes = 1
	vframes = 1
	frame = 0
	frame_coords = Vector2i.ZERO


func _resolve_references() -> void:
	if dungeon_generator == null and not dungeon_generator_path.is_empty():
		var n := get_node_or_null(dungeon_generator_path)
		if n is DungeonGenerator:
			dungeon_generator = n
	if dungeon_generator == null:
		var g := get_tree().get_first_node_in_group("dungeon_generator")
		if g is DungeonGenerator:
			dungeon_generator = g
	if turn_controller == null and not turn_controller_path.is_empty():
		var t := get_node_or_null(turn_controller_path)
		if t is TurnController:
			turn_controller = t
	if turn_controller == null:
		var tc := get_tree().get_first_node_in_group("turn_controller")
		if tc is TurnController:
			turn_controller = tc
	if dungeon_generator == null and turn_controller != null:
		turn_controller._resolve_references()
		if turn_controller.dungeon_generator != null:
			dungeon_generator = turn_controller.dungeon_generator


func get_debug_remaining_burn_turns() -> int:
	return _burning_turns_left
