
class_name WeaponResource
extends Resource

enum Family { SWORD, SCIMITAR, DAGGER, SCYTHE, BOW, SPEAR, AXE, MACE, STAFF, UNARMED }

@export var id: StringName = &""
@export var display_name: String = "Unarmed"
@export_multiline var flavor_text: String = ""
@export var family: Family = Family.UNARMED
@export var hands: int = 1

@export var designed_stats: Dictionary = {
	"dmg": 0.0,
	"speed": 1.0,
	"reach": 1.0,
	"weight": 0.0,
	"parry_bonus": 0.0,
	"crit_chance": 0.05,
}


@export var attribute_modifiers: Dictionary = {}


func apply_to_caster(caster: Node) -> bool:
	if caster == null or attribute_modifiers.is_empty():
		return false
	if not caster.has_node("AttributeComponent"):
		return false
	var ac: Node = caster.get_node("AttributeComponent")
	if not ac.has_method("apply_temp_offset"):
		return false
	for attr_id in attribute_modifiers:
		var amt: float = float(attribute_modifiers[attr_id])
		ac.call("apply_temp_offset", StringName(attr_id), amt)
	return true


func remove_from_caster(caster: Node) -> bool:
	if caster == null or attribute_modifiers.is_empty():
		return false
	if not caster.has_node("AttributeComponent"):
		return false
	var ac: Node = caster.get_node("AttributeComponent")
	if not ac.has_method("remove_temp_offset"):
		return false
	for attr_id in attribute_modifiers:
		var amt: float = float(attribute_modifiers[attr_id])
		ac.call("remove_temp_offset", StringName(attr_id), amt)
	return true

@export var stat_scaling: Dictionary = {
	"strength_to_dmg": 0.10,
	"dexterity_to_speed": 0.05,
	"dexterity_to_crit": 0.02,
	"faith_to_parry": 0.05,
}

@export var class_dmg_mult: Dictionary = {}

@export var compatible_skill_ids: Array[StringName] = []

@export var blocked_skill_ids: Array[StringName] = []



@export var category: StringName = &"melee"


func get_family_name() -> String:
	match family:
		Family.SWORD:    return "sword"
		Family.SCIMITAR: return "scimitar"
		Family.DAGGER:   return "dagger"
		Family.SCYTHE:   return "scythe"
		Family.BOW:      return "bow"
		Family.SPEAR:    return "spear"
		Family.AXE:      return "axe"
		Family.MACE:     return "mace"
		Family.STAFF:    return "staff"
		Family.UNARMED:  return "unarmed"
	return "unknown"


func get_family_display() -> String:
	match family:
		Family.SWORD:    return "Espada"
		Family.SCIMITAR: return "Alfanje"
		Family.DAGGER:   return "Daga"
		Family.SCYTHE:   return "Guadaña"
		Family.BOW:      return "Arco"
		Family.SPEAR:    return "Lanza"
		Family.AXE:      return "Hacha"
		Family.MACE:     return "Maza"
		Family.STAFF:    return "Bastón"
		Family.UNARMED:  return "Sin arma"
	return "?"


func is_skill_compatible(skill_id: StringName) -> bool:
	if skill_id in blocked_skill_ids:
		return false
	if compatible_skill_ids.is_empty():
		return family == Family.UNARMED or true
	return skill_id in compatible_skill_ids


func get_scaled_dmg(player: Node) -> float:
	var base: float = float(designed_stats.get("dmg", 0.0))
	if player == null:
		return base
	var str_pts: float = float(_read_attr_points(player, "strength"))
	var mult: float = 1.0 + float(stat_scaling.get("strength_to_dmg", 0.0)) * str_pts
	return base * mult


func get_scaled_speed(player: Node) -> float:
	var base: float = float(designed_stats.get("speed", 1.0))
	if player == null:
		return base
	var dex_pts: float = float(_read_attr_points(player, "dexterity"))
	return base * (1.0 + float(stat_scaling.get("dexterity_to_speed", 0.0)) * dex_pts)


func get_scaled_crit(player: Node) -> float:
	var base: float = float(designed_stats.get("crit_chance", 0.05))
	if player == null:
		return base
	var dex_pts: float = float(_read_attr_points(player, "dexterity"))
	return clampf(base + float(stat_scaling.get("dexterity_to_crit", 0.0)) * dex_pts, 0.0, 1.0)


func get_scaled_parry_bonus(player: Node) -> float:
	var base: float = float(designed_stats.get("parry_bonus", 0.0))
	if player == null:
		return base
	var fai_pts: float = float(_read_attr_points(player, "faith"))
	return clampf(base + float(stat_scaling.get("faith_to_parry", 0.0)) * fai_pts, 0.0, 1.0)


func get_class_mult(target_family: String) -> float:
	if target_family == "" or class_dmg_mult.is_empty():
		return 1.0
	return float(class_dmg_mult.get(target_family, 1.0))


func _read_attr_points(player: Node, stat_id: String) -> float:
	if player == null:
		return 0.0
	if player.has_node("AttributeComponent"):
		var ac: Node = player.get_node("AttributeComponent")
		if ac.has_method("get_points"):
			return float(ac.call("get_points", stat_id))
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps and "allocations" in ps and ps.allocations is Dictionary:
		var alloc: Dictionary = ps.allocations
		if alloc.has("attributes") and alloc["attributes"] is Dictionary:
			return float((alloc["attributes"] as Dictionary).get(stat_id, 0))
	return 0.0
