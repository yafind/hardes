## Player.gd
## Класс игрока, управляемого пользователем. Наследуется от BaseEntity.
class_name Player
extends BaseEntity

enum PlayerState { IDLE, MOVE, SKILL_1, SKILL_2, DEATH }

@export var skill_1_damage: int = 10
@export var skill_2_damage_reduction: float = 0.2
@export var skill_3_damage: int = 5
@export var skill_4_damage: int = 15
@export var skill_1_cooldown: float = 1.0
@export var skill_2_cooldown: float = 3.0
@export var skill_3_interval: float = 2.0
@export var skill_3_radius: float = 100.0
@export var skill_4_interval: float = 1.5
@export var skill_4_range: float = 400.0
@export var combo_reset_time: float = 1.5
@export var skill_icons: Array[Texture2D] = []

const SKILL_3_SCENE = preload("res://entities/common/player/skills/fire_zone.tscn")
const SKILL_4_SCENE = preload("res://entities/common/player/skills/arrow.tscn")

var current_state: PlayerState = PlayerState.IDLE
var combo_counter: int = 0
var combo_timer: float = 0.0
var can_combo: bool = false
var _timer_skill3: float = 0.0
var _timer_skill4: float = 0.0
var skill_3_timer: float:
	get: return _timer_skill3
var skill_4_timer: float:
	get: return _timer_skill4
var cooldowns: Array[float] = [0.0, 0.0]
var skills_ready: Array[bool] = [true, true]
var _attack_damage: int = 0  # Текущий урон атаки

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health: HealthComponent = $HealthComponent

signal skill_cooldown_updated(idx: int, time: float, active: bool)

func _ready():
	speed = 200.0
	faction = BaseEntity.Faction.PLAYER
	add_to_group("player")
	add_to_group("team_player")
	health.died.connect(_on_death)
	
	# Подключаемся к сигналам Area2D
	attack_area.body_entered.connect(_on_attack_body_entered)
	attack_area.area_entered.connect(_on_attack_area_entered)

	# Изначально выключаем зону атаки
	attack_area.monitoring = false
	attack_area.monitorable = true

	# Wave manager subscription (skip full super._ready() — player is not AI-controlled)
	await get_tree().process_frame
	_connect_wave_manager()

	# Skill 4 detection zone — fires arrow when an enemy enters range
	var skill4_zone := Area2D.new()
	skill4_zone.name = "Skill4Zone"
	skill4_zone.collision_layer = 0
	skill4_zone.collision_mask = 4  # enemy bodies (layer 3 = bit 2 = value 4)
	skill4_zone.monitoring = true
	skill4_zone.monitorable = false
	var _cs4 := CollisionShape2D.new()
	var _shape4 := CircleShape2D.new()
	_shape4.radius = skill_4_range
	_cs4.shape = _shape4
	skill4_zone.add_child(_cs4)
	add_child(skill4_zone)
	skill4_zone.body_entered.connect(_on_skill4_body_entered)

func _physics_process(delta: float):
	if current_state == PlayerState.DEATH:
		return
	_update_systems(delta)
	var dir := _get_input_direction()
	_handle_state(dir)
	_move_with_sliding()

func _move_with_sliding():
	if current_state in [PlayerState.SKILL_1, PlayerState.SKILL_2]:
		velocity = velocity.move_toward(Vector2.ZERO, speed * 0.5)
		move_and_slide()
		return
	
	move_and_slide()
	
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var normal = collision.get_normal()
		
		if velocity.length() > 10:
			var into_wall = velocity.dot(normal)
			if into_wall < 0:
				velocity = velocity - normal * into_wall * wall_slide_factor
				velocity = velocity.lerp(Vector2.ZERO, 0.1)

func _get_input_direction() -> Vector2:
	return Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("down") - Input.get_action_strength("up")
	).normalized()

func _handle_state(dir: Vector2):
	match current_state:
		PlayerState.DEATH:
			return
		PlayerState.SKILL_1:
			velocity = Vector2.ZERO
			if not sprite.is_playing():
				change_player_state(PlayerState.IDLE)
		PlayerState.SKILL_2:
			velocity = Vector2.ZERO
			if not Input.is_action_pressed("skill_2"):
				change_player_state(PlayerState.IDLE)
		PlayerState.IDLE, PlayerState.MOVE:
			_process_movement(dir)

func _process_movement(dir: Vector2):
	if Input.is_action_just_pressed("skill_1") and skills_ready[0]:
		_use_skill_1()
	elif Input.is_action_pressed("skill_2") and skills_ready[1]:
		change_player_state(PlayerState.SKILL_2)
	elif dir:
		_face(dir.x < 0)
		velocity = velocity.lerp(dir * speed, 0.2)
		change_player_state(PlayerState.MOVE)
	else:
		velocity = velocity.lerp(Vector2.ZERO, 0.15)
		change_player_state(PlayerState.IDLE)

func _update_systems(delta):
	for i in 2:
		if not skills_ready[i]:
			cooldowns[i] -= delta
			if cooldowns[i] <= 0:
				_reset_cooldown(i)
	
	_timer_skill3 = _tick_passive(_timer_skill3, delta, skill_3_interval, _cast_skill_3)
	# Skill 4 cooldown: count up to interval; arrow fires via zone entry, not here
	if _timer_skill4 < skill_4_interval:
		_timer_skill4 += delta
	
	if can_combo:
		combo_timer -= delta
		if combo_timer <= 0:
			_reset_combo()
	
	skill_cooldown_updated.emit(0, cooldowns[0], true)
	skill_cooldown_updated.emit(1, cooldowns[1], true)
	skill_cooldown_updated.emit(2, skill_3_timer, false)
	skill_cooldown_updated.emit(3, skill_4_timer, false)

func _tick_passive(timer: float, delta: float, interval: float, callback: Callable) -> float:
	timer += delta
	if timer >= interval:
		callback.call()
		return 0.0
	return timer

func _use_skill_1():
	combo_counter = (combo_counter % 2) + 1
	combo_timer = combo_reset_time
	can_combo = true
	change_player_state(PlayerState.SKILL_1)
	sprite.play("attack%d" % combo_counter)
	_start_cooldown(0, skill_1_cooldown)
	_attack_melee(skill_1_damage)

func _activate_skill_2():
	_start_cooldown(1, skill_2_cooldown)

func _cast_skill_3():
	_spawn_projectile(SKILL_3_SCENE, {"damage": skill_3_damage, "radius": skill_3_radius})

func _cast_skill_4():
	# Legacy helper — use _on_skill4_body_entered for zone-triggered arrow.
	var skill_target := _find_priority_enemy()
	if skill_target:
		var dir := (skill_target.global_position - global_position).normalized()
		_spawn_projectile(SKILL_4_SCENE, {"direction": dir, "damage": skill_4_damage, "max_distance": skill_4_range, "target": skill_target})
		_timer_skill4 = 0.0

func _on_skill4_body_entered(body: Node) -> void:
	## Fires an arrow at `body` when it enters the skill-4 zone and the cooldown is ready.
	if _timer_skill4 < skill_4_interval:
		return
	if not is_valid_target(body):
		return
	var dir := ((body as Node2D).global_position - global_position).normalized()
	_spawn_projectile(SKILL_4_SCENE, {
		"direction": dir,
		"damage": skill_4_damage,
		"max_distance": skill_4_range,
		"target": body as Node2D
	})
	_timer_skill4 = 0.0

func _spawn_projectile(scene: PackedScene, props: Dictionary):
	if not scene:
		return
	var inst = scene.instantiate()
	for p in props:
		inst.set(p, props[p])
	var spawn_pos := global_position
	var parent := get_parent()
	if parent:
		# call_deferred avoids "can't change state while flushing queries"
		# when this is triggered from a physics callback (body_entered).
		parent.call_deferred("add_child", inst)
		inst.set_deferred("global_position", spawn_pos)

# ✅ Атака с использованием Area2D
func _attack_melee(dmg: int):
	_attack_damage = dmg
	
	# Поворачиваем зону атаки в нужную сторону
	var attack_shape = attack_area.get_node("attack") as CollisionShape2D
	if attack_shape:
		if sprite.flip_h:
			attack_shape.position.x = -abs(attack_shape.position.x)
		else:
			attack_shape.position.x = abs(attack_shape.position.x)
	
	# Включаем зону атаки на короткое время
	attack_area.monitoring = true
	await get_tree().create_timer(0.2).timeout  # Атака активна 0.2 секунды
	attack_area.monitoring = false

# ✅ Обработка столкновения с телами (враги)
func _on_attack_body_entered(body: Node):
	if is_valid_target(body) and body.has_method("take_damage"):
		body.take_damage(_attack_damage)
		_create_hit_effect((body as Node2D).global_position)

# ✅ Обработка столкновения с областями (замки)
func _on_attack_area_entered(area: Node):
	if is_valid_target(area) and area.has_method("take_damage"):
		area.take_damage(_attack_damage)
		_create_hit_effect((area as Node2D).global_position)

# ✅ Создание эффекта попадания
func _create_hit_effect(pos: Vector2):
	if HIT_EFFECT:
		var effect = HIT_EFFECT.instantiate()
		effect.global_position = pos
		var parent = get_parent()
		if parent:
			parent.add_child(effect)

func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var min_dist_sq: float = skill_4_range * skill_4_range
	for e: Node2D in get_tree().get_nodes_in_group("team_enemy"):
		if not is_instance_valid(e):
			continue
		# Prioritize enemies that are already engaged with allies or closest to castle
		var d_sq: float = global_position.distance_squared_to(e.global_position)
		if d_sq < min_dist_sq:
			min_dist_sq = d_sq
			nearest = e
	return nearest

## Find the most threatening enemy (closest to player castle or attacking ally)
func _find_priority_enemy() -> Node2D:
	var priority_target: Node2D = null
	var best_score: float = INF
	
	# Get player castle position as reference
	var castle := get_tree().get_first_node_in_group("player_castle") as Node2D
	var castle_pos := castle.global_position if castle else Vector2.ZERO
	
	for e: Node2D in get_tree().get_nodes_in_group("team_enemy"):
		if not is_instance_valid(e):
			continue
		
		var dist_to_castle := e.global_position.distance_to(castle_pos)
		var dist_to_player := e.global_position.distance_to(global_position)
		
		# Score: lower is better (closer to castle + closer to player = higher threat)
		var score := dist_to_castle * 0.6 + dist_to_player * 0.4
		
		if score < best_score:
			best_score = score
			priority_target = e
	
	return priority_target if priority_target else _find_nearest_enemy()

func _start_cooldown(idx: int, time: float):
	skills_ready[idx] = false
	cooldowns[idx] = time
	skill_cooldown_updated.emit(idx, time, true)

func _reset_cooldown(idx: int):
	skills_ready[idx] = true
	cooldowns[idx] = 0.0
	skill_cooldown_updated.emit(idx, 0.0, false)

func _face(left: bool):
	sprite.flip_h = left

func change_player_state(new: PlayerState):
	if new == current_state:
		return
	current_state = new
	match new:
		PlayerState.IDLE:
			sprite.play("idle")
		PlayerState.MOVE:
			sprite.play("move")
		PlayerState.SKILL_2:
			sprite.play("block")
			_activate_skill_2()
		PlayerState.DEATH:
			sprite.play("death")
			_reset_combo()

func _reset_combo():
	combo_counter = 0
	can_combo = false

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO):
	if current_state == PlayerState.DEATH:
		return
	if current_state == PlayerState.SKILL_2:
		amount = int(amount * skill_2_damage_reduction)
		knockback *= 0.5
	DamageFeedback.apply_damage_with_feedback(
		self, health, amount, knockback, HIT_EFFECT, sprite, global_position, true)

func _on_death():
	change_player_state(PlayerState.DEATH)
	set_collision_layer_value(1, false)
	set_collision_mask_value(2, false)
	await sprite.animation_finished
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	var castle = get_tree().get_first_node_in_group("player_castle") as PlayerCastle
	if castle and is_instance_valid(castle):
		castle.respawn_player(self)

func full_respawn_reset():
	modulate = Color.WHITE
	set_collision_layer_value(1, true)
	set_collision_mask_value(2, true)
	velocity = Vector2.ZERO
	health.respawn()
	combo_counter = 0
	can_combo = false
	skills_ready[0] = true
	skills_ready[1] = true
	cooldowns[0] = 0.0
	cooldowns[1] = 0.0
	_timer_skill3 = 0.0
	_timer_skill4 = 0.0
	change_player_state(PlayerState.IDLE)

func _draw():
	if not OS.is_debug_build() or current_state == PlayerState.DEATH:
		return
	draw_circle(Vector2.ZERO, skill_3_radius, Color(1, 0.35, 0, 0.12))
	draw_arc(Vector2.ZERO, skill_3_radius, 0, TAU, 64, Color(1, 0.45, 0, 0.6), 1.5)
	draw_arc(Vector2.ZERO, skill_4_range, 0, TAU, 128, Color(0.3, 0.75, 1, 0.45), 1.5)
	
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		if collision:
			var normal = collision.get_normal()
			draw_line(Vector2.ZERO, normal * 30, Color.YELLOW, 2)

func get_skill_max_cooldown(idx: int) -> float:
	match idx:
		0: return skill_1_cooldown
		1: return skill_2_cooldown
		2: return skill_3_interval
		3: return skill_4_interval
		_: return 1.0

func get_skill_current_cooldown(idx: int) -> float:
	if idx < 2:
		return cooldowns[idx] if idx < cooldowns.size() else 0.0
	elif idx == 2:
		return skill_3_timer
	elif idx == 3:
		return skill_4_timer
	return 0.0

func is_skill_ready(idx: int) -> bool:
	if idx < 2:
		return skills_ready[idx] if idx < skills_ready.size() else false
	elif idx == 2:
		return skill_3_timer >= skill_3_interval
	elif idx == 3:
		return skill_4_timer >= skill_4_interval
	return false

func is_skill_active(idx: int) -> bool:
	return idx < 2
