## character_resource.gd — Data class for ANY character in the game.
##
## FASE 4 (2026-06-14): Unifica player, enemy, boss, NPC, ally en un solo
## schema. La ÚNICA diferencia técnica entre el player y un personaje
## del juego es `ai_controlled: bool`:
##   - ai_controlled = false → PlayerController drives it (input)
##   - ai_controlled = true  → AIController drives it (AI)
##
## El resto (skills, weapons, attributes, elements, damage modifiers)
## es EXACTAMENTE el mismo sistema. Mismo SkillResource, mismo
## WeaponResource, mismo AttributeComponent. Sin "boss skills" ni
## "enemy weapons" — todos vienen del mismo data layer que usa el
## player.
##
## Esto cumple la directiva del user:
##   "Refinar los jefes y enemigos para que sean full data driven.
##    Los skills y armas son JSON iguales a los del jugador.
##    La única diferencia técnica ... es un simple bool [ai_controlled].
##    Elimina cualquier dato quemado en el código."
class_name CharacterResource
extends Resource


# === Identidad ===
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""     # estrategia hint
@export var inspiration: String = ""               # "Dragon Ball Z", "LOTR", etc.

# === LA diferencia técnica ===
@export var ai_controlled: bool = true             # false = player, true = AI


# === Combat stats (escalables vía skill_points) ===
@export var max_hp: float = 100.0
@export var max_stamina: float = 50.0


# === Movement stats ===
@export var move_speed: float = 5.0
@export var turn_speed: float = 6.0
@export var detection_range: float = 12.0
@export var attack_range: float = 2.6
@export var lose_range: float = 18.0


# === Timings (state machine durations) ===
@export var windup_duration: float = 0.55
@export var active_duration: float = 0.18
@export var recover_duration: float = 0.75
@export var stagger_duration: float = 1.30
@export var respawn_delay: float = 999.0           # 999 = no respawnea (boss)


# === Loadout (mismo data layer que el player) ===
@export var weapon_id: StringName = &""            # WeaponResource.id (puede ser &"" para unarmed)
@export var skill_ids: Array[StringName] = []      # Skills que puede usar
@export var skill_weights: Array[float] = []       # Pesos paralelos a skill_ids


# === Progression (mismo sistema que el player) ===
## Atributos del personaje (phys_dmg, strength, burn_res, etc.) — alimenta
## AttributeComponent. Si está vacío, el personaje usa 0 puntos en todos
## los stats (sin bonus).
@export var attribute_allocations: Dictionary = {}

## Elementos (fire, water, etc.) — alimenta ResistanceComponent. Si está
## vacío, sin resistances especiales.
@export var element_allocations: Dictionary = {}


# === Damage modifiers (multiplicadores de daño recibido por elemento) ===
## Ej: {&"fire": 1.5, &"water": 0.6} = débil a fire (+50% dmg), resistente
## a water (-40% dmg). Aplicados en el actor que RECIBE el daño.
@export var damage_modifiers: Dictionary = {}


# === AI / behavior (solo si ai_controlled=true) ===
@export_enum("aggressive", "defensive", "caster", "summoner", "evasive",
		"berserker", "trickster", "tactical", "patrol", "stationary")
var behavior: String = "aggressive"

@export var aggression: float = 0.5                # 0.0 pasivo, 1.0 ultra-agresivo
@export var preferred_range: StringName = &"any"   # "melee", "ranged", "any"
@export var reaction_time_sec: float = 0.6         # tiempo entre decisiones AI


# === Visual ===
@export var base_color: Color = Color(0.8, 0.15, 0.2)
@export var model_hint: String = ""                # "goblin", "humanoid", "boss_frieza", etc.


# === Recompensa (player/enemy = 0, boss = >0) ===
@export var reward_skill_points: int = 0
@export var reward_experience: int = 0


# === Helpers ===

## Devuelve los pesos de skills, normalizados (1.0 default si vacío).
func get_skill_weights() -> Array[float]:
	if skill_weights.is_empty():
		var defaults: Array[float] = []
		for i in skill_ids.size():
			defaults.append(1.0)
		return defaults
	return skill_weights


## Devuelve true si este character respawnea después de morir.
## (boss = false, regular enemy = true).
func can_respawn() -> bool:
	return respawn_delay < 999.0


## ¿Es un boss? Un boss es un enemy AI con reward_skill_points > 0.
## (Los regular enemies no dan reward.)
func is_boss() -> bool:
	return ai_controlled and reward_skill_points > 0


## ¿Es un enemy/boss AI? (subsume boss)
func is_enemy() -> bool:
	return ai_controlled


## ¿Es el player?
func is_player() -> bool:
	return not ai_controlled
