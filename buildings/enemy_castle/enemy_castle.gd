extends CastleBase
class_name EnemyCastle

@export var enemy_scene: PackedScene
@export var spawn_interval: float = 4.0
@export var max_active_enemies: int = 5
@export var spawn_radius: float = 80.0

@onready var spawn_timer: Timer = $SpawnTimer
@onready var spawn_point: Marker2D = $SpawnPoint
@onready var _bar: TextureProgressBar = $healt/ProgressBar
@onready var _bar_text: Label = $healt/HealthText

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
	# Не спавним если лимит достигнут
	if get_tree().get_nodes_in_group("enemies").size() >= max_active_enemies:
		return
	if not enemy_scene:
		return
	
	var enemy = enemy_scene.instantiate()
	# Добавляем в дерево ДО установки позиции — навигационный агент
	# корректно регистрируется на навмеше (аналогично barracks.gd)
	get_parent().add_child(enemy)
	
	# Спавним от SpawnPoint (ниже замка) с горизонтальным разбросом,
	# как barracks.gd — это гарантирует попадание на навмеш
	var sp: Vector2 = spawn_point.global_position if spawn_point else global_position
	enemy.global_position = sp + Vector2(randf_range(-spawn_radius, spawn_radius), 0.0)
