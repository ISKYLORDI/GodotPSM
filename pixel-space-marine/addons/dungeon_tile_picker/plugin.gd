@tool
extends EditorPlugin

var _inspector_plugin: EditorInspectorPlugin


func _enter_tree() -> void:
	_inspector_plugin = preload("res://addons/dungeon_tile_picker/dungeon_inspector_plugin.gd").new()
	_inspector_plugin.set_plugin(self)
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	remove_inspector_plugin(_inspector_plugin)
	_inspector_plugin = null
