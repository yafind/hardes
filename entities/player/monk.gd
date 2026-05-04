## player_monk.gd
## Монах фракции ИГРОКА. Наследуется от BaseEntity.
## Самый медленный и слабый юнит, который только лечит союзников.
## Добавлено хаотичное движение.
##
## Слои коллизий для этого узла (CharacterBody2D):
##   Слой 2 = юниты ИИ фракции игрока
##   Маска 1 = герой игрока (избегание)
##   Маска 3 = вражеские юниты
##   Маска 6 = статические стены
##
## DetectionArea:
##   Слой: нет
##   Маска 2 + 1 = видит союзных юнитов + героя игрока
##
extends BaseEntity

@export var heal_amount: int = 8  # Количество лечения за применение
@export var heal_cooldown_time: float = 2.0  # Перезарядка между лечениями
@export var heal_range: float = 80.0  # Дальность лечения
@export var chaos_factor: float = 0.5  # Множитель хаотичности движения (0-1)
@export var chaos_interval: float = 1.0  # Как часто меняется хаотичное направление
@export var heal_effect_scene: PackedScene = preload("res://entities/ally/heal_effect.tscn")

var _chaos_direction: Vector2 = Vector2.ZERO
var _chaos_timer: float = 0.0
var _heal_timer: float = 0.0
var _is_healing: bool = false
var _heal_target: Node2D = null

func _ready() -> void:
	# ── Фракция и группы ──────────────────────────────────────────────────────
	faction = BaseEntity.Faction.PLAYER
	add_to_group("player_monks")
	add_to_group("team_player")
	
	# ── Слои коллизий ──────────────────────────────────────────────────────
	collision_layer = 2    # бит 1 = слой 2
	collision_mask  = 37   # 1 + 4 + 32  (биты 0,2,5)
	
	# Переопределяем параметры для монаха - самый медленный и слабый
	speed = 50.0  # Самый медленный
	attack_damage = 1  # Практически не наносит урона
	detection_range = heal_range  # Радиус обнаружения = радиус лечения
	
	super._ready()
	_pick_chaos_direction()
	
	# Настройка зоны обнаружения для поиска раненых союзников
	if detection_area:
		# Маска 2 = союзные юниты, маска 1 = герой
		detection_area.collision_mask = 3  # биты 0 и 1

func _physics_process(delta: float) -> void:
	# Обновляем таймер хаоса и выбираем новое направление
	_chaos_timer -= delta
	if _chaos_timer <= 0.0:
		_chaos_timer = chaos_interval
		_pick_chaos_direction()
	
	# Обновляем таймер лечения
	if _heal_timer > 0.0:
		_heal_timer -= delta
	
	# Применяем родительскую логику
	super._physics_process(delta)
	
	# Логика лечения
	if not _is_healing and _heal_timer <= 0.0:
		_find_and_heal_wounded_ally()

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

func _find_and_heal_wounded_ally() -> void:
	# Ищем раненого союзника в радиусе лечения
	var wounded_ally := _find_nearest_wounded_ally()
	
	if is_instance_valid(wounded_ally):
		_heal_target = wounded_ally
		_is_healing = true
		
		# Поворачиваемся к цели лечения
		_face(global_position.x > wounded_ally.global_position.x)
		
		# Воспроизводим анимацию лечения
		if animated_sprite.sprite_frames.has_animation("heal"):
			animated_sprite.play("heal")
		else:
			animated_sprite.play("idle")
		
		# Ждём завершения анимации лечения
		await animated_sprite.animation_finished
		
		if not is_instance_valid(self) or not is_instance_valid(_heal_target):
			_is_healing = false
			return
		
		# Применяем лечение
		if _heal_target.has_node("HealthComponent"):
			var health_comp := _heal_target.get_node("HealthComponent")
			if health_comp and health_comp is HealthComponent:
				health_comp.heal(heal_amount)
				
				# Создаём эффект лечения вокруг цели
				_spawn_heal_effect(_heal_target.global_position)
		
		_is_healing = false
		_heal_timer = heal_cooldown_time

func _find_nearest_wounded_ally() -> Node2D:
	var nearest: Node2D = null
	var nearest_health_ratio := 1.0  # 1.0 = полное здоровье
	
	# Проверяем всех союзников в группе
	for ally: Node in get_tree().get_nodes_in_group("team_player"):
		if ally == self or not is_instance_valid(ally):
			continue
		
		var dist := global_position.distance_to(ally.global_position)
		if dist > heal_range:
			continue
		
		var health_comp := ally.get_node_or_null("HealthComponent")
		if health_comp and health_comp is HealthComponent:
			var current_hp = health_comp.current_health
			var max_hp = health_comp.max_health
			
			if max_hp > 0:
				var health_ratio = float(current_hp) / float(max_hp)
				
				# Ищем самого раненого (с наименьшим процентом здоровья)
				if health_ratio < nearest_health_ratio and health_ratio < 1.0:
					nearest_health_ratio = health_ratio
					nearest = ally
	
	return nearest

func _spawn_heal_effect(position: Vector2) -> void:
	# Спавн эффекта лечения вокруг юнита которого лечат
	if heal_effect_scene:
		var effect = heal_effect_scene.instantiate()
		effect.global_position = position
		get_tree().current_scene.add_child(effect)

func _change_state(new_state: State) -> void:
	if new_state == state:
		return
	
	# Если мы лечим, не прерываем это состояние другими действиями
	if _is_healing and new_state != State.DEATH:
		return
	
	state = new_state
	match new_state:
		State.IDLE:
			if not _is_healing:
				animated_sprite.play("idle")
		State.PATROL, State.CHASE, State.SEARCH:
			if not _is_healing:
				if animated_sprite.sprite_frames.has_animation("run"):
					animated_sprite.play("run")
				else:
					animated_sprite.play("move")
		State.ATTACK:
			# Монах не атакует
			pass
		State.DEATH:
			animated_sprite.modulate = Color.WHITE
			animated_sprite.play("death")
