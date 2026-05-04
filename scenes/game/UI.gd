extends CanvasLayer

@onready var health_bar: TextureProgressBar = $HealthBarContainer/HealthBar/TextureProgressBar
@onready var health_text: Label = $HealthBarContainer/HealthBar/HealthText

func _ready():
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var hc = player.get_node("HealthComponent")
		hc.health_changed.connect(_on_health_changed)
		_on_health_changed(hc.current_health, hc.max_health)

func _on_health_changed(current: int, maximum: int):
	health_bar.max_value = maximum
	health_bar.value = current
	health_text.text = "%d / %d" % [current, maximum]
