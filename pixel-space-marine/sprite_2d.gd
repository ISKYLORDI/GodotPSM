extends Sprite2D

const DEGREES_PER_SECOND := 90.0

func _process(delta: float) -> void:
	rotation += deg_to_rad(DEGREES_PER_SECOND) * delta
