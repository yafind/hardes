extends CastleBase
class_name EnemyCastle

@export var enemy_scene: PackedScene
@export var archer_scene: PackedScene
@export var lancer_scene: PackedScene
@export var spawn_interval: float = 4.0
@export var max_active_enemies: int = 5
@export var max_archers: int = 2
@export var max_lancers: int = 2
@export var spawn_radius: float = 80.0

@onready var spawn_timer: Timer = $SpawnTimer
@onready var spawn_point: Marker2D = $SpawnPoint
@onready var _bar: TextureProgressBar = $healt/ProgressBar
@onready var _bar_text: Label = $healt/HealthText

var _spawn_index: int = 0

func _setup_health_bar_refs():
	health_bar = _bar
	health_text = _bar_text

func _ready():
	super._ready()
	add_to_group("enemy_castle")
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_spawn_enemy)
	spawn_timer.start()

func _spawn_enemy():
	# Cycle through unit types: basic enemy -> archer -> lancer
	var scene_to_spawn: PackedScene = null
	var group_name: String = ""
	var max_count: int = 0
	
	match _spawn_index % 3:
		0:
			if enemy_scene:
				scene_to_spawn = enemy_scene
				group_name = "enemies"
				max_count = max_active_enemies
		1:
			if archer_scene and get_tree().get_nodes_in_group("enemy_archers").size() < max_archers:
				scene_to_spawn = archer_scene
				group_name = "enemy_archers"
				max_count = max_archers
		2:
			if lancer_scene and get_tree().get_nodes_in_group("enemy_lancers").size() < max_lancers:
				scene_to_spawn = lancer_scene
				group_name = "enemy_lancers"
				max_count = max_lancers
	
	_spawn_index += 1
	
	# Skip if no scene selected or limit reached
	if not scene_to_spawn:
		return
	if get_tree().get_nodes_in_group(group_name).size() >= max_count:
		return
	
	var enemy = scene_to_spawn.instantiate()
	# Add to tree BEFORE setting position — navigation agent
	# registers correctly on navmesh (similar to barracks.gd)
	get_parent().add_child(enemy)
	
	# Spawn from SpawnPoint (below castle) with horizontal spread,
	# like barracks.gd — this guarantees landing on navmesh
	var sp: Vector2 = spawn_point.global_position if spawn_point else global_position
	enemy.global_position = sp + Vector2(randf_range(-spawn_radius, spawn_radius), 0.0)
