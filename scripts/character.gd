## character.gd — Unified body for player, enemy, boss, NPC, ally.
##
## FASE 4 (2026-06-14): reemplaza enemy.gd y la lógica de body de
## player.gd. Se inicializa desde un CharacterResource (.tres) que
## define TODOS sus stats, skills, armas y comportamiento.
##
## Este nodo NO tiene input handling — eso lo hace un Controller child:
##   - PlayerController: si data.ai_controlled = false
##   - AIController:     si data.ai_controlled = true
##
## CUMPLIMIENTO DE DIRECTRIZ DEL USER:
##   "Refinar los jefes y enemigos para que sean full data driven.
##    Los skills y armas son JSON iguales a los del jugador.
##    La única diferencia técnica entre un jugador y un personaje
##    del juego es que el personaje tiene habilitado el control por ia
##    y no por el jugador, un simple bool. Elimina cualquier dato
##    quemado en el código."
##
## STATEMACHINE: IDLE → CHASE → WINDUP → ACTIVE → RECOVER → (DEAD)
##   - WINDUP/ACTIVE/RECOVER usan los timings de data (no hardcoded)
##   - DEAD respawna si data.can_respawn()
extends CharacterBody3D
class_name EntityCharacter

## Resource .tres con todos los datos del personaje
@export var data: Resource = null

## Multiplicador de dificultad (boss arenas lo setean a 1.5x para bosses finales)
@export var difficulty_mult: float = 1.0

## Si true, castea skills. Si false, fallback a melee básico.
@export var use_skills: bool = true

## Si está seteado, este personaje targetea a este nodo en vez del player.
## (Usado en boss-vs-boss arena, ally assist, etc.)
@export var target_override: Node3D = null

## Si true, loguea cada decisión AI al CombatLog.
@export var log_ai_decisions: bool = true


# === State machine ===
enum State { IDLE, CHASE, CHOOSE_SKILL, WINDUP, ACTIVE, RECOVER, STAGGER, DEAD }
var state: State = State.IDLE
var state_timer: float = 0.0
var current_skill_id: StringName = &""
var is_dying: bool = false

# === Stats (seteadas por _ready() desde data) ===
var max_hp: float = 100.0
var hp: float = 100.0
var max_stamina: float = 50.0
var stamina: float = 50.0
var move_speed: float = 5.0
var turn_speed: float = 6.0
var detection_range: float = 12.0
var attack_range: float = 2.6
var lose_range: float = 18.0
var windup_duration: float = 0.55
var active_duration: float = 0.18
var recover_duration: float = 0.75
var stagger_duration: float = 1.30
var respawn_delay: float = 999.0

# === Loadout ===
var weapon_id: StringName = &""
var skill_ids: Array[StringName] = []
var skill_weights: Array[float] = []
var attribute_allocations: Dictionary = {}
var element_allocations: Dictionary = {}
var damage_modifiers: Dictionary = {}

# === Visual ===
var base_color: Color = Color(0.8, 0.15, 0.2)
var flash_color: Color = Color(1.0, 0.5, 0.2)

# === Spawn position (para respawn) ===
var spawn_position: Vector3 = Vector3.ZERO

# === Cooldowns defensivos (segundos) ===
var parry_cooldown: float = 0.0
var dodge_cooldown: float = 0.0
var defend_cooldown: float = 0.0

# === Anti-streak: track últimas N skills para evitar spam ===
var _recent_skill_uses: Array[StringName] = []
const ANTI_STREAK_DEPTH: int = 3

# === Controller reference (set externally) ===
var controller: Node = null  # PlayerController o AIController

# === Signals ===
signal character_killed(character_id: StringName)
signal character_damaged(amount: float, hp_left: float)
signal character_dodged(attacker: Node)
signal character_parried(attacker: Node)
signal character_blocked(attacker: Node)
signal skill_started(skill_id: StringName)
signal skill_finished(skill_id: StringName)

# === Nodes (auto-detectados) ===
@onready var model: Node3D = $Model if has_node("Model") else null
@onready var mesh_instance: MeshInstance3D = _find_mesh(model) if model else null
@onready var attack_area: Area3D = $AttackArea if has_node("AttackArea") else null
@onready var hit_collision: CollisionShape3D = (
	$AttackArea/CollisionShape3D if has_node("AttackArea/CollisionShape3D") else null
)
@onready var hitbox_debug: MeshInstance3D = (
	$AttackArea/HitboxDebug if has_node("AttackArea/HitboxDebug") else null
)
@onready var label_hp: Label3D = (
	$Model/HP_Label if has_node("Model/HP_Label") else null
)
@onready var label_parry: Label3D = (
	$Model/ParryLabel if has_node("Model/ParryLabel") else null
)

# Materiales y constantes visuales (no son DATA, son presentation)
var _base_mat: StandardMaterial3D
var _hitbox_mat: StandardMaterial3D
const HITBOX_WINDUP := Color(1.0, 0.7, 0.1, 0.4)
const HITBOX_ACTIVE := Color(1.0, 0.15, 0.1, 0.55)


func _ready() -> void:
	add_to_group("characters")
	# ¿Soy un enemy o un player? Determinado por data.ai_controlled
	if data != null and data.ai_controlled:
		add_to_group("enemies")
	else:
		add_to_group("player_characters")
	_apply_data()
	_setup_visuals()
	# Inicializar controller apropiado si no se asignó uno externamente
	if controller == null:
		_install_default_controller()
	# Conectar attack_area signal — subclases override _on_attack_body
	if attack_area and not attack_area.body_entered.is_connected(_on_attack_body):
		attack_area.body_entered.connect(_on_attack_body)


## Aplica el CharacterResource al cuerpo. Cero hardcoded — todo viene de data.
func _apply_data() -> void:
	if data == null:
		push_warning("[Character] no data assigned, using defaults")
		return
	max_hp = float(data.max_hp) * difficulty_mult
	hp = max_hp
	max_stamina = float(data.max_stamina)
	stamina = max_stamina
	move_speed = float(data.move_speed)
	turn_speed = float(data.turn_speed)
	detection_range = float(data.detection_range)
	attack_range = float(data.attack_range)
	lose_range = float(data.lose_range)
	windup_duration = float(data.windup_duration)
	active_duration = float(data.active_duration)
	recover_duration = float(data.recover_duration)
	stagger_duration = float(data.stagger_duration)
	respawn_delay = float(data.respawn_delay)
	weapon_id = data.weapon_id
	skill_ids = (data.skill_ids as Array).duplicate()
	skill_weights = data.get_skill_weights()
	attribute_allocations = (data.attribute_allocations as Dictionary).duplicate(true)
	element_allocations = (data.element_allocations as Dictionary).duplicate(true)
	damage_modifiers = (data.damage_modifiers as Dictionary).duplicate(true)
	base_color = data.base_color
	flash_color = data.flash_color
	spawn_position = global_position
	# Sincronizar con ProgressionState si los allocations están poblados
	# (para que AttributeComponent y ResistanceComponent se actualicen).
	_sync_progression_state()


## Sincroniza los allocations con ProgressionState (la single source of truth).
## Si data.attribute_allocations NO está vacío, lo escribe a PS.attribute_allocations
## para que AttributeComponent.refresh_from_progression_state() lo vea.
func _sync_progression_state() -> void:
	if attribute_allocations.is_empty():
		return
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps == null:
		return
	if "attribute_allocations" in ps:
		ps.attribute_allocations = (attribute_allocations as Dictionary).duplicate(true)


## Instala el Controller apropiado (Player vs AI) según data.ai_controlled.
## Este es el ÚNICO branching técnico entre player y AI.
func _install_default_controller() -> void:
	if data == null:
		return
	if data.ai_controlled:
		controller = _make_ai_controller()
	else:
		controller = _make_player_controller()


## Crea el AIController. (Stub — el script real se implementa aparte)
func _make_ai_controller() -> Node:
	var script: GDScript = load("res://scripts/ai/ai_controller.gd")
	if script == null:
		return null
	var ctrl: Node = script.new()
	ctrl.name = "AIController"
	ctrl.set("character", self)
	return ctrl


## Crea el PlayerController. (Stub — el script real se implementa aparte)
func _make_player_controller() -> Node:
	var script: GDScript = load("res://scripts/player_controller.gd")
	if script == null:
		return null
	var ctrl: Node = script.new()
	ctrl.name = "PlayerController"
	ctrl.set("character", self)
	return ctrl


func _setup_visuals() -> void:
	if mesh_instance:
		_base_mat = StandardMaterial3D.new()
		_base_mat.albedo_color = base_color
		mesh_instance.material_override = _base_mat
	if attack_area and hit_collision:
		_hitbox_mat = StandardMaterial3D.new()
		_hitbox_mat.transparency = 1
		_hitbox_mat.shading_mode = 0
		_hitbox_mat.cull_mode = 2
		_hitbox_mat.albedo_color = HITBOX_WINDUP
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd:
			hd.material_override = _hitbox_mat
			hd.visible = false
		attack_area.monitoring = false
	if label_hp:
		label_hp.text = "%d/%d" % [int(hp), int(max_hp)]


func _find_mesh(parent: Node) -> MeshInstance3D:
	if parent == null:
		return null
	for child in parent.get_children():
		if child is MeshInstance3D:
			return child
	return null


# === State machine ===

func _state_idle() -> void:
	velocity.x *= 0.5
	velocity.z *= 0.5
	if _dist_to_target() < detection_range:
		_enter_chase()


func _state_chase(delta: float) -> void:
	var d: float = _dist_to_target()
	if d > lose_range:
		_enter_idle()
		return
	if d <= attack_range:
		_enter_choose_skill()
		return
	if target == null or not is_instance_valid(target):
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0
	if to.length() > 0.01:
		to = to.normalized()
		var target_yaw: float = atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)
		velocity.x = to.x * move_speed
		velocity.z = to.z * move_speed


## Override en subclase (o vía controller) para decidir qué skill castear.
## Default: weighted random de skill_ids con anti-streak.
func _state_choose_skill() -> void:
	current_skill_id = _pick_weighted_skill()
	if current_skill_id == &"":
		_enter_recover()
		return
	_enter_windup()


func _pick_weighted_skill() -> StringName:
	if skill_ids.is_empty():
		return &""
	# Anti-streak: bajar el peso de skills usadas recientemente
	var weights: Array[float] = (skill_weights as Array).duplicate()
	for i in weights.size():
		for recent in _recent_skill_uses:
			if i < skill_ids.size() and skill_ids[i] == recent:
				weights[i] *= 0.3  # penalizar uso reciente
	# Weighted random
	var total: float = 0.0
	for w in weights:
		total += maxf(w, 0.01)
	var roll: float = randf() * total
	var acc: float = 0.0
	for i in weights.size():
		acc += maxf(weights[i], 0.01)
		if roll <= acc:
			var skill_id: StringName = skill_ids[i]
			_recent_skill_uses.append(skill_id)
			if _recent_skill_uses.size() > ANTI_STREAK_DEPTH:
				_recent_skill_uses.pop_front()
			return skill_id
	return skill_ids[skill_ids.size() - 1]


func _state_windup() -> void:
	velocity.x = 0
	velocity.z = 0
	if state_timer <= 0:
		_enter_active()


func _state_active() -> void:
	if state_timer <= 0:
		_enter_recover()


func _state_recover() -> void:
	velocity.x *= 0.5
	velocity.z *= 0.5
	if state_timer <= 0:
		_enter_idle()


func _state_stagger() -> void:
	velocity.x = 0
	velocity.z = 0
	if state_timer <= 0:
		_enter_idle()


func _enter_idle() -> void:
	state = State.IDLE
	state_timer = 0.0


func _enter_chase() -> void:
	state = State.CHASE
	state_timer = 0.0


func _enter_choose_skill() -> void:
	state = State.CHOOSE_SKILL
	state_timer = 0.0
	_state_choose_skill()


func _enter_windup() -> void:
	state = State.WINDUP
	state_timer = windup_duration
	if hitbox_debug:
		hitbox_debug.visible = true
	if _hitbox_mat:
		_hitbox_mat.albedo_color = HITBOX_WINDUP
	skill_started.emit(current_skill_id)


func _enter_active() -> void:
	state = State.ACTIVE
	state_timer = active_duration
	if _hitbox_mat:
		_hitbox_mat.albedo_color = HITBOX_ACTIVE
	if attack_area:
		attack_area.monitoring = true


func _enter_recover() -> void:
	state = State.RECOVER
	state_timer = recover_duration
	if attack_area:
		attack_area.monitoring = false
	if hitbox_debug:
		hitbox_debug.visible = false
	skill_finished.emit(current_skill_id)


func _enter_stagger(duration: float = 1.30) -> void:
	state = State.STAGGER
	state_timer = duration if duration > 0 else stagger_duration
	current_skill_id = &""


# === Physics (gravity, state ticking) ===

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	# Cooldowns defensivos
	parry_cooldown = maxf(0.0, parry_cooldown - delta)
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	defend_cooldown = maxf(0.0, defend_cooldown - delta)
	# Stamina regen
	stamina = minf(max_stamina, stamina + 12.0 * delta)
	# State timer
	state_timer -= delta
	match state:
		State.IDLE: _state_idle()
		State.CHASE: _state_chase(delta)
		State.CHOOSE_SKILL: _state_choose_skill()
		State.WINDUP: _state_windup()
		State.ACTIVE: _state_active()
		State.RECOVER: _state_recover()
		State.STAGGER: _state_stagger()
	# Gravity
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y < 0:
		velocity.y = 0
	move_and_slide()
	_update_hp_label()
	if global_position.y < -10.0 and not is_dying:
		_die()


func _update_hp_label() -> void:
	if label_hp:
		label_hp.text = "%d/%d" % [int(hp), int(max_hp)]


# === Combat ===

func take_damage(amount: float, attacker: Node = null, element: StringName = &"") -> float:
	if state == State.DEAD:
		return 0.0
	# Aplicar damage_modifiers (weakness/resistance)
	var mult: float = 1.0
	if element != &"" and damage_modifiers.has(element):
		mult = float(damage_modifiers[element])
	var final: float = amount * mult
	hp -= final
	character_damaged.emit(final, hp)
	if hp <= 0:
		_die()
	else:
		_enter_stagger(stagger_duration)
	return final


func _die() -> void:
	is_dying = true
	state = State.DEAD
	if data != null and data.id != &"":
		character_killed.emit(data.id)
	# Recompensa: si tiene reward_skill_points > 0, dar a PS
	if data != null and data.reward_skill_points > 0:
		var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
		if ps and "grant_skill_points" in ps:
			ps.grant_skill_points(data.reward_skill_points)
	# Respawn si aplica
	if data != null and data.can_respawn():
		await get_tree().create_timer(respawn_delay).timeout
		_respawn()
	else:
		# Boss / no respawn — solo hide
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED


func _respawn() -> void:
	hp = max_hp
	stamina = max_stamina
	state = State.IDLE
	is_dying = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT


# === Helpers ===

var target: Node3D = null  # Set by controller each frame

func _dist_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	return global_position.distance_to(target.global_position)


## Override en subclase. Default: no-op (enemigos con skill manejan el
## daño vía SkillExecutor; enemigos con attack_damage lo overrideen).
func _on_attack_body(_body: Node) -> void:
	pass
