## hitbox.gd — Trigger hitbox that pushes AND damages overlapping bodies.
## Supports optional movement (projectile behavior) via movement_velocity.
extends Area3D

var push_force: float = 0.0
var push_direction: Vector3 = Vector3.FORWARD
var push_effect: float = 1.0      # caster's push_effect
var caster_vitality: float = 1.0  # caster's vitality
var base_damage: float = 0.0
var lifetime: float = 0.5  # default 0.5s per RuleBook

# Movement support (projectile behavior)
var movement_velocity: Vector3 = Vector3.ZERO  # if != ZERO, hitbox moves each frame

var _has_hit: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_timeout)


func _physics_process(delta: float) -> void:
	# Move if movement_velocity is set (projectile behavior)
	if movement_velocity != Vector3.ZERO:
		global_position += movement_velocity * delta


func _on_body_entered(body: Node3D) -> void:
	if _has_hit:
		return
	if not is_inside_tree():
		return
	if body == null or not body.is_inside_tree():
		return
	# Push
	if body is CharacterBody3D:
		var dir: Vector3 = push_direction.normalized()
		dir.y = 0
		body.velocity += dir * push_force * push_effect
		# Player: 3 args (amount, attacker, element)
		if base_damage > 0.0 and body.has_method("take_damage"):
			body.take_damage(base_damage, null, &"")
		_has_hit = true
	elif body.has_method("apply_push"):
		body.apply_push(push_force, push_direction, push_effect)
		# GameObject: 4 args (amount, attacker, element, caster_vitality)
		if base_damage > 0.0 and body.has_method("take_damage"):
			body.take_damage(base_damage, null, &"", caster_vitality)
		_has_hit = true


func _on_lifetime_timeout() -> void:
	if is_inside_tree():
		queue_free()
