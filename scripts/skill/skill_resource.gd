class_name SkillResource
extends Resource

@export var id: StringName = &""
@export var name: String = ""
@export_multiline var description: String = ""
@export_multiline var flavor_text: String = ""
@export var category: StringName = &"ranged_projectile"
@export var type: StringName = &"damage"

@export var target_resolver: Dictionary = {}

@export var designed_max: Dictionary = {}

@export var atoms: Array[Dictionary] = []

@export var combo_triggers: Array[Dictionary] = []

@export var costs: Dictionary = {}

@export var vfx: Dictionary = {}

@export var icon_hint: String = ""


func get_upgradeable_stats() -> Array[StringName]:
	var stats: Array[StringName] = []
	for k in designed_max.keys():
		stats.append(StringName(k))
	return stats


func is_damage_skill() -> bool:
	return type == &"damage"


func is_control_skill() -> bool:
	return type == &"control"
