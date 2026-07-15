## ai_controller.gd — Data-driven AI brain for any Character.
##
## FASE 4+ (2026-06-22): Reescrito para ser 100% data-driven.
## Usa los campos de CharacterResource para tomar TODAS las decisiones:
##   - behavior:      estilo de combate (aggressive, defensive, caster, etc.)
##   - aggression:    0.0-1.0, frecuencia de ataque vs esperar
##   - preferred_range: melee/ranged/any — influye en chase/retreat
##   - reaction_time_sec: delay entre decisiones (simula "tiempo de reacción")
##
## NO tiene stats propios — solo DECIDE; el Character ejecuta.
## El controller también auto-resuelve el target (player) si el character
## no tiene uno asignado.
##
## Cumple la directiva del user:
##   "Los skills y armas son JSON iguales a los del jugador.
##    La única diferencia técnica ... es un simple bool [ai_controlled]."
extends Node
class_name AIController

var character: Node = null  # EntityCharacter (set externally)

# === Reaction timer ===
var _reaction_timer: float = 0.0

# === Anti-streak ===
const ANTI_STREAK_DEPTH: int = 3
var _recent_skills: Array[StringName] = []

# === Skill cache (para no re-cargar .tres cada decisión) ===
var _skill_cache: Dictionary = {}


func _ready() -> void:
	_reaction_timer = randf_range(0.1, 0.4)  # stagger initial decision


func _physics_process(delta: float) -> void:
	if character == null or not is_instance_valid(character):
		return
	# Auto-resolver target si no tiene uno
	var tgt = _ch("target")
	if tgt == null or not is_instance_valid(tgt):
		_find_target()
		tgt = _ch("target")
		if tgt == null:
			return
	# Reaction timer
	_reaction_timer = maxf(0.0, _reaction_timer - delta)
	if _reaction_timer > 0.0:
		return
	# Evaluar transiciones según estado actual
	var st = _ch("state")
	if st == null:
		return
	# State enum values: IDLE=0, CHASE=1, CHOOSE_SKILL=2, WINDUP=3, etc.
	if st == 0:  # IDLE
		_evaluate_idle()
	elif st == 1:  # CHASE
		_evaluate_chase(delta)
	elif st == 5:  # RECOVER
		_evaluate_recover()
	# Reset reaction timer
	_reaction_timer = _get_reaction_time()


## Auto-encuentra el target (player) para el character.
func _find_target() -> void:
	var override = _ch("target_override")
	if override != null and is_instance_valid(override):
		character.set("target", override)
		return
	var tree = character.get_tree()
	if tree == null:
		return
	var player: Node = tree.root.find_child("Player", true, false)
	if player != null and player is Node3D:
		character.set("target", player)


func _evaluate_idle() -> void:
	var d: float = _dist_to_target()
	var det_range: float = float(_ch("detection_range")) if _ch("detection_range") != null else 12.0
	if d < det_range:
		if character.has_method("_enter_chase"):
			character._enter_chase()


func _evaluate_chase(_delta: float) -> void:
	var d: float = _dist_to_target()
	var lose_range: float = float(_ch("lose_range")) if _ch("lose_range") != null else 18.0
	var atk_range: float = float(_ch("attack_range")) if _ch("attack_range") != null else 2.6
	if d > lose_range:
		if character.has_method("_enter_idle"):
			character._enter_idle()
		return
	if d <= atk_range:
		if _should_attack(d):
			if character.has_method("_enter_choose_skill"):
				character._enter_choose_skill()
		elif _should_retreat(d):
			_retreat_from_target()
		return
	if _should_retreat_to_range(d):
		_retreat_from_target()


func _evaluate_recover() -> void:
	pass


func _should_attack(distance: float) -> bool:
	var aggr: float = _get_aggression()
	match _get_behavior():
		"aggressive":
			return randf() < aggr + 0.3
		"berserker":
			return randf() < aggr + 0.5
		"defensive":
			return randf() < aggr - 0.2
		"evasive":
			return randf() < aggr - 0.3
		"caster":
			return randf() < aggr
		"tactical":
			return randf() < aggr + 0.1
		"trickster":
			return randf() < aggr + 0.1
		_:
			return randf() < aggr


func _should_retreat(distance: float) -> bool:
	var atk_range: float = float(_ch("attack_range")) if _ch("attack_range") != null else 2.6
	match _get_behavior():
		"evasive":
			return distance < atk_range * 1.5 and randf() < 0.6
		"defensive":
			return distance < atk_range * 0.8 and randf() < 0.3
		"caster":
			return distance < atk_range * 1.2 and randf() < 0.4
		_:
			return false


func _should_retreat_to_range(distance: float) -> bool:
	var data = _ch("data")
	if data == null:
		return false
	if "preferred_range" not in data:
		return false
	var pref: String = String(data.preferred_range)
	var atk_range: float = float(_ch("attack_range")) if _ch("attack_range") != null else 2.6
	if pref == "ranged" and distance < atk_range * 2.0:
		return randf() < 0.3
	return false


func _retreat_from_target() -> void:
	var tgt = _ch("target")
	if tgt == null:
		return
	var away: Vector3 = character.global_position - tgt.global_position
	away.y = 0
	if away.length() > 0.01:
		away = away.normalized()
		var spd: float = float(_ch("move_speed")) if _ch("move_speed") != null else 5.0
		character.velocity.x = away.x * spd
		character.velocity.z = away.z * spd


# === Skill decision (llamado por Character._state_choose_skill) ===


func decide_skill() -> StringName:
	var sids = _ch("skill_ids")
	if sids == null or (sids is Array and sids.is_empty()):
		return &""
	var behavior: String = _get_behavior()
	var weights: Array = _get_modified_weights(behavior)
	# Anti-streak
	for i in weights.size():
		for recent in _recent_skills:
			if i < sids.size() and sids[i] == recent:
				weights[i] *= 0.3
	# Weighted random
	var total: float = 0.0
	for w in weights:
		total += maxf(w, 0.01)
	if total <= 0.0:
		return sids[0]
	var roll: float = randf() * total
	var acc: float = 0.0
	for i in weights.size():
		acc += maxf(weights[i], 0.01)
		if roll <= acc:
			var picked: StringName = sids[i]
			_recent_skills.append(picked)
			if _recent_skills.size() > ANTI_STREAK_DEPTH:
				_recent_skills.pop_front()
			return picked
	return sids[sids.size() - 1]


func _get_modified_weights(behavior: String) -> Array:
	var sids = _ch("skill_ids")
	var base_weights_raw = _ch("skill_weights")
	var base_weights: Array = []
	if base_weights_raw != null and base_weights_raw is Array and not (base_weights_raw as Array).is_empty():
		base_weights = (base_weights_raw as Array).duplicate()
	else:
		if sids != null and sids is Array:
			for i in (sids as Array).size():
				base_weights.append(1.0)
	for i in base_weights.size():
		if sids == null or not (sids is Array) or i >= (sids as Array).size():
			break
		var sid: StringName = (sids as Array)[i]
		var skill_res: Resource = _get_skill_res(sid)
		if skill_res == null:
			continue
		var category: String = ""
		if "category" in skill_res:
			category = String(skill_res.category)
		var is_ranged: bool = "ranged" in category or "projectile" in category
		var is_melee: bool = "melee" in category or "swing" in category
		var is_defensive: bool = "parry" in category or "defend" in category or "dodge" in category
		var is_control: bool = "control" in category or "mind" in category
		match behavior:
			"aggressive", "berserker":
				if is_melee:
					base_weights[i] *= 1.5
				if is_ranged:
					base_weights[i] *= 0.7
			"defensive":
				if is_defensive:
					base_weights[i] *= 2.0
				if is_melee:
					base_weights[i] *= 0.8
			"caster":
				if is_ranged:
					base_weights[i] *= 1.8
				if is_melee:
					base_weights[i] *= 0.5
			"evasive":
				if is_defensive or is_control:
					base_weights[i] *= 1.5
				if is_melee:
					base_weights[i] *= 0.6
			"tactical":
				if is_control:
					base_weights[i] *= 1.4
			"trickster":
				if is_control:
					base_weights[i] *= 1.6
				if is_defensive:
					base_weights[i] *= 1.3
			"summoner":
				if "summon" in category:
					base_weights[i] *= 2.0
	return base_weights


# === Helpers ===


## Lee una propiedad del character. Usa get() primero, luego get_meta()
## como fallback (para tests que usan set_meta).
func _ch(prop: String):
	var v = character.get(prop)
	if v != null:
		return v
	if character.has_meta(prop):
		return character.get_meta(prop)
	return null


func _get_behavior() -> String:
	var data = _ch("data")
	if data != null and "behavior" in data:
		return String(data.behavior)
	return "aggressive"


func _get_aggression() -> float:
	var data = _ch("data")
	if data != null and "aggression" in data:
		return float(data.aggression)
	return 0.5


func _get_reaction_time() -> float:
	var base: float = 0.1
	var data = _ch("data")
	if data != null and "reaction_time_sec" in data:
		base = float(data.reaction_time_sec)
	return base * randf_range(0.7, 1.3)


func _dist_to_target() -> float:
	var tgt = _ch("target")
	if tgt == null or not is_instance_valid(tgt):
		return INF
	return character.global_position.distance_to(tgt.global_position)


func _get_skill_res(skill_id: StringName) -> Resource:
	var key: String = String(skill_id)
	if _skill_cache.has(key):
		return _skill_cache[key]
	var path: String = "res://data/skills/%s.tres" % key
	var res: Resource = load(path)
	if res != null:
		_skill_cache[key] = res
	return res
