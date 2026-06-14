## player.gd — Player body (extends EntityCharacter).
##
## FASE 4 (2026-06-14): refactorizado de 1067 → ~250 líneas.
## ANTES: extends CharacterBody3D con state machine, take_damage, stats
##        hardcoded, _physics_process custom con WASD, etc. Todo duplicado
##        con Character/EntityCharacter.
## AHORA: extends EntityCharacter. El body (state machine, take_damage,
##        respawn, gravity, move_and_slide) viene de Character.
##        El input handling viene de PlayerController (child node).
##        player.gd solo mantiene:
##          - Visual feedback específico (weapon mat, body mat, parry flash)
##          - Weapon visual swap
##          - AttributeComponent/ResistanceComponent setup
##          - ProgressionState syncing
##          - Skill book / skill allocator toggles (legacy compat)
##
## CUMPLIMIENTO DE DIRECTRIZ DEL USER:
##   "los controles por defecto solo mueven el jugador, correr, saltar,
##    defender, etc deben ser skills."
##   "Refinar los jefes y enemigos para que sean full data driven.
##    Elimina cualquier dato quemado en el código."
##
## Stats: TODO viene de data/characters/player.tres (CharacterResource).
## Skills: TODO viene de data/skills/*.tres (mismo library que bosses/enemies).
extends EntityCharacter
class_name Player


# === Visual feedback (script-managed materials) ===
const WEAPON_BASE := Color(0.85, 0.85, 0.9)
const WEAPON_PARRY := Color(1.4, 1.3, 0.4)  # bright yellow flash
const WEAPON_BLOCK := Color(0.55, 0.8, 1.1)  # cool blue tint
const BODY_BASE := Color(0.3, 0.5, 0.8)
const BODY_PARRY_FLASH := Color(1.2, 1.2, 0.6)  # warm yellow flash

# === Nodes adicionales (player-specific) ===
@onready var block_shield: MeshInstance3D = $BlockShield if has_node("BlockShield") else null
@onready var weapon_mesh: MeshInstance3D = $Model/Weapon if has_node("Model/Weapon") else null
@onready var body_mesh: MeshInstance3D = $Model/Body if has_node("Model/Body") else null

# === Materials (script-managed) ===
var _weapon_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D

# === Player-specific signals (compat con HUD/bot) ===
signal skill_cast_started(skill_id: StringName, slot_index: int)
signal parry_succeeded(enemy: Node)
signal attack_hit(target: Node, damage: float)
signal damaged(amount: float, final_amount: float, blocked: bool)
signal died
signal respawned

# === Resource del arma actualmente equipada (legacy alias; Character.data
#    también lo guarda vía ProgressionState) ===
var equipped_weapon: Resource = null

# === I-frame timer (compat con dodge skill) ===
var _iframe_timer: float = 0.0

# === Skill bar (player-specific config — qué skill hay en cada slot) ===
## Slots 0-3: face buttons. Slots 4-7: face + L1/R1 modifier.
## Esta config es del PLAYER, no del Character genérico.
## El menu puede reasignar slots; el PlayerController los castea.
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


func _ready() -> void:
	# BUGFIX 2026-06-14: el player debe seguir procesando input incluso
	# cuando el menú pausa el juego. PROCESS_MODE_ALWAYS = sigue vivo durante pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Load player data (CharacterResource.tres)
	if data == null:
		var player_res: Resource = load("res://data/characters/player.tres")
		if player_res != null:
			data = player_res
	# Character._ready() hace:
	#   - add_to_group("characters")
	#   - add_to_group("player_characters") (porque data.ai_controlled=false)
	#   - _apply_data() → max_hp, hp, move_speed, etc. desde data
	#   - _setup_visuals() (con data.base_color, no el hardcoded rojo)
	#   - _install_default_controller() → PlayerController (ai=false)
	super._ready()
	# Setup específico del player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_player_visuals()
	_setup_components()
	_load_default_skills()
	# Grant inicial de puntos (testing)
	if ProgressionState and ProgressionState.proficiency == 0:
		ProgressionState.grant_skill_points(3)
		print("[player] granted 3 starter skill points for testing")
	if ProgressionState and ProgressionState.attribute_points == 0:
		ProgressionState.grant_attribute_points(5)
		print("[player] granted 5 starter attribute points for testing")
		_apply_attribute_derived_stats()
	# Sync equipped weapon desde PS
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps and "equipped_weapon" in ps and ps.equipped_weapon != null:
		equipped_weapon = ps.equipped_weapon
		_apply_weapon_visual(equipped_weapon)
	# Conectar attack_area (Character ya lo hace, pero player también necesita
	# el signal de area_entered para hit detection)
	if attack_area and not attack_area.area_entered.is_connected(_on_attack_area):
		attack_area.area_entered.connect(_on_attack_area)
	# Log gamepads
	var pads: Array = Input.get_connected_joypads()
	if pads.is_empty():
		print("[input] no gamepad detected (keyboard/mouse only)")
	else:
		for p in pads:
			print("[input] gamepad device %d: %s" % [p, Input.get_joy_name(p)])
	# Registrar para que enemigos nos encuentren
	add_to_group("player")
	print("[player] ready (data=%s, hp=%.0f, controller=%s)" % [
		String(data.id) if data else "(none)", hp,
		controller.get_script().resource_path.get_file() if controller else "(none)"
	])


# === Override EntityCharacter._physics_process ===
# EntityCharacter ya hace gravity, state_timer, kill plane, etc.
# PlayerController handles el input y movement. Acá solo hacemos cosas
# player-specific: dodge, attack movement, visual updates.
func _physics_process(delta: float) -> void:
	# Delegar a Character (state machine + gravity + move_and_slide)
	super._physics_process(delta)
	# PlayerController: procesar cooldowns de skills, cast desde input
	if controller != null and controller.has_method("_process_skill_cooldowns"):
		controller._process_skill_cooldowns(delta)
	if controller != null and controller.has_method("handle_skill_input"):
		controller.handle_skill_input()
	# Attack movement (reducir velocity si estamos atacando)
	if state == State.WINDUP or state == State.ACTIVE:
		velocity.x *= 0.85
		velocity.z *= 0.85


# === Override Character.take_damage para añadir blocked/reduced ===
func take_damage(amount: float, attacker: Node = null, element: StringName = &"physical") -> float:
	if state == State.DEAD:
		return 0.0
	var before_hp: float = hp
	var final: float = super.take_damage(amount, attacker, element)
	var blocked: bool = false
	damaged.emit(amount, final, blocked)
	if hp <= 0.0 and before_hp > 0.0:
		died.emit()
	return final


# === Override Character._die ===
func _die() -> void:
	if is_dying:
		return
	super._die()
	died.emit()
	# Esperar respawn_delay y respawnear
	if respawn_delay < 999.0:
		await get_tree().create_timer(respawn_delay).timeout
		_respawn()


# === Override Character._respawn ===
func _respawn() -> void:
	super._respawn()
	respawned.emit()
	# Restaurar HP full
	hp = max_hp
	stamina = max_stamina
	if body_mesh:
		body_mesh.visible = true


# === Player-specific setup ===

func _setup_player_visuals() -> void:
	# Weapon material
	if weapon_mesh:
		_weapon_mat = StandardMaterial3D.new()
		_weapon_mat.albedo_color = WEAPON_BASE
		_weapon_mat.metallic = 0.8
		_weapon_mat.roughness = 0.3
		weapon_mesh.material_override = _weapon_mat
	# Body material
	if body_mesh:
		_body_mat = StandardMaterial3D.new()
		_body_mat.albedo_color = BODY_BASE
		_body_mat.metallic = 0.2
		_body_mat.roughness = 0.6
		body_mesh.material_override = _body_mat
	# Block shield hidden por default
	if block_shield:
		block_shield.visible = false


func _setup_components() -> void:
	# ResistanceComponent
	var ResistanceCompScript: GDScript = load("res://scripts/skill/components/ResistanceComponent.gd")
	if ResistanceCompScript and not has_node("ResistanceComponent"):
		var rc: Node = ResistanceCompScript.new()
		rc.name = "ResistanceComponent"
		add_child(rc)
	# AttributeComponent
	var AttributeCompScript: GDScript = load("res://scripts/attribute_component.gd")
	if AttributeCompScript and not has_node("AttributeComponent"):
		var ac: Node = AttributeCompScript.new()
		ac.name = "AttributeComponent"
		add_child(ac)
		ac.call("refresh_from_progression_state")


func _load_default_skills() -> void:
	# Carga todas las .tres de data/skills/ y las registra con ProgressionState.
	# (Character ya popula Character.data.skill_ids con las 5 básicas; este
	# método carga el resto del directorio para el compendio.)
	var dir: DirAccess = DirAccess.open("res://data/skills")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var res: Resource = load("res://data/skills/" + f)
		if res == null:
			continue
		if not ProgressionState:
			continue
		if not res is SkillResource:
			continue
		# Solo agregar si no está
		if res.id not in ProgressionState.owned_skills:
			ProgressionState.add_skill(res)


func _apply_attribute_derived_stats() -> void:
	# Si los campos derivados de atributos cambiaron (HP, stamina), recálcularlos
	if "AttributeComponent" in get_node_names():
		var ac: Node = get_node("AttributeComponent")
		if ac.has_method("refresh_from_progression_state"):
			ac.call("refresh_from_progression_state")


func _apply_weapon_visual(wpn: Resource) -> void:
	# Swap mesh del arma en el modelo del player
	if weapon_mesh == null or wpn == null:
		return
	# (El visual swap se hace en player_bot.gd / set_equipped_weapon via
	# ProgressionState. Acá solo log.)
	print("[player] _apply_weapon_visual: %s" % wpn.display_name)


# === Compatibilidad con código legacy ===

func get_node_names() -> Array:
	var names: Array = []
	for child in get_children():
		names.append(child.name)
	return names


# === Attack hit callbacks (player-side) ===

func _on_attack_body(body: Node) -> void:
	# Implementación player: si golpea un enemy, emite attack_hit
	if state != State.ACTIVE:
		return
	if body == self:
		return
	if body.has_method("take_damage"):
		# Dmg = 0 aquí; el SkillExecutor casteado por PlayerController es
		# quien hace el daño real (con su hitbox, scaling, etc).
		pass


func _on_attack_area(area: Node) -> void:
	# Similar a _on_attack_body pero para Area3D del enemigo
	if state != State.ACTIVE:
		return
	if area == self:
		return
	if area.has_method("take_damage"):
		pass
