extends Control

@export var game_scene_path: String = "res://levels/game.tscn"

func _ready():
	$MarginContainer/VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)
	$MarginContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

func _on_play_pressed():
	print("Запуск игры...")
	get_tree().change_scene_to_file(game_scene_path)

# Функция нажатия на "ВЫХОД"
func _on_quit_pressed():
	print("Выход из игры...")
	get_tree().quit()
