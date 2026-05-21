@tool
extends EditorInspectorPlugin

const TILE_ARRAY_PROPERTIES: Array[String] = [
	"floor_tiles",
	"abyss_tiles",
	"abyss_tiles_when_north_is_abyss",
	"background_tiles",
	"solid_wall_tiles",
	"solid_diagonal_ne_tiles",
	"solid_diagonal_nw_tiles",
	"solid_diagonal_se_tiles",
	"solid_diagonal_sw_tiles",
	"corridor_horizontal_wall_tiles",
	"corridor_vertical_wall_tiles",
	"corner_top_left_tiles",
	"corner_top_right_tiles",
	"corner_bottom_left_tiles",
	"corner_bottom_right_tiles",
	"ricochet_decor_corner_top_left_tiles",
	"ricochet_decor_corner_top_right_tiles",
	"ricochet_decor_corner_bottom_left_tiles",
	"ricochet_decor_corner_bottom_right_tiles",
	"ricochet_decor_vertical_tiles",
	"pillar_top_tiles",
	"pillar_bottom_tiles",
	"door_closed_tiles",
	"door_open_tiles",
	"inactive_door_wall_tiles",
	"exit_tiles",
]

const PRESET_MARKER_PROPERTIES: Array[String] = [
	"marker_wall_tiles",
	"marker_transparent_wall_tiles",
	"marker_ricochet_wall_tiles",
	"marker_wall_switch_face_up_tiles",
	"marker_wall_switch_face_down_tiles",
	"marker_wall_switch_floor_west_appr_tiles",
	"marker_wall_switch_floor_east_appr_tiles",
	"marker_wall_switch_tiles",
	"marker_floor_tiles",
	"marker_door_tiles",
	"marker_inactive_door_tiles",
	"marker_exit_tiles",
	"marker_player_spawn_tiles",
	"marker_enemy_tiles",
	"marker_pillar_tiles",
	"marker_barrel_tiles",
	"marker_liquid_tiles",
	"marker_abyss_tiles",
]

const WALL_SWITCH_PICK_PROPERTIES: Array[String] = [
	"marker_switch_visual_attack_from_south_row_tiles",
	"marker_switch_visual_attack_from_north_row_tiles",
	"marker_switch_visual_floor_west_tiles",
	"marker_switch_visual_floor_east_tiles",
]

const BREAKABLE_BARREL_PICK_PROPERTIES: Array[String] = [
	"abyss_submerged_atlas_tiles",
]

var _plugin: EditorPlugin
var _picker_window: Window
var _picker_atlas_preview_owner: Object = null


func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _can_handle(object: Object) -> bool:
	return _is_dungeon_generator(object) \
		or _is_preset_floor_layout(object) \
		or _is_marker_semantics(object) \
		or _is_wall_switch_entity(object) \
		or _is_breakable_barrel(object)


func _parse_begin(object: Object) -> void:
	var hint := Label.new()
	if _is_marker_semantics(object):
		hint.text = (
			"DungeonMarkerSemanticsConfig：选图预览需要 TileMap。"
			+ "若在独立 Inspector 中打不开图集：请切换到挂载了 marker_bundle 的 Preset（或任一引用同一 .tres 的关卡），"
			+ "然后从 Preset Inspector 的子资源字段里选图（推荐）。"
		)
	elif _is_wall_switch_entity(object):
		hint.text = (
			"GridWallSwitch 选图：推荐在 `editor_atlas_pick_tile_set` 直接绑定保存好的 TileSet 资源。"
			+ "也可用 `editor_atlas_pick_layer` 从场景中引用图层（两种方式二选一即可）。"
			+ "`editor_atlas_pick_source_id` 与门/开关占位所用 atlas source 对齐；为负时编辑器预览强制 source 0，运行时裁图仍按 DungeonGenerator.tile_source_id。"
		)
	elif _is_breakable_barrel(object):
		hint.text = (
			"BreakableBarrel 选图：`abyss_submerged_atlas_tiles` 会同步到 `abyss_submerged_atlas_coords`。"
			+ "也可像 Atlas Coords 一样直接改坐标；勾选 Editor Preview Submerged Visual 可在场景里预览。"
			+ "运行时优先使用场景图集 (hframes/vframes) 切帧，与 Atlas Coords 行为一致。"
		)
	elif _is_preset_floor_layout(object):
		hint.text = (
			"预设语义：赋值 marker_bundle 时选图会直接写入资源；宿主 Preset 的指示 TileMapLayer / source 用作图集预览。"
			+ "可在 Preset 下添加多个 TileMapLayer（自动收集并烘焙）；同格可分层摆放地板与实体。"
			+ "inactive 假门：`marker_inactive_door_tiles`。门在另一 atlas source：设 `marker_door_source_id` / `marker_alt_source_id`（选图器切换 source，图层仍用 design_tile_map_layer）。"
		)
	else:
		hint.text = (
			"图块数组：点击下方「从图集选取」预览 TileSet 并点选添加。"
			+ "叠层墙需指定 tile_map_layer（底）与 tile_map_layer_overlay（顶）。"
			+ "反弹装饰：corridor_vertical + 内凹角（L：两面正交邻地板且内侧对角为地板；T：三面邻地板）。"
			+ "Special Walls 叠层勿绑定主 tile_map_layer。"
		)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	add_custom_control(hint)


func _parse_property(
	object: Object,
	type: Variant.Type,
	name: String,
	hint_type: PropertyHint,
	hint_string: String,
	usage_flags: int,
	wide: bool
) -> bool:
	var allowed_props: Array[String]
	var write_target: Object = object
	var atlas_preview_bind_value: Variant = null

	if _is_marker_semantics(object):
		allowed_props = PRESET_MARKER_PROPERTIES
	elif _is_preset_floor_layout(object):
		allowed_props = PRESET_MARKER_PROPERTIES
		var bun: Variant = object.get("marker_bundle")
		if bun != null:
			write_target = bun as Object
			atlas_preview_bind_value = object
		else:
			atlas_preview_bind_value = object
	elif _is_dungeon_generator(object):
		allowed_props = TILE_ARRAY_PROPERTIES
	elif _is_wall_switch_entity(object):
		allowed_props = WALL_SWITCH_PICK_PROPERTIES
		atlas_preview_bind_value = object
	elif _is_breakable_barrel(object):
		allowed_props = BREAKABLE_BARREL_PICK_PROPERTIES
		atlas_preview_bind_value = object
	else:
		return false

	if name not in allowed_props:
		return false
	if type != TYPE_ARRAY:
		return false

	var editor := preload("res://addons/dungeon_tile_picker/tile_array_property_editor.gd").new()
	# 使用无参 Callable，避免 `.bind(...).call(目标, 属性)` 在某些 Godot 版本下与 Variant/null 绑定组合时错位。
	editor.setup(write_target, name, Callable(self, "_on_tile_array_pick_pressed_bound").bind(
			atlas_preview_bind_value,
			write_target,
			name
	))
	add_custom_control(editor)
	return true


func _on_tile_array_pick_pressed_bound(bind_atlas_host: Variant, mutation_target: Object, property_name: String) -> void:
	var atlas_owner := bind_atlas_host as Object
	
	if atlas_owner != null \
			and not _valid_tile_picker_atlas_bind_host(atlas_owner):
		atlas_owner = null

	if atlas_owner == null and _marker_semantics_related_script(mutation_target.get_script() as Script):
		atlas_owner = _guess_preset_for_marker_bundle_resource(mutation_target)

	if atlas_owner != null \
			and not _valid_tile_picker_atlas_bind_host(atlas_owner):
		atlas_owner = null

	_open_tile_array_picker(mutation_target, property_name, atlas_owner)


func _open_tile_array_picker(mutation_target: Object, property_name: String, atlas_preview_owner: Object = null) -> void:
	if _picker_window == null or not is_instance_valid(_picker_window):
		_picker_window = preload("res://addons/dungeon_tile_picker/tile_atlas_picker_window.gd").new()
		EditorInterface.get_base_control().add_child(_picker_window)
		_picker_window.coords_picked.connect(_on_coords_picked)

	_picker_atlas_preview_owner = atlas_preview_owner
	_picker_window.open_for(mutation_target, property_name, atlas_preview_owner)


func _on_coords_picked(target: Object, property_name: String, coords: Vector2i, append: bool) -> void:
	if target == null:
		return

	var current: Array = target.get(property_name)
	var new_value: Array = current.duplicate()

	if append:
		if coords not in new_value:
			new_value.append(coords)
	else:
		new_value = [coords]

	var undo_redo: EditorUndoRedoManager = _plugin.get_undo_redo()
	undo_redo.create_action("设置 %s 图块" % property_name, UndoRedo.MERGE_DISABLE, target)
	undo_redo.add_do_property(target, property_name, new_value)
	undo_redo.add_undo_property(target, property_name, current)
	undo_redo.commit_action()

	target.notify_property_list_changed()
	if target is Resource:
		(target as Resource).emit_changed()
	if _picker_atlas_preview_owner != null and is_instance_valid(_picker_atlas_preview_owner):
		_picker_atlas_preview_owner.notify_property_list_changed()

	if _picker_window != null and is_instance_valid(_picker_window):
		_picker_window.refresh_target(target, property_name, _picker_atlas_preview_owner)


func _guess_preset_for_marker_bundle_resource(bundle_obj: Object) -> Node:
	if _plugin == null:
		return null
	var iface: EditorInterface = _plugin.get_editor_interface()
	var root := iface.get_edited_scene_root()
	if root == null:
		return null
	return _find_preset_using_marker_bundle(root, bundle_obj)


func _find_preset_using_marker_bundle(node: Node, bundle_obj: Object) -> Node:
	if node == null:
		return null
	if _preset_layout_related_script(node.get_script() as Script):
		var bx: Variant = node.get("marker_bundle")
		if _marker_bundle_reference_matches(bx, bundle_obj):
			return node
	for i in node.get_child_count():
		var ch := node.get_child(i)
		var hit := _find_preset_using_marker_bundle(ch, bundle_obj)
		if hit != null:
			return hit
	return null


func _marker_bundle_reference_matches(a: Variant, b_obj: Object) -> bool:
	if not (b_obj is Resource):
		return false
	var b_res := b_obj as Resource
	if a == null:
		return false
	if not (a is Resource):
		return false
	var a_res := a as Resource
	if a_res == b_res:
		return true
	var pa := String(a_res.resource_path)
	var pb := String(b_res.resource_path)
	if pa.is_empty() or pb.is_empty():
		return false
	return pa == pb


func _is_dungeon_generator(object: Object) -> bool:
	if object == null:
		return false
	var script: Script = object.get_script()
	if script == null:
		return false
	return script.resource_path.get_file() == "dungeon_generator.gd"


func _is_preset_floor_layout(object: Object) -> bool:
	if object == null:
		return false
	return _preset_layout_related_script(object.get_script() as Script)


func _is_marker_semantics(object: Object) -> bool:
	if object == null:
		return false
	return _marker_semantics_related_script(object.get_script() as Script)


func _is_wall_switch_entity(object: Object) -> bool:
	if object == null:
		return false
	return _wall_switch_entity_script(object.get_script() as Script)


func _is_breakable_barrel(object: Object) -> bool:
	if object == null:
		return false
	return _breakable_barrel_script(object.get_script() as Script)


func _wall_switch_entity_script(script: Script) -> bool:
	if script == null:
		return false
	return String(script.resource_path.get_file()) == "wall_switch_entity.gd"


func _breakable_barrel_script(script: Script) -> bool:
	if script == null:
		return false
	return String(script.resource_path.get_file()) == "breakable_barrel.gd"


func _valid_tile_picker_atlas_bind_host(subject: Object) -> bool:
	if subject == null:
		return false
	var s := subject.get_script() as Script
	return _preset_layout_related_script(s) \
		or _wall_switch_entity_script(s) \
		or _breakable_barrel_script(s)


func _preset_layout_related_script(script: Script) -> bool:
	if script == null:
		return false
	var s := script as Script
	while s != null:
		var fname := String(s.resource_path.get_file())
		if fname == "preset_floor_layout.gd" or fname == "preset_floor_layout_template.gd":
			return true
		s = s.get_base_script()
	return false


func _marker_semantics_related_script(script: Script) -> bool:
	var s := script as Script
	while s != null:
		if String(s.resource_path.get_file()) == "dungeon_marker_semantics_config.gd":
			return true
		s = s.get_base_script()
	return false
