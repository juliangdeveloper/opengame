## game_object.gd — Data-driven interactable object.
extends StaticBody3D
class_name GameObject

@export var object_name: String = "object"
@export var max_hp: float = 10.0
@export var weight: float = 1.0
@export var material_type: String = "wood"
@export var destructible: bool = true

## Effect values (same name on caster and target; caster multiplies, target divides)
@export var push_effect: float = 1.0
@export var vitality: float = 1.0

var hp: float = 0.0

# === Push physics ===
var _velocity: Vector3 = Vector3.ZERO
var _friction: float = 5.0

signal object_destroyed(object_name: String)

var _floating_hp_scene: PackedScene = preload("res://scenes/floating_hp.tscn")
signal object_hit(object_name: String, current_hp: float, max_hp: float)


func _ready() -> void:
	hp = max_hp
	add_to_group("game_objects")
	print("[object] %s ready: hp=%.0f weight=%.1f push_eff=%.1f vitality=%.1f material=%s" % [
		object_name, hp, weight, push_effect, vitality, material_type
	])


func _physics_process(delta: float) -> void:
	if _velocity.length() > 0.01:
		var speed: float = _velocity.length()
		var decel: float = _friction * delta
		speed = maxf(0.0, speed - decel)
		_velocity = _velocity.normalized() * speed
		global_position += _velocity * delta
		# Report position to SceneManager for RuleBook sync
		if SceneManager != null:
			SceneManager.report_position(self)


## Push: final_force = base × caster.push_effect / target.push_effect
func apply_push(force: float, direction: Vector3, caster_effect: float = 1.0) -> void:
	var effective: float = force * caster_effect / maxf(push_effect, 0.01)
	var dir: Vector3 = direction.normalized()
	dir.y = 0
	_velocity += dir * effective
	print("[object] %s pushed: base=%.1f caster=%.1f target=%.1f → %.1f" % [
		object_name, force, caster_effect, push_effect, effective
	])


## Damage: final_damage = base × caster.vitality / target.vitality
func take_damage(amount: float, _attacker: Node = null, _element: StringName = &"", caster_vitality: float = 1.0) -> float:
	if not destructible:
		return 0.0
	var effective: float = amount * caster_vitality / maxf(vitality, 0.01)
	hp = maxf(0.0, hp - effective)
	print("[object] %s took %.0f damage (base=%.0f caster_vit=%.1f target_vit=%.1f) → hp=%.0f/%.0f" % [
		object_name, effective, amount, caster_vitality, vitality, hp, max_hp
	])
	# Spawn floating HP UI (top of screen)
	var fhp = _floating_hp_scene.instantiate()
	var parent = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(fhp)
	fhp.setup(object_name, hp, max_hp)
	object_hit.emit(object_name, hp, max_hp)
	# Report state to SceneManager for RuleBook sync
	if SceneManager != null:
		SceneManager.report_object_state(self, hp, weight)
	if hp <= 0.0:
		_destroy()
	return effective


func _destroy() -> void:
	print("[object] %s DESTROYED" % object_name)
	# Report destruction to SceneManager before freeing
	if SceneManager != null:
		SceneManager.report_destroyed(self)
	object_destroyed.emit(object_name)
	queue_free()
