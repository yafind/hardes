extends Node2D
class_name HealthComponent

signal health_changed(current, max)
signal died

@export var max_health: int = 100
@export var invincibility_duration: float = 0.5

var current_health: int
var is_invincible: bool = false

func _ready():
	current_health = max_health

# use_invincibility=true  → normal i-frame behaviour (check AND start frames)
# use_invincibility=false → bypass check, skip starting frames (DoT, debug hits)
# BUG FIX: DamageFeedback was calling apply_damage(amount, kb, bool) but the
# old signature only accepted 2 args — caused a runtime "too many arguments" crash.
func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, use_invincibility: bool = true) -> Dictionary:
	if use_invincibility and is_invincible:
		return {"applied": false, "died": false}

	current_health = max(0, current_health - amount)
	health_changed.emit(current_health, max_health)

	# Отбрасывание, если у родителя есть физика
	if knockback != Vector2.ZERO and get_parent() is CharacterBody2D:
		get_parent().velocity = knockback

	var died_now: bool = current_health <= 0
	if died_now:
		died.emit()
	elif use_invincibility:
		_start_invincibility()

	return {"applied": true, "died": died_now}

func heal(amount: int):
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func respawn():
	"""Полное восстановление здоровья — для респавна"""
	current_health = max_health
	is_invincible = false
	health_changed.emit(current_health, max_health)

func _start_invincibility():
	is_invincible = true
	await get_tree().create_timer(invincibility_duration).timeout
	is_invincible = false
