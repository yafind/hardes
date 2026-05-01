## barracks.gd
## Spawns player_knight units periodically up to a cap.
## Pauses during "slack" wave mode unless enemy enters proximity.
extends Area2D

@export var knight_scene: PackedScene = preload("res://entities/ally/player_knight.tscn")
@export var spawn_interval: float = 8.0
@export var max_active_knights: int = 6
@export var spawn_radius: float = 60.0
@export var spawn_in_slack: bool = false

@onready var spawn_timer: Timer         = $SpawnTimer
@onready var spawn_point: Marker2D      = $SpawnPoint
@onready var health_component: Node     = $HealthComponent
@onready var _bar: TextureProgressBar   = $healt/ProgressBar

var _wave_mode: String  = "attack"
var _destroyed: bool    = false

func _ready() -> void:
	add_to_group("barracks")

	if health_component and health_component.has_signal("died"):
		health_component.died.connect(_on_destroyed)
	if health_component and health_component.has_signal("health_changed"):
		health_component.health_changed.connect(_on_health_changed)

	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_try_spawn)
	spawn_timer.start()

	await get_tree().process_frame
	var wm := _get_wave_manager()
	if wm:
		_wave_mode = wm.get_mode() if wm.has_method("get_mode") else "attack"
		if not wm.mode_changed.is_connected(_on_wave_mode_changed):
			wm.mode_changed.connect(_on_wave_mode_changed)
	_apply_mode()

func _get_wave_manager() -> Node:
	var list := get_tree().get_nodes_in_group("wave_manager")
	return list[0] if list.size() > 0 else null

func _on_wave_mode_changed(new_mode: String) -> void:
	_wave_mode = new_mode
	_apply_mode()

func _apply_mode() -> void:
	if _destroyed:
		return
	if _wave_mode == "slack" and not spawn_in_slack:
		spawn_timer.stop()
	elif spawn_timer.is_stopped():
		spawn_timer.start()

func _try_spawn() -> void:
	if _destroyed:
		return
	if get_tree().get_nodes_in_group("player_knights").size() >= max_active_knights:
		return
	if not knight_scene:
		push_error("Barracks: knight_scene not set!")
		return
	var k := knight_scene.instantiate()
	var sp: Vector2 = spawn_point.global_position if spawn_point else global_position
	k.global_position = sp + Vector2(randf_range(-spawn_radius, spawn_radius), 0.0)
	get_parent().add_child(k)

func _on_health_changed(cur: int, max_hp: int) -> void:
	if _bar:
		_bar.max_value = max_hp
		_bar.value     = cur

func _on_destroyed() -> void:
	_destroyed = true
	spawn_timer.stop()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	await tw.finished
	queue_free()

func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if _destroyed or not health_component:
		return
	health_component.apply_damage(amount)
