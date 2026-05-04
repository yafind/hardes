## heal_effect.gd
## Эффект лечения, который воспроизводится вокруг юнита при получении лечения.
## Анимация должна быть настроена в AnimatedSprite2D (анимация "default" или "heal").
extends Node2D

@export var lifetime: float = 1.0  # Время жизни эффекта
@export var fade_out: bool = true  # Плавное исчезновение

var _timer: float = 0.0
var _initial_modulate: Color = Color.WHITE

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null

func _ready() -> void:
	_timer = lifetime
	if animated_sprite:
		_initial_modulate = animated_sprite.modulate
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("default"):
			animated_sprite.play("default")
		elif animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("heal"):
			animated_sprite.play("heal")

func _process(delta: float) -> void:
	_timer -= delta
	
	if fade_out and animated_sprite:
		var alpha = _timer / lifetime
		animated_sprite.modulate = Color(_initial_modulate.r, _initial_modulate.g, _initial_modulate.b, alpha)
	
	if _timer <= 0.0:
		queue_free()
