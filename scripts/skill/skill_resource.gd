## SkillResource — Data layer para una skill del sistema genérico.
##
## Una skill es un Resource data-driven: se define completamente en .tres
## (o vía JSON del MCP) sin código custom. El SkillExecutor lee este resource
## y dispatcha átomos vía EffectLibrary.
##
## Diseño:
## - id, name, type, target_resolver -> identidad
## - designed_max -> los valores "máximos pensados" (techo del balance)
## - atoms -> lista de efectos que componen la skill
## - combo_triggers -> disparadores condicionales
## - costs -> stamina/cooldown/charge_time
## - vfx -> presentación visual/sonido
##
## Validación: ver SkillValidator y data/contracts/skill_instance_schema.md
class_name SkillResource
extends Resource

@export var id: StringName = &""
@export var name: String = ""
@export_multiline var description: String = ""
@export_multiline var flavor_text: String = ""
@export var category: StringName = &"ranged_projectile"
## "damage" o "control". Determina qué átomos son válidos.
@export var type: StringName = &"damage"

## Resolver de target. Formato: { "kind": "...", "params": { ... } }
@export var target_resolver: Dictionary = {}

## Valores máximos diseñados por el LLM. El sistema clampea y usa como techo.
## Claves comunes: amount, dpt, radius, duration, cooldown, stamina, charge_time,
## knockback, crit_chance, speed, hitbox_radius, lifetime, count, shield_amount,
## heal_amount, hot_per_tick, magnitude.
@export var designed_max: Dictionary = {}

## Átomos que componen la skill. Cada uno: { "type": "...", "params": {...},
## "applies_to_target": "primary|all_in_aoe|chain_target|carrier" }.
@export var atoms: Array[Dictionary] = []

## Combo triggers (max 2). Cada uno: { "when": "on_skill_used|...", "condition": "...",
## "trigger_skill_id": "..." }.
@export var combo_triggers: Array[Dictionary] = []

## Costos. Claves: stamina (float), cooldown (float, seconds),
## charge_time (float, seconds), hp_cost (float).
@export var costs: Dictionary = {}

## VFX. Claves: cast_sound, cast_particle, hit_sound, screen_text.
@export var vfx: Dictionary = {}

## Tag para UI. No afecta balance.
@export var icon_hint: String = ""


## Helper: lista de stat names que se pueden upgrade.
func get_upgradeable_stats() -> Array[StringName]:
	var stats: Array[StringName] = []
	for k in designed_max.keys():
		stats.append(StringName(k))
	return stats


## Helper: ¿es damage o control?
func is_damage_skill() -> bool:
	return type == &"damage"


func is_control_skill() -> bool:
	return type == &"control"
