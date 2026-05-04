extends Area2D
class_name CastleBase

@export var max_health: int = 500
@export var destruction_effect: PackedScene
@export var health_bar_path: NodePath = ^"HealthBar"

var current_health: int
var health_bar: Range
var health_text: Label

signal castle_destroyed(castle: CastleBase)
signal castle_damaged(amount: int)

func _ready():
	current_health = max_health
	_setup_health_bar_refs()
	_update_health_bar()
	add_to_group("castles")
	_setup_navigation_obstacle()

func _setup_navigation_obstacle() -> void:
	## Adds a NavigationObstacle2D so pathfinding routes around the castle
	## instead of trying to navigate through its solid walls.
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not cs or not (cs.shape is RectangleShape2D):
		return
	var rect := cs.shape as RectangleShape2D
	var hw := rect.size.x * 0.5 + 10.0
	var hh := rect.size.y * 0.5 + 10.0
	var oy := cs.position.y
	var obstacle := NavigationObstacle2D.new()
	obstacle.avoidance_enabled = true
	obstacle.vertices = PackedVector2Array([
		Vector2(-hw, -hh + oy),
		Vector2( hw, -hh + oy),
		Vector2( hw,  hh + oy),
		Vector2(-hw,  hh + oy),
	])
	add_child(obstacle)

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO):
	current_health = max(0, current_health - amount)
	_update_health_bar()
	castle_damaged.emit(amount)
	if current_health <= 0:
		_destroy()

func _update_health_bar():
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if health_text:
		health_text.text = "%d / %d" % [current_health, max_health]

func _setup_health_bar_refs():
	# Явный путь имеет приоритет
	var bar_node: Node = null
	if health_bar_path:
		bar_node = get_node_or_null(health_bar_path)
	# Fallback: ищем по имени ProgressBar или HealthBar в любом месте дерева
	if bar_node == null:
		bar_node = find_child("ProgressBar", true, false)
	if bar_node == null:
		bar_node = find_child("HealthBar", true, false)

	if bar_node is Range:
		health_bar = bar_node as Range

	# Ищем Label с текстом хп в любом месте дерева
	var text_node: Node = find_child("HealthText", true, false)
	if text_node is Label:
		health_text = text_node as Label

func _destroy():
	castle_destroyed.emit(self)
	if destruction_effect:
		var fx = destruction_effect.instantiate()
		fx.global_position = global_position
		get_parent().add_child(fx)
	queue_free()
