## player_archer.gd
## Лучник фракции ИГРОКА. Наследуется от BaseEntity — вся логика там.
## Этот файл только устанавливает фракцию, группы и слои коллизий.
## Добавлена стрельба стрелами при атаке.
## Добавлено поведение лучника:
## - Если не видит врага — идёт вперёд
## - Если враг приближается — стреляет и отступает
## - Пока стреляет — стоит на месте
## - Хаотичность в движении
##
## Слои коллизий для этого узла (CharacterBody2D):
##   Слой 2 = юниты ИИ фракции игрока
##   Маска 1 = герой игрока (избегание)
##   Маска 3 = вражеские юниты
##   Маска 6 = статические стены
##
## DetectionArea:
##   Слой: нет
##   Маска 3 + 4 = видит вражеских юнитов + вражеский замок
##
## Attack Area2D:
##   Маска 4 + 16 = может попадать во вражеских юнитов + вражеский замок
extends BaseEntity

@export var arrow_scene: PackedScene = preload("res://entities/common/player/skills/arrow.tscn")
@export var shoot_offset: Vector2 = Vector2(30, -10)  # Смещение точки вылета стрелы
@export var retreat_range: float = 120.0  # Дистанция отступления при приближении врага
@export var advance_range: float = 200.0  # Дистанция движения вперёд когда нет врагов рядом
@export var chaos_factor: float = 0.3  # Множитель хаотичности движения (0-1)
@export var chaos_interval: float = 1.5  # Как часто меняется хаотичное направление

var _chaos_direction: Vector2 = Vector2.ZERO
var _chaos_timer: float = 0.0
var _is_retreating: bool = false
var _retreat_target: Vector2 = Vector2.ZERO

func _ready() -> void:
	# ── Фракция и группы ──────────────────────────────────────────────────────
	faction = BaseEntity.Faction.PLAYER
	add_to_group("player_archers")
	add_to_group("team_player")

	# ── Слои коллизий ──────────────────────────────────────────────────────
	# Тело: слой 2 (юниты ИИ игрока), маска: слои 1(герой)+3(враги)+6(стены)
	# Маски DetectionArea и Area2D уже правильно настроены в .tscn.
	collision_layer = 2    # бит 1 = слой 2
	collision_mask  = 37   # 1 + 4 + 32  (биты 0,2,5)

	super._ready()
	_pick_chaos_direction()

func _physics_process(delta: float) -> void:
	# Обновляем таймер хаоса и выбираем новое направление
	_chaos_timer -= delta
	if _chaos_timer <= 0.0:
		_chaos_timer = chaos_interval
		_pick_chaos_direction()
	
	# Применяем родительскую логику
	super._physics_process(delta)

func _pick_chaos_direction() -> void:
	var angle := randf_range(0.0, TAU)
	_chaos_direction = Vector2(cos(angle), sin(angle)) * chaos_factor

func _get_advanced_movement_direction(base_dir: Vector2) -> Vector2:
	# Добавляем хаотичность к направлению движения
	if base_dir.length_squared() > 0.01:
		return (base_dir + _chaos_direction).normalized()
	return base_dir

func _move_via_nav(dest: Vector2) -> void:
	if not nav_agent:
		return
	
	var base_dir := global_position.direction_to(dest)
	var dir := _get_advanced_movement_direction(base_dir)
	
	# Проверяем, есть ли угроза (враг слишком близко)
	var threat := _find_nearest_threat()
	if is_instance_valid(threat):
		var dist_to_threat := global_position.distance_to(threat.global_position)
		if dist_to_threat < retreat_range:
			# Враг слишком близко — отступаем
			_is_retreating = true
			_retreat_target = global_position - (threat.global_position - global_position).normalized() * retreat_range
			dir = (global_position.direction_to(_retreat_target) + _chaos_direction).normalized()
			velocity = dir * speed
			_face(dir.x < 0)
			_move_and_slide_with_wall_handling()
			return
		else:
			_is_retreating = false
	
	# Обычное движение с хаотичностью
	nav_agent.target_position = dest
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
	else:
		var next_path_pos := nav_agent.get_next_path_position()
		base_dir = global_position.direction_to(next_path_pos)
		dir = _get_advanced_movement_direction(base_dir)
		velocity = dir * speed
		_face(dir.x < 0)
	
	_move_and_slide_with_wall_handling()

func _find_nearest_threat() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist_sq := INF
	
	for candidate: Node2D in _candidates:
		if not is_instance_valid(candidate):
			continue
		var d_sq := global_position.distance_squared_to(candidate.global_position)
		if d_sq < nearest_dist_sq:
			nearest_dist_sq = d_sq
			nearest = candidate
	
	return nearest

# Переопределяем метод атаки для стрельбы стрелами вместо ближнего боя
func _start_attack_swing() -> void:
	_can_attack = true
	if not is_instance_valid(self):
		return
	if not (_can_attack and state == State.ATTACK):
		return
	
	# Воспроизводим анимацию стрельбы (лучник стоит на месте во время выстрела)
	if animated_sprite.sprite_frames.has_animation("shoot"):
		animated_sprite.play("shoot")
	else:
		animated_sprite.play("attack1")
	
	# Ждём завершения анимации стрельбы (лучник стоит на месте)
	await animated_sprite.animation_finished
	
	if not is_instance_valid(self) or not (_can_attack and state == State.ATTACK):
		return
	
	# Создаём стрелу в точке вылета
	var shoot_point := get_node_or_null("ShootPoint")
	var spawn_pos := global_position + shoot_offset
	if shoot_point:
		spawn_pos = shoot_point.global_position
	
	if arrow_scene:
		var arrow = arrow_scene.instantiate()
		get_parent().add_child(arrow)
		arrow.global_position = spawn_pos
		
		# Направляем стрелу в цель
		if is_instance_valid(target):
			var direction := (target.global_position - spawn_pos).normalized()
			arrow.direction = direction
			arrow.rotation = direction.angle()
			
			# Если цель имеет HealthComponent, передаём его для наведения
			if target.has_node("HealthComponent"):
				arrow.target = target
	
	# Перезарядка атаки
	_attack_timer = attack_cooldown
	_can_attack = false
