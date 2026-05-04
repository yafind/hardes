## BaseEntity.gd
## Базовый класс для всех юнитов ИИ (враги и союзники) с поддержкой фракций.
##
## Архитектура обнаружения — на сигналах, НЕ опрос каждый кадр:
##   • DetectionArea  (Area2D) — большая зона, срабатывают сигналы body_entered/body_exited.
##     Узел ДОЛЖЕН существовать в сцене как дочерний с именем "DetectionArea".
##   • Area2D         (Area2D) — малая зона ближнего боя для нанесения урона.
##
## Соглашения о слоях коллизий (настраивается в Inspector или через код):
##   Слой 1 (бит 0) = 1   → Игрок (герой, управляется пользователем)
##   Слой 2 (бит 1) = 2   → Юниты фракции игрока (рыцари, союзники)
##   Слой 3 (бит 2) = 4   → Юниты фракции врага
##   Слой 5 (бит 4) = 16  → Здания / Замки (Area2D, без физического тела)
##   Слой 6 (бит 5) = 32  → Статические стены / твёрдые тела замка
##
## collision_mask зоны DetectionArea должен видеть ПРОТИВОПОЛОЖНУЮ фракцию:
##   Зона обнаружения врага mask = 3   (слои 1+2 = герой игрока + рыцари игрока)
##   Зона обнаружения союзника mask = 4   (слой 3 = юниты врага)
##   (замки всегда известны и не требуют обнаружения — находятся через запрос группы)
##
## Режимы волн:
##   "attack" → обычное поведение ИИ
##   "slack"  → юнит приостанавливается. Возобновляет ТОЛЬКО если враг вошёл в DetectionArea
##              ИЛИ WaveManager переключился обратно на "attack".
extends CharacterBody2D
class_name BaseEntity

enum Faction { PLAYER, ENEMY }
enum TargetPriority { LOW = 0, MEDIUM = 50, HIGH = 80, CRITICAL = 200 }

# ── Экспортируемые переменные (настраиваются в Inspector) ───────────────────────

@export var faction: Faction = Faction.PLAYER  # Фракция юнита (игрок или враг)
@export var detection_range: float = 260.0  # Радиус зоны обнаружения (форма задаётся в сцене)
@export var attack_range:    float = 55.0   # Дальность атаки
@export var speed:           float = 80.0   # Скорость передвижения
@export var attack_damage:   int   = 12     # Урон от атаки
@export var attack_cooldown: float = 1.0    # Перезарядка между атаками
@export var patrol_radius:   float = 70.0   # Радиус патрулирования вокруг точки появления
@export var search_timeout:  float = 3.0    # Время поиска потерянной цели
# Как часто пересчитывается приоритет цели (в секундах). Минимум 0.3.
@export var priority_interval: float = 0.3
# Множитель скорости при движении к далёким целям (предотвращает скопление)
@export var approach_speed_factor: float = 1.0
# Минимальное расстояние до других дружественных юнитов (избегание наложения)
@export var separation_distance: float = 40.0
# Вес поведения разделения (0 = отключено)
@export var separation_weight: float = 0.6
# Коэффициент скольжения вдоль стен (0 = нет скольжения, 1 = полное скольжение)
@export var wall_slide_factor: float = 0.7

# ── Состояния ─────────────────────────────────────────────────────────────────────
enum State { IDLE, PATROL, CHASE, SEARCH, ATTACK, DEATH }  # Состояния ИИ: бездействие, патруль, преследование, поиск, атака, смерть
var state: State = State.IDLE

# Переменные состояния
var target:              Node2D  = null        # Текущая цель
var spawn_position:      Vector2 = Vector2.ZERO  # Точка появления
var patrol_target:       Vector2 = Vector2.ZERO  # Цель патрулирования
var last_known_pos:      Vector2 = Vector2.ZERO  # Последнее известное положение цели
var _can_attack:         bool    = false       # Можно ли атаковать
var _attack_timer:       float   = 0.0         # Таймер перезарядки атаки
var _search_timer:       float   = 0.0         # Таймер поиска цели
var _priority_timer:     float   = 0.0         # Таймер пересчёта приоритета
var _stuck_timer:        float   = 0.0         # Таймер застревания
var _last_pos:           Vector2 = Vector2.ZERO  # Последняя позиция
var _nav_last_dest:      Vector2 = Vector2(INF, INF)  # Последняя цель навигации
var _wave_mode:          String  = "attack"    # Режим волны ("attack" или "slack")
var _finishing_fight:    bool    = false       # Завершает ли текущий бой

# Кандидаты в цели, вошедшие в зону обнаружения — используются для выбора приоритета.
# Очищаются при выходе из зоны. Замок всегда добавляется через запрос группы (без ограничения по дальности).
var _candidates: Array[Node2D] = []

const _STUCK_INTERVAL: float = 0.5  # Интервал проверки застревания (сек)
const _STUCK_DIST_SQ:  float = 4.0   # Минимальный квадрат расстояния для определения застревания

const HIT_EFFECT := preload("res://components/hit_effect.tscn")  # Эффект попадания

# Ссылки на узлы сцены (заполняются в _ready)
@onready var animated_sprite: AnimatedSprite2D  = $AnimatedSprite2D
@onready var health_component: Node              = $HealthComponent
@onready var attack_area:      Area2D            = $Area2D
@onready var nav_agent:        NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null
var detection_area: Area2D = null  # Зона обнаружения врагов (заполняется в _ready)

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	spawn_position = global_position
	_last_pos      = global_position

	# Зона обнаружения врагов (опционально — у управляемых игроком юнитов может не быть)
	detection_area = get_node_or_null("DetectionArea")

	# Компонент здоровья
	if health_component and health_component.has_signal("died"):
		health_component.died.connect(_on_death)

	# Анимация
	animated_sprite.animation_finished.connect(_on_animation_finished)

	# Зона атаки (ближний бой) — отключена до начала удара
	if attack_area:
		attack_area.monitoring = false
		attack_area.body_entered.connect(_on_attack_body_entered)
		attack_area.area_entered.connect(_on_attack_area_entered)

	# Зона обнаружения — всегда активна; сигналы заполняют список _candidates
	if detection_area:
		detection_area.monitoring  = true
		detection_area.monitorable = false  # другие юниты не должны обнаруживать этот сенсор
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)

	if nav_agent:
		nav_agent.path_max_distance = 80.0
		nav_agent.avoidance_enabled = false  # расстояние между юнитами обрабатывается через separation_weight
		nav_agent.radius = 18.0
	_pick_patrol_target()

	# Подписка на WaveManager
	await get_tree().process_frame
	_connect_wave_manager()

	# Запуск правильного состояния для текущего режима волны
	if _wave_mode == "attack":
		_begin_active()
	else:
		_change_state(State.IDLE)

# ── Менеджер волн ──────────────────────────────────────────────────────────────

func _connect_wave_manager() -> void:
	var wm := GameUtils.get_wave_manager(get_tree())
	if wm == null:
		return
	_wave_mode = wm.get_mode() if wm.has_method("get_mode") else "attack"
	if not wm.mode_changed.is_connected(_on_wave_mode_changed):
		wm.mode_changed.connect(_on_wave_mode_changed)

func _on_wave_mode_changed(new_mode: String) -> void:
	_wave_mode = new_mode
	if new_mode == "slack":
		# Закончить текущий бой, затем остановиться
		if state == State.ATTACK or state == State.CHASE:
			_finishing_fight = true
		else:
			_hold_position()
	else:
		# Возобновить атаку
		_finishing_fight = false
		_begin_active()

# ── Сигналы обнаружения (основа подхода на сигналах) ────────────────

func _on_detection_body_entered(body: Node2D) -> void:
	if not is_valid_target(body):
		return
	if not _candidates.has(body):
		_candidates.append(body)
	# В режиме паузы: вступаем в бой только если враг подошёл к нам
	if _wave_mode == "slack" and not _finishing_fight:
		_begin_active()
	# Немедленно пересчитать приоритет цели
	_priority_timer = 0.0

func _on_detection_body_exited(body: Node2D) -> void:
	_candidates.erase(body)
	# Если наша текущая цель вышла из зоны обнаружения, попробовать выбрать новую
	if body == target:
		target = null
		_priority_timer = 0.0

# ── Помощники для работы с фракциями ──────────────────────────────────────────

## Возвращает true, если `other` — допустимая вражеская цель для этого юнита.
func is_valid_target(other: Node) -> bool:
	if not is_instance_valid(other):
		return false
	if other is BaseEntity:
		return (other as BaseEntity).faction != faction
	if other.is_in_group("enemy_castle") and faction == Faction.PLAYER:
		return true
	if other.is_in_group("player_castle") and faction == Faction.ENEMY:
		return true
	return false

## Возвращает true, если `node` — вражеский замок (основная цель).
func _is_castle(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	return (faction == Faction.ENEMY and node.is_in_group("player_castle")) \t    or (faction == Faction.PLAYER and node.is_in_group("enemy_castle"))

# ── Выбор цели ────────────────────────────────────────────────────────────

## Пересчитать цель из списка _candidates + вражеский замок.
## Вызывается каждые priority_interval секунд и при событиях обнаружения.
func _pick_best_target() -> void:
	var best: Node2D    = null
	var best_prio: int  = TargetPriority.LOW
	var best_d_sq: float = INF

	# Очистить устаревшие ссылки (удалённые объекты, которые пропустили body_exited)
	_candidates = _candidates.filter(func(c): return is_instance_valid(c))

	# ── Кандидаты из зоны обнаружения (вражеские юниты в радиусе) ──
	# Приоритет CRITICAL = юнит в радиусе ближнего боя (атаковать немедленно)
	# Приоритет HIGH = юнит обнаружен, но ещё не в радиусе атаки (атаковать перед походом к замку)
	for candidate: Node2D in _candidates:
		if not is_instance_valid(candidate):
			continue
		var d_sq := global_position.distance_squared_to(candidate.global_position)
		var prio := TargetPriority.CRITICAL if d_sq <= attack_range * attack_range else TargetPriority.HIGH
		if prio > best_prio or (prio == best_prio and d_sq < best_d_sq):
			best = candidate
			best_prio = prio
			best_d_sq = d_sq

	# ── Вражеский замок — средний приоритет (идти сюда, если рядом нет врагов) ──
	# Приоритет MEDIUM: выше патрулирования (нет цели), но ниже любого обнаруженного юнита (HIGH/CRITICAL)
	var castle_group := "player_castle" if faction == Faction.ENEMY else "enemy_castle"
	for castle: Node in get_tree().get_nodes_in_group(castle_group):
		if not is_instance_valid(castle):
			continue
		var d_sq := global_position.distance_squared_to((castle as Node2D).global_position)
		if TargetPriority.MEDIUM > best_prio or (TargetPriority.MEDIUM == best_prio and d_sq < best_d_sq):
			best = castle as Node2D
			best_prio = TargetPriority.MEDIUM
			best_d_sq = d_sq

	target = best

# ── Физический процесс (обновление каждый кадр физики) ──────────────────────────

func _physics_process(delta: float) -> void:
	if state == State.DEATH:
		velocity = Vector2.ZERO
		return

	if _attack_timer > 0.0:  _attack_timer -= delta
	if _search_timer > 0.0:  _search_timer -= delta

	# Периодическая переоценка приоритета цели
	_priority_timer -= delta
	if _priority_timer <= 0.0:
		_priority_timer = priority_interval
		_pick_best_target()

	# Кэшировать расстояние до текущей цели
	var dist_sq := global_position.distance_squared_to(target.global_position) if is_instance_valid(target) else INF

	match state:
		State.IDLE:
			velocity = Vector2.ZERO
			if is_instance_valid(target):
				last_known_pos = target.global_position
				_change_state(State.CHASE)

		State.PATROL:
			# In slack mode, stay on patrol and don't react to targets
			if _wave_mode == "attack" and is_instance_valid(target):
				last_known_pos = target.global_position
				_change_state(State.CHASE)
			elif global_position.distance_squared_to(patrol_target) < 64.0:
				velocity = Vector2.ZERO
				_change_state(State.IDLE)
			else:
				var dir := global_position.direction_to(patrol_target)
				# Apply separation during patrol
				if separation_weight > 0.0:
					var sep_dir := _compute_separation()
					if sep_dir.length_squared() > 0.01:
						dir = (dir + sep_dir * separation_weight).normalized()
				velocity = dir * (speed * 0.4)
				_face(dir.x < 0)

		State.CHASE:
			if is_instance_valid(target):
				last_known_pos = target.global_position
				# Castles are Area2D — units get blocked by castle walls before
				# reaching the center. Minimum distance = wall_half_width + body_radius ≈ 158px.
				# Multiplier 4.0 → 200px (safely > 158px for attack_range ≥ 40).
				var effective_attack_sq := attack_range * attack_range
				if _is_castle(target):
					effective_attack_sq = attack_range * 4.0 * (attack_range * 4.0)
				if dist_sq <= effective_attack_sq:
					if _attack_timer <= 0.0:
						_change_state(State.ATTACK)
					else:
						# In attack-cooldown range: hold position so navmesh
						# doesn’t route the unit away from the castle.
						velocity = Vector2.ZERO
						_face(global_position.x > target.global_position.x)
				else:
					var nav_dest := target.global_position
					if _is_castle(target):
						# Castle wall is ~143px from center, body radius ~15px → stop at ~158px.
						# Navigate to 175px from center (outside the wall) so the path is reachable.
						var to_castle := global_position.direction_to(target.global_position)
						nav_dest = target.global_position - to_castle * (attack_range * 3.5)
					_move_via_nav(nav_dest)
			else:
				_search_timer = search_timeout
				_change_state(State.SEARCH)

		State.SEARCH:
			if is_instance_valid(target):
				last_known_pos = target.global_position
				_change_state(State.CHASE)
			elif global_position.distance_squared_to(last_known_pos) < 256.0:
				velocity = Vector2.ZERO
				if _search_timer <= 0.0:
					_pick_patrol_target()
					_change_state(State.PATROL)
			else:
				_move_via_nav(last_known_pos)

		State.ATTACK:
			velocity = Vector2.ZERO
			if is_instance_valid(target):
				last_known_pos = target.global_position
				_face(global_position.x > target.global_position.x)
			# Target moved out of extended attack range → chase again
			var exit_range_sq := attack_range * attack_range * 4.0
			if _is_castle(target):
				exit_range_sq = attack_range * 6.0 * (attack_range * 6.0)
			if dist_sq > exit_range_sq:
				_change_state(State.CHASE)

	_move_and_slide_with_wall_handling()
	queue_redraw()

# ── Управление состояниями ──────────────────────────────────────────────────────────

func _change_state(new_state: State) -> void:
	if new_state == state:
		return
	# Clean up outgoing state
	if state == State.ATTACK:
		_can_attack = false
		attack_area.monitoring = false
	state = new_state
	match new_state:
		State.IDLE:
			animated_sprite.play("idle")
		State.PATROL, State.CHASE, State.SEARCH:
			animated_sprite.play("move")
		State.ATTACK:
			var tp := target.global_position if is_instance_valid(target) else last_known_pos
			_face(global_position.x > tp.x)
			animated_sprite.play("attack1")
			_start_attack_swing()
		State.DEATH:
			animated_sprite.modulate = Color.WHITE
			animated_sprite.play("death")

func _begin_active() -> void:
	## Переход из бездействия/удержания в активный бой.
	_finishing_fight = false
	_pick_best_target()
	if is_instance_valid(target):
		_change_state(State.CHASE)
	else:
		_pick_patrol_target()
		_change_state(State.PATROL)

func _hold_position() -> void:
	## Войти в пассивное удержание (режим паузы, нет врагов рядом).
	target = null
	_finishing_fight = false
	_change_state(State.IDLE)

func _pick_patrol_target() -> void:
	var angle := randf_range(0.0, TAU)
	patrol_target = spawn_position + Vector2(cos(angle), sin(angle)) * randf_range(20.0, patrol_radius)

# ── Бой ────────────────────────────────────────────────────────────────────

func _start_attack_swing() -> void:
	_can_attack = true
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(self):
		return
	if not (_can_attack and state == State.ATTACK):
		return
	attack_area.monitoring = true
	# Wait one physics frame so Godot processes overlaps and fires body/area_entered signals.
	await get_tree().physics_frame
	if not is_instance_valid(self) or not (_can_attack and state == State.ATTACK):
		return
	# Fallback: directly damage current target if it wasn't caught by signals.
	# Uses a generous range for castles (blocked by walls, far from center).
	if is_instance_valid(target) and target.has_method("take_damage"):
		var max_range := attack_range * 4.0 if _is_castle(target) else attack_range * 1.5
		if global_position.distance_to(target.global_position) <= max_range:
			if _is_castle(target):
				target.call("take_damage", attack_damage)
			else:
				var kdir := global_position.direction_to(target.global_position)
				target.call("take_damage", attack_damage, kdir * 100.0)

func _on_animation_finished() -> void:
	if state != State.ATTACK:
		return
	_can_attack = false
	attack_area.monitoring = false
	_attack_timer = attack_cooldown

	# Slack: if we were finishing a fight, now hold
	if _wave_mode == "slack" and _finishing_fight:
		_hold_position()
		return

	var stay_range := attack_range * 4.0 if _is_castle(target) else attack_range * 1.2
	if is_instance_valid(target) and \
		   global_position.distance_to(target.global_position) <= stay_range:
		_change_state(State.CHASE)
	else:
		_search_timer = search_timeout
		_change_state(State.SEARCH)

# Melee hit box callbacks — instant damage on overlap
func _on_attack_body_entered(body: Node) -> void:
	if _can_attack and state == State.ATTACK and is_valid_target(body) and body.has_method("take_damage"):
		var kdir := global_position.direction_to((body as Node2D).global_position)
		body.call("take_damage", attack_damage, kdir * 100.0)

func _on_attack_area_entered(area: Node) -> void:
	if _can_attack and state == State.ATTACK and is_valid_target(area) and area.has_method("take_damage"):
		area.call("take_damage", attack_damage)

# ── Навигация ────────────────────────────────────────────────────────────────

func _move_via_nav(dest: Vector2) -> void:
	var dir := Vector2.ZERO
	if nav_agent:
		# Only recalculate path when destination moved more than 8 px — avoids per-frame thrash
		if dest.distance_squared_to(_nav_last_dest) > 64.0:
			_nav_last_dest = dest
			nav_agent.target_position = dest
		if not nav_agent.is_navigation_finished():
			var next := nav_agent.get_next_path_position()
			if global_position.distance_squared_to(next) > 1.0:
				dir = global_position.direction_to(next)
	if dir == Vector2.ZERO and global_position.distance_squared_to(dest) > 100.0:
		dir = global_position.direction_to(dest)
	
	# Apply separation behavior to avoid stacking with friendly units
	if separation_weight > 0.0:
		var sep_dir := _compute_separation()
		if sep_dir.length_squared() > 0.01:
			dir = (dir + sep_dir * separation_weight).normalized()
	
	# Apply approach speed factor for distant targets (prevents clumping)
	var current_speed := speed
	if approach_speed_factor != 1.0 and global_position.distance_to(dest) > attack_range * 2.0:
		current_speed *= approach_speed_factor
	
	velocity = dir * current_speed
	_face(dir.x < 0)
	# Stuck detection and recovery
	if dir != Vector2.ZERO:
		_stuck_timer -= get_physics_process_delta_time()
		if _stuck_timer <= 0.0:
			_stuck_timer = _STUCK_INTERVAL
			if global_position.distance_squared_to(_last_pos) < _STUCK_DIST_SQ:
				# Apply random jitter to escape stuck state
				var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * speed * 0.5
				velocity += jitter
				# Also try to recalculate path
				if nav_agent:
					nav_agent.target_position = dest
		_last_pos = global_position

## Вычислить направление разделения от ближайших дружественных юнитов
func _compute_separation() -> Vector2:
	var sep := Vector2.ZERO
	var count := 0
	var faction_group := "team_player" if faction == Faction.PLAYER else "team_enemy"
	for other: Node in get_tree().get_nodes_in_group(faction_group):
		if other == self or not is_instance_valid(other):
			continue
		var other_pos := (other as Node2D).global_position
		var dist_sq := global_position.distance_squared_to(other_pos)
		if dist_sq < separation_distance * separation_distance and dist_sq > 0.01:
			sep += (global_position - other_pos).normalized() / sqrt(dist_sq)
			count += 1
	if count > 0:
		sep /= float(count)
	return sep.normalized()

## Обработка движения со скольжением вдоль стен, чтобы не застревать на углах
func _move_and_slide_with_wall_handling() -> void:
	move_and_slide()
	# Отталкиваем скорость от нормалей столкновений, чтобы юниты скользили вдоль стен
	# вместо того чтобы останавливаться и застревать
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var normal := col.get_normal()
		var into_wall := velocity.dot(-normal)
		if into_wall > 0.0:
			velocity += normal * into_wall

# ── Помощники ───────────────────────────────────────────────────────────────────

func _face(left: bool) -> void:
	if animated_sprite:
		animated_sprite.flip_h = left
	if attack_area:
		attack_area.position.x = abs(attack_area.position.x) * (-1.0 if left else 1.0)

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if state == State.DEATH or not health_component:
		return
	DamageFeedback.apply_damage_with_feedback(
		self, health_component, amount, knockback, HIT_EFFECT, animated_sprite, global_position)

func _on_death() -> void:
	_can_attack = false
	attack_area.monitoring = false
	if detection_area:
		detection_area.monitoring = false
	_change_state(State.DEATH)
	set_collision_layer_value(2, false)
	set_collision_layer_value(3, false)
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, false)
	set_collision_mask_value(3, false)
	if animated_sprite:
		await animated_sprite.animation_finished
	if is_instance_valid(self):
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.5)
		await tw.finished
		queue_free()

# ── Отладочная отрисовка ────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not OS.is_debug_build():
		return
	var c := Color.GREEN if faction == Faction.PLAYER else Color.RED
	# Detection radius
	draw_arc(Vector2.ZERO, detection_range, 0.0, TAU, 48, c.darkened(0.2), 1.0)
	# Attack radius
	draw_arc(Vector2.ZERO, attack_range,    0.0, TAU, 32, c,               1.5)
	# Blue line to current target
	if is_instance_valid(target):
		draw_line(Vector2.ZERO, to_local(target.global_position), Color(0.2, 0.5, 1.0, 0.8), 1.0)
