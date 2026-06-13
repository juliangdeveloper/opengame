## boss_enemy.gd — Enemigo especializado para el sistema de Objetivos.
##
## En vez del ataque melee básico del EnemyAI, este boss:
## 1. Tiene una lista de skills (BossResource.skill_ids)
## 2. Elige una skill (weighted random) y la CASTA con SkillExecutor
## 3. Usa los MISMOS átomos que el player (kamehameha, gomu_gomu, light_attack, etc)
## 4. Castea sobre el player (target_resolver.kind = "player" patcheado dinámicamente)
##
## Reusa el state machine del EnemyAI para windup/active/recover, pero el
## "active" carga y castea una skill en vez de aplicar damage directo.
##
## El BossEnemy vive en un BossFight (caben los que sea en play.tscn) o
## puede ser spawneado dinámicamente por ObjectivesManager.
extends CharacterBody3D
class_name BossEnemy

## BossResource (id, hp, skills, behavior, etc)
@export var boss_data: Resource = null

## Escalado de dificultad. 1.0 = stats del boss_data, 1.5 = +50% hp/dmg.
@export var difficulty_mult: float = 1.0

## Si true, castea skills. Si false, fallback a melee.
@export var use_skills: bool = true

# === Stats (seteadas por _ready() desde boss_data) ===
var max_hp: float = 100.0
var hp: float = 100.0
var skill_ids: Array[StringName] = []
var skill_weights: Array[float] = []
var base_color: Color = Color(0.7, 0.0, 0.0)

# === AI State (similar a EnemyAI pero CASTING) ===
enum State { IDLE, CHASE, CHOOSE_SKILL, WINDUP, ACTIVE, RECOVER, DEAD }
var state: State = State.IDLE
var state_timer: float = 0.0
var current_skill_id: StringName = &""
var is_dying: bool = false
var respawn_delay: float = 999.0  # Boss NO respawnea

## Damage modifiers (weakness/resistance del BossResource)
var damage_modifiers: Dictionary = {}

## Spawneo en
var spawn_position: Vector3

# === Tiempos (se setean desde boss_data.reaction_time_sec) ===
var reaction_time: float = 0.6
var skill_cast_time: float = 0.55  # duración del "active" — para que el boss use el skill
var skill_recover_time: float = 1.0

# === Nodes ===
@onready var model: Node3D = $Model
@onready var mesh_instance: MeshInstance3D = $Model/Body
@onready var hit_collision: CollisionShape3D = $AttackArea/CollisionShape3D
@onready var attack_area: Area3D = $AttackArea
@onready var label_hp: Label3D = $Model/HP_Label
@onready var label_parry: Label3D = $Model/ParryLabel

var player: Node3D = null
var _base_mat: StandardMaterial3D
var _hitbox_mat: StandardMaterial3D
const HITBOX_WINDUP := Color(1.0, 0.3, 0.1, 0.4)
const HITBOX_ACTIVE := Color(1.0, 0.15, 0.1, 0.55)

# Boss-specific signals
signal boss_killed(boss_id: StringName)
signal boss_damaged(amount: float, hp_left: float)


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("bosses")
	spawn_position = global_position
	_apply_boss_data()
	_setup_visuals()
	# Find player lazily
	player = get_tree().root.find_child("Player", true, false)
	print("[boss] %s ready id=%s hp=%.0f skills=%d behavior=%s" % [
		name, String(boss_data.id) if boss_data else "(none)", hp, skill_ids.size(),
		String(boss_data.behavior) if boss_data else "n/a"
	])


func _apply_boss_data() -> void:
	if boss_data == null:
		push_warning("[boss] no boss_data assigned, using defaults")
		return
	# Cargar stats
	max_hp = float(boss_data.max_hp) * difficulty_mult
	hp = max_hp
	skill_ids = boss_data.skill_ids.duplicate()
	skill_weights = boss_data.get_skill_weights()
	damage_modifiers = boss_data.get_damage_modifiers()
	reaction_time = float(boss_data.reaction_time_sec)
	# Color: derive from inspiration
	var title_hash: int = hash(String(boss_data.display_name))
	var hue: float = float(title_hash % 360) / 360.0
	base_color = Color.from_hsv(hue, 0.7, 0.85)
	# Tweak: si tiene weakness fire, color rojo; etc
	if boss_data.weakness_element == &"light":
		base_color = Color(0.6, 0.0, 0.7)
	elif boss_data.weakness_element == &"fire":
		base_color = Color(0.3, 0.5, 0.9)


func _setup_visuals() -> void:
	if model and mesh_instance:
		_base_mat = StandardMaterial3D.new()
		_base_mat.albedo_color = base_color
		mesh_instance.material_override = _base_mat
		# Make the boss a bit bigger to signal it's a boss
		model.scale = Vector3(1.3, 1.3, 1.3)
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


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().root.find_child("Player", true, false)
		if player == null:
			return
	if state == State.DEAD:
		return
	state_timer -= delta
	match state:
		State.IDLE: _state_idle()
		State.CHASE: _state_chase(delta)
		State.CHOOSE_SKILL: _state_choose_skill()
		State.WINDUP: _state_windup()
		State.ACTIVE: _state_active()
		State.RECOVER: _state_recover()
	# Gravity
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y < 0:
		velocity.y = 0
	move_and_slide()
	_update_hp_label()
	if global_position.y < -10.0 and not is_dying:
		_die()


# === State machine ===

func _state_idle() -> void:
	velocity.x *= 0.5
	velocity.z *= 0.5
	if _dist_to_player() < 12.0:
		_enter_chase()


func _state_chase(delta: float) -> void:
	var d := _dist_to_player()
	if d > 18.0:
		_enter_idle()
		return
	if d <= 8.0:
		_enter_choose_skill()
		return
	var to := (player.global_position - global_position)
	to.y = 0
	if to.length() > 0.01:
		to = to.normalized()
		var target_yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 6.0 * delta)
		velocity.x = to.x * 2.6
		velocity.z = to.z * 2.6


func _state_choose_skill() -> void:
	# Pick a skill via weighted random
	current_skill_id = _pick_skill()
	if current_skill_id == &"":
		# No skills, fallback to basic attack
		_enter_recover()
		return
	_enter_windup()


func _state_windup() -> void:
	velocity.x *= 0.7
	velocity.z *= 0.7
	if state_timer <= 0.0:
		_enter_active()


func _state_active() -> void:
	velocity.x = 0
	velocity.z = 0
	# Cast the skill on the player
	if state_timer <= 0.0 or current_skill_id == &"":
		_enter_recover()
		return
	# Cast happens ONCE at the start of ACTIVE
	# (Use a one-shot flag stored in state_timer: 0.99+ means we haven't cast yet)
	# Simpler: track via a local. We cast when entering ACTIVE.
	# (Implemented in _enter_active().)


func _state_recover() -> void:
	velocity.x *= 0.5
	velocity.z *= 0.5
	if state_timer <= 0.0:
		if _dist_to_player() < 12.0:
			_enter_choose_skill()
		else:
			_enter_chase()


func _enter_idle() -> void: state = State.IDLE
func _enter_chase() -> void: state = State.CHASE

func _enter_choose_skill() -> void:
	state = State.CHOOSE_SKILL
	state_timer = reaction_time
	if attack_area and hit_collision:
		hit_collision.disabled = true
	if attack_area:
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd: hd.visible = false

func _enter_windup() -> void:
	state = State.WINDUP
	state_timer = skill_cast_time * 0.6
	if attack_area:
		attack_area.monitoring = false
		if hit_collision: hit_collision.disabled = true
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd:
			hd.material_override.albedo_color = HITBOX_WINDUP
			hd.visible = true
	print("[boss] %s windup skill=%s" % [name, String(current_skill_id)])

func _enter_active() -> void:
	state = State.ACTIVE
	state_timer = skill_cast_time * 0.4
	# CAST THE SKILL
	_cast_skill(current_skill_id)
	if attack_area:
		attack_area.monitoring = true
		if hit_collision: hit_collision.disabled = false
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd:
			hd.material_override.albedo_color = HITBOX_ACTIVE
			hd.visible = true
	print("[boss] %s active skill=%s" % [name, String(current_skill_id)])

func _enter_recover() -> void:
	state = State.RECOVER
	state_timer = skill_recover_time
	if attack_area:
		attack_area.monitoring = false
		if hit_collision: hit_collision.disabled = true
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd: hd.visible = false


# === Skill casting ===

func _cast_skill(skill_id: StringName) -> void:
	if skill_id == &"":
		return
	if not use_skills:
		return
	# Load the skill resource
	var skill_path := "res://data/skills/%s.tres" % String(skill_id)
	var skill: Resource = load(skill_path)
	if skill == null:
		push_warning("[boss] %s skill %s not found" % [name, skill_id])
		return
	# Patch the target_resolver to "player" or "player_aoe" so it targets the player
	var original_resolver: Dictionary = skill.target_resolver
	var patched: Dictionary = original_resolver.duplicate(true)
	if String(patched.get("kind", "")) in ["aoe", "beam", "self_aoe", "nearest_npc_in_range"]:
		patched["kind"] = "player_aoe"
		if not patched.has("params"):
			patched["params"] = {}
		if not (patched["params"] as Dictionary).has("position"):
			(patched["params"] as Dictionary)["position"] = "in_front_of_caster"
	else:
		patched["kind"] = "player"
	_cast_atoms_directly(skill, patched)


## Bypass SkillExecutor para mantener parcheado target_resolver:
## Itera atoms, llama EffectLibrary.apply_atom con targets = [player] explícito.
func _cast_atoms_directly(skill: Resource, resolver: Dictionary) -> void:
	# Construir targets — siempre [player]
	var targets: Array[Node] = []
	if is_instance_valid(player):
		targets.append(player)
	# Si el resolver es player_aoe, expandir a todos en player group en radio
	if resolver.get("kind", "") == "player_aoe":
		var radius: float = float(resolver.get("params", {}).get("radius", 6.0))
		var center: Vector3 = global_position
		var r2 := radius * radius
		for n in get_tree().get_nodes_in_group("player"):
			if not is_instance_valid(n) or not n is Node3D:
				continue
			if (n as Node3D).global_position.distance_squared_to(center) <= r2:
				if n not in targets:
					targets.append(n)
	# SkillExecutor: crear uno, setear caster/progression, castear.
	var ex_script: GDScript = load("res://scripts/skill/skill_executor.gd")
	if ex_script == null:
		push_warning("[boss] SkillExecutor script not found")
		return
	var ex: Node = ex_script.new()
	ex.skill = skill
	ex.caster = self
	# Patched: hacer override del resolver via un wrapper skill
	# Para no mutar el .tres, duplicamos el resource en memoria
	var patched_skill: Resource = skill.duplicate()
	(patched_skill as Resource).set("target_resolver", resolver)
	ex.skill = patched_skill
	# Progression: usar el global si está
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps:
		ex.progression = ps
	# Add to tree, then cast
	add_child(ex)
	ex.cast()
	# The executor auto-destroys itself after 0.1s


## Pesa-random pick a skill from skill_ids using skill_weights.
func _pick_skill() -> StringName:
	if skill_ids.is_empty():
		return &""
	var weights: Array[float] = skill_weights
	if weights.size() != skill_ids.size():
		weights = []
		for i in skill_ids.size():
			weights.append(1.0)
	var total: float = 0.0
	for w in weights:
		total += w
	var roll: float = randf() * total
	var acc: float = 0.0
	for i in skill_ids.size():
		acc += weights[i]
		if roll <= acc:
			return skill_ids[i]
	return skill_ids[skill_ids.size() - 1]


# === Damage interface ===

func take_damage(amount: float, source: Node = null, element: StringName = &"physical") -> void:
	if state == State.DEAD:
		return
	var base_amount: float = float(amount)
	var modified_amount: float = base_amount
	if element != &"" and not damage_modifiers.is_empty():
		var mult: float = float(damage_modifiers.get(element, 1.0))
		modified_amount = base_amount * mult
	hp -= modified_amount
	_flash()
	print("[boss] %s hit dmg=%.1f (raw=%.1f elem=%s mult=%.2f) hp=%.1f" % [
		name, modified_amount, base_amount, element,
		float(damage_modifiers.get(element, 1.0)), hp
	])
	boss_damaged.emit(modified_amount, hp)
	if hp <= 0.0:
		_die()


func _die() -> void:
	if is_dying:
		return
	is_dying = true
	state = State.DEAD
	hp = 0.0
	if attack_area:
		attack_area.monitoring = false
		if hit_collision: hit_collision.disabled = true
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd: hd.visible = false
	if model:
		model.visible = false
	collision_layer = 0
	collision_mask = 0
	var boss_id_str: StringName = &""
	if boss_data:
		boss_id_str = boss_data.id
	print("[boss] %s DEAD id=%s" % [name, String(boss_id_str)])
	boss_killed.emit(boss_id_str)


# === Helpers ===

func _dist_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return INF
	return global_position.distance_to(player.global_position)


func _flash() -> void:
	if not _base_mat:
		return
	var orig := _base_mat.albedo_color
	_base_mat.albedo_color = Color(1.0, 0.5, 0.2)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self) and _base_mat:
		_base_mat.albedo_color = orig


func _update_hp_label() -> void:
	if is_instance_valid(label_hp):
		label_hp.text = "%d/%d" % [int(max(0, hp)), int(max_hp)]
		if is_instance_valid(get_viewport().get_camera_3d()):
			var cam := get_viewport().get_camera_3d()
			label_hp.look_at(cam.global_position, Vector3.UP)
			label_hp.rotate_object_local(Vector3.UP, PI)
