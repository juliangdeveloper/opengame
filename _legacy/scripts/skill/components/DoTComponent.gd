## DoTComponent — Damage over time aplicado a un target.
##
## Componente hijo que se añade a NPCs/jugadores cuando reciben un dot.
## Hace tick damage cada tick_interval durante duration.
class_name DoTComponent
extends Node

var _dpt: float = 0.0
var _duration: float = 0.0
var _tick_interval: float = 1.0
var _source: Node = null
var _remaining: float = 0.0
var _time_to_next_tick: float = 0.0
var _active: bool = false


func start_dot(dpt: float, duration: float, tick_interval: float, source: Node) -> void:
	_dpt = dpt
	_duration = duration
	_tick_interval = tick_interval
	_source = source
	_remaining = duration
	_time_to_next_tick = tick_interval
	_active = true
	set_process(true)
	if Engine.has_singleton("Debug"):
		pass
	# Refrescar si ya estaba activo: simplemente reiniciamos
	print("[DoT] start target=%s dpt=%.1f duration=%.1f" % [get_parent().name, dpt, duration])


func _process(delta: float) -> void:
	if not _active:
		return
	_remaining -= delta
	_time_to_next_tick -= delta
	if _time_to_next_tick <= 0.0:
		_time_to_next_tick = _tick_interval
		var target := get_parent()
		if is_instance_valid(target) and target.has_method("take_damage"):
			target.call("take_damage", _dpt * _tick_interval, _source)
	if _remaining <= 0.0:
		_active = false
		queue_free()
