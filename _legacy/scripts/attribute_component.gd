class_name AttributeComponent
extends Node


signal attribute_value_changed(attribute_id: StringName, new_value: float)

const ElementsScript := preload("res://scripts/skill/elements.gd")


const ATTRIBUTES: Array = [
	{"id": "hp_max",          "display": "HP Max",          "group": "vital",    "base": 100.0, "per_point": 10.0,  "unit": "flat", "linked_status": &"",        "description": "+10 max HP por punto"},
	{"id": "stamina_max",     "display": "Stamina Max",     "group": "vital",    "base": 50.0,  "per_point": 5.0,   "unit": "flat", "linked_status": &"",        "description": "+5 max Stamina por punto"},
	{"id": "stamina_regen",   "display": "Stamina Regen",   "group": "vital",    "base": 5.0,   "per_point": 0.5,   "unit": "flat", "linked_status": &"",        "description": "+0.5 regen/s por punto"},

	{"id": "phys_dmg",        "display": "Physical Dmg",    "group": "offense",  "base": 1.0,   "per_point": 0.05,  "unit": "%",    "linked_status": &"",        "description": "+5% daño físico"},
	{"id": "ele_dmg",         "display": "Elemental Dmg",   "group": "offense",  "base": 1.0,   "per_point": 0.05,  "unit": "%",    "linked_status": &"",        "description": "+5% daño elemental"},
	{"id": "strength",        "display": "Strength",        "group": "offense",  "base": 0.0,   "per_point": 1.0,   "unit": "flat", "linked_status": &"",        "description": "+10% dmg global como caster, +5% phys_res como target"},
	{"id": "dexterity",       "display": "Dexterity",       "group": "offense",  "base": 0.0,   "per_point": 1.0,   "unit": "flat", "linked_status": &"",        "description": "+2% crit, +2% dodge, +5% attack_speed"},
	{"id": "attack_power",    "display": "Attack Power",    "group": "offense",  "base": 1.0,   "per_point": 0.0,   "unit": "x",    "linked_status": &"",        "description": "Multiplicador de dmg (1.0 base, +0.10 por strength pt, +0.05 por phys_dmg/ele_dmg pt, +offsets de weapon)"},
	{"id": "crit_chance",     "display": "Crit Chance",     "group": "offense",  "base": 0.05,  "per_point": 0.0,   "unit": "x",    "linked_status": &"",        "description": "Probabilidad de crítico (base 0.05, +0.02 por dexterity pt, +offsets de weapon)"},
	{"id": "attack_speed",    "display": "Attack Speed",    "group": "offense",  "base": 1.0,   "per_point": 0.0,   "unit": "x",    "linked_status": &"",        "description": "Multiplicador de velocidad de ataque (1.0 base, +0.05 por dexterity pt, +offsets de weapon)"},
	{"id": "parry_bonus",     "display": "Parry Bonus",     "group": "defense",  "base": 0.0,   "per_point": 0.0,   "unit": "x",    "linked_status": &"",        "description": "Bonus al defender con éxito (0..1, +offsets de weapon)"},

	{"id": "phys_res",        "display": "Physical Res",    "group": "defense",  "base": 0.0,   "per_point": 0.05,  "unit": "x",    "linked_status": &"",        "description": "-5% daño físico recibido"},
	{"id": "ele_res",         "display": "Elemental Res",   "group": "defense",  "base": 0.0,   "per_point": 0.05,  "unit": "x",    "linked_status": &"",        "description": "-5% daño elemental recibido"},

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

var _allocations: Dictionary = {}

var _temp_offsets: Dictionary = {}

var _effective: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh()


func refresh_from_progression_state() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	if "attribute_allocations" in ps:
		_allocations = (ps.attribute_allocations as Dictionary).duplicate(true)
	else:
		_allocations = {}
	_refresh()


func apply_temp_offset(attr_id: StringName, amount: float) -> void:
	var key: String = String(attr_id)
	_temp_offsets[key] = float(_temp_offsets.get(key, 0.0)) + amount
	_refresh()


func remove_temp_offset(attr_id: StringName, amount: float) -> void:
	var key: String = String(attr_id)
	if not _temp_offsets.has(key):
		return
	var current: float = float(_temp_offsets[key])
	_temp_offsets[key] = current - amount
	if absf(_temp_offsets[key]) < 0.0001:
		_temp_offsets.erase(key)
	_refresh()


func clear_temp_offsets() -> void:
	_temp_offsets.clear()
	_refresh()



func get_value(attr_id: StringName) -> float:
	var key: String = String(attr_id)
	if not _effective.has(key):
		_refresh()
	return float(_effective.get(key, 0.0))


func get_points(attr_id: StringName) -> int:
	return int(_allocations.get(String(attr_id), 0))


func get_status_potency(status_id: StringName) -> float:
	var potency: float = 1.0
	for attr in ATTRIBUTES:
		if attr["linked_status"] == status_id:
			var pts: int = get_points(attr["id"])
			potency += 0.10 * float(pts)
			var key: String = String(attr["id"])
			potency += 0.10 * float(_temp_offsets.get(key, 0.0))
			break
	return potency


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


func get_phys_dmg_multiplier() -> float:
	return 1.0 + 0.05 * float(get_points(&"phys_dmg") + _temp_offsets.get("phys_dmg", 0.0))


func get_ele_dmg_multiplier() -> float:
	return 1.0 + 0.05 * float(get_points(&"ele_dmg") + _temp_offsets.get("ele_dmg", 0.0))


func get_phys_res_multiplier() -> float:
	var res: float = 0.05 * float(get_points(&"phys_res") + _temp_offsets.get("phys_res", 0.0))
	return clampf(1.0 - res, 0.0, 1.0)


func get_ele_res_multiplier() -> float:
	var res: float = 0.05 * float(get_points(&"ele_res") + _temp_offsets.get("ele_res", 0.0))
	return clampf(1.0 - res, 0.0, 1.0)



func get_attack_power(_dmg_type: String = "physical") -> float:
	var mult: float = 1.0
	mult += 0.05 * float(get_points(&"phys_dmg") + _temp_offsets.get("phys_dmg", 0.0))
	mult += 0.05 * float(get_points(&"ele_dmg") + _temp_offsets.get("ele_dmg", 0.0))
	mult += 0.10 * float(get_points(&"strength") + _temp_offsets.get("strength", 0.0))
	mult += _temp_offsets.get("attack_power", 0.0)
	return mult


func get_crit_chance() -> float:
	var base: float = 0.05
	var dex_bonus: float = 0.02 * float(get_points(&"dexterity") + _temp_offsets.get("dexterity", 0.0))
	var weapon_offset: float = _temp_offsets.get("crit_chance", 0.0)
	return clampf(base + dex_bonus + weapon_offset, 0.0, 1.0)


func get_dodge_chance() -> float:
	var base: float = 0.05
	var dex_bonus: float = 0.02 * float(get_points(&"dexterity") + _temp_offsets.get("dexterity", 0.0))
	var weapon_offset: float = _temp_offsets.get("dodge_chance", 0.0)
	return clampf(base + dex_bonus + weapon_offset, 0.0, 1.0)


func get_attack_speed() -> float:
	var mult: float = 1.0
	mult += 0.05 * float(get_points(&"dexterity") + _temp_offsets.get("dexterity", 0.0))
	mult += _temp_offsets.get("attack_speed", 0.0)
	return mult


func get_parry_bonus() -> float:
	return clampf(_temp_offsets.get("parry_bonus", 0.0), 0.0, 1.0)



func _refresh() -> void:
	for attr in ATTRIBUTES:
		var id: StringName = attr["id"]
		var key: String = String(id)
		var base: float = float(attr["base"])
		var per_pt: float = float(attr["per_point"])
		var pts: int = int(_allocations.get(key, 0))
		var temp: float = float(_temp_offsets.get(key, 0.0))
		var value: float = base + per_pt * float(pts) + temp
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
	var root: Window = tree.root
	var node := root.get_node_or_null("ProgressionState")
	if node == null:
		node = root.find_child("ProgressionState", true, false)
	return node
