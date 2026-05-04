## enemy_archer.gd
## Лучник фракции ВРАГА. Наследуется от BaseEntity — вся логика там.
## Этот файл только устанавливает фракцию, группы и слои коллизий.
## Добавлена стрельба стрелами при атаке.
##
## Слои коллизий для этого узла (CharacterBody2D):
##   Слой 3 = юниты ИИ фракции врага
##   Маска 1 = герой игрока (избегание)
##   Маска 2 = юниты игрока
##   Маска 6 = статические стены
##
## DetectionArea:
##   Слой: нет
##   Маска 1 + 2 = видит героя игрока + юниты игрока
##   Маска 5     = видит замок игрока
##
## Attack Area2D:
##   Маска 1 + 2 + 5 = может попадать в героя игрока, юниты игрока, замок игрока
extends BaseEntity

@export var arrow_scene: PackedScene = preload("res://entities/common/player/skills/arrow.tscn")
@export var shoot_offset: Vector2 = Vector2(30, -10)  # Смещение точки вылета стрелы

func _ready() -> void:
	# ── Фракция и группы ──────────────────────────────────────────────────────
	faction = BaseEntity.Faction.ENEMY
	add_to_group("enemy_archers")
	add_to_group("team_enemy")

	# ── Слои коллизий ──────────────────────────────────────────────────────
	# Тело: слой 3 (юниты ИИ врага), маска: слои 1(игрок)+2(союзники игрока)+6(стены)
	collision_layer = 4    # бит 2 = слой 3
	collision_mask  = 35   # 1 + 2 + 32  (биты 0,1,5)

	super._ready()

# Переопределяем метод атаки для стрельбы стрелами вместо ближнего боя
func _start_attack_swing() -> void:
	_can_attack = true
	if not is_instance_valid(self):
		return
	if not (_can_attack and state == State.ATTACK):
		return
	
	# Воспроизводим анимацию стрельбы
	animated_sprite.play("shoot")
	
	# Ждём завершения анимации стрельбы
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
		get_tree().current_scene.add_child(arrow)
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
