class_name BossResource
extends CharacterResource


@export var tier: int = 1
@export var weakness_element: StringName = &""
@export var weakness_mult: float = 1.5
@export var resistance_element: StringName = &""
@export var resistance_mult: float = 0.5
@export var custom_damage_modifiers: Dictionary = {}


func get_damage_modifiers() -> Dictionary:
	var mods: Dictionary = {}
	for k in damage_modifiers:
		mods[k] = damage_modifiers[k]
	if weakness_element != &"":
		mods[weakness_element] = weakness_mult
	if resistance_element != &"":
		mods[resistance_element] = resistance_mult
	for k in custom_damage_modifiers:
		mods[k] = custom_damage_modifiers[k]
	return mods


func get_reward() -> int:
	return reward_skill_points
