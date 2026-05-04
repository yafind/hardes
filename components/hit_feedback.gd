extends RefCounted
class_name HitFeedback

static func spawn_hit_effect(tree: SceneTree, effect_scene: PackedScene, world_position: Vector2) -> void:
	if tree == null or tree.current_scene == null or effect_scene == null:
		return
	var fx := effect_scene.instantiate()
	tree.current_scene.add_child(fx)
	fx.global_position = world_position + Vector2(randf_range(-10, 10), randf_range(-20, 0))

static func flash_sprite(owner: Node, sprite: CanvasItem) -> void:
	if owner == null or sprite == null:
		return
	var tween := owner.create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3), 0.04)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)
