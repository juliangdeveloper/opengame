## hitbox.gd — Trigger hitbox that pushes overlapping bodies.
extends Area3D

var push_force: float = 0.0
var push_direction: Vector3 = Vector3.FORWARD
var push_effect: float = 1.0  # caster's push_effect stat
var lifetime: float = 0.1

var _has_hit: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_timeout)


func _on_body_entered(body: Node3D) -> void:
	if _has_hit:
		return
	if body is CharacterBody3D:
		var force_dir: Vector3 = push_direction.normalized()
		force_dir.y = 0
		body.velocity += force_dir * push_force * push_effect
		_has_hit = true
	elif body.has_method("apply_push"):
		body.apply_push(push_force, push_direction, push_effect)
		_has_hit = true


func _on_lifetime_timeout() -> void:
	if is_inside_tree():
		queue_free()
