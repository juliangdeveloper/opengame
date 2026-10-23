class_name CharacterResource
extends Resource


@export var id: StringName = &""
@export var display_name: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var inspiration: String = ""

@export var ai_controlled: bool = true


@export var max_hp: float = 100.0
@export var max_stamina: float = 50.0
@export var weight: float = 1.0
@export var push_effect: float = 1.0
@export var vitality: float = 1.0


@export var move_speed: float = 5.0
@export var turn_speed: float = 6.0
@export var detection_range: float = 12.0
@export var attack_range: float = 2.6
@export var lose_range: float = 18.0


@export var windup_duration: float = 0.55
@export var active_duration: float = 0.18
@export var recover_duration: float = 0.75
@export var stagger_duration: float = 1.30
@export var respawn_delay: float = 999.0


@export var weapon_id: StringName = &""
@export var skill_ids: Array[StringName] = []
@export var skill_weights: Array[float] = []


@export var attribute_allocations: Dictionary = {}

@export var element_allocations: Dictionary = {}


@export var damage_modifiers: Dictionary = {}


@export_enum("aggressive", "defensive", "caster", "summoner", "evasive",
		"berserker", "trickster", "tactical", "patrol", "stationary")
var behavior: String = "aggressive"

@export var aggression: float = 0.5
@export var preferred_range: StringName = &"any"
@export var reaction_time_sec: float = 0.6


@export var base_color: Color = Color(0.8, 0.15, 0.2)
@export var flash_color: Color = Color(1.0, 0.5, 0.2)
@export var model_hint: String = ""
@export var body_shape: StringName = &"capsule"
@export var body_height: float = 1.8
@export var body_radius: float = 0.35
@export var size_scale: float = 1.0
@export var head_color: Color = Color(1, 1, 1)
@export var has_head: bool = true


@export var attack_damage: float = 0.0


@export var reward_skill_points: int = 0
@export var reward_experience: int = 0



func get_skill_weights() -> Array[float]:
	if skill_weights.is_empty():
		var defaults: Array[float] = []
		for i in skill_ids.size():
			defaults.append(1.0)
		return defaults
	return skill_weights


func can_respawn() -> bool:
	return respawn_delay < 999.0


func is_boss() -> bool:
	return ai_controlled and reward_skill_points > 0


func is_enemy() -> bool:
	return ai_controlled


func is_player() -> bool:
	return not ai_controlled
