extends CastleBase
class_name PlayerCastle

@export var player_scene: PackedScene
@export var upgrade_ui_scene: PackedScene

@onready var interact_area: Area2D = $InteractArea
@onready var respawn_point: Marker2D = $RespawnPoint
@onready var upgrade_marker: Marker2D = $UpgradeMarker

signal request_upgrade_ui(castle: PlayerCastle)
signal player_respawned()

func _ready():
	super._ready()
	interact_area.body_entered.connect(_on_player_entered)
	add_to_group("player_castle")

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
