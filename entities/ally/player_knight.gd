## player_knight.gd
## PLAYER-faction AI ally spawned by Barracks. Extends BaseEntity.
##
## Collision layers for THIS node (CharacterBody2D):
##   Layer 2 = player-faction AI units
##   Mask  1 = player hero  (avoidance)
##   Mask  3 = enemy units
##   Mask  6 = static walls
##
## DetectionArea:
##   Layer: none
##   Mask 3 + 4(enemy_castle layer 5?) = sees enemy units + enemy castle
##   Mask  4 = enemy units (layer 3 = bit 2 = value 4)
##   Mask 16 = enemy castle (layer 5 = bit 4 = value 16)
##
## Attack Area2D:
##   Mask 4 + 16 = can hit enemy units + enemy castle
extends BaseEntity

func _ready() -> void:
	# ── Faction & groups ──────────────────────────────────────────────────────
	faction = BaseEntity.Faction.PLAYER
	add_to_group("player_knights")
	add_to_group("team_player")

	# ── Collision layers ──────────────────────────────────────────────────────
	# Body: layer 2 (player AI units), mask: layers 1(hero)+3(enemies)+6(walls)
	# DetectionArea and Area2D masks are already set correctly in the .tscn.
	collision_layer = 2    # bit 1 = layer 2
	collision_mask  = 37   # 1 + 4 + 32  (bits 0,2,5)

	super._ready()
