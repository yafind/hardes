## enemy_archer.gd
## ENEMY-faction AI archer unit. Extends BaseEntity — all logic lives there.
## This file only sets the faction, groups, and collision layers.
##
## Collision layers for THIS node (CharacterBody2D):
##   Layer 3 = enemy-faction AI units
##   Mask  1 = player hero  (avoidance)
##   Mask  2 = player units
##   Mask  6 = static walls
##
## DetectionArea:
##   Layer: none
##   Mask 1 + 2 = sees player hero + player units
##   Mask 5     = sees player castle
##
## Attack Area2D:
##   Mask 1 + 2 + 5 = can hit player hero, player units, player castle
extends BaseEntity

func _ready() -> void:
	# ── Faction & groups ──────────────────────────────────────────────────────
	faction = BaseEntity.Faction.ENEMY
	add_to_group("enemy_archers")
	add_to_group("team_enemy")

	# ── Collision layers ──────────────────────────────────────────────────────
	# Body: layer 3 (enemy AI units), mask: layers 1(player)+2(player allies)+6(walls)
	collision_layer = 4    # bit 2 = layer 3
	collision_mask  = 35   # 1 + 2 + 32  (bits 0,1,5)

	super._ready()
