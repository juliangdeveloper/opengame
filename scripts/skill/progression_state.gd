## ProgressionState — Estado del jugador: skill points, proficiency, allocations.
##
## Mantiene:
## - skill_points: cuántos puntos tiene para gastar AHORA
## - proficiency: total de skill points que ha ganado en su vida
## - allocations: {skill_id: {stat_name: points}}  (por skill individual)
## - element_allocations: {element_id: points}  (sistema de elementos)
## - owned_skills: Array[StringName] de skill IDs
##
## Es un autoload singleton (Project Settings > Autoload) para que cualquier
## nodo pueda acceder a él: ProgressionState.xxx
##
## Comunicación con MCP (fase 2): el FastAPI bridge hace POSTs a este estado.
##
## NOTA: no usa class_name porque choca con el nombre del autoload.
## Se accede vía el autoload directamente: ProgressionState.xxx
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

## Emitido en cada mutación del estado. SaveSystem escucha este signal
## (junto a los de MissionManager y ObjectivesManager) y persiste tras
## debounce. Es un signal "cualquier cambio", no un signal por campo.
signal data_changed

## Puntos disponibles para gastar en skills específicos. Empieza en 0.
@export var skill_points: int = 0

## Puntos disponibles para gastar en Atributos (HP, Stamina, Resistencias).
@export var attribute_points: int = 0

## Proficiency total ganado en challenges.
@export var proficiency: int = 0

## Allocations: {skill_id_string: {stat_string: points}}
var allocations: Dictionary = {}

## Allocations de ELEMENTOS: {element_id_string: points}
## Cada punto sube TANTO el attack multiplier (1.0 + 0.1*pts) COMO el
## resistance multiplier (1.0 - 0.1*pts) de ese elemento. Ver Elements.
var element_allocations: Dictionary = {}

## Allocations de ATRIBUTOS: {attribute_id_string: points}
## Cada punto sube el stat correspondiente Y (para status_res) la
## resistencia al status homónimo. Ver AttributeComponent.ATTRIBUTES.
var attribute_allocations: Dictionary = {}

## Skills owned: Array[StringName]
var owned_skills: Array[StringName] = []

## Catálogo de SkillResources por ID (para consultar designed_max, type, etc.).
## Se llena al cargar skills .tres.
var skill_catalog: Dictionary = {}  # {StringName(id): SkillResource}

## === SISTEMA DE ARMAS (Post-MVP) ===
## owned_weapons: Array[StringName] — armas en posesión del jugador.
## equipped_weapon: Resource (WeaponResource) — el arma activa.
## weapon_allocations: {weapon_id: {stat_name: points}} — puntos gastados
##                    en stats concretos de un arma concreta (como skills).
var owned_weapons: Array[StringName] = []
var equipped_weapon: Resource = null
var weapon_allocations: Dictionary = {}


func _ready() -> void:
	Balance.load_config()
	# Inicializar el catálogo de armas (carga todos los .tres de data/weapons/).
	# Llamar esto en _ready es seguro porque el catálogo es estático (no autoload).
	WeaponCatalogScript.initialize()
	# Auto-otorgar armas básicas al jugador si no las tiene.
	# unarmed siempre está en owned; short_sword se otorga al primer ready.
	_starter_weapon_grant()
	# Restaurar estado persistido (SaveSystem) ANTES de imprimir, para que
	# el print refleje el bank real (no el de un fresh start).
	_apply_saved_state()
	print("[ProgressionState] ready (skill_points=%d, proficiency=%d, tier=%s)" % [
		skill_points, proficiency, Balance.get_tier(proficiency).name
	])
	print("[ProgressionState] weapons in catalog: %d" % WeaponCatalogScript.list_ids().size())


## Restaura el estado desde SaveSystem (si hay datos guardados).
## Se llama en _ready() después de _starter_weapon_grant, así que el
## auto-grant no doble-otorga las armas starter. Si no hay save, no-op.
func _apply_saved_state() -> void:
	var save_sys: Node = Engine.get_main_loop().root.get_node_or_null("SaveSystem")
	if save_sys == null or not save_sys.has_method("consume"):
		return
	var data: Dictionary = save_sys.consume(&"progression")
	if data.is_empty():
		return
	from_dict(data)


## to_dict() — serializa el estado mutable del game master.
## NO incluye skill_catalog (es derivada de los .tres files en boot).
## NO incluye owned_skills (player.gd los carga en su propio _ready).
func to_dict() -> Dictionary:
	var equipped_id: String = ""
	if equipped_weapon != null and "id" in equipped_weapon:
		equipped_id = String(equipped_weapon.id)
	return {
		"skill_points": skill_points,
		"attribute_points": attribute_points,
		"proficiency": proficiency,
		"allocations": _dict_to_str_keys(allocations),
		"element_allocations": _dict_to_str_keys(element_allocations),
		"attribute_allocations": _dict_to_str_keys(attribute_allocations),
		"weapon_allocations": _dict_to_str_keys(weapon_allocations),
		"owned_weapons": _stringname_array_to_strings(owned_weapons),
		"equipped_weapon_id": equipped_id,
	}


## from_dict(data) — restaura el estado desde un dict producido por to_dict().
## Idempotente: si se llama sin datos, no hace nada.
func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	skill_points = int(data.get("skill_points", 0))
	attribute_points = int(data.get("attribute_points", 0))
	proficiency = int(data.get("proficiency", 0))
	allocations = _str_keys_to_dict_of_str_keys(data.get("allocations", {}))
	element_allocations = _str_keys_to_dict_of_int(data.get("element_allocations", {}))
	attribute_allocations = _str_keys_to_dict_of_int(data.get("attribute_allocations", {}))
	weapon_allocations = _str_keys_to_dict_of_str_keys(data.get("weapon_allocations", {}))
	# owned_weapons: merge con los ya otorgados por _starter_weapon_grant.
	var saved_weapons: Array = data.get("owned_weapons", [])
	for w in saved_weapons:
		var ws: StringName = StringName(String(w))
		if ws != &"" and ws not in owned_weapons:
			owned_weapons.append(ws)
	# equipped_weapon: re-load del WeaponResource desde el catálogo.
	var eq_id: String = String(data.get("equipped_weapon_id", ""))
	if eq_id != "":
		var ws2: StringName = StringName(eq_id)
		if ws2 in owned_weapons:
			equip_weapon(ws2)
	# Re-aplicar stats derivados (HP/Stamina/regen cambian con attribute_allocations).
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_method("_apply_attribute_derived_stats"):
		player.call("_apply_attribute_derived_stats")


# Helpers de serialización (StringName no es JSON-friendly)
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


## Otorga las armas starter al jugador. Idempotente.
##
## Hasta nuevo aviso: forzamos short_sword como arma equipada. Cualquier
## otra arma que el jugador haya equipado via MCP es re-equipada con
## short_sword al boot. Cuando se reactive el modelado de armas, cambiar
## este guard a un check de "no hay otra equipada todavía".
func _starter_weapon_grant() -> void:
	if &"unarmed" not in owned_weapons:
		grant_weapon(&"unarmed")
	# Starter weapon: short_sword. Auto-grant al boot.
	if &"short_sword" not in owned_weapons:
		grant_weapon(&"short_sword")
	# FORCE: short_sword siempre equipada al boot (decisión temporal).
	equip_weapon(&"short_sword")


## grant_skill_points(points) — añade puntos al bank y al proficiency.
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


## spend_points(points) — resta puntos del bank. Devuelve true si exitoso.
func spend_points(points: int) -> bool:
	if points > skill_points:
		return false
	skill_points -= points
	skill_points_changed.emit(skill_points)
	data_changed.emit()
	return true


## allocate(skill_id, stat, points) — distribuye puntos a un stat.
## Devuelve true si exitoso, false si no hay puntos o excede max.
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


## deallocate(skill_id, stat, points) — devuelve puntos al bank.
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


## can_allocate_more(skill_id, stat, points) — ¿se puede asignar?
func can_allocate_more(skill_id: StringName, stat: StringName, points: int) -> bool:
	if skill_points < points:
		return false
	var current: int = int(allocations.get(String(skill_id), {}).get(String(stat), 0))
	var max_points := int(Balance.DEFAULT_MAX_POINTS_PER_STAT)
	return current + points <= max_points


## add_skill(skill: SkillResource) — añade a owned y al catálogo.
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
	# Devolver allocations al bank
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


## get_skill(id) — devuelve el SkillResource por ID.
func get_skill(id: StringName):
	return skill_catalog.get(id, null)


## Devuelve el nombre del tier actual ("Novice", "Apprentice", etc.)
func get_tier_name() -> String:
	Balance.load_config()
	return String(Balance.get_tier(proficiency).get("name", "Unknown"))


## get_effective_stat_for_skill(skill_id, stat_name, designed_value)
## El corazón del balance: dado un stat y su designed_max, devuelve el valor
## efectivo considerando points invertidos y proficiency.
func get_effective_stat_for_skill(skill_id: StringName, stat_name: StringName, designed_value: float) -> float:
	var points := 0
	if allocations.has(String(skill_id)):
		points = int(allocations[String(skill_id)].get(String(stat_name), 0))
	return Balance.compute_effective(designed_value, points, Balance.DEFAULT_MAX_POINTS_PER_STAT, proficiency)


## get_skill_power_ratio(skill_id) — ratio de poder total (0..1) del skill.
## Útil para cost scaling: stamina = base * (1 - power_ratio) ... etc.
## Promedio ponderado de los stats de la skill.
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


## get_effective_designed_max(skill_id) — devuelve el designed_max de la skill owned.
func get_effective_designed_max(skill_id: StringName) -> Dictionary:
	var skill = get_skill(skill_id)
	if skill == null:
		return {}
	return skill.designed_max.duplicate()


## trigger_skill(skill_id, caster) — para combo triggers.
## Busca la skill en el catálogo, crea un SkillExecutor, y la castea sobre caster.
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


## get_state_snapshot() — estado serializable para MCP/UI/debug.
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
	# Snapshot de elementos con sus multipliers derivados
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


# === ELEMENT ALLOCATION (sistema de fortalezas/resistencias) ===

## allocate_element(element, points) — asigna puntos a un elemento.
## Devuelve true si exitoso.
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
	# Refrescar ResistanceComponent del player
	_refresh_resistance_components()
	data_changed.emit()
	return true


## deallocate_element(element, points) — devuelve puntos al bank.
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


## can_allocate_element_more(element, points) — ¿hay cupo?
func can_allocate_element_more(element: StringName, points: int) -> bool:
	if points > skill_points:
		return false
	var current: int = int(element_allocations.get(element, 0))
	return current + points <= Elements.MAX_ELEMENT_POINTS


## get_element_attack_multiplier(element) — multiplicador de ataque del player.
func get_element_attack_multiplier(element: StringName) -> float:
	var pts: int = int(element_allocations.get(element, 0))
	return Elements.get_attack_multiplier(pts)


## get_element_resistance_multiplier(element) — multiplicador de resistencia.
func get_element_resistance_multiplier(element: StringName) -> float:
	var pts: int = int(element_allocations.get(element, 0))
	return Elements.get_resistance_multiplier(pts)


## _refresh_resistance_components() — llama a los ResistanceComponents
## del player para que recarguen desde element_allocations.
func _refresh_resistance_components() -> void:
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_node("ResistanceComponent"):
		player.get_node("ResistanceComponent").call("_refresh_from_progression")


# === ATTRIBUTE ALLOCATION (sistema de stats + resistencias) ===

## grant_attribute_points(points) — añade puntos al bank de atributos.
func grant_attribute_points(points: int) -> void:
	if points <= 0:
		return
	attribute_points += points
	attribute_points_changed.emit(attribute_points)
	print("[Progression] +%d attribute_points (bank=%d)" % [points, attribute_points])
	data_changed.emit()


## spend_attribute_points(points) — resta puntos del bank. Devuelve true si exitoso.
func spend_attribute_points(points: int) -> bool:
	if points > attribute_points:
		return false
	attribute_points -= points
	attribute_points_changed.emit(attribute_points)
	data_changed.emit()
	return true


## allocate_attribute(attr_id, points) — asigna puntos a un atributo.
## Devuelve true si exitoso.
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


## deallocate_attribute(attr_id, points) — devuelve puntos al bank.
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
	attribute_points += points
	attribute_points_changed.emit(attribute_points)
	attribute_allocation_changed.emit(attr_id, int(attribute_allocations.get(key, 0)))
	_refresh_attribute_components()
	data_changed.emit()
	return true


## can_allocate_attribute_more(attr_id, points) — ¿hay cupo?
## Máximo 5 puntos por atributo (igual que skill stats).
func can_allocate_attribute_more(attr_id: StringName, points: int) -> bool:
	if points > attribute_points:
		return false
	var current: int = int(attribute_allocations.get(String(attr_id), 0))
	return current + points <= 5


## get_attribute_points(attr_id) — puntos asignados a un atributo.
func get_attribute_points(attr_id: StringName) -> int:
	return int(attribute_allocations.get(String(attr_id), 0))


## get_total_allocated_attribute_points() — total de puntos asignados.
func get_total_allocated_attribute_points() -> int:
	var total := 0
	for v in attribute_allocations.values():
		total += int(v)
	return total


## reset_attribute_allocations() — devuelve todos los puntos al bank.
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


## _refresh_attribute_components() — recarga AttributeComponents del player.
func _refresh_attribute_components() -> void:
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_node("AttributeComponent"):
		player.get_node("AttributeComponent").call("refresh_from_progression_state")
		# Aplicar cambios de HP/Stamina max al player
		if player.has_method("_apply_attribute_derived_stats"):
			player.call("_apply_attribute_derived_stats")


# ============================================================
# === SISTEMA DE ARMAS (Post-MVP) ===
# ============================================================

## grant_weapon(weapon_id) — añade un arma al inventario del jugador.
## El arma debe existir en el WeaponCatalog.
func grant_weapon(weapon_id: StringName) -> bool:
	if weapon_id in owned_weapons:
		return false
	owned_weapons.append(weapon_id)
	weapon_owned.emit(weapon_id)
	# Auto-equipa la primera arma si no hay nada equipado
	if equipped_weapon == null:
		equip_weapon(weapon_id)
	data_changed.emit()
	return true


## remove_weapon(weapon_id) — quita un arma del inventario.
func remove_weapon(weapon_id: StringName) -> bool:
	if weapon_id not in owned_weapons:
		return false
	owned_weapons.erase(weapon_id)
	weapon_allocations.erase(weapon_id)
	weapon_unowned.emit(weapon_id)
	# Si era la equipada, desequipa
	if equipped_weapon != null and String(equipped_weapon.id) == String(weapon_id):
		unequip_weapon()
	data_changed.emit()
	return true


## equip_weapon(weapon_id) — marca un arma como equipada.
## Carga el WeaponResource desde el catálogo y lo guarda en equipped_weapon.
func equip_weapon(weapon_id: StringName) -> bool:
	if weapon_id not in owned_weapons:
		push_warning("[ProgressionState] equip_weapon: %s not owned" % weapon_id)
		return false
	var catalog := preload("res://scripts/skill/weapon_catalog.gd")
	var wpn: Resource = catalog.get_weapon(weapon_id)
	if wpn == null:
		push_warning("[ProgressionState] equip_weapon: %s not in catalog" % weapon_id)
		return false
	equipped_weapon = wpn
	weapon_equipped.emit(weapon_id)
	print("[ProgressionState] equipped weapon: %s (%s, %dh)" % [String(weapon_id), wpn.display_name, wpn.hands])
	# Notificar al player para que cambie el visual
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_method("set_equipped_weapon"):
		player.call("set_equipped_weapon", wpn)
	data_changed.emit()
	return true


## unequip_weapon() — desequipa el arma actual. Pasa a "unarmed" implícito.
func unequip_weapon() -> void:
	if equipped_weapon == null:
		return
	equipped_weapon = null
	weapon_unequipped.emit()
	var player: Node = Engine.get_main_loop().root.find_child("Player", true, false)
	if player and player.has_method("set_equipped_weapon"):
		player.call("set_equipped_weapon", null)
	data_changed.emit()


## can_allocate_weapon(weapon_id, stat, points) — ¿se pueden asignar N puntos más?
func can_allocate_weapon(weapon_id: StringName, stat: StringName, points: int) -> bool:
	if points <= 0:
		return false
	var current: int = get_weapon_points(weapon_id, stat)
	if current + points > 5:
		return false
	return points <= skill_points


## allocate_weapon(weapon_id, stat, points) — asigna puntos a un stat del arma.
## Consume skill_points. Cap 5 puntos por stat. El efecto real se calcula en
## WeaponResource.get_scaled_*() (str, dex, etc.) leyendo estos puntos.
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


## deallocate_weapon(weapon_id, stat, points) — devuelve puntos al bank.
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


## get_weapon_points(weapon_id, stat) — puntos asignados a un stat de un arma.
func get_weapon_points(weapon_id: StringName = &"", stat: StringName = &"") -> int:
	if weapon_id == &"":
		return skill_points
	if not weapon_allocations.has(weapon_id):
		return 0
	return int((weapon_allocations[weapon_id] as Dictionary).get(stat, 0))


## get_weapon(weapon_id) — devuelve el WeaponResource del catálogo, o null.
func get_weapon(weapon_id: StringName) -> Resource:
	if WeaponCatalogScript == null:
		return null
	return WeaponCatalogScript.get_weapon(weapon_id)


## get_weapon_catalog(filter) — Array[StringName] de weapon_ids del catálogo.
## filter: "all" (default), "owned", "unequipped".
func get_weapon_catalog(filter: StringName = &"all") -> Array[StringName]:
	if WeaponCatalogScript == null:
		return []
	var ids: Array[StringName] = WeaponCatalogScript.list_ids()
	if filter == &"owned":
		return ids.filter(func(wid): return wid in owned_weapons)
	return ids
