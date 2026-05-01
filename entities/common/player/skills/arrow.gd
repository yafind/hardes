extends Area2D

@export var damage: int = 15
@export var speed: float = 600.0
@export var max_distance: float = 400.0
@export var knockback_force: float = 50.0
@export var homing_strength: float = 0.15  ## How strongly arrow homes to target (0 = no homing)
@export var homing_max_angle: float = 45.0  ## Maximum turn angle per second in degrees

var direction: Vector2 = Vector2.RIGHT
var travel_distance: float = 0.0
var target: Node2D = null  ## Optional target for homing

@onready var sprite: Sprite2D = $ArrowSprite

func _ready():
	if direction.length() > 0.01:
		rotation = direction.angle()
	body_entered.connect(_on_body_entered)

# _physics_process: runs at fixed physics rate (default 60 Hz) instead of
# display rate (144+ Hz). Eliminates spurious extra ticks on fast monitors.
func _physics_process(delta: float) -> void:
	# Apply homing if target is set and valid
	if target and is_instance_valid(target):
		var to_target := (target.global_position - global_position).normalized()
		if to_target.length() > 0.01:
			# Calculate angle between current direction and target direction
			var current_angle := direction.angle()
			var target_angle := to_target.angle()
			var angle_diff := wrapf(target_angle - current_angle, -PI, PI)
			
			# Limit turn rate
			var max_turn := deg_to_rad(homing_max_angle) * delta
			angle_diff = clampf(angle_diff, -max_turn, max_turn)
			
			# Blend with homing strength
			var new_angle := current_angle + angle_diff * homing_strength
			direction = Vector2(cos(new_angle), sin(new_angle))
			rotation = new_angle
	
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
