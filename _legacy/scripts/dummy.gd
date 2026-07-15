extends CharacterBody3D
## Dummy enemy for testing combat. Static (no AI), takes damage, dies.

@export var max_hp := 100.0
@export var flash_color := Color(1, 0.3, 0.3)
@export var base_color := Color(0.7, 0.2, 0.2)

var hp: float

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var mat: StandardMaterial3D = StandardMaterial3D.new()


func _ready() -> void:
	hp = max_hp
	mat.albedo_color = base_color
	mesh_instance.material_override = mat


func take_damage(amount: float, source: Node = null) -> void:
	hp -= amount
	# visual feedback
	mat.albedo_color = flash_color
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(self) and mat:
		mat.albedo_color = base_color

	if hp <= 0:
		die()


func die() -> void:
	# Simple death: collapse and queue_free
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	await get_tree().create_timer(0.6).timeout
	queue_free()
