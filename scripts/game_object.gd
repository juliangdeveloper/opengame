## game_object.gd — Data-driven interactable object.
##
## Every object in the world that can be affected by skills.
## Properties come from the RuleBook (HP, weight, material, resistances).
## Push works like jump: apply velocity impulse, let physics resolve.
extends StaticBody3D
class_name GameObject

## Object properties (from RuleBook)
@export var object_name: String = "object"
@export var max_hp: float = 10.0
@export var weight: float = 1.0
@export var material_type: String = "wood"
@export var destructible: bool = true

## Effect values (from RuleBook: effect_resistance.json)
## Same variable on caster (multiplies) and target (divides).
## If not defined, defaults to 1.0
@export var push_effect: float = 1.0

var hp: float = 0.0

# === Push physics (like jump: velocity + gravity + friction) ===
var _velocity: Vector3 = Vector3.ZERO
var _friction: float = 5.0  # deceleration per second

signal object_destroyed(object_name: String)


func _ready() -> void:
	hp = max_hp
	add_to_group("game_objects")
	print("[object] %s ready: hp=%.0f weight=%.1f push_effect=%.1f material=%s" % [
		object_name, hp, weight, push_effect, material_type
	])


func _physics_process(delta: float) -> void:
	if _velocity.length() > 0.01:
		var speed: float = _velocity.length()
		var decel: float = _friction * delta
		speed = maxf(0.0, speed - decel)
		_velocity = _velocity.normalized() * speed
		global_position += _velocity * delta


## Called by hitbox.gd or any skill that pushes.
## Formula: final_force = base_force × caster.push_effect / target.push_effect
func apply_push(force: float, direction: Vector3, caster_push_effect: float = 1.0) -> void:
	var effective_force: float = force * caster_push_effect / maxf(push_effect, 0.01)
	var push_dir: Vector3 = direction.normalized()
	push_dir.y = 0
	_velocity += push_dir * effective_force
	print("[object] %s pushed: base=%.1f caster_effect=%.1f target_effect=%.1f → final=%.1f" % [
		object_name, force, caster_push_effect, push_effect, effective_force
	])


## Called by hitbox.gd or any skill that deals damage.
func take_damage(amount: float, _source: Node = null) -> void:
	if not destructible:
		return
	hp = maxf(0.0, hp - amount)
	print("[object] %s took %.0f damage → hp=%.0f/%.0f" % [
		object_name, amount, hp, max_hp
	])
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	print("[object] %s DESTROYED" % object_name)
	object_destroyed.emit(object_name)
	queue_free()
