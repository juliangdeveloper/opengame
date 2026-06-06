## StatusComponent — Aplica un status effect (stun, root, slow, etc.).
##
## Implementación: expone flags en el componente que el parent lee.
## Convención: el parent (CharacterBody3D del enemy/player) consulta
##   status_component.is_stunned() / is_rooted() / is_silenced() / etc.
## en su lógica de _physics_process y se comporta acorde.
class_name StatusComponent
extends Node

enum Kind { STUN, ROOT, SLOW, SILENCE, DISARM, SLEEP, BLIND, CHARM, FEAR, TAUNT, CONFUSE }

var _active_effects: Array[Dictionary] = []


func start_status(kind_str: String, duration: float, magnitude: float) -> void:
	var kind := Kind.values().find(kind_str.to_upper())
	if kind == -1:
		push_warning("[Status] unknown kind: %s" % kind_str)
		return
	_active_effects.append({
		"kind": kind, "kind_str": kind_str,
		"duration": duration, "elapsed": 0.0,
		"magnitude": magnitude
	})
	set_process(true)
	print("[Status] start target=%s kind=%s duration=%.1f" % [get_parent().name, kind_str, duration])


func _process(delta: float) -> void:
	var still: Array[Dictionary] = []
	for e in _active_effects:
		e.elapsed += delta
		if e.elapsed < e.duration:
			still.append(e)
		else:
			print("[Status] expired target=%s kind=%s" % [get_parent().name, e.kind_str])
	_active_effects = still
	if _active_effects.is_empty():
		set_process(false)
		queue_free()


## Queries ---------------------------------------------------------------

func is_stunned() -> bool:
	for e in _active_effects:
		if e.kind == Kind.STUN or e.kind == Kind.SLEEP:
			return true
	return false


func is_rooted() -> bool:
	for e in _active_effects:
		if e.kind == Kind.ROOT:
			return true
	return false


func is_silenced() -> bool:
	for e in _active_effects:
		if e.kind == Kind.SILENCE:
			return true
	return false


func is_disarmed() -> bool:
	for e in _active_effects:
		if e.kind == Kind.DISARM:
			return true
	return false


## 0.0 = no slow, 1.0 = full slow. Si múltiples, toma el mayor.
func get_slow_magnitude() -> float:
	var m := 0.0
	for e in _active_effects:
		if e.kind == Kind.SLOW or e.kind == Kind.ROOT:
			m = max(m, float(e.magnitude))
	return m


func has_status(kind_str: String) -> bool:
	for e in _active_effects:
		if e.kind_str == kind_str:
			return true
	return false
