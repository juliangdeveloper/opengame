class_name ShieldComponent
extends Node

var _amount: float = 0.0
var _remaining: float = 0.0
var _duration: float = 0.0
var _time_left: float = 0.0
var _active: bool = false


func start_shield(amount: float, duration: float) -> void:
	_amount = max(_amount, amount)
	_remaining = max(_remaining, amount)
	_duration = duration
	_time_left = duration
	_active = true
	set_process(true)
	print("[Shield] start target=%s amount=%.1f duration=%.1f" % [get_parent().name, amount, duration])


func absorb_damage(damage: float) -> float:
	if not _active or _remaining <= 0.0:
		return damage
	var absorbed: float = min(_remaining, damage)
	_remaining -= absorbed
	if _remaining <= 0.0:
		_active = false
		print("[Shield] broken on %s" % get_parent().name)
		queue_free()
	return damage - absorbed


func _process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_active = false
		print("[Shield] expired on %s" % get_parent().name)
		queue_free()
