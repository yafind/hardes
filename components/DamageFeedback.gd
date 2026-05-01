extends RefCounted
class_name DamageFeedback

static func apply_damage_with_feedback(
	actor: Node,
	health_component: Node,
	amount: int,
	knockback: Vector2,
	effect_scene: PackedScene,
	sprite: CanvasItem,
	world_position: Vector2,
	apply_invincibility: bool = true
) -> Dictionary:
	if health_component == null:
		return {"applied": false, "died": false}

	var damage_result: Dictionary = health_component.apply_damage(amount, knockback, apply_invincibility)
	if not damage_result.get("applied", false):
		return damage_result
	if damage_result.get("died", false):
		return damage_result

	HitFeedback.spawn_hit_effect(actor.get_tree(), effect_scene, world_position)
	HitFeedback.flash_sprite(actor, sprite)
	return damage_result
