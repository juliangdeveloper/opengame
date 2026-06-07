extends CharacterBody3D
## NPC — Enemigo que usa el sistema de skills data-driven del jugador.
##
## A diferencia de enemy.gd (AI manual de melee), este NPC es un Saibaman
## débil que:
##   - Tiene poca HP (60) y muere rápido
##   - Detecta al player en detection_range
##   - Cuando está en attack_range, con probabilidad skill_use_chance castea
##     una skill data-driven (configurable desde editor) usando un
##     SkillExecutor como el player.
##   - Si no castea skill, hace un melee básico (damage 8).
##   - No respawnea — al morir se queue_free.
##
## Diseñado para que un dev/MCP pueda crear un NPC fácil de testear
## instanciando scenes/npc_easy.tscn, sin tocar código.
##
## IMPORTANTE: usa preloads en vez de class_name para ser --script-runnable
## y para evitar colisión con el autoload ProgressionState.

const SkillResource := preload("res://scripts/skill/skill_resource.gd")
const SkillExecutorScript := preload("res://scripts/skill/skill_executor.gd")

# Estado del NPC
enum State { IDLE, CHASE, CAST, DEAD }

# --- Tunables (editor-exposed) ---
@export_group("Stats")
@export var max_hp := 60.0
@export var move_speed := 1.8
@export var detection_range := 8.0
@export var lose_range := 14.0
@export var attack_range := 1.8
@export var melee_damage := 8.0
@export var attack_cooldown := 1.5
@export var respawn_delay := 0.0  # 0 = no respawnea

@export_group("Skill")
## Skill .tres que el NPC castea. Si está vacío, usa light_attack como fallback.
@export var skill: SkillResource = null
## Probabilidad de castear skill en vez de melee cuando está en rango (0..1).
@export var skill_use_chance := 0.5
## Cooldown del skill cast (segundos). Independiente del cooldown de la skill misma.
@export var skill_cooldown := 4.0
## Tiempo de windup del skill cast antes de aplicar la skill (segundos).
@export var cast_windup := 1.0
## Duración de la ventana activa de hit (después del windup, antes de recuperar).
@export var cast_active := 0.2
## Duración de la recovery después del cast.
@export var cast_recovery := 0.3

@export_group("Visuals")
@export var drop_label := "Saibaman"
@export var color_base := Color(0.5, 0.9, 0.4)
@export var color_flash := Color(1.0, 1.0, 0.4)

# --- State ---
var state: State = State.IDLE
var hp: float
var state_timer: float = 0.0
var is_dying: bool = false
var _attack_cooldown_left: float = 0.0
var _skill_cooldown_left: float = 0.0

# --- Nodes (configurados en .tscn) ---
@onready var model: Node3D = $Model
@onready var body_mesh: MeshInstance3D = $Model/Body
@onready var hp_label: Label3D = $Model/HP_Label
@onready var parry_label: Label3D = $Model/ParryLabel
@onready var attack_area: Area3D = $AttackArea
@onready var hit_collision: CollisionShape3D = $AttackArea/CollisionShape3D
@onready var hitbox_debug: MeshInstance3D = $AttackArea/HitboxDebug
@onready var executor: Node = $SkillExecutor

# --- Internals ---
var player: Node3D = null
var _base_mat: StandardMaterial3D
var _hitbox_mat: StandardMaterial3D

# Colores del hitbox (mismo estilo que enemy.gd)
const HITBOX_WINDUP := Color(1.0, 0.9, 0.2, 0.45)   # amarillo (CAST windup)
const HITBOX_ACTIVE := Color(1.0, 0.2, 0.1, 0.55)   # rojo (CAST active)


func _ready() -> void:
	hp = max_hp
	# Fallback: si nadie asignó una skill desde el editor, cargar light_attack.tres
	if skill == null:
		skill = load("res://data/skills/light_attack.tres") as SkillResource
		if skill != null:
			print("[npc] %s: no skill assigned, fallback a %s" % [name, skill.id])
	# Materiales para body + hitbox
	_base_mat = StandardMaterial3D.new()
	_base_mat.albedo_color = color_base
	_base_mat.metallic = 0.1
	_base_mat.roughness = 0.7
	body_mesh.material_override = _base_mat
	# Hitbox debug: sphere transparente que cambia de color en windup/active
	# (mismo estilo que enemy.gd: transparency=1, shading=0, cull=2)
	_hitbox_mat = StandardMaterial3D.new()
	_hitbox_mat.transparency = 1
	_hitbox_mat.shading_mode = 0
	_hitbox_mat.cull_mode = 2
	_hitbox_mat.albedo_color = HITBOX_WINDUP
	hitbox_debug.material_override = _hitbox_mat
	hitbox_debug.visible = false
	attack_area.monitoring = false
	hit_collision.disabled = true
	# Añadir al grupo de enemigos para que player + AI los encuentre
	add_to_group("enemies")
	# Cargar executor con la skill
	if executor != null and skill != null:
		executor.skill = skill
		executor.caster = self
		executor.progression = ProgressionState
	# Buscar player (puede no existir en editor preview)
	player = get_tree().root.find_child("Player", true, false)
	print("[npc] %s ready hp=%.0f skill=%s" % [name, hp, skill.id if skill else "<null>"])


func _physics_process(delta: float) -> void:
	if is_dying or state == State.DEAD:
		return
	# Re-buscar player si se perdió (respawn, scene change, etc.)
	if player == null or not is_instance_valid(player):
		player = get_tree().root.find_child("Player", true, false)
		if player == null:
			return
	# Cooldowns
	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left -= delta
	if _skill_cooldown_left > 0.0:
		_skill_cooldown_left -= delta
	state_timer -= delta
	match state:
		State.IDLE:
			_state_idle()
		State.CHASE:
			_state_chase(delta)
		State.CAST:
			_state_cast()
		_:
			pass
	# Gravedad (igual que player)
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y < 0:
		velocity.y = 0
	move_and_slide()
	_update_hp_label()
	# Kill plane: si cae del mundo, muere (no respawnea)
	if global_position.y < -10.0 and not is_dying:
		print("[npc] %s fell off the world -> die" % name)
		_die()


# --- Estados ---

func _state_idle() -> void:
	velocity.x *= 0.5
	velocity.z *= 0.5
	var d := _dist_to_player()
	if d < detection_range:
		_enter_chase()


func _state_chase(delta: float) -> void:
	var d := _dist_to_player()
	if d > lose_range:
		_enter_idle()
		return
	if d <= attack_range and _attack_cooldown_left <= 0.0:
		_decide_attack_or_skill()
		return
	# Moverse hacia el player
	var to := (player.global_position - global_position)
	to.y = 0
	if to.length() > 0.01:
		to = to.normalized()
		var target_yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 6.0 * delta)
		model.rotation.y = target_yaw - rotation.y
		velocity.x = to.x * move_speed
		velocity.z = to.z * move_speed


func _state_cast() -> void:
	# Mantenerse quieto durante el cast
	velocity.x *= 0.5
	velocity.z *= 0.5
	if state_timer <= 0.0:
		_enter_cast_active()


# --- Decisión: ¿skill o melee? ---

func _decide_attack_or_skill() -> void:
	var can_skill: bool = (skill != null) and (_skill_cooldown_left <= 0.0) and (executor != null) and not bool(executor.get("_is_casting"))
	if can_skill and randf() < skill_use_chance:
		_enter_cast_windup()
	else:
		_enter_melee()


# --- State transitions ---

func _enter_idle() -> void:
	state = State.IDLE
	attack_area.monitoring = false
	hit_collision.disabled = true
	hitbox_debug.visible = false
	# Reset hitbox color por si acaso
	_hitbox_mat.albedo_color = HITBOX_WINDUP


func _enter_chase() -> void:
	state = State.CHASE
	attack_area.monitoring = false
	hit_collision.disabled = true
	hitbox_debug.visible = false
	# Reset hitbox color
	_hitbox_mat.albedo_color = HITBOX_WINDUP


func _enter_melee() -> void:
	# Melee básico: hit instantáneo de melee_damage al player
	state = State.IDLE  # vuelve a idle, no hay recover (rápido)
	_attack_cooldown_left = attack_cooldown
	if is_instance_valid(player) and player.has_method("take_damage"):
		player.take_damage(melee_damage, self)
		print("[npc] %s melee_hit dmg=%.1f target=%s" % [name, melee_damage, player.name])
	else:
		print("[npc] %s melee_missed (no player)" % name)


func _enter_cast_windup() -> void:
	state = State.CAST
	state_timer = cast_windup
	attack_area.monitoring = false
	hit_collision.disabled = true
	# Visual: hitbox amarillo durante el windup
	_hitbox_mat.albedo_color = HITBOX_WINDUP
	hitbox_debug.visible = true
	print("[npc] %s cast_windup skill=%s t=%.2f" % [name, skill.id, cast_windup])


func _enter_cast_active() -> void:
	# Windup terminó: castear la skill via executor.
	# El executor se encarga de resolver targets y aplicar átomos.
	state = State.IDLE
	state_timer = 0.0
	# Cooldown global de skill (separado del cooldown interno del executor)
	_skill_cooldown_left = skill_cooldown
	_attack_cooldown_left = attack_cooldown
	# Visual: hitbox rojo durante el active
	_hitbox_mat.albedo_color = HITBOX_ACTIVE
	hitbox_debug.visible = true
	# Reactivamos la hitbox del NPC durante el active
	attack_area.monitoring = true
	hit_collision.disabled = false
	# Llamar al executor (es async; corre sin await)
	if executor != null:
		executor.cast()
		print("[npc] %s cast_active skill=%s" % [name, skill.id])
	# Pequeña espera para que el active se vea, luego recover
	await get_tree().create_timer(cast_active).timeout
	if not is_instance_valid(self) or is_dying:
		return
	attack_area.monitoring = false
	hit_collision.disabled = true
	hitbox_debug.visible = false
	# Recovery: bloquea movimiento durante cast_recovery
	await get_tree().create_timer(cast_recovery).timeout


# --- Damage interface (compatible con player/enemy/dummy) ---

func take_damage(amount: float, source: Node = null) -> void:
	if is_dying or state == State.DEAD:
		return
	hp -= amount
	_flash()
	print("[npc] %s hit dmg=%.1f hp=%.1f state=%s" % [name, amount, hp, State.keys()[state]])
	if hp <= 0.0:
		_die()


func is_attack_active() -> bool:
	# Compatible con player.gd parry check
	return state == State.CAST and state_timer <= cast_active and state_timer > 0.0


func is_attack_winding_up() -> bool:
	return state == State.CAST and state_timer > cast_active


func on_parried(_source: Node) -> void:
	# Sin parry visual custom: el NPC no tiene stagger elaborado.
	# El player.gd check usa is_attack_active/winding_up, así que con esto
	# basta para que parry sea funcional.
	print("[npc] %s parried" % name)


# --- Internals ---

func _dist_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return INF
	return global_position.distance_to(player.global_position)


func _flash() -> void:
	_base_mat.albedo_color = color_flash
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self) and _base_mat:
		_base_mat.albedo_color = color_base


func _update_hp_label() -> void:
	if is_instance_valid(hp_label):
		hp_label.text = "%s\nHP: %d/%d" % [drop_label, int(max(0, hp)), int(max_hp)]
		# Billboard hacia la cámara
		if is_instance_valid(get_viewport().get_camera_3d()):
			var cam := get_viewport().get_camera_3d()
			hp_label.look_at(cam.global_position, Vector3.UP)
			hp_label.rotate_object_local(Vector3.UP, PI)


func _on_attack_body(body: Node) -> void:
	# El executor también puede aplicar daño, pero el AttackArea del NPC
	# sirve como hitbox de respaldo (mismo patrón que enemy.gd).
	if not is_instance_valid(body) or body == self:
		return
	if body.has_method("take_damage") and (body is Node3D):
		body.take_damage(melee_damage, self)
		print("[npc] %s area_hit body=%s dmg=%.1f" % [name, body.name, melee_damage])


func _die() -> void:
	if is_dying:
		return
	is_dying = true
	state = State.DEAD
	hp = 0.0
	attack_area.monitoring = false
	hit_collision.disabled = true
	hitbox_debug.visible = false
	collision_layer = 0
	collision_mask = 0
	model.visible = false
	print("[npc] %s DEAD" % name)
	# Sin respawn: queue_free directo.
	# (respawn_delay exportado por compatibilidad, pero en NPC siempre es 0)
	if respawn_delay > 0.0:
		await get_tree().create_timer(respawn_delay).timeout
	if is_instance_valid(self):
		queue_free()
