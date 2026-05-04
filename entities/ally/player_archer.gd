## player_archer.gd
## Лучник фракции ИГРОКА. Наследуется от BaseEntity — вся логика там.
## Этот файл только устанавливает фракцию, группы и слои коллизий.
## Добавлена стрельба стрелами при атаке.
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
