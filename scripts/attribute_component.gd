class_name AttributeComponent
extends Node

## AttributeComponent — Puntos de Atributos (Vitales, Ataque, Defensa, Resistencias a status)
##
## Inspirado en la mecánica "Stat AND Resistance" tipo Pokémon/Path of Exile:
##   1 punto en HP_MAX         → +10 HP máximo             (sin resistencia asociada)
##   1 punto en STAMINA_MAX    → +10 Stamina máximo        (sin resistencia asociada)
##   1 punto en STAMINA_REGEN  → +1.0 regen/segundo
##   1 punto en PHYS_DMG       → +5% daño físico (attack)
##   1 punto in ELE_DMG        → +5% daño elemental (attack)
##   1 punto in PHYS_RES       → -5% daño físico recibido
##   1 punto in ELE_RES        → -5% daño elemental recibido
##   1 punto en STUN_RES       → -10% duración de stun recibido
##                                +10% potencia de stun aplicado por ti
##   (misma regla para cada status: burn_res, sleep_res, freeze_res, ...)
##
## Cada punto, por tanto, dobla efecto: sube el stat correspondiente Y la
## resistencia al status homónimo (cuando aplique).
##
## El componente se "alimenta" del ProgressionState.attribute_allocations
## (que es el storage persistente) y de buffs temporales que los skills
## pueden aplicar.
##
## El componente NO guarda estado persistente. La fuente de verdad es
## ProgressionState. El componente cachea los valores calculados para
## evitar recalcularlos en cada consulta.

signal attribute_value_changed(attribute_id: StringName, new_value: float)

const ElementsScript := preload("res://scripts/skill/elements.gd")

# --- Definición de atributos disponibles ---
# Cada atributo tiene:
#   - id: StringName único
#   - display_name: nombre para UI
#   - group: categoría (vital / offense / defense / status_res)
#   - base_value: valor con 0 puntos
#   - per_point: cuánto cambia por punto
#   - unit: "%", "flat", "x" (multiplicador)
#   - linked_status: status_id cuya resistencia sube con este stat (opcional)
#   - description: texto ayuda UI
#
# Mapeo per_point:
#   stats planos (HP, stamina): "flat" +5/+10/+15 según
#   stats porcentuales (%): "%" +5% por punto
#   resistencias (multiplicador 0.0-1.0): "x" -0.05 por punto (clamped 0.0..1.0)
#   status resistencias (duración): "x" -0.10 por punto (clamped 0.0..1.0)
#   status potency (caster): "%" +10% por punto
#
# Para mantener el sistema simple, los valores se almacenan como un único
# "effective_value" (float). El consumidor (Player, StatusComponent, etc.)
# interpreta según la unidad del atributo.

const ATTRIBUTES: Array = [
	# --- Vitales (sin status link) ---
	{"id": "hp_max",          "display": "HP Max",          "group": "vital",    "base": 100.0, "per_point": 10.0,  "unit": "flat", "linked_status": &"",        "description": "+10 max HP por punto"},
	{"id": "stamina_max",     "display": "Stamina Max",     "group": "vital",    "base": 50.0,  "per_point": 5.0,   "unit": "flat", "linked_status": &"",        "description": "+5 max Stamina por punto"},
	{"id": "stamina_regen",   "display": "Stamina Regen",   "group": "vital",    "base": 5.0,   "per_point": 0.5,   "unit": "flat", "linked_status": &"",        "description": "+0.5 regen/s por punto"},

	# --- Offense (escalan daño) ---
	{"id": "phys_dmg",        "display": "Physical Dmg",    "group": "offense",  "base": 1.0,   "per_point": 0.05,  "unit": "%",    "linked_status": &"",        "description": "+5% daño físico"},
	{"id": "ele_dmg",         "display": "Elemental Dmg",   "group": "offense",  "base": 1.0,   "per_point": 0.05,  "unit": "%",    "linked_status": &"",        "description": "+5% daño elemental"},
	# FASE 0: stats "primarios" para el sistema bilateral caster/target.
	# Strength = fuerza bruta del caster (+10% dmg global) y aporta algo de
	# defensa (mantiene la simetría con dexterous = "agilidad" puramente
	# ofensiva/defensiva, no defensiva pura).
	{"id": "strength",        "display": "Strength",        "group": "offense",  "base": 0.0,   "per_point": 1.0,   "unit": "flat", "linked_status": &"",        "description": "+10% dmg global como caster, +5% phys_res como target"},
	# Dexterity = agilidad del caster (crit, dodge, attack_speed).
	{"id": "dexterity",       "display": "Dexterity",       "group": "offense",  "base": 0.0,   "per_point": 1.0,   "unit": "flat", "linked_status": &"",        "description": "+2% crit, +2% dodge, +5% attack_speed"},

	# --- Defense (sin status link) ---
	{"id": "phys_res",        "display": "Physical Res",    "group": "defense",  "base": 0.0,   "per_point": 0.05,  "unit": "x",    "linked_status": &"",        "description": "-5% daño físico recibido"},
	{"id": "ele_res",         "display": "Elemental Res",   "group": "defense",  "base": 0.0,   "per_point": 0.05,  "unit": "x",    "linked_status": &"",        "description": "-5% daño elemental recibido"},

	# --- Status: cada stat sube su resistencia y la potency del caster ---
	{"id": "stun_res",        "display": "Stun Res",        "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"stun",    "description": "-10% duración stun recibido / +10% potencia stun aplicado"},
	{"id": "sleep_res",       "display": "Sleep Res",       "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"sleep",   "description": "-10% duración sleep / +10% potencia sleep aplicado"},
	{"id": "burn_res",        "display": "Burn Res",        "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"burn",    "description": "-10% duración burn / +10% potencia burn aplicado"},
	{"id": "freeze_res",      "display": "Freeze Res",      "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"freeze",  "description": "-10% duración freeze / +10% potencia freeze aplicado"},
	{"id": "shock_res",       "display": "Shock Res",       "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"shock",   "description": "-10% duración shock / +10% potencia shock aplicado"},
	{"id": "bleed_res",       "display": "Bleed Res",       "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"bleed",   "description": "-10% duración bleed / +10% potencia bleed aplicado"},
	{"id": "poison_res",      "display": "Poison Res",      "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"poison",  "description": "-10% duración poison / +10% potencia poison aplicado"},
	{"id": "slow_res",        "display": "Slow Res",        "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"slow",    "description": "-10% slow aplicado a ti / +10% slow aplicado por ti"},
	{"id": "root_res",        "display": "Root Res",        "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"root",    "description": "-10% duración root / +10% potencia root aplicado"},
	{"id": "silence_res",     "display": "Silence Res",     "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"silence", "description": "-10% duración silence / +10% potencia silence aplicado"},
	{"id": "disarm_res",      "display": "Disarm Res",      "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"disarm",  "description": "-10% duración disarm / +10% potencia disarm aplicado"},
	{"id": "blind_res",       "display": "Blind Res",       "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"blind",   "description": "-10% duración blind / +10% potencia blind aplicado"},
	{"id": "charm_res",       "display": "Charm Res",       "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"charm",   "description": "-10% duración charm / +10% potencia charm aplicado"},
	{"id": "fear_res",        "display": "Fear Res",        "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"fear",    "description": "-10% duración fear / +10% potencia fear aplicado"},
	{"id": "taunt_res",       "display": "Taunt Res",       "group": "status_res", "base": 0.0, "per_point": 0.10, "unit": "x", "linked_status": &"taunt",   "description": "-10% duración taunt / +10% potencia taunt aplicado"},
]

# Cache de puntos asignados (sincronizado con ProgressionState en refresh)
var _allocations: Dictionary = {}

# Buffs temporales (reset entre escenas o controlados por skill).
# Keys: StringName attribute_id, value: float offset (se suma al base + puntos).
var _temp_offsets: Dictionary = {}

# Cache del valor efectivo de cada atributo (recalculado en refresh).
var _effective: Dictionary = {}


func _ready() -> void:
	# Asegurar que el nodo procesa aún si el árbol está pausado
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh()


## Recarga allocations desde ProgressionState (source-of-truth).
## Llamar después de que el jugador asigne/desasigne puntos.
func refresh_from_progression_state() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	if "attribute_allocations" in ps:
		_allocations = (ps.attribute_allocations as Dictionary).duplicate(true)
	else:
		_allocations = {}
	_refresh()


## Aplica un offset temporal (buff/debuff) a un atributo.
## Positivo suma, negativo resta. Se removerá con clear_temp_offsets.
func apply_temp_offset(attr_id: StringName, amount: float) -> void:
	var key: String = String(attr_id)
	_temp_offsets[key] = float(_temp_offsets.get(key, 0.0)) + amount
	_refresh()


## Quita un offset temporal específico (si amount coincide).
func remove_temp_offset(attr_id: StringName, amount: float) -> void:
	var key: String = String(attr_id)
	if not _temp_offsets.has(key):
		return
	var current: float = float(_temp_offsets[key])
	_temp_offsets[key] = current - amount
	if absf(_temp_offsets[key]) < 0.0001:
		_temp_offsets.erase(key)
	_refresh()


## Limpia todos los offsets temporales (e.g. al cambiar de escena).
func clear_temp_offsets() -> void:
	_temp_offsets.clear()
	_refresh()


# --- Consultas ---

## Devuelve el valor efectivo de un atributo (base + puntos + buffs).
func get_value(attr_id: StringName) -> float:
	var key: String = String(attr_id)
	if not _effective.has(key):
		_refresh()
	return float(_effective.get(key, 0.0))


## Devuelve los puntos asignados actualmente a un atributo.
func get_points(attr_id: StringName) -> int:
	return int(_allocations.get(String(attr_id), 0))


## Devuelve el multiplicador de potencia para un status específico cuando
## el actor CAUSA ese status. Sube con los puntos invertidos en
## linked_status. 1.0 = sin cambio. >1.0 = potenciado.
func get_status_potency(status_id: StringName) -> float:
	var potency: float = 1.0
	for attr in ATTRIBUTES:
		if attr["linked_status"] == status_id:
			var pts: int = get_points(attr["id"])
			potency += 0.10 * float(pts)
			# Aplicar offsets temporales también
			var key: String = String(attr["id"])
			potency += 0.10 * float(_temp_offsets.get(key, 0.0))
			break
	return potency


## Devuelve el multiplicador de resistencia a un status específico cuando
## el actor RECIBE ese status. 0.0 = inmune, 1.0 = duración normal, >1.0 = más vulnerable.
## Los puntos bajan este multiplicador (más resistente = menos duración).
func get_status_resistance(status_id: StringName) -> float:
	var res: float = 0.0
	for attr in ATTRIBUTES:
		if attr["linked_status"] == status_id:
			var pts: int = get_points(attr["id"])
			res = 0.10 * float(pts)
			var key: String = String(attr["id"])
			res += 0.10 * float(_temp_offsets.get(key, 0.0))
			res = clampf(res, 0.0, 1.0)
			break
	return res


## Devuelve el multiplicador de daño físico de ataque (1.0 = sin cambio).
func get_phys_dmg_multiplier() -> float:
	return 1.0 + 0.05 * float(get_points(&"phys_dmg") + _temp_offsets.get("phys_dmg", 0.0))


## Devuelve el multiplicador de daño elemental de ataque (1.0 = sin cambio).
func get_ele_dmg_multiplier() -> float:
	return 1.0 + 0.05 * float(get_points(&"ele_dmg") + _temp_offsets.get("ele_dmg", 0.0))


## Devuelve el multiplicador de mitigación de daño físico (0.0 = inmune,
## 1.0 = sin mitigación). Se usa como damage_multiplier = 1.0 - res.
func get_phys_res_multiplier() -> float:
	var res: float = 0.05 * float(get_points(&"phys_res") + _temp_offsets.get("phys_res", 0.0))
	return clampf(1.0 - res, 0.0, 1.0)


## Devuelve el multiplicador de mitigación de daño elemental.
func get_ele_res_multiplier() -> float:
	var res: float = 0.05 * float(get_points(&"ele_res") + _temp_offsets.get("ele_res", 0.0))
	return clampf(1.0 - res, 0.0, 1.0)


# ============================================================================
# FASE 0 (2026-06-14): Derivados bilaterales para el nuevo _compute_skill_power
#
# Antes: el "poder" de un skill dependía del weapon.dmg y stats hardcoded.
# Ahora: depende de los ATRIBUTOS de ambas instancias (caster + target).
#   - Caster: attack_power (fuerza total), crit_chance, attack_speed
#   - Target: dodge (probabilidad de esquivar), phys_res, ele_res
#
# Los derivados se computan desde los puntos del componente + temp_offsets
# (los temp_offsets son los que aplican los weapons al equiparse — Fase 1).
# ============================================================================

## Multiplicador total de ataque del caster, para un tipo de daño dado.
## Combina phys_dmg (per-point +5%) y ele_dmg (per-point +5%) — los DOS
## atributos básicos cuentan para el daño físico (el user lo confirmó:
## "Los elementos y atributos básicos solo se tienen en cuenta para el
## daño físico"). Strength (per-point +10%) suma siempre como fuerza bruta.
## 1.0 = sin bonus, 1.5 = +50% dmg.
##
## dmg_type se ignora actualmente (siempre suma ambos); el parámetro
## se mantiene para que el caller pueda pasar "physical" o "elemental"
## y se anticipe a futuras especializaciones (e.g. +X% solo a fire skills).
func get_attack_power(_dmg_type: String = "physical") -> float:
	var mult: float = 1.0
	mult += 0.05 * float(get_points(&"phys_dmg") + _temp_offsets.get("phys_dmg", 0.0))
	mult += 0.05 * float(get_points(&"ele_dmg") + _temp_offsets.get("ele_dmg", 0.0))
	mult += 0.10 * float(get_points(&"strength") + _temp_offsets.get("strength", 0.0))
	return mult


## Probabilidad de crítico del caster. Base 5% + 2% por punto de dexterity.
## El arma luego añade un offset vía temp_offset (Fase 1).
func get_crit_chance() -> float:
	var base: float = 0.05
	var dex_bonus: float = 0.02 * float(get_points(&"dexterity") + _temp_offsets.get("dexterity", 0.0))
	return clampf(base + dex_bonus, 0.0, 1.0)


## Probabilidad de esquivar un golpe. Base 5% + 2% por punto de dexterity
## (se acumula con crit del caster: dexterity es un stat ofensivo Y defensivo).
## También afectado por el stat dedicado "dodge" si existe (futuro).
func get_dodge_chance() -> float:
	var base: float = 0.05
	var dex_bonus: float = 0.02 * float(get_points(&"dexterity") + _temp_offsets.get("dexterity", 0.0))
	return clampf(base + dex_bonus, 0.0, 1.0)


## Multiplicador de velocidad de ataque del caster. Base 1.0 = normal.
## +5% por punto de dexterity. El weapon añade un offset (Fase 1).
func get_attack_speed() -> float:
	return 1.0 + 0.05 * float(get_points(&"dexterity") + _temp_offsets.get("dexterity", 0.0))


# --- Internos ---

func _refresh() -> void:
	for attr in ATTRIBUTES:
		var id: StringName = attr["id"]
		var key: String = String(id)
		var base: float = float(attr["base"])
		var per_pt: float = float(attr["per_point"])
		var pts: int = int(_allocations.get(key, 0))
		var temp: float = float(_temp_offsets.get(key, 0.0))
		var value: float = base + per_pt * float(pts) + temp
		# Clamps por unidad
		var unit: String = String(attr["unit"])
		if unit == "x":
			value = clampf(value, 0.0, 1.0)
		elif unit == "%":
			value = maxf(value, 0.0)
		_effective[key] = value
		attribute_value_changed.emit(id, value)


func _get_progression_state() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	# ProgressionState es autoload. Lo buscamos como singleton del scene tree root.
	var root: Window = tree.root
	var node := root.get_node_or_null("ProgressionState")
	if node == null:
		# fallback: buscar en todo el árbol
		node = root.find_child("ProgressionState", true, false)
	return node
