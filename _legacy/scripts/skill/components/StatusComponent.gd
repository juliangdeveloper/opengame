## StatusComponent — Aplica un status effect (stun, root, slow, etc.).
##
## Implementación: expone flags en el componente que el parent lee.
## Convención: el parent (CharacterBody3D del enemy/player) consulta
##   status_component.is_stunned() / is_rooted() / is_silenced() / etc.
## en su lógica de _physics_process y se comporta acorde.
##
## Soporta tanto statuses clásicos (STUN, ROOT, etc.) como elementales
## (BURN, FREEZE, SHOCK, BLEED, POISON). Los elementales también tienen
## DoT — se manejan aquí con un mini-timer por status elemental.
class_name StatusComponent
extends Node

const Elements := preload("res://scripts/skill/elements.gd")

# Statuses clásicos. Los elementales (BURN/FREEZE/SHOCK/BLEED/POISON) se
# buscan por nombre en runtime, no están en este enum (para no chocar
# con los kinds pre-existentes del código).
enum Kind { STUN, ROOT, SLOW, SILENCE, DISARM, SLEEP, BLIND, CHARM, FEAR, TAUNT, CONFUSE }

var _active_effects: Array[Dictionary] = []
## Statuses elementales activos (separados para no contaminar _active_effects
## con campos DoT). Cada entry: {kind, element, dpt, tick_interval, elapsed,
## duration, prevents_regen, source}.
var _elemental_statuses: Array[Dictionary] = []


func start_status(kind_str: String, duration: float, magnitude: float) -> void:
	# CORRECCIÓN: usar keys() (nombres) en vez de values() (enteros).
	# values().find("ROOT") devolvía -1 porque values() son enteros (0,1,2,...).
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


## Aplica un status elemental (burn, freeze, shock, bleed, poison) con
## DoT opcional. La definición viene de Elements.STATUS_EFFECTS.
func start_elemental_status(status_id: StringName, duration: float, source: Node = null) -> void:
	var def: Dictionary = Elements.get_status(status_id)
	if def.is_empty():
		push_warning("[Status] unknown elemental status: %s" % status_id)
		return
	# Si ya tiene este elemental activo, refrescar duración (no stackear).
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
	# Si el status aplica slow/root/stun, también lo agregamos como
	# status clásico (para que el parent consulte is_rooted/is_stunned).
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


## Quita un status elemental activo (ej. "burn" se remueve con agua).
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
	# Tick de DoT elementales
	var still_elem: Array[Dictionary] = []
	for e in _elemental_statuses:
		e.elapsed += delta
		# Tick DoT cuando elapsed cruza tick_interval multiples
		# (cuántos ticks pasaron en este frame)
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


## Aplica el tick de daño de un status elemental al parent.
func _apply_elem_damage(e: Dictionary) -> void:
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	var amount: float = float(e["dpt"]) * float(e["tick_interval"])
	var source: Node = e.get("source", null)
	# Si el parent tiene ResistanceComponent, aplica el multiplier elemental.
	var mult: float = 1.0
	if parent.has_node("ResistanceComponent"):
		var rc: Node = parent.get_node("ResistanceComponent")
		if rc.has_method("get_resistance"):
			mult = float(rc.call("get_resistance", e["element"]))
	amount *= mult
	if parent.has_method("take_damage"):
		parent.call("take_damage", amount, source)
	# Shock: chance de stun adicional en cada tick
	var def: Dictionary = Elements.get_status(e["kind"])
	if def.has("stun_chance") and randf() < float(def["stun_chance"]):
		start_status("stun", 0.6, 1.0)


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


## True si el actor tiene CUALQUIER status elemental activo
## (burn, freeze, shock, bleed, poison).
func has_elemental_status() -> bool:
	return not _elemental_statuses.is_empty()


## True si el actor tiene el status elemental específico.
func has_elemental_status_kind(kind: StringName) -> bool:
	for e in _elemental_statuses:
		if e["kind"] == kind:
			return true
	return false


## Devuelve los element ids activos (para la UI de "bad effects on me").
func get_active_elemental_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in _elemental_statuses:
		out.append(e["kind"])
	return out


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
