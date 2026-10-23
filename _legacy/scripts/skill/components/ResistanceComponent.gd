class_name ResistanceComponent
extends Node

const Elements := preload("res://scripts/skill/elements.gd")

var permanent: Dictionary = {}

var temporary: Dictionary = {}


func _ready() -> void:
	_refresh_from_progression()


func _refresh_from_progression() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps == null:
		return
	if not ("element_allocations" in ps):
		return
	var allocs: Dictionary = ps.element_allocations
	permanent.clear()
	for element_id in allocs.keys():
		var pts: int = int(allocs[element_id])
		permanent[element_id] = Elements.get_resistance_multiplier(pts)


func get_resistance(element: StringName) -> float:
	if element == &"" or element == &"physical":
		return 1.0
	var perm: float = float(permanent.get(element, 1.0))
	var temp: float = 1.0
	if temporary.has(element):
		var t: Dictionary = temporary[element]
		temp = float(t.get("mult", 1.0))
	return minf(perm, temp)


func add_temporary_resistance(element: StringName, multiplier: float, duration: float) -> void:
	if element == &"" or element == &"physical":
		return
	temporary[element] = {
		"mult": multiplier,
		"elapsed": 0.0,
		"duration": duration,
	}


func remove_temporary_resistance(element: StringName) -> void:
	temporary.erase(element)


func clear_temporary_resistances() -> void:
	temporary.clear()


func _process(delta: float) -> void:
	if temporary.is_empty():
		return
	var still: Dictionary = {}
	for element in temporary.keys():
		var t: Dictionary = temporary[element]
		t["elapsed"] = float(t.get("elapsed", 0.0)) + delta
		var dur: float = float(t.get("duration", 0.0))
		if dur <= 0.0 or t["elapsed"] < dur:
			still[element] = t
	temporary = still
	if temporary.is_empty():
		set_process(false)


func get_resisted_elements() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in permanent.keys():
		if float(permanent[e]) < 1.0:
			out.append(e)
	for e in temporary.keys():
		if not e in out:
			out.append(e)
	return out
