extends Area2D

@export var damage: int = 15
@export var speed: float = 600.0
@export var max_distance: float = 400.0
@export var knockback_force: float = 50.0

var direction: Vector2 = Vector2.RIGHT
var travel_distance: float = 0.0

@onready var sprite: Sprite2D = $ArrowSprite

func _ready():
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)

# _physics_process: runs at fixed physics rate (default 60 Hz) instead of
# display rate (144+ Hz). Eliminates spurious extra ticks on fast monitors.
func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	# direction is normalized → ||direction * speed * delta|| == speed * delta exactly.
	# Replaces movement.length() which called sqrt() every display frame.
	travel_distance += speed * delta
	if travel_distance >= max_distance:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Skip friendly faction (player unit group and ally knights)
	if body.is_in_group("player") or body.is_in_group("team_player"):
		return
	if body.is_in_group("team_enemy") and body.has_method("take_damage"):
		body.take_damage(damage, direction * knockback_force)
		queue_free()
