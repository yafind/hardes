## BaseEntity.gd
## Abstract base for all faction-aware AI units (enemies & allies).
##
## Detection architecture — signal-driven, NOT per-frame polling:
##   • DetectionArea  (Area2D) — large circle, triggers body_entered/body_exited.
##     The node MUST exist in the scene as a child named "DetectionArea".
##   • Area2D         (Area2D) — small melee zone, used for actual hit detection.
##
## Collision layer convention (configure in Inspector or via code):
##   Layer 1 (bit 0) = 1   → Player (hero, user-controlled)
##   Layer 2 (bit 1) = 2   → Player-faction AI units (knights, allies)
##   Layer 3 (bit 2) = 4   → Enemy-faction AI units
##   Layer 5 (bit 4) = 16  → Buildings / Castles (Area2D, no physics body)
##   Layer 6 (bit 5) = 32  → Static walls / castle solid bodies
##
## DetectionArea collision_mask should see the OPPOSING faction:
##   Enemy unit DetectionArea mask  = 3   (layers 1+2  = player hero + player knights)
##   Ally  unit DetectionArea mask  = 4   (layer  3    = enemy units)
##   (castles are always known and don't need detection — found by group query)
##
## Wave modes:
##   "attack" → normal AI behavior
##   "slack"  → unit pauses. Resumes ONLY if an enemy enters DetectionArea
##              OR WaveManager switches back to "attack".
extends CharacterBody2D
class_name BaseEntity

enum Faction { PLAYER, ENEMY }

# ── Exports ───────────────────────────────────────────────────────────────────
@export var faction: Faction = Faction.PLAYER
@export var detection_range: float = 260.0  ## radius of DetectionArea (set shape in scene)
@export var attack_range:    float = 55.0
@export var speed:           float = 80.0
@export var attack_damage:   int   = 12
@export var attack_cooldown: float = 1.0
@export var patrol_radius:   float = 70.0
@export var search_timeout:  float = 3.0
## How often target priority is re-evaluated (seconds). Min 0.3.
@export var priority_interval: float = 0.3

# ── State ─────────────────────────────────────────────────────────────────────
enum State { IDLE, PATROL, CHASE, SEARCH, ATTACK, DEATH }
var state: State = State.IDLE

var target:              Node2D  = null
var spawn_position:      Vector2 = Vector2.ZERO
var patrol_target:       Vector2 = Vector2.ZERO
var last_known_pos:      Vector2 = Vector2.ZERO
var _can_attack:         bool    = false
var _attack_timer:       float   = 0.0
var _search_timer:       float   = 0.0
var _priority_timer:     float   = 0.0
var _stuck_timer:        float   = 0.0
var _last_pos:           Vector2 = Vector2.ZERO
var _wave_mode:          String  = "attack"
var _finishing_fight:    bool    = false

# Candidates that entered the DetectionArea — used for priority picking.
# Cleared on body_exited. Castle is always included via group query (no range limit).
var _candidates: Array[Node2D] = []

const _STUCK_INTERVAL: float = 0.5
const _STUCK_DIST_SQ:  float = 4.0

const HIT_EFFECT := preload("res://components/hit_effect.tscn")

@onready var animated_sprite: AnimatedSprite2D  = $AnimatedSprite2D
@onready var health_component: Node              = $HealthComponent
@onready var attack_area:      Area2D            = $Area2D
@onready var nav_agent:        NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null
var detection_area: Area2D = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	spawn_position = global_position
	_last_pos      = global_position

	# Detection area (optional — human-controlled units may not have one)
	detection_area = get_node_or_null("DetectionArea")

	# Health
	if health_component and health_component.has_signal("died"):
		health_component.died.connect(_on_death)

	# Animation
	animated_sprite.animation_finished.connect(_on_animation_finished)

	# Attack area (melee hit zone) — disabled until swing
	attack_area.monitoring = false
	attack_area.body_entered.connect(_on_attack_body_entered)
	attack_area.area_entered.connect(_on_attack_area_entered)

	# Detection area — always monitoring; signals populate _candidates
	if detection_area:
		detection_area.monitoring  = true
		detection_area.monitorable = false  # other units don't need to detect this sensor
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)

	if nav_agent:
		nav_agent.path_max_distance = 40.0
		nav_agent.avoidance_enabled = true
		nav_agent.radius = 18.0
	_pick_patrol_target()

	# Subscribe to WaveManager
	await get_tree().process_frame
	_connect_wave_manager()

	# Start in correct state for current wave mode
	if _wave_mode == "attack":
		_begin_active()
	else:
		_change_state(State.IDLE)

# ── Wave manager ──────────────────────────────────────────────────────────────

func _connect_wave_manager() -> void:
	var wm := _get_wave_manager()
	if wm == null:
		return
	_wave_mode = wm.get_mode() if wm.has_method("get_mode") else "attack"
	if not wm.mode_changed.is_connected(_on_wave_mode_changed):
		wm.mode_changed.connect(_on_wave_mode_changed)

func _get_wave_manager() -> Node:
	var list := get_tree().get_nodes_in_group("wave_manager")
	return list[0] if list.size() > 0 else null

func _on_wave_mode_changed(new_mode: String) -> void:
	_wave_mode = new_mode
	if new_mode == "slack":
		# Finish current engagement, then hold
		if state == State.ATTACK or state == State.CHASE:
			_finishing_fight = true
		else:
			_hold_position()
	else:
		# Resume attack
		_finishing_fight = false
		_begin_active()

# ── Detection signals (the core of the signal-driven approach) ────────────────

func _on_detection_body_entered(body: Node2D) -> void:
	if not is_valid_target(body):
		return
	if not _candidates.has(body):
		_candidates.append(body)
	# In slack mode: only engage if an enemy walked up to us
	if _wave_mode == "slack" and not _finishing_fight:
		_begin_active()
	# Immediately re-evaluate priority
	_priority_timer = 0.0

func _on_detection_body_exited(body: Node2D) -> void:
	_candidates.erase(body)
	# If our current target left detection range, try to re-pick
	if body == target:
		target = null
		_priority_timer = 0.0

# ── Faction helpers ───────────────────────────────────────────────────────────

## True when `other` is a valid hostile target for this unit.
func is_valid_target(other: Node) -> bool:
	if not is_instance_valid(other):
		return false
	if other is BaseEntity:
		return (other as BaseEntity).faction != faction
	if other.is_in_group("enemy_castle") and faction == Faction.PLAYER:
		return true
	if other.is_in_group("player_castle") and faction == Faction.ENEMY:
		return true
	return false

## True when `node` is the opposing primary castle objective.
func _is_castle(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	return (faction == Faction.ENEMY and node.is_in_group("player_castle")) 	    or (faction == Faction.PLAYER and node.is_in_group("enemy_castle"))

# ── Target picking ────────────────────────────────────────────────────────────

## Re-evaluate target from _candidates + opposing castle.
## Called every priority_interval seconds, and on detection events.
func _pick_best_target() -> void:
	var best: Node2D    = null
	var best_prio: int  = -1
	var best_d_sq: float = INF

	# Purge stale references (freed bodies that missed body_exited)
	_candidates = _candidates.filter(func(c): return is_instance_valid(c))

	# ── Candidates from DetectionArea (enemy units in range) ──
	# Priority 200 = unit within melee range (fight it immediately)
	# Priority  80 = unit detected but not yet in melee range (fight before marching to castle)
	for candidate: Node2D in _candidates:
		if not is_instance_valid(candidate):
			continue
		var d_sq := global_position.distance_squared_to(candidate.global_position)
		var prio := 200 if d_sq <= attack_range * attack_range else 80
		if prio > best_prio or (prio == best_prio and d_sq < best_d_sq):
			best = candidate
			best_prio = prio
			best_d_sq = d_sq

	# ── Opposing castle — mid priority (march here when no enemies nearby) ──
	# Priority 50: beats patrol (no target) but loses to any detected unit (80/200)
	var castle_group := "player_castle" if faction == Faction.ENEMY else "enemy_castle"
	for castle: Node in get_tree().get_nodes_in_group(castle_group):
		if not is_instance_valid(castle):
			continue
		var d_sq := global_position.distance_squared_to((castle as Node2D).global_position)
		if 50 > best_prio or (50 == best_prio and d_sq < best_d_sq):
			best = castle as Node2D
			best_prio = 50
			best_d_sq = d_sq

	target = best

# ── Physics process ───────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if state == State.DEATH:
		velocity = Vector2.ZERO
		return

	if _attack_timer > 0.0:  _attack_timer -= delta
	if _search_timer > 0.0:  _search_timer -= delta

	# Periodic priority re-evaluation
	_priority_timer -= delta
	if _priority_timer <= 0.0:
		_priority_timer = priority_interval
		_pick_best_target()

	# Cache distance to current target
	var dist_sq := global_position.distance_squared_to(target.global_position) 		if is_instance_valid(target) else INF

	match state:
		State.IDLE:
			velocity = Vector2.ZERO
			if is_instance_valid(target):
				last_known_pos = target.global_position
				_change_state(State.CHASE)

		State.PATROL:
			# In slack mode, stay on patrol and don't react to targets
			if _wave_mode == "attack" and is_instance_valid(target):
				last_known_pos = target.global_position
				_change_state(State.CHASE)
			elif global_position.distance_squared_to(patrol_target) < 64.0:
				velocity = Vector2.ZERO
				_change_state(State.IDLE)
			else:
				var dir := global_position.direction_to(patrol_target)
				velocity = dir * (speed * 0.4)
				_face(dir.x < 0)

		State.CHASE:
			if is_instance_valid(target):
				last_known_pos = target.global_position
				# Castles are Area2D — units get blocked by castle walls before reaching
				# the center, so use a larger attack threshold for buildings.
				var effective_attack_sq := attack_range * attack_range
				if _is_castle(target):
					effective_attack_sq = attack_range * 3.0 * (attack_range * 3.0)
				if dist_sq <= effective_attack_sq and _attack_timer <= 0.0:
					_change_state(State.ATTACK)
				else:
					_move_via_nav(target.global_position)
			else:
				_search_timer = search_timeout
				_change_state(State.SEARCH)

		State.SEARCH:
			if is_instance_valid(target):
				last_known_pos = target.global_position
				_change_state(State.CHASE)
			elif global_position.distance_squared_to(last_known_pos) < 256.0:
				velocity = Vector2.ZERO
				if _search_timer <= 0.0:
					_pick_patrol_target()
					_change_state(State.PATROL)
			else:
				_move_via_nav(last_known_pos)

		State.ATTACK:
			velocity = Vector2.ZERO
			if is_instance_valid(target):
				last_known_pos = target.global_position
				_face(global_position.x > target.global_position.x)
			# Target moved out of extended attack range → chase again
			var exit_range_sq := attack_range * attack_range * 4.0
			if _is_castle(target):
				exit_range_sq = attack_range * 6.0 * (attack_range * 6.0)
			if dist_sq > exit_range_sq:
				_change_state(State.CHASE)

	move_and_slide()
	queue_redraw()

# ── State management ──────────────────────────────────────────────────────────

func _change_state(new_state: State) -> void:
	if new_state == state:
		return
	# Clean up outgoing state
	if state == State.ATTACK:
		_can_attack = false
		attack_area.monitoring = false
	state = new_state
	match new_state:
		State.IDLE:
			animated_sprite.play("idle")
		State.PATROL, State.CHASE, State.SEARCH:
			animated_sprite.play("move")
		State.ATTACK:
			var tp := target.global_position if is_instance_valid(target) else last_known_pos
			_face(global_position.x > tp.x)
			animated_sprite.play("attack1")
			_start_attack_swing()
		State.DEATH:
			animated_sprite.modulate = Color.WHITE
			animated_sprite.play("death")

func _begin_active() -> void:
	## Transition from idle/hold into active combat logic.
	_finishing_fight = false
	_pick_best_target()
	if is_instance_valid(target):
		_change_state(State.CHASE)
	else:
		_pick_patrol_target()
		_change_state(State.PATROL)

func _hold_position() -> void:
	## Enter passive hold (slack mode, no enemy nearby).
	target = null
	_finishing_fight = false
	_change_state(State.IDLE)

func _pick_patrol_target() -> void:
	var angle := randf_range(0.0, TAU)
	patrol_target = spawn_position + Vector2(cos(angle), sin(angle)) * randf_range(20.0, patrol_radius)

# ── Combat ────────────────────────────────────────────────────────────────────

func _start_attack_swing() -> void:
	_can_attack = true
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(self):
		return
	if not (_can_attack and state == State.ATTACK):
		return
	attack_area.monitoring = true
	# Wait one physics frame so Godot processes overlaps and fires body/area_entered signals.
	await get_tree().physics_frame
	if not is_instance_valid(self) or not (_can_attack and state == State.ATTACK):
		return
	# Fallback: directly damage current target if it wasn't caught by signals.
	# Uses a generous range for castles (blocked by walls, far from center).
	if is_instance_valid(target) and target.has_method("take_damage"):
		var max_range := attack_range * 4.0 if _is_castle(target) else attack_range * 1.5
		if global_position.distance_to(target.global_position) <= max_range:
			var kdir := global_position.direction_to(target.global_position)
			target.call("take_damage", attack_damage, kdir * 100.0)

func _on_animation_finished() -> void:
	if state != State.ATTACK:
		return
	_can_attack = false
	attack_area.monitoring = false
	_attack_timer = attack_cooldown

	# Slack: if we were finishing a fight, now hold
	if _wave_mode == "slack" and _finishing_fight:
		_hold_position()
		return

	if is_instance_valid(target) and 	   global_position.distance_to(target.global_position) <= attack_range * 1.2:
		_change_state(State.CHASE)
	else:
		_search_timer = search_timeout
		_change_state(State.SEARCH)

# Melee hit box callbacks — instant damage on overlap
func _on_attack_body_entered(body: Node) -> void:
	if _can_attack and state == State.ATTACK and is_valid_target(body) and body.has_method("take_damage"):
		var kdir := global_position.direction_to((body as Node2D).global_position)
		body.call("take_damage", attack_damage, kdir * 100.0)

func _on_attack_area_entered(area: Node) -> void:
	if _can_attack and state == State.ATTACK and is_valid_target(area) and area.has_method("take_damage"):
		area.call("take_damage", attack_damage)

# ── Navigation ────────────────────────────────────────────────────────────────

func _move_via_nav(dest: Vector2) -> void:
	var dir := Vector2.ZERO
	if nav_agent:
		nav_agent.target_position = dest
		if not nav_agent.is_navigation_finished():
			var next := nav_agent.get_next_path_position()
			if global_position.distance_squared_to(next) > 1.0:
				dir = global_position.direction_to(next)
	if dir == Vector2.ZERO and global_position.distance_squared_to(dest) > 100.0:
		dir = global_position.direction_to(dest)
	velocity = dir * speed
	_face(dir.x < 0)
	# Stuck detection
	_stuck_timer -= get_physics_process_delta_time()
	if _stuck_timer <= 0.0:
		_stuck_timer = _STUCK_INTERVAL
		if global_position.distance_squared_to(_last_pos) < _STUCK_DIST_SQ and dir != Vector2.ZERO:
			velocity += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * speed
		_last_pos = global_position

# ── Helpers ───────────────────────────────────────────────────────────────────

func _face(left: bool) -> void:
	if animated_sprite:
		animated_sprite.flip_h = left
	if attack_area:
		attack_area.position.x = abs(attack_area.position.x) * (-1.0 if left else 1.0)

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if state == State.DEATH or not health_component:
		return
	DamageFeedback.apply_damage_with_feedback(
		self, health_component, amount, knockback, HIT_EFFECT, animated_sprite, global_position)

func _on_death() -> void:
	_can_attack = false
	attack_area.monitoring = false
	if detection_area:
		detection_area.monitoring = false
	_change_state(State.DEATH)
	set_collision_layer_value(2, false)
	set_collision_layer_value(3, false)
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, false)
	set_collision_mask_value(3, false)
	if animated_sprite:
		await animated_sprite.animation_finished
	if is_instance_valid(self):
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.5)
		await tw.finished
		queue_free()

# ── Debug draw ────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not OS.is_debug_build():
		return
	var c := Color.GREEN if faction == Faction.PLAYER else Color.RED
	# Detection radius
	draw_arc(Vector2.ZERO, detection_range, 0.0, TAU, 48, c.darkened(0.2), 1.0)
	# Attack radius
	draw_arc(Vector2.ZERO, attack_range,    0.0, TAU, 32, c,               1.5)
	# Blue line to current target
	if is_instance_valid(target):
		draw_line(Vector2.ZERO, to_local(target.global_position), Color(0.2, 0.5, 1.0, 0.8), 1.0)
