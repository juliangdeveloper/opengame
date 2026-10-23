class_name StatusComponent
extends Node

const Elements := preload("res://scripts/skill/elements.gd")

enum Kind { STUN, ROOT, SLOW, SILENCE, DISARM, SLEEP, BLIND, CHARM, FEAR, TAUNT, CONFUSE }

var _active_effects: Array[Dictionary] = []
var _elemental_statuses: Array[Dictionary] = []


func start_status(kind_str: String, duration: float, magnitude: float) -> void:
	var kind := Kind.keys().find(kind_str.to_upper())
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


func start_elemental_status(status_id: StringName, duration: float, source: Node = null) -> void:
	var def: Dictionary = Elements.get_status(status_id)
	if def.is_empty():
		push_warning("[Status] unknown elemental status: %s" % status_id)
		return
	for e in _elemental_statuses:
		if e["kind"] == status_id:
			e["elapsed"] = 0.0
			e["duration"] = max(e["duration"], duration)
			return
	var dpt: float = float(def.get("dpt", 0.0))
	var tick_interval: float = float(def.get("tick_interval", 1.0))
	_elemental_statuses.append({
		"kind": status_id,
		"element": def.get("element", &"physical"),
		"dpt": dpt,
		"tick_interval": tick_interval,
		"elapsed": 0.0,
		"duration": duration,
		"prevents_regen": bool(def.get("prevents_regen", false)),
		"source": source,
	})
	if def.has("is_root") and bool(def["is_root"]):
		start_status("root", duration, 1.0)
	if def.has("is_slow") and bool(def["is_slow"]):
		start_status("slow", duration, float(def.get("slow_magnitude", 0.5)))
	if def.has("is_stun") and bool(def["is_stun"]):
		start_status("stun", duration, 1.0)
	set_process(true)
	print("[Status] elemental start target=%s kind=%s duration=%.1f dpt=%.1f" % [
		get_parent().name, status_id, duration, dpt
	])


func remove_elemental_status(status_id: StringName) -> void:
	var still_active: Array[Dictionary] = []
	for e in _elemental_statuses:
		if e["kind"] != status_id:
			still_active.append(e)
	_elemental_statuses = still_active


func _process(delta: float) -> void:
	var still: Array[Dictionary] = []
	for e in _active_effects:
		e.elapsed += delta
		if e.elapsed < e.duration:
			still.append(e)
		else:
			print("[Status] expired target=%s kind=%s" % [get_parent().name, e.kind_str])
	_active_effects = still
	var still_elem: Array[Dictionary] = []
	for e in _elemental_statuses:
		e.elapsed += delta
		var prev_ticks: int = int((e.elapsed - delta) / e.tick_interval)
		var new_ticks: int = int(e.elapsed / e.tick_interval)
		for _t in range(new_ticks - prev_ticks):
			_apply_elem_damage(e)
		if e.elapsed < e.duration:
			still_elem.append(e)
		else:
			print("[Status] elemental expired target=%s kind=%s" % [get_parent().name, e["kind"]])
	_elemental_statuses = still_elem
	if _active_effects.is_empty() and _elemental_statuses.is_empty():
		set_process(false)
		queue_free()


func _apply_elem_damage(e: Dictionary) -> void:
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	var amount: float = float(e["dpt"]) * float(e["tick_interval"])
	var source: Node = e.get("source", null)
	var mult: float = 1.0
	if parent.has_node("ResistanceComponent"):
		var rc: Node = parent.get_node("ResistanceComponent")
		if rc.has_method("get_resistance"):
			mult = float(rc.call("get_resistance", e["element"]))
	amount *= mult
	if parent.has_method("take_damage"):
		parent.call("take_damage", amount, source)
	var def: Dictionary = Elements.get_status(e["kind"])
	if def.has("stun_chance") and randf() < float(def["stun_chance"]):
		start_status("stun", 0.6, 1.0)



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


func has_elemental_status() -> bool:
	return not _elemental_statuses.is_empty()


func has_elemental_status_kind(kind: StringName) -> bool:
	for e in _elemental_statuses:
		if e["kind"] == kind:
			return true
	return false


func get_active_elemental_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in _elemental_statuses:
		out.append(e["kind"])
	return out


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
