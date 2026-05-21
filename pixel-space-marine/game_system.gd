class_name GameSystem
extends Node2D
## 回合、关卡流程、刷怪、迷雾、摄像机；**玩家实例在本子场景内**，与敌人同 `Node2D` 父级以便 `y_sort`。
## `world_path` 留空时，刷怪/液体等会把本节点当作 `Node2D` 父级。


func _ready() -> void:
	add_to_group("game_system")
