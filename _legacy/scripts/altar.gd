extends StaticBody3D

const MAX_ALIVE := 3

@export var npc_scene: PackedScene
@export var spawn_offset := Vector3(0, 0, 2.0)
@export var interaction_radius := 2.5
@export var interaction_min_distance := 3.0
@export var base_prompt := "Summon Saibaman"

var _player_in_range: bool = false
var _spawned: Array[Node] = []
var _prompt_label: Label3D
var _last_input_was_gamepad: bool = false
var _last_prompt_text: String = ""

@onready var interaction_area: Area3D = $InteractionArea
@onready var model: Node3D = $Model
@onready var crystal: MeshInstance3D = $Model/TopCrystal
@onready var omni_light: OmniLight3D = $OmniLight3D


func _ready() -> void:
	add_to_group("interactables")
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)
	if model != null:
		_prompt_label = model.get_node_or_null("SummonSaibaman")
	if not _prompt_label and model:
		_prompt_label = Label3D.new()
		_prompt_label.name = "SummonSaibaman"
		_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_prompt_label.fixed_size = true
		_prompt_label.no_depth_test = true
		_prompt_label.position = Vector3(0, 2.0, 0)
		model.add_child(_prompt_label)
	_update_prompt()
	set_process_input(true)
	print("[altar] %s ready base_prompt=%s" % [name, base_prompt])


func _process(_delta: float) -> void:
	if not _player_in_range:
		return
	if Input.is_action_just_pressed("interact"):
		spawn_npc()
	_update_prompt()
	if is_instance_valid(crystal):
		var t := Time.get_ticks_msec() / 1000.0
		var k := 0.8 + 0.2 * sin(t * 3.0)
		crystal.scale = Vector3.ONE * k


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_last_input_was_gamepad = true
	elif event is InputEventKey and event.pressed:
		_last_input_was_gamepad = false


func _update_prompt() -> void:
	if not _prompt_label:
		return
	var button: String = "X" if _last_input_was_gamepad else "E"
	var text: String = "[%s] %s" % [button, base_prompt]
	if text != _last_prompt_text:
		_prompt_label.text = text
		_last_prompt_text = text



func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		print("[altar] %s player_in_range" % name)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		print("[altar] %s player_out_of_range" % name)



func spawn_npc() -> void:
	if npc_scene == null:
		push_warning("[altar] %s: npc_scene not set" % name)
		return
	var player := get_tree().root.find_child("Player", true, false)
	if player == null or not is_instance_valid(player):
		print("[altar] %s spawn_failed reason=no_player" % name)
		return
	var d := global_position.distance_to(player.global_position)
	if d > interaction_min_distance:
		print("[altar] %s spawn_failed reason=too_far d=%.2f" % [name, d])
		return
	_cleanup_spawned()
	if _spawned.size() >= MAX_ALIVE:
		print("[altar] %s spawn_failed reason=max_alive" % name)
		return
	var npc: Node = npc_scene.instantiate()
	get_tree().current_scene.add_child(npc)
	npc.global_position = global_position + spawn_offset
	_spawned.append(npc)
	print("[altar] %s summoned npc total_alive=%d" % [name, _spawned.size()])


func _cleanup_spawned() -> void:
	var alive: Array[Node] = []
	for n in _spawned:
		if is_instance_valid(n):
			alive.append(n)
	_spawned = alive
