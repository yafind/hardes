## monastery.gd
## Здание монастыря, которое спавнит монахов для лечения союзников.
## Наследуется от Area2D аналогично barracks и archery.
extends Area2D

@export var monk_scene: PackedScene = preload("res://entities/ally/player_monk.tscn")
@export var spawn_interval: float = 10.0
@export var max_active_monks: int = 4
@export var spawn_radius: float = 60.0
@export var spawn_in_slack: bool = false

@onready var spawn_timer: Timer         = $SpawnTimer
@onready var spawn_point: Marker2D      = $SpawnPoint
@onready var health_component: HealthComponent = $HealthComponent
@onready var _bar: TextureProgressBar   = $healt/ProgressBar if has_node("healt/ProgressBar") else null

var _wave_mode: String  = "attack"
var _destroyed: bool    = false

func _ready() -> void:
	add_to_group("monastery")
	
	if health_component and health_component.has_signal("died"):
		health_component.died.connect(_on_destroyed)
	if health_component and health_component.has_signal("health_changed"):
		health_component.health_changed.connect(_on_health_changed)
	
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_try_spawn)
	spawn_timer.start()
	
	await get_tree().process_frame
	var wm := GameUtils.get_wave_manager(get_tree())
	if wm:
		_wave_mode = wm.get_mode() if wm.has_method("get_mode") else "attack"
		if not wm.mode_changed.is_connected(_on_wave_mode_changed):
			wm.mode_changed.connect(_on_wave_mode_changed)
	_apply_mode()

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
	if get_tree().get_nodes_in_group("player_monks").size() >= max_active_monks:
		return
	if not monk_scene:
		push_error("Monastery: monk_scene not set!")
		return
	var m := monk_scene.instantiate()
	var sp: Vector2 = spawn_point.global_position if spawn_point else global_position
	m.global_position = sp + Vector2(randf_range(-spawn_radius, spawn_radius), 0.0)
	get_parent().add_child(m)

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
