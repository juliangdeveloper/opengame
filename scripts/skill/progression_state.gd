extends Node

const Balance := preload("res://scripts/skill/balance.gd")
const Elements := preload("res://scripts/skill/elements.gd")
const AttributeComponentScript := preload("res://scripts/attribute_component.gd")
const SkillExecutorScript := preload("res://scripts/skill/skill_executor.gd")
const WeaponCatalogScript := preload("res://scripts/skill/weapon_catalog.gd")

signal skill_points_changed(new_value: int)
signal proficiency_changed(new_value: int)
signal allocation_changed(skill_id: StringName, stat: StringName, points: int)
signal element_allocation_changed(element: StringName, points: int)
signal attribute_points_changed(new_value: int)
signal attribute_allocation_changed(attribute_id: StringName, points: int)
signal skill_owned(skill_id: StringName)
signal skill_unowned(skill_id: StringName)
signal weapon_owned(weapon_id: StringName)
signal weapon_unowned(weapon_id: StringName)
signal weapon_equipped(weapon_id: StringName)
signal weapon_unequipped()
signal weapon_allocation_changed(weapon_id: StringName, stat: StringName, points: int)

signal data_changed

@export var skill_points: int = 0

var attribute_points: int:
	get: return skill_points
	set(value): skill_points = value

@export var proficiency: int = 0

var allocations: Dictionary = {}

var element_allocations: Dictionary = {}

var attribute_allocations: Dictionary = {}

var owned_skills: Array[StringName] = []

var skill_catalog: Dictionary = {}

var owned_weapons: Array[StringName] = []
var equipped_weapon: Resource = null
var weapon_allocations: Dictionary = {}


func _ready() -> void:
	Balance.load_config()
	WeaponCatalogScript.initialize()
	_starter_weapon_grant()
	_apply_saved_state()
	print("[ProgressionState] ready (skill_points=%d, proficiency=%d, tier=%s)" % [
		skill_points, proficiency, Balance.get_tier(proficiency).name
	])
	print("[ProgressionState] weapons in catalog: %d" % WeaponCatalogScript.list_ids().size())


func _apply_saved_state() -> void:
	var save_sys: Node = Engine.get_main_loop().root.get_node_or_null("SaveSystem")
	if save_sys == null or not save_sys.has_method("consume"):
		return
	var data: Dictionary = save_sys.consume(&"progression")
	if data.is_empty():
		return
	from_dict(data)


func to_dict() -> Dictionary:
	var equipped_id: String = ""
	if equipped_weapon != null and "id" in equipped_weapon:
		equipped_id = String(equipped_weapon.id)
	return {
		"skill_points": skill_points,
		"proficiency": proficiency,
		"allocations": _dict_to_str_keys(allocations),
		"element_allocations": _dict_to_str_keys(element_allocations),
		"attribute_allocations": _dict_to_str_keys(attribute_allocations),
		"weapon_allocations": _dict_to_str_keys(weapon_allocations),
		"owned_weapons": _stringname_array_to_strings(owned_weapons),
		"equipped_weapon_id": equipped_id,
	}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	skill_points = int(data.get("skill_points", 0))
	var old_attr_pts: int = int(data.get("attribute_points", 0))
	if old_attr_pts > 0 and skill_points == 0:
		skill_points = old_attr_pts
		attribute_allocations = _str_keys_to_dict_of_int(data.get("attribute_allocations", {}))
	proficiency = int(data.get("proficiency", 0))
	allocations = _str_keys_to_dict_of_str_keys(data.get("allocations", {}))
	element_allocations = _str_keys_to_dict_of_int(data.get("element_allocations", {}))
	attribute_allocations = _str_keys_to_dict_of_int(data.get("attribute_allocations", {}))
	weapon_allocations = _str_keys_to_dict_of_str_keys(data.get("weapon_allocations", {}))
	var saved_weapons: Array = data.get("owned_weapons", [])
	for w in saved_weapons:
		var ws: StringName = StringName(String(w))
		if ws != &"" and ws not in owned_weapons:
			owned_weapons.append(ws)
	var eq_id: String = String(data.get("equipped_weapon_id", ""))
	if eq_id != "":
		var ws2: StringName = StringName(eq_id)
		if ws2 in owned_weapons:
			equip_weapon(ws2)
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_method("_apply_attribute_derived_stats"):
		player.call("_apply_attribute_derived_stats")


func _dict_to_str_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		var v: Variant = d[k]
		if v is Dictionary:
			out[String(k)] = _dict_to_str_keys(v)
		else:
			out[String(k)] = v
	return out


func _str_keys_to_dict_of_str_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		var v: Variant = d[k]
		if v is Dictionary:
			out[String(k)] = _str_keys_to_dict_of_str_keys(v)
		else:
			out[String(k)] = v
	return out


func _str_keys_to_dict_of_int(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[String(k)] = int(d[k])
	return out


func _stringname_array_to_strings(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(String(v))
	return out


func _starter_weapon_grant() -> void:
	if &"unarmed" not in owned_weapons:
		grant_weapon(&"unarmed")
	if &"short_sword" not in owned_weapons:
		grant_weapon(&"short_sword")
	equip_weapon(&"short_sword")


func grant_skill_points(points: int) -> void:
	if points <= 0:
		return
	skill_points += points
	proficiency += points
	skill_points_changed.emit(skill_points)
	proficiency_changed.emit(proficiency)
	print("[Progression] +%d skill_points (bank=%d, proficiency=%d, tier=%s)" % [
		points, skill_points, proficiency, Balance.get_tier(proficiency).name
	])
	data_changed.emit()


func spend_points(points: int) -> bool:
	if points > skill_points:
		return false
	skill_points -= points
	skill_points_changed.emit(skill_points)
	data_changed.emit()
	return true


func allocate(skill_id: StringName, stat: StringName, points: int) -> bool:
	if points <= 0:
		return false
	if not can_allocate_more(skill_id, stat, points):
		return false
	if not spend_points(points):
		return false
	var sid := String(skill_id)
	if not allocations.has(sid):
		allocations[sid] = {}
	var current: int = int(allocations[sid].get(stat, 0))
	allocations[sid][stat] = current + points
	allocation_changed.emit(skill_id, stat, allocations[sid][stat])
	print("[Progression] allocate skill=%s stat=%s +%d (total=%d)" % [skill_id, stat, points, allocations[sid][stat]])
	data_changed.emit()
	return true


func deallocate(skill_id: StringName, stat: StringName, points: int) -> bool:
	if points <= 0:
		return false
	var sid := String(skill_id)
	if not allocations.has(sid) or not allocations[sid].has(stat):
		return false
	var current: int = int(allocations[sid][stat])
	if points > current:
		return false
	allocations[sid][stat] = current - points
	if allocations[sid][stat] == 0:
		allocations[sid].erase(stat)
	skill_points += points
	skill_points_changed.emit(skill_points)
	allocation_changed.emit(skill_id, stat, allocations[sid].get(stat, 0))
	data_changed.emit()
	return true


func can_allocate_more(skill_id: StringName, stat: StringName, points: int) -> bool:
	if skill_points < points:
		return false
	var current: int = int(allocations.get(String(skill_id), {}).get(String(stat), 0))
	var max_points := int(Balance.DEFAULT_MAX_POINTS_PER_STAT)
	return current + points <= max_points


func add_skill(skill) -> void:
	if skill == null or skill.id == &"":
		push_warning("[Progression] add_skill with null/empty id")
		return
	if skill.id in owned_skills:
		return
	owned_skills.append(skill.id)
	skill_catalog[StringName(skill.id)] = skill
	skill_owned.emit(skill.id)
	print("[Progression] +skill %s (%s)" % [skill.id, skill.name])
	data_changed.emit()


func remove_skill(skill_id: StringName) -> void:
	if skill_id not in owned_skills:
		return
	owned_skills.erase(skill_id)
	var to_return := 0
	var sid := String(skill_id)
	if allocations.has(sid):
		var alloc_dict: Dictionary = allocations[sid]
		for stat_key in alloc_dict.keys():
			to_return += int(alloc_dict[stat_key])
		allocations.erase(sid)
	if to_return > 0:
		skill_points += to_return
	skill_catalog.erase(skill_id)
	skill_unowned.emit(skill_id)
	print("[Progression] -skill %s (+%d points refunded)" % [skill_id, to_return])
	data_changed.emit()


func get_skill(id: StringName):
	return skill_catalog.get(id, null)


func get_tier_name() -> String:
	Balance.load_config()
	return String(Balance.get_tier(proficiency).get("name", "Unknown"))


func get_effective_stat_for_skill(skill_id: StringName, stat_name: StringName, designed_value: float) -> float:
	var points := 0
	if allocations.has(String(skill_id)):
		points = int(allocations[String(skill_id)].get(String(stat_name), 0))
	return Balance.compute_effective(designed_value, points, Balance.DEFAULT_MAX_POINTS_PER_STAT, proficiency)


func get_skill_power_ratio(skill_id: StringName) -> float:
	var skill = get_skill(skill_id)
	if skill == null:
		return 0.0
	var total_ratio := 0.0
	var count := 0
	for stat_name_v in skill.designed_max.keys():
		var stat_name := StringName(stat_name_v)
		var designed := float(skill.designed_max[stat_name_v])
		if designed <= 0.0:
			continue
		var effective := get_effective_stat_for_skill(skill_id, stat_name, designed)
		total_ratio += effective / designed
		count += 1
	if count == 0:
		return 0.0
	return clampf(total_ratio / float(count), 0.0, 1.0)


func get_effective_designed_max(skill_id: StringName) -> Dictionary:
	var skill = get_skill(skill_id)
	if skill == null:
		return {}
	return skill.designed_max.duplicate()


func trigger_skill(skill_id: StringName, caster: Node) -> void:
	var skill = get_skill(skill_id)
	if skill == null or caster == null:
		return
	var ex = SkillExecutorScript.new()
	ex.skill = skill
	ex.caster = caster
	ex.progression = self
	caster.add_child(ex)
	ex.cast()


func get_state_snapshot() -> Dictionary:
	var owned := []
	for sid in owned_skills:
		var skill = get_skill(sid)
		if skill == null:
			continue
		var alloc: Dictionary = allocations.get(String(sid), {})
		var eff := {}
		for stat_name_v in skill.designed_max.keys():
			var stat_name := StringName(stat_name_v)
			eff[String(stat_name)] = get_effective_stat_for_skill(sid, stat_name, float(skill.designed_max[stat_name_v]))
		owned.append({
			"id": String(sid),
			"name": skill.name,
			"type": String(skill.type),
			"category": String(skill.category),
			"allocations": alloc,
			"effective_stats": eff,
			"power_ratio": get_skill_power_ratio(sid),
		})
	var element_snapshot := []
	for e in Elements.ELEMENTS:
		var id_v: StringName = e["id"]
		var pts: int = int(element_allocations.get(id_v, 0))
		element_snapshot.append({
			"id": String(id_v),
			"name": e["name"],
			"points": pts,
			"attack_mult": Elements.get_attack_multiplier(pts),
			"resistance_mult": Elements.get_resistance_multiplier(pts),
		})
	return {
		"skill_points_available": skill_points,
		"proficiency": proficiency,
		"proficiency_tier": Balance.get_tier(proficiency).name,
		"owned_skills": owned,
		"element_allocations": element_snapshot,
	}



func allocate_element(element: StringName, points: int) -> bool:
	if points <= 0:
		return false
	if points > skill_points:
		return false
	if not can_allocate_element_more(element, points):
		return false
	if not spend_points(points):
		return false
	var current: int = int(element_allocations.get(element, 0))
	element_allocations[element] = current + points
	element_allocation_changed.emit(element, element_allocations[element])
	print("[Progression] element allocate %s +%d (total=%d)" % [element, points, element_allocations[element]])
	_refresh_resistance_components()
	data_changed.emit()
	return true


func deallocate_element(element: StringName, points: int) -> bool:
	if points <= 0:
		return false
	var current: int = int(element_allocations.get(element, 0))
	if points > current:
		return false
	element_allocations[element] = current - points
	if element_allocations[element] == 0:
		element_allocations.erase(element)
	skill_points += points
	skill_points_changed.emit(skill_points)
	element_allocation_changed.emit(element, int(element_allocations.get(element, 0)))
	_refresh_resistance_components()
	data_changed.emit()
	return true


func can_allocate_element_more(element: StringName, points: int) -> bool:
	if points > skill_points:
		return false
	var current: int = int(element_allocations.get(element, 0))
	return current + points <= Elements.MAX_ELEMENT_POINTS


func get_element_attack_multiplier(element: StringName) -> float:
	var pts: int = int(element_allocations.get(element, 0))
	return Elements.get_attack_multiplier(pts)


func get_element_resistance_multiplier(element: StringName) -> float:
	var pts: int = int(element_allocations.get(element, 0))
	return Elements.get_resistance_multiplier(pts)


func _refresh_resistance_components() -> void:
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_node("ResistanceComponent"):
		player.get_node("ResistanceComponent").call("_refresh_from_progression")



func grant_attribute_points(points: int) -> void:
	if points <= 0:
		return
	skill_points += points
	skill_points_changed.emit(skill_points)
	attribute_points_changed.emit(skill_points)
	print("[Progression] +%d attribute_points → skill_points (bank=%d)" % [points, skill_points])
	data_changed.emit()


func spend_attribute_points(points: int) -> bool:
	return spend_points(points)


func allocate_attribute(attr_id: StringName, points: int) -> bool:
	if points <= 0:
		return false
	if not can_allocate_attribute_more(attr_id, points):
		return false
	if not spend_attribute_points(points):
		return false
	var key: String = String(attr_id)
	var current: int = int(attribute_allocations.get(key, 0))
	attribute_allocations[key] = current + points
	attribute_allocation_changed.emit(attr_id, attribute_allocations[key])
	_refresh_attribute_components()
	print("[Progression] attribute allocate %s +%d (total=%d)" % [attr_id, points, attribute_allocations[key]])
	data_changed.emit()
	return true


func deallocate_attribute(attr_id: StringName, points: int) -> bool:
	if points <= 0:
		return false
	var key: String = String(attr_id)
	if not attribute_allocations.has(key):
		return false
	var current: int = int(attribute_allocations[key])
	if points > current:
		return false
	attribute_allocations[key] = current - points
	if attribute_allocations[key] == 0:
		attribute_allocations.erase(key)
	skill_points += points
	skill_points_changed.emit(skill_points)
	attribute_points_changed.emit(skill_points)
	attribute_allocation_changed.emit(attr_id, int(attribute_allocations.get(key, 0)))
	_refresh_attribute_components()
	data_changed.emit()
	return true


func can_allocate_attribute_more(attr_id: StringName, points: int) -> bool:
	if points > skill_points:
		return false
	var current: int = int(attribute_allocations.get(String(attr_id), 0))
	return current + points <= 5


func get_attribute_points(attr_id: StringName) -> int:
	return int(attribute_allocations.get(String(attr_id), 0))


func get_total_allocated_attribute_points() -> int:
	var total := 0
	for v in attribute_allocations.values():
		total += int(v)
	return total


func reset_attribute_allocations() -> int:
	var total: int = get_total_allocated_attribute_points()
	if total == 0:
		return 0
	attribute_points += total
	attribute_allocations.clear()
	attribute_points_changed.emit(attribute_points)
	_refresh_attribute_components()
	data_changed.emit()
	return total


func _refresh_attribute_components() -> void:
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_node("AttributeComponent"):
		player.get_node("AttributeComponent").call("refresh_from_progression_state")
		if player.has_method("_apply_attribute_derived_stats"):
			player.call("_apply_attribute_derived_stats")



func grant_weapon(weapon_id: StringName) -> bool:
	if weapon_id in owned_weapons:
		return false
	owned_weapons.append(weapon_id)
	weapon_owned.emit(weapon_id)
	if equipped_weapon == null:
		equip_weapon(weapon_id)
	data_changed.emit()
	return true


func remove_weapon(weapon_id: StringName) -> bool:
	if weapon_id not in owned_weapons:
		return false
	owned_weapons.erase(weapon_id)
	weapon_allocations.erase(weapon_id)
	weapon_unowned.emit(weapon_id)
	if equipped_weapon != null and String(equipped_weapon.id) == String(weapon_id):
		unequip_weapon()
	data_changed.emit()
	return true


func equip_weapon(weapon_id: StringName) -> bool:
	if weapon_id not in owned_weapons:
		push_warning("[ProgressionState] equip_weapon: %s not owned" % weapon_id)
		return false
	var catalog := preload("res://scripts/skill/weapon_catalog.gd")
	var wpn: Resource = catalog.get_weapon(weapon_id)
	if wpn == null:
		push_warning("[ProgressionState] equip_weapon: %s not in catalog" % weapon_id)
		return false
	if equipped_weapon != null and equipped_weapon.has_method("remove_from_caster"):
		var old_caster: Node = Engine.get_main_loop().root.find_child("Player", true, false)
		equipped_weapon.remove_from_caster(old_caster)
	equipped_weapon = wpn
	weapon_equipped.emit(weapon_id)
	print("[ProgressionState] equipped weapon: %s (%s, %dh)" % [String(weapon_id), wpn.display_name, wpn.hands])
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_method("set_equipped_weapon"):
		player.call("set_equipped_weapon", wpn)
	if wpn.has_method("apply_to_caster"):
		wpn.apply_to_caster(player)
	data_changed.emit()
	return true


func unequip_weapon() -> void:
	if equipped_weapon == null:
		return
	if equipped_weapon.has_method("remove_from_caster"):
		var caster: Node = Engine.get_main_loop().root.find_child("Player", true, false)
		equipped_weapon.remove_from_caster(caster)
	equipped_weapon = null
	weapon_unequipped.emit()
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_method("set_equipped_weapon"):
		player.call("set_equipped_weapon", null)
	data_changed.emit()


func can_allocate_weapon(weapon_id: StringName, stat: StringName, points: int) -> bool:
	if points <= 0:
		return false
	var current: int = get_weapon_points(weapon_id, stat)
	if current + points > 5:
		return false
	return points <= skill_points


func allocate_weapon(weapon_id: StringName, stat: StringName, points: int) -> bool:
	if not can_allocate_weapon(weapon_id, stat, points):
		return false
	skill_points -= points
	if not weapon_allocations.has(weapon_id):
		weapon_allocations[weapon_id] = {}
	var alloc: Dictionary = weapon_allocations[weapon_id]
	alloc[stat] = int(alloc.get(stat, 0)) + points
	weapon_allocation_changed.emit(weapon_id, stat, int(alloc[stat]))
	skill_points_changed.emit(skill_points)
	data_changed.emit()
	return true


func deallocate_weapon(weapon_id: StringName, stat: StringName, points: int) -> bool:
	if points <= 0:
		return false
	if not weapon_allocations.has(weapon_id):
		return false
	var alloc: Dictionary = weapon_allocations[weapon_id]
	var current: int = int(alloc.get(stat, 0))
	if current < points:
		return false
	alloc[stat] = current - points
	if int(alloc[stat]) <= 0:
		alloc.erase(stat)
	skill_points += points
	weapon_allocation_changed.emit(weapon_id, stat, int(alloc.get(stat, 0)))
	skill_points_changed.emit(skill_points)
	data_changed.emit()
	return true


func get_weapon_points(weapon_id: StringName = &"", stat: StringName = &"") -> int:
	if weapon_id == &"":
		return skill_points
	if not weapon_allocations.has(weapon_id):
		return 0
	return int((weapon_allocations[weapon_id] as Dictionary).get(stat, 0))


func get_weapon(weapon_id: StringName) -> Resource:
	if WeaponCatalogScript == null:
		return null
	return WeaponCatalogScript.get_weapon(weapon_id)


func get_weapon_catalog(filter: StringName = &"all") -> Array[StringName]:
	if WeaponCatalogScript == null:
		return []
	var ids: Array[StringName] = WeaponCatalogScript.list_ids()
	if filter == &"owned":
		return ids.filter(func(wid): return wid in owned_weapons)
	return ids
