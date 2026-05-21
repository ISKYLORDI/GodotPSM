@tool
extends Window

signal coords_picked(target: Object, property_name: String, coords: Vector2i, append: bool)

const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 8.0

## 属性的写入目标（如 Preset、`DungeonMarkerSemanticsConfig`）。
var _target: Object
## 若为 PresetFloorLayout 节点：用于预览 TileMap/ source id；与 `_target` 可不同。
var _atlas_preview_owner: Object
var _property_name: String
var _append_mode: bool = true

var _atlas_source: TileSetAtlasSource
var _atlas_texture: Texture2D
var _tile_set: TileSet
var _zoom: float = 2.0

var _selected_layer_prop: String = "tile_map_layer"

var _canvas: Control
var _status_label: Label
var _property_label: Label
var _append_check: CheckBox
var _zoom_slider: HSlider
var _layer_option: OptionButton


func _init() -> void:
	title = "TileSet 图块选取器"
	size = Vector2i(720, 560)
	min_size = Vector2i(480, 360)
	unresizable = false
	visible = false
	close_requested.connect(hide)


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.set_offset(SIDE_LEFT, 8)
	root.set_offset(SIDE_TOP, 8)
	root.set_offset(SIDE_RIGHT, -8)
	root.set_offset(SIDE_BOTTOM, -8)
	add_child(root)

	_property_label = Label.new()
	_property_label.text = "未选择属性"
	root.add_child(_property_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	root.add_child(_status_label)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)

	_append_check = CheckBox.new()
	_append_check.text = "点击添加到数组（关闭则替换为单项）"
	_append_check.button_pressed = true
	_append_check.toggled.connect(func(v: bool) -> void: _append_mode = v)
	toolbar.add_child(_append_check)

	var sep := VSeparator.new()
	toolbar.add_child(sep)

	var layer_lbl := Label.new()
	layer_lbl.text = "TileSet 来源："
	toolbar.add_child(layer_lbl)

	_layer_option = OptionButton.new()
	_layer_option.item_selected.connect(_on_layer_selected)
	toolbar.add_child(_layer_option)

	toolbar.add_spacer(false)
	var zoom_lbl := Label.new()
	zoom_lbl.text = "缩放"
	toolbar.add_child(zoom_lbl)

	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = MIN_ZOOM
	_zoom_slider.max_value = MAX_ZOOM
	_zoom_slider.step = 0.1
	_zoom_slider.value = _zoom
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	toolbar.add_child(_zoom_slider)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	_canvas = _AtlasCanvas.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.picker_window = self
	scroll.add_child(_canvas)

	var footer := HBoxContainer.new()
	root.add_child(footer)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(hide)
	footer.add_child(close_btn)


func _atlas_display_subject() -> Object:
	if _atlas_preview_owner != null and _is_preset_floor_layout_script(_atlas_preview_owner):
		return _atlas_preview_owner
	return _target


func _rebuild_layer_dropdown_for_target() -> void:
	var atlas_subj := _atlas_display_subject()
	if _layer_option == null or atlas_subj == null:
		return
	_layer_option.set_block_signals(true)
	_layer_option.clear()
	if _is_preset_floor_layout_script(atlas_subj):
		var select_idx := 0
		var item_idx := 0
		var add_preset_layer := func(layer: TileMapLayer, label: String, prop_key: String) -> void:
			if layer == null or layer.tile_set == null:
				return
			_layer_option.add_item(label)
			_layer_option.set_item_metadata(item_idx, prop_key)
			if _selected_layer_prop == prop_key:
				select_idx = item_idx
			item_idx += 1
		var primary: Variant = atlas_subj.get("design_tile_map_layer")
		if primary is TileMapLayer:
			var main_sid: int = int(atlas_subj.get("marker_source_id"))
			add_preset_layer.call(primary, "指示层 (source %d)" % main_sid, "design_tile_map_layer")
			var alt_sid: int = int(atlas_subj.get("marker_alt_source_id"))
			if alt_sid != main_sid:
				_layer_option.add_item("指示层 (备选 source %d)" % alt_sid)
				_layer_option.set_item_metadata(item_idx, "alt_source")
				if _selected_layer_prop == "alt_source":
					select_idx = item_idx
				item_idx += 1
		var extras: Variant = atlas_subj.get("design_tile_map_layers_extra")
		if extras is Array:
			for extra_item in extras:
				if extra_item is TileMapLayer:
					var el: TileMapLayer = extra_item
					add_preset_layer.call(el, "指示层 (额外): %s" % el.name, "node:%s" % el.name)
		var auto_discover: bool = bool(atlas_subj.get("auto_discover_design_tile_map_layers"))
		if auto_discover:
			for discovered in _discover_preset_design_layers(atlas_subj):
				var prop_key := "node:%s" % discovered.name
				var already := false
				for i in range(_layer_option.item_count):
					if String(_layer_option.get_item_metadata(i)) == prop_key:
						already = true
						break
				if not already:
					add_preset_layer.call(discovered, "指示层: %s" % discovered.name, prop_key)
		if _layer_option.item_count == 0:
			_selected_layer_prop = "design_tile_map_layer"
		elif not _selected_layer_prop.begins_with("node:") \
				and _selected_layer_prop != "alt_source" \
				and _selected_layer_prop != "design_tile_map_layer":
			_selected_layer_prop = String(_layer_option.get_item_metadata(0))
		_layer_option.select(select_idx)
	elif _mutation_is_wall_switch_script(atlas_subj):
		_layer_option.add_item("直接 TileSet 资源（editor_atlas_pick_tile_set）")
		_layer_option.set_item_metadata(0, "editor_atlas_pick_tile_set")
		_layer_option.add_item("从 TileMapLayer（editor_atlas_pick_layer）")
		_layer_option.set_item_metadata(1, "editor_atlas_pick_layer")
		var want := _selected_layer_prop
		if want != "editor_atlas_pick_tile_set" and want != "editor_atlas_pick_layer":
			want = "editor_atlas_pick_tile_set"
		_selected_layer_prop = want
		var sel := 0
		if want == "editor_atlas_pick_layer":
			sel = 1
		_layer_option.select(sel)
	elif _mutation_is_breakable_barrel_script(atlas_subj):
		_layer_option.add_item("直接 TileSet 资源（editor_atlas_pick_tile_set）")
		_layer_option.set_item_metadata(0, "editor_atlas_pick_tile_set")
		_layer_option.add_item("从 TileMapLayer（editor_atlas_pick_layer）")
		_layer_option.set_item_metadata(1, "editor_atlas_pick_layer")
		var want_barrel := _selected_layer_prop
		if want_barrel != "editor_atlas_pick_tile_set" and want_barrel != "editor_atlas_pick_layer":
			want_barrel = "editor_atlas_pick_tile_set"
		_selected_layer_prop = want_barrel
		var sel_barrel := 0
		if want_barrel == "editor_atlas_pick_layer":
			sel_barrel = 1
		_layer_option.select(sel_barrel)
	else:
		var props: Array[String] = [
			"tile_map_layer",
			"tile_map_layer_background",
			"tile_map_layer_overlay",
			"tile_map_layer_pillar",
		]
		var select_idx := 0
		for idx in range(props.size()):
			var prop := props[idx]
			_layer_option.add_item(prop)
			_layer_option.set_item_metadata(idx, prop)
			if prop == _selected_layer_prop:
				select_idx = idx
		if _selected_layer_prop.is_empty() or not _selected_layer_prop in props:
			_selected_layer_prop = props[0]
			select_idx = 0
		_layer_option.select(select_idx)
	_layer_option.visible = true
	_layer_option.set_block_signals(false)


func open_for(
		mutation_target: Object,
		property_name: String,
		atlas_preview_owner: Object = null
	) -> void:
	_target = mutation_target
	_atlas_preview_owner = atlas_preview_owner
	_property_name = property_name
	_property_label.text = "正在编辑：%s" % property_name
	_rebuild_layer_dropdown_for_target()
	_load_atlas_from_target()
	if _canvas != null:
		_canvas.queue_redraw()
	popup_centered_ratio(0.65)


func refresh_target(target: Object, property_name: String, atlas_preview_owner: Object = null) -> void:
	_target = target
	_property_name = property_name
	if atlas_preview_owner != null:
		_atlas_preview_owner = atlas_preview_owner
	_canvas.queue_redraw()


func _on_layer_selected(index: int) -> void:
	if _layer_option == null or _atlas_display_subject() == null:
		return
	var meta: Variant = _layer_option.get_item_metadata(index)
	if meta is String:
		_selected_layer_prop = meta as String
	_load_atlas_from_target()
	_canvas.queue_redraw()


func _load_atlas_from_target() -> void:
	_atlas_source = null
	_atlas_texture = null
	_tile_set = null

	if _target == null:
		if _status_label != null:
			_status_label.text = "未选择节点。"
		return

	var atlas_subj := _atlas_display_subject()

	var preset_layout := _is_preset_floor_layout_script(atlas_subj)
	var grid_wall_switch_pick := _mutation_is_wall_switch_script(atlas_subj)
	var breakable_barrel_pick := _mutation_is_breakable_barrel_script(atlas_subj)
	var entity_pick_used_fallback_source_zero := false

	var layer: TileMapLayer = null
	var wall_switch_tile_set_direct: TileSet = null
	var source_id: int = 0
	var tile_px: int = 16

	if preset_layout:
		var dtl := atlas_subj.get("design_tile_map_layer")
		if dtl is TileMapLayer:
			layer = dtl
		source_id = int(atlas_subj.get("marker_source_id"))
		if _selected_layer_prop == "alt_source":
			source_id = int(atlas_subj.get("marker_alt_source_id"))
		elif _selected_layer_prop.begins_with("node:"):
			var node_name := _selected_layer_prop.substr(5)
			var picked: Node = atlas_subj.get_node_or_null(NodePath(node_name))
			if picked is TileMapLayer:
				layer = picked as TileMapLayer
		if layer != null and layer.tile_set != null:
			tile_px = int(maxf(1.0, float(layer.tile_set.tile_size.x)))
	elif grid_wall_switch_pick or breakable_barrel_pick:
		source_id = int(atlas_subj.get("editor_atlas_pick_source_id"))
		if source_id < 0:
			source_id = 0
			entity_pick_used_fallback_source_zero = true
		var pick_via := String(_selected_layer_prop)
		if pick_via == "editor_atlas_pick_tile_set":
			var tsv: Variant = atlas_subj.get("editor_atlas_pick_tile_set")
			if tsv is TileSet:
				wall_switch_tile_set_direct = tsv
				tile_px = int(maxf(1.0, float((tsv as TileSet).tile_size.x)))
		else:
			var gsl: Variant = atlas_subj.get("editor_atlas_pick_layer")
			if gsl is TileMapLayer:
				layer = gsl
				if layer.tile_set != null:
					tile_px = int(maxf(1.0, float(layer.tile_set.tile_size.x)))
	else:
		layer = _target.get(_selected_layer_prop)
		if layer == null:
			layer = _target.get("tile_map_layer")
		if layer != null and layer.tile_set != null:
			source_id = int(_target.get("tile_source_id"))
			tile_px = int(maxi(1, int(_target.get("tile_size"))))

	if wall_switch_tile_set_direct != null:
		_tile_set = wall_switch_tile_set_direct
	elif layer == null:
		if _status_label != null:
			if preset_layout:
				_status_label.text = "PresetFloorLayout 未指定 design_tile_map_layer（需绑定指示用 TileMapLayer）。"
			elif grid_wall_switch_pick:
				_status_label.text = (
					"GridWallSwitch：请在「TileSet 来源」里选择「直接 TileSet 资源」并指定 editor_atlas_pick_tile_set，"
					+ "或选择「从 TileMapLayer」并绑定 editor_atlas_pick_layer。"
				)
			elif breakable_barrel_pick:
				_status_label.text = (
					"BreakableBarrel：请在「TileSet 来源」里选择「直接 TileSet 资源」并指定 editor_atlas_pick_tile_set，"
					+ "或选择「从 TileMapLayer」并绑定 editor_atlas_pick_layer。"
				)
			elif _mutation_is_marker_semantics(_target):
				_status_label.text = (
					"无法在独立资源中选图预览：请先打开挂载了本 bundle 的关卡场景，或在 Preset Inspector 里展开 marker_bundle 后再选图。"
				)
			else:
				_status_label.text = "请先在 DungeonGenerator 上指定「%s」。" % _selected_layer_prop
		return
	else:
		_tile_set = layer.tile_set
	if _tile_set == null:
		if _status_label != null:
			if grid_wall_switch_pick:
				_status_label.text = "GridWallSwitch：当前「从 TileMapLayer」引用的图层没有 TileSet；请为该层指定 TileSet，或改用「直接 TileSet 资源」。"
			elif breakable_barrel_pick:
				_status_label.text = "BreakableBarrel：当前「从 TileMapLayer」引用的图层没有 TileSet；请为该层指定 TileSet，或改用「直接 TileSet 资源」。"
			else:
				_status_label.text = "TileMapLayer 没有 TileSet。"
		return

	if not preset_layout:
		var dsc := _target.get_script() as Script
		if dsc != null and String(dsc.resource_path.get_file()) == "dungeon_generator.gd":
			source_id = int(_target.get("tile_source_id"))
			tile_px = int(maxi(1, int(_target.get("tile_size"))))

	var source := _tile_set.get_source(source_id)
	if source == null or not source is TileSetAtlasSource:
		if _status_label != null:
			if grid_wall_switch_pick or breakable_barrel_pick:
				var entity_name := "GridWallSwitch" if grid_wall_switch_pick else "BreakableBarrel"
				_status_label.text = (
					"%s：Source ID %d 无效或非 TileSetAtlasSource；请检查 editor_atlas_pick_source_id，"
					+ "以及与当前「TileSet 来源」中选用的 TileSet 是否一致。"
					% [entity_name, source_id]
				)
			else:
				_status_label.text = (
					"Source ID %d 不是 TileSetAtlasSource（预设请检查 marker_source_id / marker_alt_source_id）。"
					% source_id
				)
		return

	_atlas_source = source as TileSetAtlasSource
	_atlas_texture = _atlas_source.texture
	if _atlas_texture == null:
		if _status_label != null:
			_status_label.text = "图集纹理为空。"
		return

	if _status_label != null:
		var summary := (
			"图集：%s | 图块像素约 %d | 共 %d 个图块 | 左键点选。"
			% [_atlas_texture.resource_path.get_file(), tile_px, _atlas_source.get_tiles_count()]
		)
		if grid_wall_switch_pick and entity_pick_used_fallback_source_zero:
			summary += " | 编辑器：editor_atlas_pick_source_id 为负 → 预览用 source 0；运行时按 DungeonGenerator.tile_source_id 切贴图。"
		if breakable_barrel_pick and entity_pick_used_fallback_source_zero:
			summary += " | 编辑器：editor_atlas_pick_source_id 为负 → 预览用 source 0；运行时按 DungeonGenerator 柱/桶 atlas source 切贴图。"
		_status_label.text = summary
	_update_canvas_size()


func _is_preset_floor_layout_script(t: Object) -> bool:
	if t == null:
		return false
	return _preset_script_extends_preset_layout(t.get_script() as Script)


func _mutation_is_wall_switch_script(mut_obj: Object) -> bool:
	return _wall_switch_related_script(mut_obj.get_script() as Script if mut_obj != null else null)


func _mutation_is_breakable_barrel_script(mut_obj: Object) -> bool:
	return _breakable_barrel_related_script(mut_obj.get_script() as Script if mut_obj != null else null)


func _wall_switch_related_script(script: Script) -> bool:
	var s := script as Script
	while s != null:
		if String(s.resource_path.get_file()) == "wall_switch_entity.gd":
			return true
		s = s.get_base_script()
	return false


func _breakable_barrel_related_script(script: Script) -> bool:
	var s := script as Script
	while s != null:
		if String(s.resource_path.get_file()) == "breakable_barrel.gd":
			return true
		s = s.get_base_script()
	return false


func _mutation_is_marker_semantics(mut_obj: Object) -> bool:
	return _marker_semantics_related_script(mut_obj.get_script() as Script if mut_obj != null else null)


func _marker_semantics_related_script(script: Script) -> bool:
	var s := script as Script
	while s != null:
		if String(s.resource_path.get_file()) == "dungeon_marker_semantics_config.gd":
			return true
		s = s.get_base_script()
	return false


func _discover_preset_design_layers(preset: Node) -> Array[TileMapLayer]:
	var found: Array[TileMapLayer] = []
	if preset == null:
		return found
	_gather_preset_design_layers_recursive(preset, found)
	return found


func _gather_preset_design_layers_recursive(node: Node, out: Array[TileMapLayer]) -> void:
	for child in node.get_children():
		if child is TileMapLayer:
			var layer := child as TileMapLayer
			if out.find(layer) < 0:
				out.append(layer)
		_gather_preset_design_layers_recursive(child, out)


func _preset_script_extends_preset_layout(script: Script) -> bool:
	if script == null:
		return false
	var s := script as Script
	while s != null:
		var fname := String(s.resource_path.get_file())
		if fname == "preset_floor_layout.gd" or fname == "preset_floor_layout_template.gd":
			return true
		s = s.get_base_script()
	return false


func _update_canvas_size() -> void:
	if _atlas_texture == null:
		_canvas.custom_minimum_size = Vector2(64, 64)
		return
	_canvas.custom_minimum_size = _atlas_texture.get_size() * _zoom


func _on_zoom_changed(value: float) -> void:
	_zoom = value
	_update_canvas_size()
	_canvas.queue_redraw()


func _pick_at_canvas_position(local_pos: Vector2) -> void:
	if _atlas_source == null or _atlas_texture == null:
		return

	var texture_pos := local_pos / _zoom
	for i in _atlas_source.get_tiles_count():
		var coords: Vector2i = _atlas_source.get_tile_id(i)
		var region: Rect2 = _atlas_source.get_tile_texture_region(coords, 0)
		if region.has_point(texture_pos):
			coords_picked.emit(_target, _property_name, coords, _append_mode)
			return

	_status_label.text = "未点中图块，请点击图集上的有效区域。"


func _get_selected_tiles() -> Array:
	if _target == null or _property_name.is_empty():
		return []
	return _target.get(_property_name)


class _AtlasCanvas extends Control:
	var picker_window: Window

	func _draw() -> void:
		var win: Window = picker_window as Window
		if win == null or win._atlas_texture == null:
			draw_string(
				ThemeDB.fallback_font,
				Vector2(8, 24),
				"无法预览：请设置 Tile Map Layer 与 TileSet。",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				14,
				Color(1, 0.6, 0.6)
			)
			return

		var tex: Texture2D = win._atlas_texture
		var zoom: float = win._zoom
		draw_texture_rect(tex, Rect2(Vector2.ZERO, tex.get_size() * zoom), false)

		var selected: Array = win._get_selected_tiles()
		for i in win._atlas_source.get_tiles_count():
			var coords: Vector2i = win._atlas_source.get_tile_id(i)
			var region: Rect2 = win._atlas_source.get_tile_texture_region(coords, 0)
			var scaled := Rect2(region.position * zoom, region.size * zoom)
			if coords in selected:
				draw_rect(scaled, Color(0.2, 1.0, 0.35, 0.35), true)
				draw_rect(scaled, Color(0.2, 1.0, 0.35), false, 2.0)
			else:
				draw_rect(scaled, Color(1, 1, 1, 0.06), true)


	func _gui_input(event: InputEvent) -> void:
		var win := picker_window as Window
		if win == null:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				win._pick_at_canvas_position(mb.position)
				accept_event()
