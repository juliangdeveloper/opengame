## ResistanceComponent — Maneja las resistencias elementales del actor.
##
## Combina dos fuentes de resistencia:
## 1. **Permanente** (de ProgressionState.element_allocations): sube al
##    invertir puntos en un elemento en el Element Allocator UI.
## 2. **Temporal** (de skills/self-buffs): ej. "fire shield" se aplica a
##    sí mismo por 5s.
##
## El multiplicador final se calcula como el mínimo de todas las fuentes
## (más bajo = más resistencia). Ej: resistencia permanente 0.7 (30% menos)
## + temporal 0.5 (50% menos) = 0.5 (capped al mínimo).
##
## Uso desde effect_library:
##   resistance = target.get_node("ResistanceComponent").get_resistance(element)
##   damage *= resistance
class_name ResistanceComponent
extends Node

const Elements := preload("res://scripts/skill/elements.gd")

## Multiplicadores permanentes por elemento. {element_id: multiplier}
## Carga desde ProgressionState.element_allocations en _ready.
var permanent: Dictionary = {}

## Multiplicadores temporales por elemento. {element_id: {mult, elapsed, duration}}
var temporary: Dictionary = {}


func _ready() -> void:
	_refresh_from_progression()


## Carga el permanent desde ProgressionState.element_allocations.
## Llamar también cuando el jugador asigna puntos en el Element Allocator.
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


## Devuelve el multiplicador de resistencia final para un elemento.
## Combina permanente (de puntos) + temporal (de buffs/skills).
## 1.0 = neutral, 0.5 = mitad de daño, 0.0 = inmune.
func get_resistance(element: StringName) -> float:
	if element == &"" or element == &"physical":
		return 1.0
	# Buscar en permanente
	var perm: float = float(permanent.get(element, 1.0))
	# Buscar en temporal
	var temp: float = 1.0
	if temporary.has(element):
		var t: Dictionary = temporary[element]
		temp = float(t.get("mult", 1.0))
	# El mínimo (más resistente)
	return minf(perm, temp)


## Aplica una resistencia temporal. Útil para skills de "buff" o
## "shield" que se aplican al caster.
## duration = 0 → permanente (se mantiene hasta que se remueva).
func add_temporary_resistance(element: StringName, multiplier: float, duration: float) -> void:
	if element == &"" or element == &"physical":
		return
	temporary[element] = {
		"mult": multiplier,
		"elapsed": 0.0,
		"duration": duration,
	}


## Quita una resistencia temporal específica.
func remove_temporary_resistance(element: StringName) -> void:
	temporary.erase(element)


## Quita TODAS las resistencias temporales.
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
		# duration = 0 → permanente, no se remueve por tiempo
		if dur <= 0.0 or t["elapsed"] < dur:
			still[element] = t
	temporary = still
	if temporary.is_empty():
		set_process(false)


## Devuelve todos los element ids que tienen resistencia activa (perm o temp).
## Útil para la UI de "resistances" del actor.
func get_resisted_elements() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in permanent.keys():
		if float(permanent[e]) < 1.0:
			out.append(e)
	for e in temporary.keys():
		if not e in out:
			out.append(e)
	return out
