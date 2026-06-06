## BuffComponent — Buff/debuff de stat temporal.
##
## Modifica un stat del parent (e.g., damage_mult, speed_mult, defense).
## Implementación simple: guarda el valor original y restaura al expirar.
##
## Convención:
##   - stat names conocidos: damage_mult, speed_mult, defense, stamina_regen,
##     skill_points_gain, cooldown_mult, knockback_resist.
##   - kind "add": parent.value += value durante duration
##   - kind "multiply": parent.value *= value durante duration
##
## El parent debe leer el stat actualizado cada vez que lo use
## (no monkey-patching; el BuffComponent expone get_buffed_value).
class_name BuffComponent
extends Node

var _stat: String = ""
var _value: float = 0.0
var _kind: String = "multiply"
var _duration: float = 0.0
var _time_left: float = 0.0
var _active: bool = false

# Stats activos (varios buffs pueden叠加)
var _active_buffs: Array[Dictionary] = []


func start_buff(stat: String, value: float, kind: String, duration: float) -> void:
	_active_buffs.append({
		"stat": stat, "value": value, "kind": kind, "duration": duration, "elapsed": 0.0
	})
	_active = true
	set_process(true)
	print("[Buff] start target=%s stat=%s value=%.2f kind=%s duration=%.1f" % [get_parent().name, stat, value, kind, duration])


## Devuelve el valor buffed de un stat.
## El parent hace: var dmg = base * BuffComponent.get_buffed_value(self, "damage_mult")
static func get_buffed_value(node: Node, stat: String, base: float = 1.0) -> float:
	var value := base
	for child in node.get_children():
		if child is BuffComponent:
			var bc := child as BuffComponent
			for b in bc._active_buffs:
				if b.stat == stat:
					if b.kind == "multiply":
						value *= b.value
					else:  # add
						value += b.value
	return value


## Helper: tiene algún buff activo del stat dado?
static func has_buff(node: Node, stat: String) -> bool:
	for child in node.get_children():
		if child is BuffComponent:
			var bc := child as BuffComponent
			for b in bc._active_buffs:
				if b.stat == stat:
					return true
	return false


func _process(delta: float) -> void:
	if not _active:
		return
	# Tick todos los buffs
	var still_active: Array[Dictionary] = []
	for b in _active_buffs:
		b.elapsed += delta
		if b.elapsed < b.duration:
			still_active.append(b)
		else:
			print("[Buff] expired target=%s stat=%s" % [get_parent().name, b.stat])
	_active_buffs = still_active
	if _active_buffs.is_empty():
		_active = false
		queue_free()
