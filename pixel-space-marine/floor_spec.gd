class_name FloorSpec
extends Resource

enum SourceType {
	SCENE = 0,
	RANDOM = 1,
}

@export var source_type: SourceType = SourceType.RANDOM
@export var layout_scene: PackedScene
@export var random_profile_id: StringName = &"default"


func uses_scene_layout() -> bool:
	return source_type == SourceType.SCENE and layout_scene != null
