## ProgressionState — Estado del jugador: skill points, proficiency, allocations.
##
## Mantiene:
## - skill_points_available: cuántos puntos tiene para gastar AHORA
## - proficiency: total de skill points que ha ganado en su vida
## - allocations: {skill_id: {stat_name: points}}
## - owned_skills: Array[StringName] de skill IDs
##
## Es un autoload singleton (Project Settings > Autoload) para que cualquier
## nodo pueda acceder a él: ProgressionState.spend_points(...)
##
## Comunicación con MCP (fase 2): el FastAPI bridge hace POSTs a este estado.
##
## NOTA: no usa class_name porque choca con el nombre del autoload.
## Se accede vía el autoload directamente: ProgressionState.xxx
extends Node

const Balance := preload("res://scripts/skill/balance.gd")
const SkillExecutorScript := preload("res://scripts/skill/skill_executor.gd")

signal skill_points_changed(new_value: int)
signal proficiency_changed(new_value: int)
signal allocation_changed(skill_id: StringName, stat: StringName, points: int)
signal skill_owned(skill_id: StringName)
signal skill_unowned(skill_id: StringName)

## Puntos disponibles para gastar. Empieza en 0 (jugador empieza sin nada).
@export var skill_points: int = 0

## Proficiency total ganado en challenges.
@export var proficiency: int = 0

## Allocations: {skill_id_string: {stat_string: points}}
var allocations: Dictionary = {}

## Skills owned: Array[StringName]
var owned_skills: Array[StringName] = []

## Catálogo de SkillResources por ID (para consultar designed_max, type, etc.).
## Se llena al cargar skills .tres.
var skill_catalog: Dictionary = {}  # {StringName(id): SkillResource}


func _ready() -> void:
	Balance.load_config()
	print("[ProgressionState] ready (skill_points=%d, proficiency=%d, tier=%s)" % [
		skill_points, proficiency, Balance.get_tier(proficiency).name
	])


## grant_skill_points(points) — añade puntos al bank y al proficiency.
func grant_skill_points(points: int) -> void:
	if points <= 0:
		return
	skill_points += points
	proficiency += points
	skill_points_changed.emit(skill_points)
	proficiency_changed.emit(proficiency)
	print("[Progression] +%d skill_points (bank=%d, proficiency=%d, tier=%s)" % [
		points, skill_points, proficiency, Balance.get_tier(proficiency).name
	])


## spend_points(points) — resta puntos del bank. Devuelve true si exitoso.
func spend_points(points: int) -> bool:
	if points > skill_points:
		return false
	skill_points -= points
	skill_points_changed.emit(skill_points)
	return true


## allocate(skill_id, stat, points) — distribuye puntos a un stat.
## Devuelve true si exitoso, false si no hay puntos o excede max.
func allocate(skill_id: StringName, stat: StringName, points: int) -> bool:
	if points <= 0:
		return false
	if not can_allocate_more(skill_id, stat, points):
		return false
	if not spend_points(points):
		return false
	var sid := String(skill_id)
	if not allocations.has(sid):
		allocations[sid] = {}
	var current: int = int(allocations[sid].get(stat, 0))
	allocations[sid][stat] = current + points
	allocation_changed.emit(skill_id, stat, allocations[sid][stat])
	print("[Progression] allocate skill=%s stat=%s +%d (total=%d)" % [skill_id, stat, points, allocations[sid][stat]])
	return true


## deallocate(skill_id, stat, points) — devuelve puntos al bank.
func deallocate(skill_id: StringName, stat: StringName, points: int) -> bool:
	if points <= 0:
		return false
	var sid := String(skill_id)
	if not allocations.has(sid) or not allocations[sid].has(stat):
		return false
	var current: int = int(allocations[sid][stat])
	if points > current:
		return false
	allocations[sid][stat] = current - points
	if allocations[sid][stat] == 0:
		allocations[sid].erase(stat)
	skill_points += points
	skill_points_changed.emit(skill_points)
	allocation_changed.emit(skill_id, stat, allocations[sid].get(stat, 0))
	return true


## can_allocate_more(skill_id, stat, points) — ¿se puede asignar?
func can_allocate_more(skill_id: StringName, stat: StringName, points: int) -> bool:
	if skill_points < points:
		return false
	var current: int = int(allocations.get(String(skill_id), {}).get(String(stat), 0))
	var max_points := int(Balance.DEFAULT_MAX_POINTS_PER_STAT)
	return current + points <= max_points


## add_skill(skill: SkillResource) — añade a owned y al catálogo.
func add_skill(skill) -> void:
	if skill == null or skill.id == &"":
		push_warning("[Progression] add_skill with null/empty id")
		return
	if skill.id in owned_skills:
		return
	owned_skills.append(skill.id)
	skill_catalog[StringName(skill.id)] = skill
	skill_owned.emit(skill.id)
	print("[Progression] +skill %s (%s)" % [skill.id, skill.name])


func remove_skill(skill_id: StringName) -> void:
	if skill_id not in owned_skills:
		return
	owned_skills.erase(skill_id)
	# Devolver allocations al bank
	var to_return := 0
	var sid := String(skill_id)
	if allocations.has(sid):
		var alloc_dict: Dictionary = allocations[sid]
		for stat_key in alloc_dict.keys():
			to_return += int(alloc_dict[stat_key])
		allocations.erase(sid)
	if to_return > 0:
		skill_points += to_return
	skill_catalog.erase(skill_id)
	skill_unowned.emit(skill_id)
	print("[Progression] -skill %s (+%d points refunded)" % [skill_id, to_return])


## get_skill(id) — devuelve el SkillResource por ID.
func get_skill(id: StringName):
	return skill_catalog.get(id, null)


## Devuelve el nombre del tier actual ("Novice", "Apprentice", etc.)
func get_tier_name() -> String:
	Balance.load_config()
	return String(Balance.get_tier(proficiency).get("name", "Unknown"))


## get_effective_stat_for_skill(skill_id, stat_name, designed_value)
## El corazón del balance: dado un stat y su designed_max, devuelve el valor
## efectivo considerando points invertidos y proficiency.
func get_effective_stat_for_skill(skill_id: StringName, stat_name: StringName, designed_value: float) -> float:
	var points := 0
	if allocations.has(String(skill_id)):
		points = int(allocations[String(skill_id)].get(String(stat_name), 0))
	return Balance.compute_effective(designed_value, points, Balance.DEFAULT_MAX_POINTS_PER_STAT, proficiency)


## get_skill_power_ratio(skill_id) — ratio de poder total (0..1) del skill.
## Útil para cost scaling: stamina = base * (1 - power_ratio) ... etc.
## Promedio ponderado de los stats de la skill.
func get_skill_power_ratio(skill_id: StringName) -> float:
	var skill = get_skill(skill_id)
	if skill == null:
		return 0.0
	var total_ratio := 0.0
	var count := 0
	for stat_name_v in skill.designed_max.keys():
		var stat_name := StringName(stat_name_v)
		var designed := float(skill.designed_max[stat_name_v])
		if designed <= 0.0:
			continue
		var effective := get_effective_stat_for_skill(skill_id, stat_name, designed)
		total_ratio += effective / designed
		count += 1
	if count == 0:
		return 0.0
	return clampf(total_ratio / float(count), 0.0, 1.0)


## get_effective_designed_max(skill_id) — devuelve el designed_max de la skill owned.
func get_effective_designed_max(skill_id: StringName) -> Dictionary:
	var skill = get_skill(skill_id)
	if skill == null:
		return {}
	return skill.designed_max.duplicate()


## trigger_skill(skill_id, caster) — para combo triggers.
## Busca la skill en el catálogo, crea un SkillExecutor, y la castea sobre caster.
func trigger_skill(skill_id: StringName, caster: Node) -> void:
	var skill = get_skill(skill_id)
	if skill == null or caster == null:
		return
	var ex = SkillExecutorScript.new()
	ex.skill = skill
	ex.caster = caster
	ex.progression = self
	caster.add_child(ex)
	ex.cast()


## get_state_snapshot() — estado serializable para MCP/UI/debug.
func get_state_snapshot() -> Dictionary:
	var owned := []
	for sid in owned_skills:
		var skill = get_skill(sid)
		if skill == null:
			continue
		var alloc: Dictionary = allocations.get(String(sid), {})
		var eff := {}
		for stat_name_v in skill.designed_max.keys():
			var stat_name := StringName(stat_name_v)
			eff[String(stat_name)] = get_effective_stat_for_skill(sid, stat_name, float(skill.designed_max[stat_name_v]))
		owned.append({
			"id": String(sid),
			"name": skill.name,
			"type": String(skill.type),
			"category": String(skill.category),
			"allocations": alloc,
			"effective_stats": eff,
			"power_ratio": get_skill_power_ratio(sid),
		})
	return {
		"skill_points_available": skill_points,
		"proficiency": proficiency,
		"proficiency_tier": Balance.get_tier(proficiency).name,
		"owned_skills": owned,
	}
