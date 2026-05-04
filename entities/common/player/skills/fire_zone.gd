extends Area2D

@export var damage: int = 5
@export var radius: float = 100.0
@export var duration: float = 3.0
@export var damage_interval: float = 0.5
# lifetime var removed: no longer needed after replacing _process with Tween

@onready var damage_timer: Timer = $DamageTimer
@onready var collision_shape: CollisionShape2D = $DamageZone

func _ready():
	var shape = CircleShape2D.new()
	shape.radius = radius
	collision_shape.shape = shape
	
	damage_timer.wait_time = damage_interval
	damage_timer.timeout.connect(_on_damage_timer_timeout)
	damage_timer.start()

	# Replace _process fade with a Tween: animation runs on the GPU timeline,
	# costs 0 CPU ticks per frame vs _process which ran at 144+ Hz.
	await get_tree().create_timer(duration * 0.7).timeout
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration * 0.3)
	await tween.finished
	queue_free()

func _on_damage_timer_timeout() -> void:
	for body: Node in get_overlapping_bodies():
		# Only damage enemy-faction units; skip friendly knights
		if not body.is_in_group("team_enemy"):
			continue
		if body.has_method("take_damage"):
			body.take_damage(damage, Vector2.ZERO)
# _process removed: fade is now driven by Tween, not per-frame polling
