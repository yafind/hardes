extends Area2D

## Урон от стрелы
@export var damage: int = 15
## Скорость полёта стрелы (пикселей в секунду)
@export var speed: float = 600.0
## Максимальная дистанция полёта перед исчезновением
@export var max_distance: float = 400.0
## Сила отбрасывания при попадании
@export var knockback_force: float = 50.0
## Сила самонаведения (0 = нет наведения, 1 = сильное наведение)
@export var homing_strength: float = 0.15
## Максимальный угол поворота в секунду (градусы)
@export var homing_max_angle: float = 45.0

## Направление полёта стрелы (нормализованный вектор)
var direction: Vector2 = Vector2.RIGHT
## Пройденное расстояние
var travel_distance: float = 0.0
## Цель для самонаведения (опционально)
var target: Node2D = null

@onready var sprite: Sprite2D = $ArrowSprite

func _ready():
	# Поворачиваем стрелу по направлению полёта
	if direction.length() > 0.01:
		rotation = direction.angle()
	body_entered.connect(_on_body_entered)

# _physics_process: выполняется с фиксированной частотой физики (60 Гц)
# вместо частоты отображения (144+ Гц). Устраняет лишние тики на быстрых мониторах.
func _physics_process(delta: float) -> void:
	# Применяем самонаведение, если цель задана и существует
	if target and is_instance_valid(target):
		var to_target := (target.global_position - global_position).normalized()
		if to_target.length() > 0.01:
			# Вычисляем угол между текущим направлением и направлением на цель
			var current_angle := direction.angle()
			var target_angle := to_target.angle()
			var angle_diff := wrapf(target_angle - current_angle, -PI, PI)
			
			# Ограничиваем скорость поворота
			var max_turn := deg_to_rad(homing_max_angle) * delta
			angle_diff = clampf(angle_diff, -max_turn, max_turn)
			
			# Смешиваем с силой самонаведения
			var new_angle := current_angle + angle_diff * homing_strength
			direction = Vector2(cos(new_angle), sin(new_angle))
			rotation = new_angle
	
	# Двигаем стрелу вперёд
	position += direction * speed * delta
	# direction нормализован → ||direction * speed * delta|| == speed * delta точно.
	# Заменяем movement.length(), который вызывал sqrt() каждый кадр отображения.
	travel_distance += speed * delta
	if travel_distance >= max_distance:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Пропускаем дружественную фракцию (юниты игрока и союзные рыцари)
	if body.is_in_group("player") or body.is_in_group("team_player"):
		return
	
	# Наносим урон вражеским юнитам
	if body.is_in_group("team_enemy") and body.has_method("take_damage"):
		body.take_damage(damage, direction * knockback_force)
		queue_free()
		return
	
	# Наносим урон замкам (Area2D без take_damage, но с HealthComponent)
	if body.is_in_group("enemy_castle") or body.is_in_group("player_castle"):
		if body.has_node("HealthComponent"):
			var health = body.get_node("HealthComponent")
			if health.has_method("apply_damage"):
				health.apply_damage(damage)
				queue_free()
				return
		# Если у замка есть метод take_damage напрямую
		if body.has_method("take_damage"):
			body.take_damage(damage, Vector2.ZERO)
			queue_free()
