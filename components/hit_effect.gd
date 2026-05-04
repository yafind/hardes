extends Node2D

func _ready():
	rotation = randf_range(0.0, TAU)
	scale = Vector2(0.3, 0.3)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 0.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)
