class_name EnvironmentObject
extends StaticBody3D

enum Material { STONE, METAL, WOOD, CRYSTAL, VEGETAL, GLASS, BONE, FLESH }

const WEIGHT_PICKUP_MAX := 5.0

const MATERIAL_RESISTANCE: Dictionary = {
	Material.STONE: 200.0,
	Material.METAL: 350.0,
	Material.WOOD: 80.0,
	Material.CRYSTAL: 60.0,
	Material.VEGETAL: 30.0,
	Material.GLASS: 25.0,
	Material.BONE: 70.0,
	Material.FLESH: 20.0,
}

@export var object_name: String = "Object"
@export var weight: float = 1.0
@export var durability: float = 1.0
@export var max_durability: float = 100.0
@export var material: Material = Material.WOOD
@export var flammable: bool = false
@export var conductive: bool = false
@export var fragile: bool = false
@export var is_pickup: bool = false
@export var breakable: bool = true

var _current_durability: float
var _broken: bool = false

signal broken(obj: Node)
signal damaged(obj: Node, amount: float, remaining: float)
signal picked_up(by: Node)
signal moved(by: Node, distance: float)


func _ready() -> void:
	_current_durability = max_durability
	if not is_in_group("env_objects"):
		add_to_group("env_objects")
	if collision_layer == 0:
		collision_layer = 1 << 4
	if collision_mask == 1:
		collision_mask = 1


func get_material_resistance() -> float:
	return float(MATERIAL_RESISTANCE.get(material, 100.0))


func take_damage(amount: float, source: Node = null) -> float:
	if _broken:
		return 0.0
	_current_durability -= amount
	durability = clampf(_current_durability / max_durability, 0.0, 1.0)
	damaged.emit(self, amount, _current_durability)
	if breakable and _current_durability <= 0.0:
		_break(source)
	return amount


func resist(skill_power: float) -> Dictionary:
	if _broken:
		return { "can_affect": false, "resisted_by": 1.0, "effective": 0.0 }
	var mat_res: float = get_material_resistance()
	var resisted: float = clampf(mat_res / max(1.0, mat_res + skill_power), 0.0, 0.95)
	if fragile:
		resisted *= 0.5
	return {
		"can_affect": skill_power > 0.0 and resisted < 0.95,
		"resisted_by": resisted,
		"effective": skill_power * (1.0 - resisted),
	}


func _break(source: Node = null) -> void:
	_broken = true
	broken.emit(self)
	queue_free()


func can_be_picked_up() -> bool:
	return is_pickup and not _broken and weight <= WEIGHT_PICKUP_MAX


func is_too_heavy_to_move(skill_move_power: float) -> bool:
	return weight > max(1.0, skill_move_power * 2.0)
