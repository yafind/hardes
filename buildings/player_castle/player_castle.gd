extends CastleBase
class_name PlayerCastle

@export var player_scene: PackedScene
@export var upgrade_ui_scene: PackedScene
@export var lancer_scene: PackedScene = preload("res://entities/ally/player_lancer.tscn")
@export var spawn_interval: float = 8.0
@export var max_active_lancers: int = 6
@export var spawn_radius: float = 60.0

@onready var interact_area: Area2D = $InteractArea
@onready var respawn_point: Marker2D = $RespawnPoint
@onready var upgrade_marker: Marker2D = $UpgradeMarker
@onready var spawn_timer: Timer = $SpawnTimer
@onready var spawn_point: Marker2D = $SpawnPoint

signal request_upgrade_ui(castle: PlayerCastle)
signal player_respawned()

var _wave_mode: String = "attack"
var _destroyed: bool = false

func _ready():
	super._ready()
	interact_area.body_entered.connect(_on_player_entered)
	add_to_group("player_castle")
	
	# Setup lancer spawning
	if spawn_timer:
		spawn_timer.wait_time = spawn_interval
		spawn_timer.timeout.connect(_try_spawn_lancer)
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
	if _wave_mode == "slack":
		spawn_timer.stop()
	elif spawn_timer.is_stopped():
		spawn_timer.start()

func _try_spawn_lancer() -> void:
	if _destroyed:
		return
	if get_tree().get_nodes_in_group("player_lancers").size() >= max_active_lancers:
		return
	if not lancer_scene:
		push_error("PlayerCastle: lancer_scene not set!")
		return
	var l := lancer_scene.instantiate()
	var sp: Vector2 = spawn_point.global_position if spawn_point else global_position
	l.global_position = sp + Vector2(randf_range(-spawn_radius, spawn_radius), 0.0)
	get_parent().add_child(l)

func _on_player_entered(body: CharacterBody2D):
	if body.is_in_group("player"):
		request_upgrade_ui.emit(self)

func respawn_player(player: CharacterBody2D):
	if is_instance_valid(player):
		# full_respawn_reset() handles: State.DEATH → IDLE, modulate.a=0 → 1,
		# collision restore, velocity zero, health.respawn() (with signal), timers reset.
		# Previous code called non-existent reset_skills() and set health directly
		# (bypassing health_changed signal), leaving player invisible and frozen.
		player.global_position = respawn_point.global_position
		player.full_respawn_reset()
		player_respawned.emit()
		return
	if not player_scene:
		push_error("PlayerCastle: player_scene not assigned!")
		return
	var new_player = player_scene.instantiate()
	new_player.global_position = respawn_point.global_position
	var parent = get_parent()
	if parent:
		parent.add_child(new_player)
	player_respawned.emit()

func get_upgrade_position() -> Vector2:
	return upgrade_marker.global_position
