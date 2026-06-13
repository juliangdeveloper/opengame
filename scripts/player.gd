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
const MENU_SCENE := preload("res://scenes/ui/menu.tscn")
const MENU_NODE_NAME := "Menu"

# --- Signals for external observability (HUD, bot, sim logger) ---
signal skill_cast_started(skill_id: StringName, slot_index: int)
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
## Costos legacy (referencia). Ahora la stamina se consume via los costs
## del SkillResource casteado (ej: esquivar_001.tres cuesta 18, defenderse_001.tres
## cuesta 12). Se mantienen los export vars para compat con el HUD.
@export var stamina_drain_attack := 22.0
@export var stamina_drain_dodge := 28.0
@export var stamina_drain_block := 18.0
@export var stamina_drain_parry := 18.0

@export_group("Combat")
## (Attack windup/active/recovery ahora se leen del SkillResource.light_attack_001)
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

## === SISTEMA DE SKILLS PARA COMBATE BÁSICO (Post-MVP) ===
## Todo lo que antes era código hardcodeado (attack/dodge/parry/block) ahora
## es un skill data-driven. Estos IDs mapean acciones del jugador al skill_id.
## El jugador puede sustituirlos desde el skill book (asignar otro skill al
## "slot ataque", etc.). Por defecto apuntan a:
##   light_attack_001  → ataque básico con el arma equipada
##   esquivar_001      → dash con i-frames
##   defenderse_001    → ventana de parry / contraataque
@export var basic_attack_skill_id: StringName = &"light_attack_001"
@export var dodge_skill_id: StringName = &"esquivar_001"
@export var parry_skill_id: StringName = &"defenderse_001"

## Resource del arma actualmente equipada (la que se muestra en la mano).
## Se asigna vía ProgressionState.equip_weapon() o set_equipped_weapon().
var equipped_weapon: Resource = null

## Estado interno del i-frame timer (controlado por set_iframes).
var _iframe_timer: float = 0.0

# --- Nodes ---
@onready var model: Node3D = $Model
@onready var attack_area: Area3D = $AttackArea
@onready var hitbox_debug: MeshInstance3D = $AttackArea/HitboxDebug
@onready var block_shield: MeshInstance3D = $BlockShield
@onready var weapon_mesh: MeshInstance3D = $Model/Weapon
@onready var body_mesh: MeshInstance3D = $Model/Body

# --- Data-driven skill system ---
## Skills asignadas a slots de input. Hay 8 slots totales.
## Cada slot es un StringName del skill_id, o vacío para no asignar.
##
## Mapeo de input (gamepad):
##   Sin modifier:
##     X        → slot 0  (light_attack_001 por defecto)
##     Square   → slot 1  (parry_riposte_001 o skill básica)
##     Circle   → slot 2  (esquivar_001)
##     Triangle → slot 3  (defenderse_001)
##   L1 / R1 held (modifier):
##     L1+X     → slot 4
##     L1+□     → slot 5
##     L1+○     → slot 6
##     L1+△     → slot 7
##     R1+X     → slot 4 (equivalente a L1+)
##   L2 held: block legacy (held).
##
## Mapeo de input (teclado, fallback):
##   Teclas 1-4 → slots 0-3 (skills básicas)
##   L1/R1 + 1-4 → slots 4-7 (skills especiales)
@export var skill_bar: Array[StringName] = [
	&"light_attack_001",     # slot 0: X
	&"",                     # slot 1: □
	&"esquivar_001",         # slot 2: ○
	&"defenderse_001",       # slot 3: △
	&"kamehameha_001",       # slot 4: L1+X
	&"gomu_gomu_pistol_001", # slot 5: L1+□
	&"uraraka_zero_gravity_001", # slot 6: L1+○
	&"serious_punch_001",    # slot 7: L1+△
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
	# Sync con el autoload ProgressionState: si ya hay un arma equipada
	# en el singleton, traerla al player (caso típico: PS._ready corrió
	# antes de que el player existiera en la escena).
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps and ps.equipped_weapon != null:
		equipped_weapon = ps.equipped_weapon
		_apply_weapon_visual(equipped_weapon)
		print("[player] _ready: synced equipped_weapon from PS = %s" % equipped_weapon.display_name)
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
	# ResistanceComponent (resistencias elementales + temporales).
	# Se carga desde ProgressionState.element_allocations y buffs de skills.
	var ResistanceCompScript: GDScript = load("res://scripts/skill/components/ResistanceComponent.gd")
	var rc: Node = ResistanceCompScript.new()
	rc.name = "ResistanceComponent"
	add_child(rc)
	print("[player] ResistanceComponent ready (will load from ProgressionState)")

	# AttributeComponent (HP, Stamina, Atk%, Res%, status_res).
	# Se carga desde ProgressionState.attribute_allocations.
	var AttributeCompScript: GDScript = load("res://scripts/attribute_component.gd")
	var ac: Node = AttributeCompScript.new()
	ac.name = "AttributeComponent"
	add_child(ac)
	ac.call("refresh_from_progression_state")
	# Grant inicial de attribute points (en prod vienen de challenges)
	if ProgressionState and ProgressionState.attribute_points == 0 and ProgressionState.get_total_allocated_attribute_points() == 0:
		ProgressionState.grant_attribute_points(5)
		print("[player] granted 5 starter attribute points for testing")
		# Aplicar HP/Stamina actuales tras grant (si los campos existen)
		_apply_attribute_derived_stats()


func _input(event: InputEvent) -> void:
	# SHARE / BACK button (PS4/Xbox JOY_BUTTON 4) debe abrir el libro aunque
	# el evento luego sea consumido. Escuchamos el botón crudo como fallback
	# por si el InputMap action no se triggerea.
	if event is InputEventJoypadButton and event.pressed and event.button_index == 4:
		_open_skill_book_consumed_this_frame = true
		_toggle_skill_book()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_skill_book"):
		_open_skill_book_consumed_this_frame = true
		_toggle_skill_book()
		get_viewport().set_input_as_handled()

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
	# Tab abre el skill allocator viejo (UI clásica)
	if Input.is_action_just_pressed("open_skill_allocator"):
		_toggle_skill_allocator()
	# SHARE button (PS4/Xbox JOY_BUTTON 4) abre el skill book (nuevo compendio)
	if Input.is_action_just_pressed("open_skill_book") and not _open_skill_book_consumed_this_frame:
		_toggle_skill_book()
	_open_skill_book_consumed_this_frame = false

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

	# TODO se castea como SKILL data-driven (handle_skill_input abajo).
	# L1/R1 son SOLO modifiers (no pueden disparar nada por sí mismos, ya
	# que se usan para cambiar de tab en el skill book y para elegir
	# grupo de slots en handle_skill_input). El block legacy (held) se
	# mapea al botón "atrás" (joy button 7) y al RMB. El resto
	# (attack/dodge/parry) son SKILLS puras casteadas vía skill_bar[slot].

	# Parry window check: si el jugador está casteando defenderse_001, el
	# timer lo abrió vía _on_executor_skill_started. Si un enemy está
	# atacando (windup o active) y la parry window está abierta,
	# contraatacamos.
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
				# Auto-castear parry_riposte (combo trigger del skill defenderse)
				_cast_basic_skill(&"parry_riposte_001")
				break

	# Block (held) — atajo legacy con L2 (joy button 7) o RMB.
	var is_block_held := false
	if can_act and stamina > 0 and not is_parrying:
		if Input.is_action_pressed("block"):
			is_block_held = true
		elif Input.is_action_pressed("modifier_l2") and stamina > 0:
			is_block_held = true
	if is_block_held:
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


## Castea un skill de combate básico (ataque/esquivar/defenderse/ripost).
## Crea un SkillExecutor temporal, conecta sus signals, y lo deja correr.
## El skill determinará su propio windup/active/recovery vía sus atoms.
func _cast_basic_skill(skill_id: StringName) -> void:
	if skill_id == &"":
		return
	# Lookup del .tres
	var skill_res: Resource = null
	if _skill_res_cache.has(skill_id):
		skill_res = _skill_res_cache[skill_id]
	else:
		skill_res = load("res://data/skills/%s.tres" % String(skill_id))
		if skill_res != null:
			_skill_res_cache[skill_id] = skill_res
	if skill_res == null:
		push_warning("[player] _cast_basic_skill: no se encontró %s.tres" % String(skill_id))
		return
	# Chequear costo
	var cost_stamina: float = float(skill_res.costs.get("stamina", 0.0))
	if cost_stamina > 0 and stamina < cost_stamina:
		print("[player] _cast_basic_skill: no stamina (need %.1f, have %.1f)" % [cost_stamina, stamina])
		return
	# Consumir stamina
	stamina -= cost_stamina
	last_stamina_use = Time.get_ticks_msec() / 1000.0
	# Crear executor
	var ex: Node = SkillExecutorScript.new()
	ex.skill = skill_res
	ex.caster = self
	# Hookear el progression state para scaling
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps:
		ex.progression = ps
	# Conectar signal para reaccionar (parry window, etc.)
	if not ex.skill_started.is_connected(_on_executor_skill_started):
		ex.skill_started.connect(_on_executor_skill_started)
	if not ex.skill_finished.is_connected(_on_executor_skill_finished):
		ex.skill_finished.connect(_on_executor_skill_finished)
	_current_executor = ex
	add_child(ex)
	ex.cast()
	print("[player] _cast_basic_skill: %s" % String(skill_id))


## React al inicio de un skill: si es esquivar/defenderse, abrir ventana.
func _on_executor_skill_started(skill) -> void:
	if skill == null:
		return
	var sid: StringName = StringName(skill.id) if "id" in skill else &""
	# Esquivar: marcar estado de dodge, i-frames los activa el move atom
	if sid == &"esquivar_001" or String(sid).begins_with("esquivar_"):
		is_dodging = true
		dodge_timer = float(skill.designed_max.get("duration", 0.3))
		is_attacking = false
	# Defenderse: abrir parry window
	elif sid == &"defenderse_001" or String(sid).begins_with("defenderse_"):
		is_parrying = true
		parry_window_timer = float(skill.designed_max.get("parry_window", 0.4))
		# Visual flash
		_weapon_mat.albedo_color = WEAPON_PARRY
		_body_mat.albedo_color = BODY_PARRY_FLASH
	# Light attack / melee: marcar attacking
	elif sid == &"light_attack_001" or sid == &"parry_riposte_001":
		is_attacking = true
		_hit_this_swing.clear()


## Al terminar el skill, limpiar estado.
func _on_executor_skill_finished(skill) -> void:
	if skill == null:
		return
	var sid: StringName = StringName(skill.id) if "id" in skill else &""
	if sid == &"defenderse_001" or String(sid).begins_with("defenderse_"):
		is_parrying = false
		_weapon_mat.albedo_color = WEAPON_BASE
		_body_mat.albedo_color = BODY_BASE
	elif sid == &"esquivar_001" or String(sid).begins_with("esquivar_"):
		is_dodging = false
		collision_layer = 2  # Player layer
		collision_mask = 1 | 4  # World + Enemy
	elif sid == &"light_attack_001" or sid == &"parry_riposte_001":
		is_attacking = false


# Cache para no recargar .tres en cada cast
var _skill_res_cache: Dictionary = {}


# === HELPERS LLAMADOS POR EffectLibrary cuando aplica átomos del caster ===
## Llamado por EffectLibrary._apply_move cuando el átomo move tiene i_frames=true.
## Baja la collision layer durante `duration` segundos y la sube al terminar.
func set_iframes(duration: float) -> void:
	_iframe_timer = duration
	collision_layer = 0
	collision_mask = 1
	# Usamos un timer para restaurar (no await para no bloquear la skill)
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		collision_layer = 2  # Player
		collision_mask = 1 | 4
		_iframe_timer = 0.0
		print("[player] iframe_end")
	)


## Llamado por EffectLibrary._apply_move cuando el átomo move tiene blink=true.
## Hace blink del modelo durante la duración del dash.
func start_dodge_blink(duration: float) -> void:
	if _dodge_blink_tween != null and _dodge_blink_tween.is_valid():
		_dodge_blink_tween.kill()
	_dodge_blink_tween = create_tween().set_loops(int(duration * 12))
	_dodge_blink_tween.tween_property(model, "visible", false, 1.0 / 24.0)
	_dodge_blink_tween.tween_property(model, "visible", true, 1.0 / 24.0)
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		if _dodge_blink_tween != null and _dodge_blink_tween.is_valid():
			_dodge_blink_tween.kill()
		model.visible = true
		_dodge_blink_tween = null
	)


## Llamado por EffectLibrary._apply_move cuando el átomo move tiene stamina_drain.
## (Generalmente ya consumimos stamina al castear; este es fallback para refundir).
func spend_stamina(amount: float) -> void:
	stamina = max(0.0, stamina - amount)
	last_stamina_use = Time.get_ticks_msec() / 1000.0


## Llamado por ProgressionState.equip_weapon() cuando el jugador equipa un arma.
## Actualiza el visual, el color de la mesh, y guarda la referencia.
## Es seguro llamarlo antes de _ready del player (sólo guarda la referencia);
## el visual se aplica en _ready del player cuando _weapon_mat exista.
func set_equipped_weapon(weapon: Resource) -> void:
	equipped_weapon = weapon
	if weapon == null:
		print("[player] set_equipped_weapon: None (unarmed)")
		_apply_weapon_visual(null)
		return
	# Aplicar visual sólo si _weapon_mat ya existe (player._ready corrió).
	# Si no, _ready lo recogerá vía el valor de equipped_weapon.
	_apply_weapon_visual(weapon)
	print("[player] set_equipped_weapon: %s (family=%s, hands=%d, dmg=%.1f)" % [
		weapon.display_name, weapon.get_family_display(), weapon.hands,
		float(weapon.designed_stats.get("dmg", 0.0))
	])


## Helper interno: aplica el tinte/color al mesh del arma, si está listo.
## Además instancia el .glb del arma equipada como hijo del Weapon node,
## reemplazando el BoxMesh placeholder.
func _apply_weapon_visual(weapon: Resource) -> void:
	if _weapon_mat == null:
		return  # _ready no ha corrido aún; se reaplicará desde allí
	if weapon == null:
		_weapon_mat.albedo_color = WEAPON_BASE
		_clear_weapon_model()
		return
	var tint: Color = Color(0.85, 0.85, 0.9)
	if "tint_color" in weapon:
		tint = weapon.tint_color
	_weapon_mat.albedo_color = tint
	_load_weapon_model(weapon)


## Cache de PackedScenes de modelos .glb cargados, para no recargarlos.
var _weapon_model_cache: Dictionary = {}


## Carga el .glb declarado en weapon.model_path y lo instancia como hijo
## del Weapon node. La rotación base convierte Blender Z-up a Godot Y-up:
##   +Z (handle up en Blender) → +Y (up en Godot)
##   +Y (blade forward en Blender) → -Z (forward en Godot)
## Sobre esa base, se aplica weapon.model_rotation (Euler XYZ, grados) para
## sostener el arma en orientaciones distintas (e.g. bow horizontal).
## El grip_offset del modelo (eje Y local post-rotación) se alinea con la
## mano del jugador bajando el modelo en Y por ese valor.
##
## TODO: el .tres es la fuente de verdad (data-driven). Esto permite que
## la IA vía MCP cree nuevas armas con su propio .glb + grip_offset.
func _load_weapon_model(weapon: Resource) -> void:
	_clear_weapon_model()
	var glb_path: String = _weapon_glb_path(weapon)
	if glb_path.is_empty():
		# No hay modelo (e.g. unarmed). Mantenemos placeholder BoxMesh.
		weapon_mesh.visible = true
		return
	var packed: PackedScene = _weapon_model_cache.get(glb_path)
	if packed == null:
		packed = load(glb_path)
		if packed == null:
			push_warning("[player] cannot load weapon model: %s" % glb_path)
			weapon_mesh.visible = true
			return
		_weapon_model_cache[glb_path] = packed
	var instance: Node3D = packed.instantiate()
	if instance == null:
		push_warning("[player] failed to instantiate weapon model: %s" % glb_path)
		weapon_mesh.visible = true
		return
	# Renombrar para que el scene tree muestre el modelo identificable
	# (suele ser "@Node3D@52" en la primera instanciación; el rename se
	# hace post-add_child para que Godot lo respete).
	var wid: String = String(weapon.id) if "id" in weapon else "unknown"
	# Rotación base: -90° en X (Blender Z-up → Godot Y-up).
	# Sobre eso, aplicamos weapon.model_rotation si está declarada.
	var base_rot_x: float = deg_to_rad(-90.0)
	var extra_rot: Vector3 = Vector3.ZERO
	if "model_rotation" in weapon:
		extra_rot = weapon.model_rotation
	instance.rotation = Vector3(base_rot_x, 0.0, 0.0) + Vector3(deg_to_rad(extra_rot.x), deg_to_rad(extra_rot.y), deg_to_rad(extra_rot.z))
	# Posición: bajar el modelo en Y para alinear el grip con (0,0,0) del
	# Weapon node (= la mano del jugador).
	var grip_offset: float = 0.20  # default sensato
	if "grip_offset" in weapon:
		grip_offset = float(weapon.grip_offset)
	instance.position = Vector3(0.0, -grip_offset, 0.0)
	# Escala (e.g. armas grandes que necesitan ajuste).
	if "model_scale" in weapon and float(weapon.model_scale) != 1.0:
		instance.scale = Vector3.ONE * float(weapon.model_scale)
	# Hide the placeholder box; show the actual model.
	weapon_mesh.visible = false
	# Add the model DIRECTLY as a child of weapon_mesh (so local position
	# is respected). Don't add to player first — that would cause a
	# reparent to keep the global transform and reset the local pos.
	weapon_mesh.add_child(instance)
	# Renombrar DESPUÉS de add_child (antes no se respetaba — Godot 4
	# resetea el nombre a "@Node3D@52" en la primera instanciación si
	# se setea antes de entrar al árbol).
	instance.name = "WeaponModel_%s" % wid
	# Re-set position now that the parent is weapon_mesh.
	instance.position = Vector3(0.0, -grip_offset, 0.0)


## Elimina el modelo de arma instanceado (si existe) y restaura el placeholder.
func _clear_weapon_model() -> void:
	for child in weapon_mesh.get_children():
		child.queue_free()
	weapon_mesh.visible = true


## Devuelve el path al .glb del arma, leído desde el .tres (data-driven).
## Si el .tres no tiene model_path o el archivo no existe, retorna "".
func _weapon_glb_path(weapon: Resource) -> String:
	if weapon == null or not ("model_path" in weapon):
		return ""
	var p: String = String(weapon.model_path)
	if p.is_empty():
		return ""
	if not ResourceLoader.exists(p):
		push_warning("[player] weapon %s declares model_path='%s' but file does not exist" % [weapon.id, p])
		return ""
	return p


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

	# Aplicar resistencias de Atributos (AttributeComponent).
	# phys_res reduce daño FÍSICO, ele_res reduce daño ELEMENTAL.
	# source puede traer "damage_type" (físico/elemental) o se infiere
	# por su melee_atom.element.
	var phys_attr: Node = null
	if has_node("AttributeComponent"):
		phys_attr = get_node("AttributeComponent")
	if phys_attr:
		# Heurística: si el source tiene un atributo "last_damage_type" lo usamos.
		# Por defecto, melee NPC = physical; spells = elemental.
		var dmg_type: String = "physical"
		if source and "last_damage_type" in source:
			dmg_type = String(source.last_damage_type)
		if dmg_type == "physical":
			final *= float(phys_attr.call("get_phys_res_multiplier"))
		else:
			final *= float(phys_attr.call("get_ele_res_multiplier"))

	hp -= final
	damage_iframes_timer = damage_iframe_duration
	_start_damage_blink()
	damaged.emit(amount, final, blocked)
	print("[player] damage amount=%.1f final=%.1f blocked=%s hp=%.1f" % [amount, final, blocked, hp])

	if hp <= 0.0:
		_die()


## Aplica los stats derivados de los Atributos (HP max, Stamina max,
## Stamina regen) a las variables internas. Llamar tras cambios de
## allocations.
func _apply_attribute_derived_stats() -> void:
	if not has_node("AttributeComponent"):
		return
	var ac: Node = get_node("AttributeComponent")
	var old_max_hp := max_hp
	max_hp = float(ac.call("get_value", &"hp_max"))
	max_stamina = float(ac.call("get_value", &"stamina_max"))
	stamina_regen = float(ac.call("get_value", &"stamina_regen"))
	# Mantener HP proporcional al cambio de max
	if old_max_hp > 0.0 and hp > 0.0:
		var ratio := hp / old_max_hp
		hp = max_hp * ratio
	hp = min(hp, max_hp)
	stamina = min(stamina, max_stamina)
	print("[player] derived stats: hp_max=%.1f stamina_max=%.1f regen=%.1f" % [max_hp, max_stamina, stamina_regen])


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
		# El daño se calcula ahora desde el skill (vía EffectLibrary._compute_skill_power
		# con el arma equipada). Aquí simplemente pasamos un dmg "raw" legacy para
		# las colisiones del attack_area físico, pero el dmg real del skill es
		# el que se aplica al target. Si este handler se activa sin skill, usa
		# un fallback de 0 (no aplica daño sin skill activa).
		var fallback_dmg: float = 0.0
		body.take_damage(fallback_dmg, self)
		print("[player] attack_area body=%s (skill applies real dmg, this is no-op)" % body.name)


## Cura al jugador. Usado por heal/hot atoms del sistema de skills.
func heal(amount: float) -> void:
	if is_dying:
		return
	hp = min(max_hp, hp + amount)
	print("[player] heal +%.1f hp=%.1f" % [amount, hp])


func _on_attack_area(area: Area3D) -> void:
	if not _hit_this_swing.has(area) and area.has_method("take_damage"):
		_hit_this_swing.append(area)
		var fallback_dmg: float = 0.0
		area.take_damage(fallback_dmg, self)
		print("[player] attack_area area=%s (skill applies real dmg)" % area.name)


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
## (Implementación legacy — usa ProgressionState para cooldown tracking.
## La versión nueva _cast_basic_skill() carga el .tres directamente, sin
## requerir que la skill esté en owned_skills; se usa para esquivar/defenderse/
## light_attack que están "siempre disponibles" sin necesidad de grant explícito.)
func cast_data_skill(skill_id: StringName, slot_index: int = -1) -> bool:
	if not ProgressionState:
		return false
	# Chequear cooldown
	if _skill_cooldowns.get(String(skill_id), 0.0) > 0.0:
		print("[player] skill %s on cooldown (%.1fs remaining)" % [skill_id, _skill_cooldowns[String(skill_id)]])
		return false
	# Castear (la stamina ya se consume en _cast_basic_skill, pero verificamos costo del .tres)
	var skill_res: Resource = _skill_res_cache.get(skill_id)
	if skill_res == null:
		skill_res = load("res://data/skills/%s.tres" % String(skill_id))
		if skill_res != null:
			_skill_res_cache[skill_id] = skill_res
	if skill_res == null:
		push_warning("[player] cast_data_skill: skill %s not found" % skill_id)
		return false
	var cost_stamina: float = float(skill_res.costs.get("stamina", 0.0))
	if cost_stamina > 0 and stamina < cost_stamina:
		return false
	# Consumir
	stamina -= cost_stamina
	last_stamina_use = Time.get_ticks_msec() / 1000.0
	# Crea el ejecutor
	var ex: Node = SkillExecutorScript.new()
	ex.skill = skill_res
	ex.caster = self
	ex.progression = ProgressionState
	if not ex.skill_started.is_connected(_on_executor_skill_started):
		ex.skill_started.connect(_on_executor_skill_started)
	if not ex.skill_finished.is_connected(_on_executor_skill_finished):
		ex.skill_finished.connect(_on_executor_skill_finished)
	add_child(ex)
	_current_executor = ex
	ex.cast()
	# Programar cooldown
	var cd: float = ex.get_effective_cost("cooldown")
	if cd > 0.0:
		_skill_cooldowns[String(skill_id)] = cd
	skill_cast_started.emit(skill_id, slot_index)
	return true


## Llama este método en _physics_process para tick cooldowns.
func _process_skill_cooldowns(delta: float) -> void:
	for k in _skill_cooldowns.keys():
		_skill_cooldowns[k] = max(0.0, _skill_cooldowns[k] - delta)
		if _skill_cooldowns[k] == 0.0:
			_skill_cooldowns.erase(k)


## Maneja los input actions de cast. Llamar desde _physics_process.
##
## Sistema de modifier: 3 grupos de slots según el modifier presionado.
##   - Sin modifier   → slots 0-3 (face buttons X/□/○/△ directos)
##   - L1 held        → slots 4-7 (L1+face)
##   - R1 held        → slots 8-11 (R1+face) — futuro, sólo 8 slots hoy
##   - L2 held        → block legacy (held)
##
## Esto permite que las "skills básicas" (light_attack, esquivar, defenderse)
## se asignen a slots 0-3 y se casteen con un face button solo, sin
## modifier. Y las "skills especiales" se castean con L1+face o R1+face.
##
## El gamepad tiene prioridad sobre el teclado: si L1 está held, slots 4-7.
## Si no hay modifier, slots 0-3. Sin modifier ni face button, no castea.
func handle_skill_input() -> void:
	if is_dying or is_dodging or is_attacking:
		return
	# Si el menú está abierto o acaba de cerrarse, ignorar presses.
	var book := get_tree().root.find_child("Menu", true, false)
	if book == null:
		book = get_tree().root.find_child("SkillBook", true, false)  # backwards compat
	if book and book.has_method("was_recently_open") and book.was_recently_open():
		return
	# Mapeo: action_name -> offset dentro del grupo (0-3)
	var face_buttons := {
		"cast_skill_x": 0,        # X / Cross (PS4) / A (Xbox)
		"cast_skill_square": 1,   # Square (PS4) / X (Xbox)
		"cast_skill_circle": 2,   # Circle (PS4) / B (Xbox)
		"cast_skill_triangle": 3, # Triangle (PS4) / Y (Xbox)
	}
	# Determinar base_slot según modifier (L1/R1/nada).
	# Prioridad: R1 > L1 > sin modifier.
	var base_slot: int = 0  # por defecto, sin modifier → slots 0-3
	if Input.is_action_pressed("modifier_r1"):
		base_slot = 4
	elif Input.is_action_pressed("modifier_l1"):
		base_slot = 4  # L1 también va a 4-7 (R1 y L1 equivalentes por ahora)
	# Chequear cada face button.
	for action in face_buttons:
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			var slot: int = base_slot + int(face_buttons[action])
			_try_cast_slot(slot)
			return
	# --- Teclado: 1-8 directo (fallback) ---
	# Si hay L1/R1 pressed, sumar 4 al slot teclado.
	var kb_offset := 0
	if Input.is_action_pressed("modifier_l1") or Input.is_action_pressed("modifier_r1"):
		kb_offset = 4
	for n in range(1, 9):
		var action: String = "cast_skill_%d" % n
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			_try_cast_slot(n - 1 + kb_offset)
			return


## Intenta castear el skill del slot dado. Si el slot está vacío o fuera
## de rango, no hace nada (silencioso).
func _try_cast_slot(slot: int) -> void:
	if slot < 0 or slot >= skill_bar.size():
		return
	if skill_bar[slot] == &"":
		return
	cast_data_skill(skill_bar[slot], slot)


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


## Abre o cierra el Menú (antes "Skill Book"). SHARE button PS4.
## Lazy-instancia la escena la primera vez y la agrega al root.
var _menu_instance: Control = null
var _open_skill_book_consumed_this_frame := false

func _toggle_skill_book() -> void:
	# Inicializar el master (única vez) si no existe.
	if _menu_instance == null or not is_instance_valid(_menu_instance):
		var existing := get_tree().root.find_child(MENU_NODE_NAME, true, false)
		if existing == null:
			existing = get_tree().root.find_child("SkillBook", true, false)  # backwards compat
		if existing and existing is Control:
			_menu_instance = existing
		else:
			_menu_instance = MENU_SCENE.instantiate()
			_menu_instance.name = MENU_NODE_NAME
			var layer := get_tree().root.find_child("MenuContainer", true, false)
			if layer == null:
				layer = get_tree().root.find_child("MenuLayer", true, false)
			if layer == null:
				layer = get_tree().root.find_child("SkillBookContainer", true, false)  # backwards compat
			if layer == null:
				layer = get_tree().root.find_child("SkillBookLayer", true, false)  # backwards compat
			var host: Node = layer if layer else get_tree().root
			host.add_child(_menu_instance)
			await get_tree().process_frame
	if not is_instance_valid(_menu_instance):
		return

	# Detectar si HAY algún sub-tab abierto (ElementAllocator/AttributeAllocator/WeaponAllocator).
	# Buscar SOLO en el MenuContainer (que es donde se crean los sub-tabs),
	# no en el resto del tree, para evitar falsos positivos.
	var sub_tab_names: Array[StringName] = [
		&"ElementAllocator", &"AttributeAllocator", &"WeaponAllocator"
	]
	var open_sub: Control = null
	var layer2: Node = get_tree().root.find_child("MenuContainer", true, false)
	if layer2 == null:
		layer2 = get_tree().root.find_child("MenuLayer", true, false)
	if layer2 == null:
		layer2 = get_tree().root.find_child("SkillBookContainer", true, false)  # backwards compat
	if layer2 == null:
		layer2 = get_tree().root.find_child("SkillBookLayer", true, false)  # backwards compat
	if layer2:
		for sub_name in sub_tab_names:
			var sub: Node = layer2.get_node_or_null(String(sub_name))
			if sub and sub is Control and sub.visible:
				open_sub = sub
				break

	# Si algo está visible (master o sub-tab), ciérralo todo.
	if _menu_instance.visible or open_sub != null:
		# Cerrar sub-tab primero (si existe).
		if open_sub and open_sub.has_method("close"):
			open_sub.close()
		# Luego cerrar el master (si está visible).
		if _menu_instance.visible and _menu_instance.has_method("close"):
			_menu_instance.close()
		# Si el master estaba OCULTO (caso: usuario cambió a un sub-tab y
		# luego presionó Share desde allí), reabrirlo en lugar de dejar
		# el juego paused sin UI. Esto es la UX esperada: Share desde un
		# sub-tab = "salir del sub-tab y volver al master".
		elif not _menu_instance.visible and _menu_instance.has_method("open"):
			_menu_instance.open()
		return

	# Nada visible: abrir el master.
	if _menu_instance.has_method("open"):
		_menu_instance.open()
		if _menu_instance.has_method("focus_skill_list"):
			_menu_instance.focus_skill_list()
