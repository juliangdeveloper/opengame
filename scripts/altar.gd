extends StaticBody3D
## Altar — Punto interactuable que spawnea NPCs (Saibamen) cuando el player
## se acerca y presiona la acción de interacción.
##
## Detección de rango: un Area3D hijo (InteractionArea) con CollisionShape3D
## sphere radius=interaction_radius. Conectado a body_entered / body_exited.
##
## Input: el action "interact" (definido en project.godot: tecla E + gamepad A).
##
## UX:
##   - Al estar en rango, muestra un Label3D con el prompt "[E] Summon Saibaman"
##   - Al presionar interact, spawnea un NPC (configurable vía npc_scene) en
##     spawn_offset. Máximo 3 NPCs vivos (los queue_freed se eliminan del tracking).
##   - El player debe estar a menos de 3m del altar (además del rango) para que
##     el spawn sea válido (anti-exploit a distancia).
##
## IMPORTANTE: usa preloads en vez de class_name para ser --script-runnable
## y para evitar colisión con el autoload ProgressionState.

const MAX_ALIVE := 3  # máximo de NPCs vivos spawneados por altar

# --- Tunables (editor-exposed) ---
@export var npc_scene: PackedScene
@export var spawn_offset := Vector3(0, 0, 2.0)
@export var interaction_radius := 2.5
@export var interaction_min_distance := 3.0
@export var prompt_text := "[E] Summon Saibaman"

# --- State ---
var _player_in_range: bool = false
var _spawned: Array[Node] = []  # NPCs spawneados por este altar (vivos o muertos)
var _prompt_label: Label3D

# --- Nodes (configurados en .tscn) ---
@onready var interaction_area: Area3D = $InteractionArea
@onready var model: Node3D = $Model
@onready var crystal: MeshInstance3D = $Model/TopCrystal
@onready var omni_light: OmniLight3D = $OmniLight3D


func _ready() -> void:
	add_to_group("interactables")
	# Configurar Area3D detection
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)
	# Cargar prompt_label y aplicar texto
	if model != null:
		_prompt_label = model.get_node_or_null("SummonSaibaman")
	if _prompt_label:
		_prompt_label.text = prompt_text
	print("[altar] %s ready prompt=%s" % [name, prompt_text])


func _process(_delta: float) -> void:
	if not _player_in_range:
		return
	if Input.is_action_just_pressed("interact"):
		spawn_npc()
	# Animar cristal: pulso suave
	if is_instance_valid(crystal):
		var t := Time.get_ticks_msec() / 1000.0
		var k := 0.8 + 0.2 * sin(t * 3.0)
		crystal.scale = Vector3.ONE * k


# --- Rango ---

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		print("[altar] %s player_in_range" % name)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		print("[altar] %s player_out_of_range" % name)


# --- Spawn ---

func spawn_npc() -> void:
	if npc_scene == null:
		push_warning("[altar] %s: npc_scene not set" % name)
		return
	# Buscar al player
	var player := get_tree().root.find_child("Player", true, false)
	if player == null or not is_instance_valid(player):
		print("[altar] %s spawn_failed reason=no_player" % name)
		return
	# Verificar distancia real (no solo rango de trigger)
	var d := global_position.distance_to(player.global_position)
	if d > interaction_min_distance:
		print("[altar] %s spawn_failed reason=too_far d=%.2f" % [name, d])
		return
	# Limpiar queue_freed del tracking
	_cleanup_spawned()
	# Cap de NPCs vivos
	if _spawned.size() >= MAX_ALIVE:
		print("[altar] %s spawn_failed reason=max_alive" % name)
		return
	# Spawnear el NPC
	var npc: Node = npc_scene.instantiate()
	get_tree().current_scene.add_child(npc)
	# Posición: global del altar + spawn_offset
	npc.global_position = global_position + spawn_offset
	# Tracking
	_spawned.append(npc)
	print("[altar] %s summoned npc total_alive=%d" % [name, _spawned.size()])


## Limpia entradas queue_freed del array de tracking.
func _cleanup_spawned() -> void:
	var alive: Array[Node] = []
	for n in _spawned:
		if is_instance_valid(n):
			alive.append(n)
	_spawned = alive
