extends HBoxContainer

@export var player: Player

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
		_update_all_overlays()

func _setup_slots():
	slots.clear()
	icons.clear()
	cooldown_overlays.clear()
	
	for child in get_children():
		if not (child is Control):
			continue
		slots.append(child)
		
		var icon_rect: TextureRect = child.get_node_or_null("Icon") as TextureRect
		if not icon_rect:
			icon_rect = TextureRect.new()
			icon_rect.name = "Icon"
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			child.add_child(icon_rect)
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icons.append(icon_rect)
		
		var overlay = ColorRect.new()
		overlay.name = "CooldownOverlay"
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		overlay.position = Vector2.ZERO
		overlay.color = Color(0.1, 0.1, 0.4, 0.65)
		overlay.visible = false
		child.add_child(overlay)
		cooldown_overlays.append(overlay)
	
	_load_skill_icons()

func _load_skill_icons():
	if not player:
		return
	for i in range(min(icons.size(), player.skill_icons.size())):
		if player.skill_icons[i]:
			icons[i].texture = player.skill_icons[i]

func _connect_signals():
	if player and player.has_signal("skill_cooldown_updated"):
		player.skill_cooldown_updated.connect(_on_cooldown_updated)

func _update_all_overlays():
	if not player:
		return
	for i in range(min(4, cooldown_overlays.size())):
		_on_cooldown_updated(i, player.get_skill_current_cooldown(i), player.is_skill_active(i))

func _on_cooldown_updated(skill_index: int, current_value: float, is_active_skill: bool):
	if skill_index >= cooldown_overlays.size() or not player:
		return

	var overlay = cooldown_overlays[skill_index]
	var slot = slots[skill_index]
	var slot_size = slot.size.clamp(Vector2(1, 1), Vector2(4096, 4096))
	var max_cd = player.get_skill_max_cooldown(skill_index)

	if not is_active_skill:
		var progress = clampf(current_value / max_cd, 0.0, 1.0) if max_cd > 0 else 1.0
		overlay.visible = progress < 1.0
		if overlay.visible:
			overlay.size = Vector2(slot_size.x, slot_size.y * (1.0 - progress))
		return

	if current_value <= 0:
		overlay.visible = false
		return

	if overlay.has_meta("tween"):
		var t = overlay.get_meta("tween")
		if t and t.is_valid():
			t.kill()
		overlay.remove_meta("tween")

	overlay.size = slot_size
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.visible = true
	
	var tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	overlay.set_meta("tween", tween)
	tween.tween_property(overlay, "size:y", 0.0, max_cd)
	tween.tween_callback(func():
		if is_instance_valid(overlay):
			overlay.visible = false
			overlay.remove_meta("tween")
	)
