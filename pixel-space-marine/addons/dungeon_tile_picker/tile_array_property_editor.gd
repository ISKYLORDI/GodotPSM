@tool
extends VBoxContainer

var _target: Object
var _property_name: String
var _open_picker_callable: Callable

var _list_box: VBoxContainer
var _summary: Label


func setup(target: Object, property_name: String, open_picker: Callable) -> void:
	_target = target
	_property_name = property_name
	_open_picker_callable = open_picker
	_build_ui()
	_refresh_list()


func _build_ui() -> void:
	custom_minimum_size.x = 0

	var header := HBoxContainer.new()
	add_child(header)

	var title := Label.new()
	title.text = _property_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var pick_btn := Button.new()
	pick_btn.text = "从图集选取…"
	pick_btn.pressed.connect(_on_pick_pressed)
	header.add_child(pick_btn)

	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.pressed.connect(_on_clear_pressed)
	header.add_child(clear_btn)

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 12)
	_summary.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	add_child(_summary)

	_list_box = VBoxContainer.new()
	add_child(_list_box)


func _on_pick_pressed() -> void:
	if _open_picker_callable.is_valid():
		_open_picker_callable.call()


func _on_clear_pressed() -> void:
	if _target == null:
		return
	var undo_redo := EditorInterface.get_editor_undo_redo()
	var old_value: Array = _target.get(_property_name)
	undo_redo.create_action("清空 %s" % _property_name, UndoRedo.MERGE_DISABLE, _target)
	undo_redo.add_do_property(_target, _property_name, [])
	undo_redo.add_undo_property(_target, _property_name, old_value)
	undo_redo.commit_action()
	_target.notify_property_list_changed()
	if _target is Resource:
		(_target as Resource).emit_changed()
	_refresh_list()


func _refresh_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()

	if _target == null:
		return

	var tiles: Array = _target.get(_property_name)
	if _property_name.begins_with("marker_"):
		_summary.text = "共 %d 项（多种图块可视为同一语义）" % tiles.size()
	else:
		_summary.text = "共 %d 项（多项时运行时随机）" % tiles.size()

	for i in tiles.size():
		var coords: Vector2i = tiles[i]
		var row := HBoxContainer.new()
		_list_box.add_child(row)

		var label := Label.new()
		label.text = "  (%d, %d)" % [coords.x, coords.y]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var remove_btn := Button.new()
		remove_btn.text = "×"
		remove_btn.custom_minimum_size = Vector2(28, 0)
		var index := i
		remove_btn.pressed.connect(func() -> void: _remove_at(index))
		row.add_child(remove_btn)


func _remove_at(index: int) -> void:
	if _target == null:
		return
	var old_value: Array = _target.get(_property_name)
	var new_value: Array = old_value.duplicate()
	if index < 0 or index >= new_value.size():
		return
	new_value.remove_at(index)

	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("移除图块", UndoRedo.MERGE_DISABLE, _target)
	undo_redo.add_do_property(_target, _property_name, new_value)
	undo_redo.add_undo_property(_target, _property_name, old_value)
	undo_redo.commit_action()
	_target.notify_property_list_changed()
	if _target is Resource:
		(_target as Resource).emit_changed()
	_refresh_list()
