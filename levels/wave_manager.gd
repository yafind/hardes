extends Node2D  # ← Можно оставить Node2D или сменить на Node

signal wave_started(wave_number: int)
signal wave_ended(wave_number: int)
signal mode_changed(new_mode: String)
signal timer_updated(time_remaining: float)

@export_group("Wave Settings")
@export var attack_duration: float = 60.0
@export var slack_duration: float = 60.0
@export var total_waves: int = 10

var current_wave: int = 0
var time_remaining: float = 0.0
var current_mode: String = "attack"
var is_active: bool = false

func _ready():
	add_to_group("wave_manager")
	start_wave(1)

func _process(delta):
	if not is_active:
		return
	
	time_remaining -= delta
	timer_updated.emit(time_remaining)
	
	if time_remaining <= 0:
		_switch_mode()

func start_wave(wave_number: int):
	current_wave = wave_number
	current_mode = "attack"
	time_remaining = attack_duration
	is_active = true
	
	print("🌊 Волна %d началась! Режим: АТАКА" % current_wave)
	wave_started.emit(current_wave)
	mode_changed.emit(current_mode)

func end_wave():
	print("✅ Волна %d завершена!" % current_wave)
	wave_ended.emit(current_wave)

func _switch_mode():
	if current_mode == "attack":
		end_wave()
		current_mode = "slack"
		time_remaining = slack_duration
		
		print("😌 Затишье началось!")
		mode_changed.emit(current_mode)
		
		if current_wave >= total_waves:
			_game_won()
			return
	else:
		current_wave += 1
		start_wave(current_wave)

func _game_won():
	is_active = false
	print("🎉 ПОБЕДА!")

func get_wave_number() -> int:
	return current_wave

# ← Исправлено: корректное форматирование
func get_time_formatted() -> String:
	var mins: int = int(time_remaining / 60.0)
	var secs: int = int(time_remaining) % 60
	return "%02d:%02d" % [mins, secs]

func get_mode() -> String:
	return current_mode

func get_mode_color() -> Color:
	return Color.RED if current_mode == "attack" else Color.GREEN
