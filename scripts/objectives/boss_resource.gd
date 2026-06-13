## boss_resource.gd — Data class for an objective boss.
##
## Un "objetivo" es un villano predefinido con stats/skills/armas fijas.
## El jugador lo enfrenta via ObjectivesManager; al derrotarlo recibe
## skill_points (recompensa fija, escalando por tier).
##
## Diseñados para ser MUY diferentes entre sí — cada uno requiere una
## estrategia distinta. El AI del boss (BossEnemy.gd) decide cuál skill
## usar basándose en su behavior + skill_weights + la situación actual.
class_name BossResource
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var title: String = ""            # "El Tirano del Espacio"
@export var description: String = ""      # Estrategia hint para el jugador
@export var inspiration: String = ""      # "Dragon Ball Z"

## Combat
@export var max_hp: float = 100.0
@export var tier: int = 1                 # 1-5 (afecta recompensa)
@export var weapon_id: StringName = &""   # WeaponResource.id (puede ser &"" para unarmed)
@export var skill_ids: Array[StringName] = []  # Skills que puede usar

## AI / behavior
@export_enum("aggressive", "defensive", "caster", "summoner", "evasive", "berserker", "trickster", "tactical")
var behavior: String = "aggressive"
@export var aggression: float = 0.5       # 0.0 pasivo, 1.0 ultra-agresivo
@export var preferred_range: StringName = &"any"  # "melee", "ranged", "any"
@export var reaction_time_sec: float = 0.6

## Strategy
## Elemento que el boss es VULNERABLE (toma daño extra)
@export var weakness_element: StringName = &""
@export var weakness_mult: float = 1.5
## Elemento que el boss RESISTE (toma daño reducido)
@export var resistance_element: StringName = &""
@export var resistance_mult: float = 0.5

## Ponderación de skills (índice paralelo a skill_ids)
## 1.0 = usa esa skill con la misma frecuencia que las demás
## >1.0 = la prefiere, <1.0 = la usa poco
@export var skill_weights: Array[float] = []

## Otros modificadores elementales (opcional, se mergean con los de mission)
@export var custom_damage_modifiers: Dictionary = {}

## Recompensa
@export var reward_skill_points: int = 5  ## Muchos — esto es el incentivo


## Devuelve la recompensa efectiva (skill_points + bonus por tier si lo deseas).
func get_reward() -> int:
	return reward_skill_points


## Devuelve los modificadores elementales completos: weakness + resistance + custom.
func get_damage_modifiers() -> Dictionary:
	var mods: Dictionary = {}
	if weakness_element != &"":
		mods[weakness_element] = weakness_mult
	if resistance_element != &"":
		mods[resistance_element] = resistance_mult
	for k in custom_damage_modifiers:
		mods[k] = custom_damage_modifiers[k]
	return mods


## Devuelve los pesos de skills, normalizados (1.0 default si vacío).
func get_skill_weights() -> Array[float]:
	if skill_weights.is_empty():
		var defaults: Array[float] = []
		for i in skill_ids.size():
			defaults.append(1.0)
		return defaults
	return skill_weights
