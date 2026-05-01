extends Control

@onready var wave_label: Label = $MarginContainer/VBoxContainer/TopHBoxContainer/WavePanel/WaveLabel
@onready var mode_label: Label = $MarginContainer/VBoxContainer/ModePanel/ModeLabel
@onready var timer_label: Label = $MarginContainer/VBoxContainer/TopHBoxContainer/TimerPanel/TimerLabel
@onready var info_label: Label = $MarginContainer/VBoxContainer/InfoPanel/InfoLabel
@onready var wave_panel: Panel = $MarginContainer/VBoxContainer/TopHBoxContainer/WavePanel
@onready var timer_panel: Panel = $MarginContainer/VBoxContainer/TopHBoxContainer/TimerPanel
@onready var mode_panel: Panel = $MarginContainer/VBoxContainer/ModePanel
@onready var info_panel: Panel = $MarginContainer/VBoxContainer/InfoPanel

var wave_manager: Node

func _ready():
	await get_tree().process_frame
	
	wave_manager = get_node_or_null("../../WaveManager")
	
	if wave_manager:
		wave_manager.wave_started.connect(_on_wave_started)
		wave_manager.wave_ended.connect(_on_wave_ended)
		wave_manager.mode_changed.connect(_on_mode_changed)
		wave_manager.timer_updated.connect(_on_timer_updated)
		
		_update_ui()

func _update_ui():
	if not wave_manager:
		return
	
	wave_label.text = "WAVE: %d" % wave_manager.get_wave_number()
	# Используем публичную переменную напрямую
	timer_label.text = _format_time(wave_manager.time_remaining)
	mode_label.text = "MODE: " + wave_manager.get_mode().to_upper()
	
	var mode_color = wave_manager.get_mode_color()
	mode_label.add_theme_color_override("font_color", mode_color)
	
	if wave_manager.get_mode() == "attack":
		wave_panel.modulate = Color(1, 0.3, 0.3)
		timer_panel.modulate = Color(1, 0.3, 0.3)
		info_label.text = "⚔️ Враги атакуют!"
	else:
		wave_panel.modulate = Color(0.3, 1, 0.3)
		timer_panel.modulate = Color(0.3, 1, 0.3)
		info_label.text = " Затишье..."

func _on_wave_started(_wave_number: int):
	_update_ui()
	_flash_ui()

func _on_wave_ended(wave_number: int):
	info_label.text = "✅ Волна %d отбита!" % wave_number

func _on_mode_changed(_new_mode: String):
	_update_ui()

func _on_timer_updated(time_remaining: float):
	timer_label.text = _format_time(time_remaining)
	
	if time_remaining <= 10 and time_remaining > 0:
		timer_label.modulate = Color.RED if int(time_remaining * 10) % 2 == 0 else Color.WHITE
	else:
		timer_label.modulate = Color.WHITE

# ✅ ИСПРАВЛЕНО: Делим float на float (60.0), чтобы убрать warning
func _format_time(seconds: float) -> String:
	if seconds < 0:
		seconds = 0
	var mins: int = int(seconds / 60.0)
	var secs: int = int(seconds) % 60
	return "%02d:%02d" % [mins, secs]

func _flash_ui():
	var original_color = wave_panel.modulate
	var tween = create_tween()
	tween.tween_property(wave_panel, "modulate", Color.WHITE, 0.1)
	tween.tween_property(wave_panel, "modulate", original_color, 0.3)
