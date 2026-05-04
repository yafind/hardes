extends HBoxContainer

@export var player: Player  # Типизировано для автодополнения

var slots: Array[Control] = []
var icons: Array[TextureRect] = []
var cooldown_overlays: Array[ColorRect] = []

func _ready():
	await get_tree().process_frame
	
	if not player:
		player = get_tree().get_first_node_in_group("player") as Player
	
	if player:
		_setup_slots()
		_connect_signals()
		# Инициализируем состояние при старте
		_update_all_overlays()

func _setup_slots():
	slots.clear()
	icons.clear()
	cooldown_overlays.clear()
	
	for child in get_children():
		if not (child is Control):
			continue
		
		slots.append(child)
		
		# Ищем или создаём иконку
		var icon_rect: TextureRect
		if child.has_node("Icon"):
			icon_rect = child.get_node("Icon") as TextureRect
		else:
			icon_rect = TextureRect.new()
			icon_rect.name = "Icon"
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			child.add_child(icon_rect)
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		
		icons.append(icon_rect)
		
		# Создаём overlay для кулдауна
		var overlay := ColorRect.new()
		overlay.name = "CooldownOverlay"
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		child.add_child(overlay)
		# Настройки оверлея (устанавливаются один раз)
		overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		overlay.position = Vector2.ZERO
		overlay.color = Color(0.1, 0.1, 0.4, 0.65)
		overlay.visible = false
		cooldown_overlays.append(overlay)
	
	# Загружаем иконки из player
	_load_skill_icons()

func _load_skill_icons():
	if not player:
		return
	for i in range(icons.size()):
		if i < player.skill_icons.size() and player.skill_icons[i]:
			icons[i].texture = player.skill_icons[i]

func _connect_signals():
	if player and player.has_signal("skill_cooldown_updated"):
		player.skill_cooldown_updated.connect(_on_cooldown_updated)

# Вспомогательная функция для инициализации всех оверлеев
func _update_all_overlays():
	if not player:
		return
	for i in 4:
		if i < cooldown_overlays.size():
			var is_active = player.is_skill_active(i)
			var current = player.get_skill_current_cooldown(i)
			_on_cooldown_updated(i, current, is_active)

func _on_cooldown_updated(skill_index: int, current_value: float, is_active_skill: bool):
	if skill_index >= cooldown_overlays.size() or not player:
		return

	var overlay = cooldown_overlays[skill_index]
	var slot = slots[skill_index]
	var slot_size = slot.size if slot.size.x > 0 and slot.size.y > 0 else Vector2(64, 64)
	var max_cd = player.get_skill_max_cooldown(skill_index)

	# === Пассивный навык (интервал) ===
	# Прогресс: 0 → навык только что сработал, 1 → готов к срабатыванию
	if not is_active_skill:
		var progress = current_value / max_cd if max_cd > 0 else 1.0
		
		if progress >= 1.0:
			overlay.visible = false
			return
		
		# Заполнение снизу вверх: высота = (1 - progress) * полная_высота
		overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		overlay.position = Vector2.ZERO
		overlay.size = Vector2(slot_size.x, slot_size.y * (1.0 - progress))
		overlay.color = Color(0.1, 0.1, 0.4, 0.65)
		overlay.visible = true
		return

	# === Активный навык (кулдаун) ===
	# current_value = оставшееся время, 0 = готов
	if current_value <= 0:
		overlay.visible = false
		return
	
	# Отменяем предыдущий твин, если он ещё работает
	if overlay.has_meta("tween"):
		var old_tween = overlay.get_meta("tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()
			overlay.remove_meta("tween")
	
	# Начальное состояние: оверлей закрывает весь слот
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.position = Vector2.ZERO
	overlay.size = slot_size
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.visible = true
	
	# Анимация: высота уменьшается от полной до 0 за время max_cd
	var tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	overlay.set_meta("tween", tween)
	tween.tween_property(overlay, "size:y", 0.0, max_cd)
	tween.tween_callback(func(): 
		if is_instance_valid(overlay):
			overlay.visible = false
			if overlay.has_meta("tween"):
				overlay.remove_meta("tween")
	)
