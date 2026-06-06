extends CharacterBody3D
## Player controller: 3rd person, souls-like.
##
## Controles:
##   WASD      -> mover (W = adelante, en la dirección que mira la cámara)
##   Shift     -> sprint (gasta stamina)
##   Space     -> saltar
##   Ctrl      -> esquivar (dodge, gasta stamina, i-frames)
##   LMB       -> atacar (gasta stamina, 1 ataque base)
##   RMB       -> bloquear (mantener, gasta stamina, reduce daño)
##   F         -> parry (tap, ventana 0.4s, staggerea al enemigo si ataca)
##   T         -> cast_skill_1 (skill data-driven en slot 0)
##   G         -> cast_skill_2 (skill data-driven en slot 1)
##   H         -> cast_skill_3 (skill data-driven en slot 2)
##   Tab       -> abrir skill allocator UI
##   Mouse     -> mirar (yaw del cuerpo, pitch de la cámara)
##   Esc       -> liberar/atrapar mouse

const SkillResource := preload("res://scripts/skill/skill_resource.gd")
const SkillExecutorScript := preload("res://scripts/skill/skill_executor.gd")

# --- Signals for external observability (HUD, bot, sim logger) ---
signal parry_succeeded(enemy: Node)
signal attack_hit(target: Node, damage: float)
signal damaged(amount: float, final_amount: float, blocked: bool)
signal died
signal respawned

# --- Tunables ---
@export_group("Movement")
@export var move_speed := 4.0
@export var sprint_speed := 6.5
@export var acceleration := 18.0
@export var rotation_lerp := 12.0
@export var jump_velocity := 6.5
@export var gravity := 22.0

@export_group("Camera")
@export var mouse_sensitivity := 0.0025
@export var gamepad_look_sensitivity := 3.0
@export var gamepad_deadzone := 0.15
@export var min_pitch := -1.4
@export var max_pitch := 1.2

@export_group("Stamina")
@export var max_stamina := 100.0
@export var stamina_regen := 18.0
@export var stamina_regen_delay := 0.8
@export var stamina_drain_attack := 22.0
@export var stamina_drain_dodge := 28.0
@export var stamina_drain_block := 18.0
@export var stamina_drain_parry := 18.0

@export_group("Combat")
@export var attack_windup := 0.12
@export var attack_active := 0.10
@export var attack_recovery := 0.18
@export var attack_damage := 28.0
@export var dodge_distance := 4.5
@export var dodge_duration := 0.35
@export var parry_window := 0.40
@export var block_damage_reduction := 0.3
@export var damage_iframe_duration := 0.6
@export var respawn_delay := 2.0

@export_group("Health")
@export var max_hp := 100.0

# --- State ---
var stamina: float
var hp: float
var last_stamina_use := -10.0
var is_attacking := false
var is_dodging := false
var is_blocking := false
var is_parrying := false
var parry_window_timer := 0.0
var damage_iframes_timer := 0.0
var is_dying := false
var dodge_timer := 0.0
var dodge_velocity := Vector3.ZERO
var _hit_this_swing: Array = []
var _dodge_blink_tween: Tween = null
var _damage_blink_tween: Tween = null

# --- Nodes ---
@onready var model: Node3D = $Model
@onready var attack_area: Area3D = $AttackArea
@onready var hitbox_debug: MeshInstance3D = $AttackArea/HitboxDebug
@onready var block_shield: MeshInstance3D = $BlockShield
@onready var weapon_mesh: MeshInstance3D = $Model/Weapon
@onready var body_mesh: MeshInstance3D = $Model/Body

# --- Data-driven skill system ---
## Skills asignadas a slots de input (cast_skill_1, cast_skill_2, cast_skill_3).
## Cada slot es un StringName del skill_id, o vacío para no asignar.
@export var skill_bar: Array[StringName] = [
	&"kamehameha_001",
	&"gomu_gomu_pistol_001",
	&"uraraka_zero_gravity_001",
]

## Cooldown tracking por skill_id (en segundos del motor).
var _skill_cooldowns: Dictionary = {}

## SkillExecutor actualmente casteando (para evitar doble cast).
var _current_executor: Node = null

# Spawn point (set by external code or default to (0, 1, 0))
var spawn_position := Vector3(0, 1, 0)

# Visual feedback materials (script-managed so we can flash/tint at runtime)
var _weapon_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D
const WEAPON_BASE := Color(0.85, 0.85, 0.9)
const WEAPON_PARRY := Color(1.4, 1.3, 0.4)  # bright yellow flash
const WEAPON_BLOCK := Color(0.55, 0.8, 1.1)  # cool blue tint
const BODY_BASE := Color(0.3, 0.5, 0.8)
const BODY_PARRY_FLASH := Color(1.2, 1.2, 0.6)  # warm yellow flash


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stamina = max_stamina
	hp = max_hp
	spawn_position = global_position
	attack_area.monitoring = false
	hitbox_debug.visible = false
	block_shield.visible = false
	# Script-managed materials so we can flash/tint at runtime
	_weapon_mat = StandardMaterial3D.new()
	_weapon_mat.albedo_color = WEAPON_BASE
	_weapon_mat.metallic = 0.8
	_weapon_mat.roughness = 0.3
	weapon_mesh.material_override = _weapon_mat
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = BODY_BASE
	_body_mat.metallic = 0.2
	_body_mat.roughness = 0.6
	body_mesh.material_override = _body_mat
	attack_area.body_entered.connect(_on_attack_body)
	attack_area.area_entered.connect(_on_attack_area)
	# log connected gamepads
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		print("[input] no gamepad detected (keyboard/mouse only)")
	else:
		for p in pads:
			print("[input] gamepad device %d: %s" % [p, Input.get_joy_name(p)])
	# Register so enemies can find us
	add_to_group("player")
	# Cargar skills data-driven y registrarlas con ProgressionState
	_load_default_skills()
	# Grant inicial de skill points para testear (en prod, vienen de challenges)
	if ProgressionState and ProgressionState.proficiency == 0:
		ProgressionState.grant_skill_points(3)
		print("[player] granted 3 starter skill points for testing")


func _unhandled_input(event: InputEvent) -> void:
	# In headless/bot mode, mouse_mode may not be CAPTURED, but we still want to
	# process injected mouse motion events. Only require CAPTURED for real input.
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or OS.has_feature("headless") or event is InputEventMouseMotion and event.device == -1:
			rotate_y(-event.relative.x * mouse_sensitivity)
			$CameraPivot.rotate_x(-event.relative.y * mouse_sensitivity)
			$CameraPivot.rotation.x = clamp($CameraPivot.rotation.x, min_pitch, max_pitch)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	if is_dying:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var can_act := not is_dodging and not is_attacking and not is_dying

	# Data-driven skill system: input + cooldowns
	_process_skill_cooldowns(delta)
	handle_skill_input()
	# Tab abre el skill allocator (UI)
	if Input.is_action_just_pressed("open_skill_allocator"):
		_toggle_skill_allocator()

	# Tick parry window
	if parry_window_timer > 0.0:
		parry_window_timer -= delta
		is_parrying = true
	else:
		is_parrying = false

	# Tick damage iframes
	if damage_iframes_timer > 0.0:
		damage_iframes_timer -= delta
		if damage_iframes_timer <= 0.0:
			_stop_damage_blink()
			model.visible = true

	# Stamina regen
	if can_act and not is_blocking and now - last_stamina_use > stamina_regen_delay:
		stamina = min(max_stamina, stamina + stamina_regen * delta)

	# Actions (only if grounded + free)
	if can_act and is_on_floor():
		if Input.is_action_just_pressed("attack") and stamina >= stamina_drain_attack:
			_start_attack(now)
		elif Input.is_action_just_pressed("dodge") and stamina >= stamina_drain_dodge:
			_start_dodge(now)
		elif Input.is_action_just_pressed("parry") and stamina >= stamina_drain_parry:
			_start_parry(now)

	# Parry success check: any enemy currently winding up or in active attack phase?
	if is_parrying:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy):
				continue
			var attackable := false
			if enemy.has_method("is_attack_active") and enemy.is_attack_active():
				attackable = true
			elif enemy.has_method("is_attack_winding_up") and enemy.is_attack_winding_up():
				attackable = true
			if attackable:
				# Parry the attack
				enemy.on_parried(self)
				parry_window_timer = 0.0
				is_parrying = false
				parry_succeeded.emit(enemy)
				print("[player] parry_success enemy=%s" % enemy.name)
				break

	# Block (held)
	if can_act and Input.is_action_pressed("block") and stamina > 0 and not is_parrying:
		is_blocking = true
		stamina -= stamina_drain_block * delta
		last_stamina_use = now
		if stamina <= 0:
			stamina = 0
			is_blocking = false
	else:
		is_blocking = false
	# Visual: block shield visible while blocking
	block_shield.visible = is_blocking
	if is_blocking:
		_weapon_mat.albedo_color = WEAPON_BLOCK
	else:
		_weapon_mat.albedo_color = WEAPON_BASE

	# Jump
	if can_act and is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Movement
	if is_dodging:
		dodge_timer -= delta
		velocity = dodge_velocity
		if dodge_timer <= 0:
			is_dodging = false
	elif is_attacking:
		velocity.x *= 0.85
		velocity.z *= 0.85
	else:
		# get_vector(neg_x, pos_x, neg_y, pos_y) -> (pos_x - neg_x, pos_y - neg_y).
		# move_back is "down" on the stick (neg_y), move_forward is "up" (pos_y), so W -> +1 here.
		var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		# Convention: W (input_dir.y=+1) -> -Z in player local space (away from camera)
		var dir := transform.basis * Vector3(input_dir.x, 0, -input_dir.y)
		if dir.length() > 1.0:
			dir = dir.normalized()

		if is_blocking:
			dir = Vector3.ZERO

		var can_sprint := Input.is_action_pressed("sprint") and stamina > 0
		var target_speed := sprint_speed if can_sprint else move_speed
		var target_vel := Vector3(dir.x * target_speed, velocity.y, dir.z * target_speed)
		velocity.x = lerp(velocity.x, target_vel.x, clamp(acceleration * delta, 0.0, 1.0))
		velocity.z = lerp(velocity.z, target_vel.z, clamp(acceleration * delta, 0.0, 1.0))

		if input_dir.length() > 0.1 and not is_blocking:
			# FIX: target_yaw must account for player body rotation so the model
			# faces the world-space movement dir, not the player-local one.
			# model world rot = player.rot + model.rot; we want world -Z aligned with dir.
			# => model.rot = atan2(dir.x, -dir.z) - player.rot
			var target_yaw := atan2(dir.x, -dir.z) - rotation.y
			model.rotation.y = lerp_angle(model.rotation.y, target_yaw, rotation_lerp * delta)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0:
		velocity.y = 0

	move_and_slide()

	# Kill plane: respawn if we fall off the world
	if global_position.y < -10.0 and not is_dying:
		print("[player] fell off the world -> respawn")
		_die()


func _process(delta: float) -> void:
	# Right-stick camera (gamepad)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var dev := pads[0]
		var rx := Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
		if absf(rx) > gamepad_deadzone:
			rotate_y(-rx * gamepad_look_sensitivity * delta)
		if absf(ry) > gamepad_deadzone:
			$CameraPivot.rotate_x(-ry * gamepad_look_sensitivity * delta)
			$CameraPivot.rotation.x = clamp($CameraPivot.rotation.x, min_pitch, max_pitch)


func _start_attack(now: float) -> void:
	stamina -= stamina_drain_attack
	last_stamina_use = now
	is_attacking = true
	_hit_this_swing.clear()
	print("[player] attack_start stamina=%.1f" % stamina)

	# Windup
	hitbox_debug.visible = false
	await get_tree().create_timer(attack_windup).timeout
	if not is_attacking:
		return
	attack_area.monitoring = true
	hitbox_debug.visible = true
	print("[player] attack_active hitbox=on")

	# Active hit window
	await get_tree().create_timer(attack_active).timeout
	attack_area.monitoring = false
	hitbox_debug.visible = false
	print("[player] attack_recovery hitbox=off")

	# Recovery
	await get_tree().create_timer(attack_recovery).timeout
	is_attacking = false
	print("[player] attack_end")


func _start_dodge(now: float) -> void:
	stamina -= stamina_drain_dodge
	last_stamina_use = now
	is_dodging = true
	dodge_timer = dodge_duration
	print("[player] dodge_start stamina=%.1f" % stamina)

	var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if input_dir.length() < 0.1:
		input_dir = Vector2(0, 1)  # forward if no input (matches new convention)
	# Same convention as movement: W (input_dir.y=+1) means -Z (away from camera)
	var world := (transform.basis * Vector3(input_dir.x, 0, -input_dir.y)).normalized()
	dodge_velocity = world * (dodge_distance / dodge_duration)

	# i-frames: hide model + pass-through enemies (Node3D has no modulate, use visibility)
	# Blink the model to give a clear visual cue
	_start_dodge_blink()
	collision_layer = 0  # off all layers
	collision_mask = 1   # only world

	await get_tree().create_timer(dodge_duration).timeout
	_stop_dodge_blink()
	collision_layer = 2  # Player layer
	collision_mask = 1 | 4  # World (1) + Enemy (3, bit 2)
	print("[player] dodge_end")


func _start_parry(now: float) -> void:
	stamina -= stamina_drain_parry
	last_stamina_use = now
	parry_window_timer = parry_window
	is_parrying = true
	print("[player] parry_start stamina=%.1f window=%.2f" % [stamina, parry_window])
	# Visual: flash weapon + body bright yellow for the parry window
	_weapon_mat.albedo_color = WEAPON_PARRY
	_body_mat.albedo_color = BODY_PARRY_FLASH
	await get_tree().create_timer(parry_window).timeout
	_weapon_mat.albedo_color = WEAPON_BASE
	_body_mat.albedo_color = BODY_BASE


func take_damage(amount: float, source: Node = null) -> void:
	if is_dying or damage_iframes_timer > 0.0 or is_dodging:
		print("[player] damage_ignored reason=%s" % (
			"dying" if is_dying
			else ("iframes" if damage_iframes_timer > 0.0 else "dodging")
		))
		return

	var final := amount
	var blocked := false
	if is_blocking:
		final = amount * block_damage_reduction
		stamina = max(0.0, stamina - 15.0)  # block hit costs extra stamina
		blocked = true
		# Knockback: small
		if source and source is Node3D:
			var dir := (global_position - (source as Node3D).global_position).normalized()
			velocity += dir * 2.0

	hp -= final
	damage_iframes_timer = damage_iframe_duration
	_start_damage_blink()
	damaged.emit(amount, final, blocked)
	print("[player] damage amount=%.1f final=%.1f blocked=%s hp=%.1f" % [amount, final, blocked, hp])

	if hp <= 0.0:
		_die()


func _die() -> void:
	is_dying = true
	hp = 0.0
	is_attacking = false
	is_dodging = false
	is_blocking = false
	parry_window_timer = 0.0
	_stop_dodge_blink()
	_stop_damage_blink()
	model.visible = false
	collision_layer = 0
	collision_mask = 1
	died.emit()
	print("[player] DEATH respawn in %.1fs" % respawn_delay)
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	hp = max_hp
	stamina = max_stamina
	global_position = spawn_position
	velocity = Vector3.ZERO
	model.visible = true
	is_dying = false
	collision_layer = 2
	collision_mask = 1 | 4
	respawned.emit()
	print("[player] RESPAWN hp=%.1f" % hp)


func _start_dodge_blink() -> void:
	if _dodge_blink_tween:
		_dodge_blink_tween.kill()
	_dodge_blink_tween = create_tween().set_loops()
	_dodge_blink_tween.tween_property(model, "visible", false, 0.06)
	_dodge_blink_tween.tween_property(model, "visible", true, 0.06)

func _stop_dodge_blink() -> void:
	if _dodge_blink_tween:
		_dodge_blink_tween.kill()
		_dodge_blink_tween = null
	model.visible = true

func _start_damage_blink() -> void:
	if _damage_blink_tween:
		_damage_blink_tween.kill()
	# Cap at a safe number of loops so even if _stop_damage_blink is never called,
	# the tween dies after ~3s instead of running forever.
	_damage_blink_tween = create_tween().set_loops(22)
	_damage_blink_tween.tween_property(model, "visible", false, 0.07)
	_damage_blink_tween.tween_property(model, "visible", true, 0.07)

func _stop_damage_blink() -> void:
	if _damage_blink_tween:
		_damage_blink_tween.kill()
		_damage_blink_tween = null


func _on_attack_body(body: Node) -> void:
	if not _hit_this_swing.has(body) and body.has_method("take_damage"):
		_hit_this_swing.append(body)
		body.take_damage(attack_damage, self)
		attack_hit.emit(body, attack_damage)
		print("[player] attack_hit body=%s dmg=%.1f" % [body.name, attack_damage])


## Cura al jugador. Usado por heal/hot atoms del sistema de skills.
func heal(amount: float) -> void:
	if is_dying:
		return
	hp = min(max_hp, hp + amount)
	print("[player] heal +%.1f hp=%.1f" % [amount, hp])


func _on_attack_area(area: Area3D) -> void:
	if not _hit_this_swing.has(area) and area.has_method("take_damage"):
		_hit_this_swing.append(area)
		area.take_damage(attack_damage, self)
		attack_hit.emit(area, attack_damage)
		print("[player] attack_hit area=%s dmg=%.1f" % [area.name, attack_damage])


# === Data-driven skill system ===

## Carga las skills .tres del directorio data/skills/ y las registra con
## ProgressionState. También las asigna a los slots del skill_bar.
func _load_default_skills() -> void:
	if not ProgressionState:
		push_warning("[player] ProgressionState autoload not found")
		return
	var dir := DirAccess.open("res://data/skills")
	if dir == null:
		push_warning("[player] res://data/skills/ not found")
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var res_path := "res://data/skills/" + f
		var skill: Resource = load(res_path)
		if skill == null:
			continue
		# Verifica que sea un SkillResource
		if not skill is SkillResource:
			continue
		ProgressionState.add_skill(skill)
		print("[player] loaded skill %s -> id=%s name=%s" % [f, skill.id, skill.name])


## Castea una skill por su ID. Verifica cooldowns y costo de stamina.
## Devuelve true si la skill se empezó a castear.
func cast_data_skill(skill_id: StringName) -> bool:
	if not ProgressionState:
		return false
	var skill = ProgressionState.get_skill(skill_id)
	if skill == null:
		push_warning("[player] cast_data_skill: skill %s not owned" % skill_id)
		return false
	# Cooldown
	if _skill_cooldowns.get(String(skill_id), 0.0) > 0.0:
		print("[player] skill %s on cooldown (%.1fs remaining)" % [skill_id, _skill_cooldowns[String(skill_id)]])
		return false
	# Crea el ejecutor
	var ex = SkillExecutorScript.new()
	ex.skill = skill
	ex.caster = self
	ex.progression = ProgressionState
	add_child(ex)
	_current_executor = ex
	# Lanza el cast (es async)
	ex.cast()
	# Después de cast(), programa el cooldown
	var cd: float = ex.get_effective_cost("cooldown")
	if cd > 0.0:
		_skill_cooldowns[String(skill_id)] = cd
		print("[player] skill %s cooldown=%.1fs" % [skill_id, cd])
	return true


## Llama este método en _physics_process para tick cooldowns.
func _process_skill_cooldowns(delta: float) -> void:
	for k in _skill_cooldowns.keys():
		_skill_cooldowns[k] = max(0.0, _skill_cooldowns[k] - delta)
		if _skill_cooldowns[k] == 0.0:
			_skill_cooldowns.erase(k)


## Maneja los input actions de cast_skill_1/2/3. Llamar desde _physics_process.
func handle_skill_input() -> void:
	if is_dying or is_dodging or is_attacking:
		return
	if Input.is_action_just_pressed("cast_skill_1") and skill_bar.size() > 0 and skill_bar[0] != &"":
		cast_data_skill(skill_bar[0])
	elif Input.is_action_just_pressed("cast_skill_2") and skill_bar.size() > 1 and skill_bar[1] != &"":
		cast_data_skill(skill_bar[1])
	elif Input.is_action_just_pressed("cast_skill_3") and skill_bar.size() > 2 and skill_bar[2] != &"":
		cast_data_skill(skill_bar[2])


## Abre o cierra el skill allocator (UI). Busca el nodo en el tree.
func _toggle_skill_allocator() -> void:
	var allocator: Control = get_tree().root.find_child("SkillAllocator", true, false)
	if allocator == null:
		push_warning("[player] SkillAllocator not found in scene tree")
		return
	if allocator.visible:
		if allocator.has_method("_close"):
			allocator._close()
	else:
		if allocator.has_method("open"):
			allocator.open()
