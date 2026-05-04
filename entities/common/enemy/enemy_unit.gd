## enemy.gd
## ENEMY-faction AI unit. Extends BaseEntity — all logic lives there.
## This file only sets the faction, groups, and collision layers.
##
## Collision layers for THIS node (CharacterBody2D):
##   Layer 3 = enemy units body
##   Mask  1 = player hero (for navigation avoidance)
##   Mask  2 = player-faction AI units
##   Mask  6 = static walls
##
## DetectionArea (child Area2D "DetectionArea"):
##   Layer: none (monitorable = false)
##   Mask 1 + 2 = sees player hero + player knights
##   Mask 5     = sees player castle (Area2D on layer 5)
##
## Attack Area2D (child Area2D "Area2D"):
##   Mask 1 + 2 + 5 = can hit player hero, knights, player castle
extends BaseEntity

func _ready() -> void:
	# ── Faction & groups ──────────────────────────────────────────────────────
	faction = BaseEntity.Faction.ENEMY
	add_to_group("enemies")
	add_to_group("team_enemy")

	# ── Collision layers ──────────────────────────────────────────────────────
	# Body: layer 3 (enemy units), mask: layers 1(player)+2(allies)+6(walls)
	# DetectionArea and Area2D masks are already set correctly in the .tscn.
	collision_layer = 4    # bit 2 = layer 3
	collision_mask  = 35   # 1 + 2 + 32  (bits 0,1,5)

	super._ready()
