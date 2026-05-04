extends Area2D

# Зона атаки врага — используется для нанесения урона при атаке

func _ready():
	# Отключаем мониторинг при старте, включаем только во время атаки
	# Проверяем существование узла перед доступом к свойствам
	if not is_instance_valid(self):
		return
	monitoring = false
	monitorable = true  # Другие объекты могут обнаруживать эту зону

# Включить зону атаки (начало удара)
func enable_attack():
	if is_instance_valid(self):
		monitoring = true

# Выключить зону атаки (конец удара)
func disable_attack():
	if is_instance_valid(self):
		monitoring = false
