extends CharacterBody3D
class_name EnemyAI
## Enemy: simple souls-like foe. State machine with idle/chase/windup/active/recover/stagger/dead.
## Respawns after death so the simulation can run indefinitely.

enum State { IDLE, CHASE, WINDUP, ACTIVE, RECOVER, STAGGER, DEAD }

@export_group("Stats")
@export var max_hp := 100.0
@export var move_speed := 2.6
@export var turn_speed := 6.0
@export var attack_damage := 22.0

@export_group("Ranges")
@export var detection_range := 12.0
@export var attack_range := 1.9
@export var lose_range := 18.0

@export_group("Attack Timings")
@export var windup_duration := 0.55
@export var active_duration := 0.18
@export var recover_duration := 0.75
@export var stagger_duration := 1.30
@export var respawn_delay := 2.0

# State
var state: State = State.IDLE
var hp: float
var state_timer := 0.0
var spawn_position: Vector3
var is_dying: bool = false

# Nodes
@onready var model: Node3D = $Model
@onready var mesh_instance: MeshInstance3D = $Model/Body
@onready var attack_area: Area3D = $AttackArea
@onready var hit_collision: CollisionShape3D = $AttackArea/CollisionShape3D
@onready var hitbox_debug: MeshInstance3D = $AttackArea/HitboxDebug
@onready var label_hp: Label3D = $Model/HP_Label
@onready var label_parry: Label3D = $Model/ParryLabel

@onready var player: Node3D = null

var base_color := Color(0.8, 0.15, 0.2)
var flash_color := Color(1.0, 0.5, 0.2)
var _base_mat: StandardMaterial3D
var _hitbox_mat: StandardMaterial3D
const HITBOX_WINDUP := Color(1.0, 0.7, 0.1, 0.4)   # yellow/orange telegraph
const HITBOX_ACTIVE := Color(1.0, 0.15, 0.1, 0.55)  # red active hit


func _ready() -> void:
	spawn_position = global_position
	hp = max_hp
	_base_mat = StandardMaterial3D.new()
	_base_mat.albedo_color = base_color
	mesh_instance.material_override = _base_mat
	# Script-managed hitbox material so we can change color per phase
	_hitbox_mat = StandardMaterial3D.new()
	_hitbox_mat.transparency = 1
	_hitbox_mat.shading_mode = 0
	_hitbox_mat.cull_mode = 2
	_hitbox_mat.albedo_color = HITBOX_WINDUP
	hitbox_debug.material_override = _hitbox_mat
	hitbox_debug.visible = false
	attack_area.monitoring = false
	attack_area.body_entered.connect(_on_attack_body)
	add_to_group("enemies")
	# Find player lazily (may not exist in editor preview)
	player = get_tree().root.find_child("Player", true, false)
	print("[enemy] %s ready hp=%.0f" % [name, hp])


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().root.find_child("Player", true, false)
		if player == null:
			return
	if state == State.DEAD:
		return

	state_timer -= delta

	match state:
		State.IDLE:
			_state_idle()
		State.CHASE:
			_state_chase(delta)
		State.WINDUP:
			_state_windup()
		State.ACTIVE:
			_state_active()
		State.RECOVER:
			_state_recover()
		State.STAGGER:
			_state_stagger()

	# Gravity
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y < 0:
		velocity.y = 0

	move_and_slide()
	_update_hp_label()

	# Kill plane: if we fall off the world, respawn
	if global_position.y < -10.0 and not is_dying:
		print("[enemy] %s fell off the world -> respawn" % name)
		_die()


func _state_idle() -> void:
	velocity.x *= 0.5
	velocity.z *= 0.5
	if _dist_to_player() < detection_range:
		_enter_chase()


func _state_chase(delta: float) -> void:
	var d := _dist_to_player()
	if d > lose_range:
		_enter_idle()
		return
	if d <= attack_range:
		_enter_windup()
		return
	# Move toward player
	var to := (player.global_position - global_position)
	to.y = 0
	if to.length() > 0.01:
		to = to.normalized()
		# Face player
		var target_yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)
		model.rotation.y = target_yaw - rotation.y
		velocity.x = to.x * move_speed
		velocity.z = to.z * move_speed


func _state_windup() -> void:
	# Telegraph: lean toward player + small jitter
	velocity.x *= 0.7
	velocity.z *= 0.7
	# Visual: scale model slightly
	model.scale = Vector3(1.0, 1.0 + 0.15 * (1.0 - state_timer / windup_duration), 1.0)
	if state_timer <= 0.0:
		_enter_active()


func _state_active() -> void:
	# Hitbox is on during ACTIVE
	velocity.x = 0
	velocity.z = 0
	if state_timer <= 0.0:
		_enter_recover()


func _state_recover() -> void:
	velocity.x *= 0.5
	velocity.z *= 0.5
	model.scale = Vector3.ONE
	if state_timer <= 0.0:
		if _dist_to_player() < attack_range * 1.3:
			_enter_windup()
		else:
			_enter_chase()


func _state_stagger() -> void:
	velocity.x *= 0.6
	velocity.z *= 0.6
	if state_timer <= 0.0:
		_enter_chase()


# --- State transitions ---

func _enter_idle() -> void:
	state = State.IDLE
	attack_area.monitoring = false
	hit_collision.disabled = true
	hitbox_debug.visible = false
	model.scale = Vector3.ONE


func _enter_chase() -> void:
	state = State.CHASE
	attack_area.monitoring = false
	hit_collision.disabled = true
	hitbox_debug.visible = false
	model.scale = Vector3.ONE


func _enter_windup() -> void:
	state = State.WINDUP
	state_timer = windup_duration
	attack_area.monitoring = false
	hit_collision.disabled = true
	# Telegraph: show yellow/orange hitbox so player can see WHERE the hit will land
	_hitbox_mat.albedo_color = HITBOX_WINDUP
	hitbox_debug.visible = true
	print("[enemy] %s attack_windup t=%.2f" % [name, windup_duration])


func _enter_active() -> void:
	state = State.ACTIVE
	state_timer = active_duration
	attack_area.monitoring = true
	hit_collision.disabled = false
	# Active: hitbox turns red and stays visible
	_hitbox_mat.albedo_color = HITBOX_ACTIVE
	hitbox_debug.visible = true
	print("[enemy] %s attack_ACTIVE dmg=%.1f" % [name, attack_damage])


func _enter_recover() -> void:
	state = State.RECOVER
	state_timer = recover_duration
	attack_area.monitoring = false
	hit_collision.disabled = true
	hitbox_debug.visible = false
	print("[enemy] %s attack_recover t=%.2f" % [name, recover_duration])


func _enter_stagger() -> void:
	state = State.STAGGER
	state_timer = stagger_duration
	attack_area.monitoring = false
	hit_collision.disabled = true
	hitbox_debug.visible = false
	model.scale = Vector3(1.0, 0.7, 1.0)
	_flash()
	print("[enemy] %s STAGGER t=%.2f" % [name, stagger_duration])


# --- Damage + parry interface ---

func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	_flash()
	print("[enemy] %s hit dmg=%.1f hp=%.1f state=%s" % [name, amount, hp, State.keys()[state]])
	# Light stagger on hit (less than full stagger from parry)
	if state == State.WINDUP or state == State.ACTIVE:
		_enter_stagger()
	if hp <= 0.0:
		_die()


func on_parried(source: Node) -> void:
	print("[enemy] %s PARRIED by %s -> stagger" % [name, source.name])
	_show_parry_label()
	_parry_punch()
	_enter_stagger()


func is_attack_active() -> bool:
	return state == State.ACTIVE


func is_attack_winding_up() -> bool:
	# More forgiving: also parryable during the windup telegraph (not just the active hit)
	return state == State.WINDUP


func _die() -> void:
	if is_dying:
		return
	is_dying = true
	state = State.DEAD
	hp = 0.0
	attack_area.monitoring = false
	hit_collision.disabled = true
	hitbox_debug.visible = false
	model.scale = Vector3.ONE
	model.visible = false
	collision_layer = 0
	collision_mask = 0
	print("[enemy] %s DEAD respawn in %.1fs" % [name, respawn_delay])
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	is_dying = false
	hp = max_hp
	global_position = spawn_position
	velocity = Vector3.ZERO
	model.visible = true
	collision_layer = 4
	collision_mask = 1 | 2
	_enter_idle()
	print("[enemy] %s RESPAWN hp=%.0f" % [name, hp])


# --- Internals ---

func _dist_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return INF
	return global_position.distance_to(player.global_position)


func _flash() -> void:
	_base_mat.albedo_color = flash_color
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self) and _base_mat:
		_base_mat.albedo_color = base_color


func _parry_punch() -> void:
	# Bright yellow body flash (more obvious than the default orange stagger flash)
	var parry_color := Color(1.0, 0.95, 0.2)  # hot yellow
	_base_mat.albedo_color = parry_color
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self) and _base_mat and state == State.STAGGER:
		_base_mat.albedo_color = base_color


func _show_parry_label() -> void:
	# Pop a big "PARRY!" label above the enemy for 0.5s
	label_parry.visible = true
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(self):
		label_parry.visible = false


func _update_hp_label() -> void:
	if is_instance_valid(label_hp):
		label_hp.text = "%d/%d" % [int(max(0, hp)), int(max_hp)]
		# Billboard the label toward the camera
		if is_instance_valid(get_viewport().get_camera_3d()):
			var cam := get_viewport().get_camera_3d()
			label_hp.look_at(cam.global_position, Vector3.UP)
			label_hp.rotate_object_local(Vector3.UP, PI)


func _on_attack_body(body: Node) -> void:
	if state != State.ACTIVE:
		return
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage(attack_damage, self)
		print("[enemy] %s hit_player body=%s dmg=%.1f" % [name, body.name, attack_damage])
