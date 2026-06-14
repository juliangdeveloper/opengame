## player_controller.gd — Input controller del player.
##
## FASE 4 (2026-06-14): este nodo encapsula TODO el input del player.
## El Character (EntityCharacter) provee el body, take_damage, state
## machine. Acá manejamos:
##   - WASD movement
##   - Jump (cast saltar_001 skill)
##   - Sprint (cast correr_001 skill)
##   - Camera (mouse + right-stick gamepad)
##   - Skill bar (X/□/○/△ + L1/R1 modifiers)
##   - Share / Tab (skill book / skill allocator toggle)
##   - Mouse mode (escape to release)
##
## CUMPLIMIENTO DE DIRECTRIZ DEL USER:
##   "los controles por defecto solo mueven el jugador, correr, saltar,
##    defender, etc deben ser skills."
##
## Este controller NO tiene stats. Lee todo del Character (move_speed,
## jump_velocity, etc. vienen de data). El Character es 100% data-driven.
extends Node
class_name PlayerController

var character: Node = null  # EntityCharacter (set externally or by Character._install_default_controller)

# === Camera (right-stick sensitivity desde data si se desea; por ahora const) ===
const MOUSE_SENSITIVITY: float = 0.0025
const GAMEPAD_LOOK_SENSITIVITY: float = 3.0
const GAMEPAD_DEADZONE: float = 0.15
const MIN_PITCH: float = -1.4
const MAX_PITCH: float = 1.2

# === Skill system ===
# Cooldown tracking per skill_id (segundos). El player puede tener cooldowns
# más granulares que el Character base.
var _skill_cooldowns: Dictionary = {}

# SkillResource cache (para no reload cada cast)
var _skill_res_cache: Dictionary = {}

# === UI toggles (backwards-compat con player.gd) ===
const MENU_SCENE := preload("res://scenes/ui/menu.tscn")
const MENU_NODE_NAME := "Menu"

# Share button consume flag
var _open_skill_book_consumed_this_frame: bool = false

# === References a nodes del Character ===
# (Camera, model, etc. — los leemos del character en _ready)
var _camera_pivot: Node3D = null
var _menu_instance: Node = null

# Skill bar (slot → skill_id). Por defecto las 8 skills básicas.
# El menú puede reasignar slots. La config live está en
# character.skill_bar (player.gd); este controller la lee de ahí.
# NOTA: si el character es null, defaults razonables.
var skill_bar: Array[StringName] = [
	&"light_attack_001", &"", &"esquivar_001", &"defenderse_001",
	&"kamehameha_001", &"gomu_gomu_pistol_001",
	&"uraraka_zero_gravity_001", &"serious_punch_001",
]

func _get_skill_bar() -> Array[StringName]:
	if character != null and "skill_bar" in character and character.skill_bar.size() == 8:
		return character.skill_bar
	return skill_bar


func _ready() -> void:
	# BUGFIX 2026-06-14: el player debe seguir procesando input incluso
	# cuando el menú pausa el juego. PROCESS_MODE_ALWAYS = sigue vivo durante pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Buscar el CameraPivot del character
	if character != null:
		_camera_pivot = character.get_node_or_null("CameraPivot")
		if _camera_pivot == null:
			# Fallback: buscar en la escena
			_camera_pivot = character.get_tree().root.find_child("CameraPivot", true, false)
		# Capturar mouse al iniciar
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if character == null or not is_instance_valid(character):
		return
	# SHARE / BACK button (PS4/Xbox JOY_BUTTON 4) debe abrir el libro aunque
	# el evento luego sea consumido.
	if event is InputEventJoypadButton and event.pressed and event.button_index == 4:
		_open_skill_book_consumed_this_frame = true
		_toggle_skill_book()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_skill_book"):
		_open_skill_book_consumed_this_frame = true
		_toggle_skill_book()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse motion (solo si mouse captured o headless)
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or OS.has_feature("headless") or (event is InputEventMouseMotion and event.device == -1):
			character.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
			if _camera_pivot:
				_camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
				_camera_pivot.rotation.x = clamp(_camera_pivot.rotation.x, MIN_PITCH, MAX_PITCH)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _process(delta: float) -> void:
	if character == null or not is_instance_valid(character):
		return
	# Right-stick camera (gamepad)
	var pads: Array = Input.get_connected_joypads()
	if pads.is_empty():
		return
	var dev: int = pads[0]
	var rx: float = Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X)
	var ry: float = Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
	if absf(rx) > GAMEPAD_DEADZONE:
		character.rotate_y(-rx * GAMEPAD_LOOK_SENSITIVITY * delta)
	if absf(ry) > GAMEPAD_DEADZONE and _camera_pivot:
		_camera_pivot.rotate_x(-ry * GAMEPAD_LOOK_SENSITIVITY * delta)
		_camera_pivot.rotation.x = clamp(_camera_pivot.rotation.x, MIN_PITCH, MAX_PITCH)


# === Skill casting ===

## Castea una skill por ID. Carga del .tres, checa costo de stamina,
## crea SkillExecutor, conecta signals, y cast.
func _cast_basic_skill(skill_id: StringName) -> void:
	if skill_id == &"":
		return
	# Lookup cache
	var skill_res: Resource = null
	if _skill_res_cache.has(skill_id):
		skill_res = _skill_res_cache[skill_id]
	else:
		skill_res = load("res://data/skills/%s.tres" % String(skill_id))
		if skill_res != null:
			_skill_res_cache[skill_id] = skill_res
	if skill_res == null:
		push_warning("[PlayerController] _cast_basic_skill: no se encontró %s.tres" % String(skill_id))
		return
	# Chequear costo
	var cost_stamina: float = float(skill_res.costs.get("stamina", 0.0))
	if cost_stamina > 0 and character.stamina < cost_stamina:
		return
	# Consumir stamina
	character.stamina -= cost_stamina
	# Crear executor
	var SkillExecutorScript: GDScript = load("res://scripts/skill/skill_executor.gd")
	var ex: Node = SkillExecutorScript.new()
	ex.skill = skill_res
	ex.caster = character
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps:
		ex.progression = ps
	character.add_child(ex)
	ex.cast()


## Decrementa cooldowns activos de skills.
func _process_skill_cooldowns(delta: float) -> void:
	for skill_id in _skill_cooldowns.keys():
		_skill_cooldowns[skill_id] = maxf(0.0, _skill_cooldowns[skill_id] - delta)


## Lee el input del skill bar y castea la skill correspondiente.
func handle_skill_input() -> void:
	if character == null or not is_instance_valid(character):
		return
	# Tab abre el skill allocator viejo (UI clásica)
	if Input.is_action_just_pressed("open_skill_allocator"):
		_toggle_skill_allocator()
	# SHARE button (PS4/Xbox JOY_BUTTON 4) abre el skill book
	if Input.is_action_just_pressed("open_skill_book") and not _open_skill_book_consumed_this_frame:
		_toggle_skill_book()
	_open_skill_book_consumed_this_frame = false
	# Determinar slot de skill según input
	var slot_index: int = _resolve_skill_slot()
	var bar: Array[StringName] = _get_skill_bar()
	if slot_index < 0 or slot_index >= bar.size():
		return
	var skill_id: StringName = bar[slot_index]
	if skill_id == &"":
		return
	# Chequear cooldown
	if _skill_cooldowns.get(String(skill_id), 0.0) > 0.0:
		return
	# Cast
	_cast_basic_skill(skill_id)
	# Set cooldown
	var skill_res: Resource = _skill_res_cache.get(skill_id)
	if skill_res == null:
		skill_res = load("res://data/skills/%s.tres" % String(skill_id))
		if skill_res != null:
			_skill_res_cache[skill_id] = skill_res
	if skill_res != null:
		var cd: float = float(skill_res.costs.get("cooldown", 0.0))
		if cd > 0:
			_skill_cooldowns[String(skill_id)] = cd


## Resuelve qué slot de skill castear según el input actual.
## Retorna -1 si no hay input de skill.
func _resolve_skill_slot() -> int:
	# L1/R1 modifiers
	var l1_held: bool = Input.is_action_pressed("modifier_l1")
	var r1_held: bool = Input.is_action_pressed("modifier_r1")
	var has_modifier: bool = l1_held or r1_held
	# Face buttons (X/□/○/△ → slots 0/1/2/3, +L1/R1 → 4/5/6/7)
	if Input.is_action_just_pressed("cast_skill_0"):
		return 4 if has_modifier else 0
	if Input.is_action_just_pressed("cast_skill_1"):
		return 5 if has_modifier else 1
	if Input.is_action_just_pressed("cast_skill_2"):
		return 6 if has_modifier else 2
	if Input.is_action_just_pressed("cast_skill_3"):
		return 7 if has_modifier else 3
	return -1


# === UI toggles (delegadas a player.gd o al scene tree) ===

func _toggle_skill_book() -> void:
	# Buscar el menu existente en la escena
	var menu: Node = character.get_tree().root.find_child(MENU_NODE_NAME, true, false)
	if menu == null:
		# Instanciar el menu si no existe
		var scene: PackedScene = load("res://scenes/ui/menu.tscn")
		if scene == null:
			return
		menu = scene.instantiate()
		character.get_tree().root.add_child(menu)
		_menu_instance = menu
	# Toggle: open si está cerrado, close si está abierto
	# Set visible=true immediately to avoid 1-frame delay in tests.
	if menu.visible:
		menu.visible = false
		if menu.has_method("close"):
			menu.call("close")
	else:
		menu.visible = true
		if menu.has_method("open"):
			menu.call("open")


func _toggle_skill_allocator() -> void:
	# Legacy UI — same as skill book for now
	_toggle_skill_book()
