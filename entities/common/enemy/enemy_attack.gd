extends Area2D

func _ready():
	monitoring = false
	monitorable = true

func enable_attack():
	monitoring = true

func disable_attack():
	monitoring = false
