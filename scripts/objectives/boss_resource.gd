## boss_resource.gd — DEPRECATED: ahora es un alias/extensión de CharacterResource.
##
## FASE 4 (2026-06-14): Toda la lógica de "boss" es ahora parte de
## CharacterResource (ai_controlled=true + reward_skill_points>0).
##
## BossResource se mantiene SOLO como wrapper de CharacterResource
## para backwards compat con código viejo (objectives_manager.gd,
## boss_enemy.gd) que lee campos legacy como `weakness_element`,
## `resistance_element`, `custom_damage_modifiers`.
##
## Estos campos se MERGEAN en `damage_modifiers: Dictionary` (el
## nuevo schema unificado) via get_damage_modifiers().
##
## Para NUEVO código, usa CharacterResource directamente. BossResource
## no añade NADA funcional — solo campos legacy para no romper.
class_name BossResource
extends CharacterResource


## === Campos legacy (solo para compat con bosses.json parsing) ===
## Nuevo código debería usar `damage_modifiers: Dictionary` directamente.
@export var tier: int = 1
@export var weakness_element: StringName = &""
@export var weakness_mult: float = 1.5
@export var resistance_element: StringName = &""
@export var resistance_mult: float = 0.5
@export var custom_damage_modifiers: Dictionary = {}


## Devuelve los modificadores elementales completos: weakness + resistance
## + custom + (opcional) damage_modifiers heredado de CharacterResource.
func get_damage_modifiers() -> Dictionary:
	var mods: Dictionary = {}
	# 1) Heredado de CharacterResource
	for k in damage_modifiers:
		mods[k] = damage_modifiers[k]
	# 2) Legacy weakness/resistance/custom (sobrescriben si hay colisión)
	if weakness_element != &"":
		mods[weakness_element] = weakness_mult
	if resistance_element != &"":
		mods[resistance_element] = resistance_mult
	for k in custom_damage_modifiers:
		mods[k] = custom_damage_modifiers[k]
	return mods


## Devuelve la recompensa efectiva (alias de reward_skill_points).
func get_reward() -> int:
	return reward_skill_points
