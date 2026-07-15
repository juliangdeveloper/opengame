## player_controller.gd — RuleBook-driven input controller.
extends Node
class_name PlayerController

var character: Node = null

var active_skills: Array[StringName] = [
	&"camera_rotate_right",
	&"camera_rotate_left",
	&"camera_look_up",
	&"camera_look_down",
	&"camera_reset",
	&"walk",
	&"jump",
	&"hit",
]

# === Camera params (from .tres) ===
var _camera_yaw_speed: float = 0.0
var _camera_pitch_speed: float = 0.0
var _camera_pitch_clamp_min: float = -85.0
var _camera_pitch_clamp_max: float = 85.0
var _camera_reset_duration: float = 0.2
var _camera_pivot: Node3D = null
var _camera_loaded: bool = false

# === Walk params (loaded from walk.tres) ===
var _walk_speed: float = 0.0
var _walk_loaded: bool = false

# === Jump params (loaded from jump.tres) ===
var _jump_height: float = 0.0
var _jump_loaded: bool = false

# === Stamina (generic — reads costs from any skill .tres) ===
var current_stamina: float = 100.0
var max_stamina: float = 100.0
var stamina_regen_rate: float = 15.0  # points/sec when idle
var _stamina_consuming_this_frame: bool = false  # set by skills, reset each frame

# === Cooldowns (generic — reads cooldown from any skill .tres) ===
var _cooldowns: Dictionary = {}  # skill_id → remaining seconds

const MOUSE_SENSITIVITY: float = 0.0025
const GAMEPAD_DEADZONE: float = 0.15


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if character != null:
		_camera_pivot = character.get_node_or_null("CameraPivot")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_load_camera_params()
	_load_walk_params()
	_load_jump_params()
	# Load max_stamina from character data
	if character != null and "max_stamina" in character:
		max_stamina = character.max_stamina
	current_stamina = max_stamina
	_log("=== PlayerController ready ===")
	_log("Active skills: %s" % str(active_skills))
	_log("Camera yaw=%.2f pitch=%.2f | Walk speed=%.1f | Jump height=%.1f" % [_camera_yaw_speed, _camera_pitch_speed, _walk_speed, _jump_height])
	_log("Stamina: %.0f/%.0f (regen %.1f/s)" % [current_stamina, max_stamina, stamina_regen_rate])
	var pads: Array = Input.get_connected_joypads()
	if pads.is_empty():
		_log("No gamepad — keyboard/mouse only")
	else:
		for p in pads:
			_log("Gamepad %d: %s" % [p, Input.get_joy_name(p)])


func _load_camera_params() -> void:
	if _camera_loaded:
		return
	var yaw_res: Resource = load("res://data/skills/camera_rotate_right.tres")
	if yaw_res != null and yaw_res.atoms.size() > 0:
		_camera_yaw_speed = float(yaw_res.atoms[0].get("params", {}).get("base_speed", 2.5))
		_log("Loaded camera_rotate_right: base_speed=%.2f" % _camera_yaw_speed)
	else:
		_camera_yaw_speed = 2.5
	var pitch_res: Resource = load("res://data/skills/camera_look_up.tres")
	if pitch_res != null and pitch_res.atoms.size() > 0:
		var p: Dictionary = pitch_res.atoms[0].get("params", {})
		_camera_pitch_speed = float(p.get("base_speed", 2.0))
		_camera_pitch_clamp_min = deg_to_rad(float(p.get("clamp_min", -85.0)))
		_camera_pitch_clamp_max = deg_to_rad(float(p.get("clamp_max", 85.0)))
		_log("Loaded camera_look_up: base_speed=%.2f" % _camera_pitch_speed)
	else:
		_camera_pitch_speed = 2.0
	var reset_res: Resource = load("res://data/skills/camera_reset.tres")
	if reset_res != null and reset_res.atoms.size() > 0:
		_camera_reset_duration = float(reset_res.atoms[0].get("params", {}).get("duration", 0.2))
	_camera_loaded = true


func _load_walk_params() -> void:
	if _walk_loaded:
		return
	var walk_res: Resource = load("res://data/skills/walk.tres")
	if walk_res != null and walk_res.atoms.size() > 0:
		_walk_speed = float(walk_res.atoms[0].get("params", {}).get("speed", 4.0))
		_log("Loaded walk: speed=%.1f" % _walk_speed)
	else:
		_walk_speed = 0.0
	_walk_loaded = true


func _load_jump_params() -> void:
	if _jump_loaded:
		return
	var jump_res: Resource = load("res://data/skills/jump.tres")
	if jump_res != null and jump_res.atoms.size() > 0:
		_jump_height = float(jump_res.atoms[0].get("params", {}).get("height", 6.5))
		_log("Loaded jump: height=%.1f" % _jump_height)
	else:
		_jump_height = 6.5
	_jump_loaded = true


func _is_skill_active(skill_id: StringName) -> bool:
	return skill_id in active_skills


## Generic: read stamina_per_second from a skill's .tres costs.
## Returns 0.0 if the skill has no per-second cost.
func _get_skill_cost_per_second(skill_id: StringName) -> float:
	var res: Resource = load("res://data/skills/%s.tres" % String(skill_id))
	if res == null:
		return 0.0
	return float(res.costs.get("stamina_per_second", 0.0))


## Generic: read stamina (flat) from a skill's .tres costs.
## Returns 0.0 if the skill has no flat stamina cost.
func _get_skill_cost_flat(skill_id: StringName) -> float:
	var res: Resource = load("res://data/skills/%s.tres" % String(skill_id))
	if res == null:
		return 0.0
	return float(res.costs.get("stamina", 0.0))


## Generic: read cooldown from a skill's .tres costs.
func _get_skill_cooldown(skill_id: StringName) -> float:
	var res: Resource = load("res://data/skills/%s.tres" % String(skill_id))
	if res == null:
		return 0.0
	return float(res.costs.get("cooldown", 0.0))


## Generic: check if a skill is off cooldown and has enough stamina.
## Deducts flat stamina cost if available. Returns true if skill can execute.
func _try_activate_skill(skill_id: StringName) -> bool:
	# Cooldown check
	if _cooldowns.get(String(skill_id), 0.0) > 0.0:
		return false
	# Stamina check
	var cost: float = _get_skill_cost_flat(skill_id)
	if cost > 0.0 and current_stamina < cost:
		return false
	# Deduct stamina
	if cost > 0.0:
		current_stamina = maxf(0.0, current_stamina - cost)
		_stamina_consuming_this_frame = true
	# Set cooldown
	var cd: float = _get_skill_cooldown(skill_id)
	if cd > 0.0:
		_cooldowns[String(skill_id)] = cd
	return true


## Walk + jump + stamina — called from player._physics_process.
func process_movement(delta: float) -> void:
	if character == null or not is_instance_valid(character):
		return

	# Reset stamina flag each frame
	_stamina_consuming_this_frame = false

	# === Walk: set velocity, drain stamina per second ===
	if _is_skill_active(&"walk") and _walk_speed > 0.0:
		var input_dir := _read_move_input()
		if input_dir != Vector2.ZERO:
			# Check stamina before moving
			var walk_cost: float = _get_skill_cost_per_second(&"walk")
			if walk_cost > 0.0 and current_stamina <= 0.0:
				# No stamina → can't walk
				character.velocity.x = 0.0
				character.velocity.z = 0.0
			else:
				var forward: Vector3 = -character.global_transform.basis.z
				forward.y = 0
				forward = forward.normalized()
				var right_v: Vector3 = character.global_transform.basis.x
				right_v.y = 0
				right_v = right_v.normalized()
				var world_dir: Vector3 = forward * input_dir.y + right_v * input_dir.x
				if world_dir.length() > 1.0:
					world_dir = world_dir.normalized()
				character.velocity.x = world_dir.x * _walk_speed
				character.velocity.z = world_dir.z * _walk_speed
				# Drain stamina
				if walk_cost > 0.0:
					current_stamina = maxf(0.0, current_stamina - walk_cost * delta)
					_stamina_consuming_this_frame = true
		else:
			character.velocity.x = 0.0
			character.velocity.z = 0.0

	# === Gravity ===
	if not character.is_on_floor():
		character.velocity.y -= 22.0 * delta
	elif character.velocity.y < 0:
		character.velocity.y = 0

	# === Jump: flat stamina cost on activation ===
	if _is_skill_active(&"jump") and _jump_height > 0.0:
		if character.is_on_floor():
			var want_jump: bool = false
			var pads: Array = Input.get_connected_joypads()
			if not pads.is_empty():
				if Input.is_joy_button_pressed(pads[0], JOY_BUTTON_A):
					want_jump = true
			if Input.is_key_pressed(KEY_SPACE):
				want_jump = true
			if want_jump and _try_activate_skill(&"jump"):
				character.velocity.y = _jump_height
				_log("jump: height=%.1f stamina=%.0f/%.0f" % [_jump_height, current_stamina, max_stamina])

	# === Cooldown tick ===
	for skill_id in _cooldowns.keys():
		_cooldowns[skill_id] = maxf(0.0, _cooldowns[skill_id] - delta)

	# === Stamina regeneration ===
	if not _stamina_consuming_this_frame and current_stamina < max_stamina:
		current_stamina = minf(max_stamina, current_stamina + stamina_regen_rate * delta)

	# === Move ===
	character.move_and_slide()


## Camera yaw: rotate CHARACTER around Y (CameraPivot follows as child).
## Camera pitch: rotate CameraPivot around local X only.
func _process(delta: float) -> void:
	if character == null or not is_instance_valid(character):
		return
	if _camera_pivot == null:
		return

	# === Yaw: rotate character body → camera follows ===
	if _is_skill_active(&"camera_rotate_right") or _is_skill_active(&"camera_rotate_left"):
		var rx: float = _get_joy_axis(JOY_AXIS_RIGHT_X)
		if absf(rx) > GAMEPAD_DEADZONE:
			character.rotate_y(-rx * _camera_yaw_speed * delta)

	# === Pitch: rotate CameraPivot only ===
	if _is_skill_active(&"camera_look_up") or _is_skill_active(&"camera_look_down"):
		var ry: float = _get_joy_axis(JOY_AXIS_RIGHT_Y)
		if absf(ry) > GAMEPAD_DEADZONE:
			_camera_pivot.rotate_x(-ry * _camera_pitch_speed * delta)
			_camera_pivot.rotation.x = clampf(
				_camera_pivot.rotation.x,
				_camera_pitch_clamp_min,
				_camera_pitch_clamp_max
			)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if _is_skill_active(&"camera_rotate_right"):
				character.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
			if _is_skill_active(&"camera_look_up"):
				_camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
				_camera_pivot.rotation.x = clampf(
					_camera_pivot.rotation.x,
					_camera_pitch_clamp_min,
					_camera_pitch_clamp_max
				)
	elif event is InputEventJoypadButton and event.pressed:
		# R3 (button 8) → camera reset
		if event.button_index == 8 and _is_skill_active(&"camera_reset"):
			_execute_camera_reset()
		# Square (button 2) → hit
		if event.button_index == 2 and _is_skill_active(&"hit"):
			_execute_hit()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = (
				Input.MOUSE_MODE_VISIBLE
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else Input.MOUSE_MODE_CAPTURED
			)
		# F → hit (keyboard)
		if event.physical_keycode == 70 and _is_skill_active(&"hit"):
			_execute_hit()


func _execute_camera_reset() -> void:
	if _camera_pivot == null:
		return
	_log("camera_reset")
	if _camera_reset_duration > 0.0:
		var tween: Tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(_camera_pivot, "rotation:x", 0.0, _camera_reset_duration)
	else:
		_camera_pivot.rotation.x = 0.0


## Hit skill interpreter — reads hit.tres atom, spawns trigger hitbox.
## Atom: { type: "hit", params: { asset, offset, dimensions, duration, push_force, weight_multiplier } }
func _execute_hit() -> void:
	if not _try_activate_skill(&"hit"):
		return
	var hit_res: Resource = load("res://data/skills/hit.tres")
	if hit_res == null or hit_res.atoms.size() == 0:
		return
	var params: Dictionary = hit_res.atoms[0].get("params", {})
	var asset_path: String = params.get("asset", "res://assets/hitbox_cube.tscn")
	var offset: Dictionary = params.get("offset", {})
	var dims: Dictionary = params.get("dimensions", {})
	var duration: float = float(params.get("duration", 0.1))
	var push_force: float = float(params.get("push_force", 8.0))
	var weight_mult: bool = params.get("weight_multiplier", true)
	# Load and instantiate
	var packed: PackedScene = load(asset_path)
	if packed == null:
		_log("ERROR: hit asset not found: %s" % asset_path)
		return
	var hitbox: Node3D = packed.instantiate()
	# Set dimensions (scale relative to asset's base 1x1x1)
	var sx: float = float(dims.get("x", 1.0))
	var sy: float = float(dims.get("y", 1.0))
	var sz: float = float(dims.get("z", 1.0))
	hitbox.scale = Vector3(sx, sy, sz)
	# Set position: offset from CAMERA facing direction
	var cam: Camera3D = _camera_pivot.get_node_or_null("Camera3D")
	var forward: Vector3 = Vector3.FORWARD
	if cam != null:
		forward = -cam.global_transform.basis.z
	else:
		forward = -_camera_pivot.global_transform.basis.z
	forward = forward.normalized()
	var right_v: Vector3 = forward.cross(Vector3.UP).normalized()
	var spawn_pos: Vector3 = character.global_position
	spawn_pos += forward * float(offset.get("forward", 0.0))
	spawn_pos += right_v * float(offset.get("right", 0.0))
	spawn_pos.y += float(offset.get("up", 0.0))
	hitbox.global_position = spawn_pos
	# Set hitbox properties
	if "push_force" in hitbox:
		hitbox.push_force = push_force
	if "push_effect" in hitbox:
		var effect: float = 1.0
		if character.get("data") != null and "push_effect" in character.data:
			effect = float(character.data.push_effect)
		hitbox.push_effect = effect
	if "push_direction" in hitbox:
		hitbox.push_direction = forward
	if "lifetime" in hitbox:
		hitbox.lifetime = duration
	# Add to scene
	character.get_tree().current_scene.add_child(hitbox)
	_log("hit: force=%.1f stamina=%.0f/%.0f cd=%.1f" % [
		push_force, current_stamina, max_stamina,
		_cooldowns.get("hit", 0.0)
	])


func _read_move_input() -> Vector2:
	var input_dir := Vector2.ZERO
	var lx: float = _get_joy_axis(JOY_AXIS_LEFT_X)
	var ly: float = _get_joy_axis(JOY_AXIS_LEFT_Y)
	if absf(lx) > GAMEPAD_DEADZONE or absf(ly) > GAMEPAD_DEADZONE:
		input_dir = Vector2(lx, -ly)
	if Input.is_action_pressed("move_forward"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_backward"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	if input_dir.length() < 0.1:
		return Vector2.ZERO
	return input_dir


func _get_joy_axis(axis: int) -> float:
	var pads: Array = Input.get_connected_joypads()
	if pads.is_empty():
		return 0.0
	return Input.get_joy_axis(pads[0], axis)


func _log(msg: String) -> void:
	print("[engine] %s" % msg)
