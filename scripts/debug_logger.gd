extends Node

## Скрипт для логирования ошибок отладки в файл
## Файл лога очищается при каждом запуске проекта

const LOG_FILE_PATH: String = "user://debug_errors.log"

var log_file: FileAccess


func _ready() -> void:
	# Очищаем старый лог и создаём новый при запуске
	_initialize_log_file()
	
	# Подключаемся к сигналам ошибок
	_connect_error_signals()
	
	print("[DebugLogger] Логирование ошибок запущено. Файл: ", LOG_FILE_PATH)


func _initialize_log_file() -> void:
	# Удаляем старый файл лога если он существует
	if FileAccess.file_exists(LOG_FILE_PATH):
		var err := DirAccess.remove_absolute(LOG_FILE_PATH)
		if err != OK:
			push_warning("[DebugLogger] Не удалось удалить старый файл лога: ", err)
	
	# Создаём новый файл лога с заголовком
	log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)
	if log_file == null:
		push_error("[DebugLogger] Не удалось создать файл лога! Ошибка: ", FileAccess.get_open_error())
		return
	
	# Записываем заголовок с датой запуска
	var timestamp := Time.get_datetime_string_from_system()
	log_file.store_line("=== Debug Log Started: %s ===" % timestamp)
	log_file.store_line("")
	log_file.flush()


func _connect_error_signals() -> void:
	# Подключаемся к сигналу печати ошибок
	EngineDebugger.register_message_capture("debug", _on_debug_message)


func _on_debug_message(message: String, data: Array) -> bool:
	# Логируем сообщения отладки
	_write_to_log("DEBUG: " + message)
	return false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			# Закрываем файл при выходе
			_close_log_file()


func _write_to_log(text: String) -> void:
	if log_file == null or log_file.is_closed():
		return
	
	# Добавляем временную метку
	var timestamp := Time.get_time_string_from_system()
	var log_entry := "[%s] %s" % [timestamp, text]
	
	log_file.store_line(log_entry)
	log_file.flush()
	
	# Также выводим в консоль для видимости во время разработки
	print(log_entry)


func _close_log_file() -> void:
	if log_file != null and not log_file.is_closed():
		log_file.close()
		print("[DebugLogger] Файл лога закрыт.")


## Вспомогательная функция для ручного логирования
func log_message(message: String) -> void:
	_write_to_log("CUSTOM: " + message)


## Вспомогательная функция для логирования ошибок
func log_error(error_message: String) -> void:
	_write_to_log("ERROR: " + error_message)


## Вспомогательная функция для логирования предупреждений
func log_warning(warning_message: String) -> void:
	_write_to_log("WARNING: " + warning_message)
