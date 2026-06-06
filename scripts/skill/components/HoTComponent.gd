## HoTComponent — Heal over time.
class_name HoTComponent
extends Node

var _apt: float = 0.0
var _duration: float = 0.0
var _tick_interval: float = 1.0
var _remaining: float = 0.0
var _time_to_next_tick: float = 0.0
var _active: bool = false


func start_hot(apt: float, duration: float, tick_interval: float) -> void:
	_apt = apt
	_duration = duration
	_tick_interval = tick_interval
	_remaining = duration
	_time_to_next_tick = tick_interval
	_active = true
	set_process(true)
	print("[HoT] start target=%s apt=%.1f duration=%.1f" % [get_parent().name, apt, duration])


func _process(delta: float) -> void:
	if not _active:
		return
	_remaining -= delta
	_time_to_next_tick -= delta
	if _time_to_next_tick <= 0.0:
		_time_to_next_tick = _tick_interval
		var target := get_parent()
		if is_instance_valid(target) and target.has_method("heal"):
			target.call("heal", _apt * _tick_interval)
	if _remaining <= 0.0:
		_active = false
		queue_free()
