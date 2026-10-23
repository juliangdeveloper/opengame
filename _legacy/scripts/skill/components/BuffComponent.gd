class_name BuffComponent
extends Node

var _stat: String = ""
var _value: float = 0.0
var _kind: String = "multiply"
var _duration: float = 0.0
var _time_left: float = 0.0
var _active: bool = false

var _active_buffs: Array[Dictionary] = []


func start_buff(stat: String, value: float, kind: String, duration: float) -> void:
	_active_buffs.append({
		"stat": stat, "value": value, "kind": kind, "duration": duration, "elapsed": 0.0
	})
	_active = true
	set_process(true)
	print("[Buff] start target=%s stat=%s value=%.2f kind=%s duration=%.1f" % [get_parent().name, stat, value, kind, duration])


static func get_buffed_value(node: Node, stat: String, base: float = 1.0) -> float:
	var value := base
	for child in node.get_children():
		if child is BuffComponent:
			var bc := child as BuffComponent
			for b in bc._active_buffs:
				if b.stat == stat:
					if b.kind == "multiply":
						value *= b.value
					else:
						value += b.value
	return value


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
