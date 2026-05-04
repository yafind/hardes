## game_utils.gd
## Static utility helpers shared across multiple scripts.
class_name GameUtils
extends RefCounted

## Returns the first WaveManager node registered in the "wave_manager" group,
## or null if none exists. Use in _ready() after process_frame to ensure the
## scene tree is fully populated.
static func get_wave_manager(tree: SceneTree) -> Node:
	var list := tree.get_nodes_in_group("wave_manager")
	return list[0] if list.size() > 0 else null
