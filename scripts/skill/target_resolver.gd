## TargetResolver — Resuelve targets de skills en runtime.
##
## Dado un SkillResource y un caster, devuelve los nodos que son targets
## de la skill en el frame actual. Se llama cada frame por SkillExecutor.
##
## Kinds soportados (deben coincidir con skill_atoms.json):
##   - self                 -> el caster
##   - selected_npc         -> el NPC bajo el retículo (lock-on target)
##   - nearest_npc_in_range -> el NPC más cercano dentro de max_distance
##   - aoe                  -> todos los NPCs en un área (center+radio)
##   - self_aoe             -> todos los NPCs en radio alrededor del caster
##   - chain                -> hasta max_hops NPCs cercanos
##   - projectile_carrier   -> el proyectil de un atom projectile previo
##   - zone_entered         -> NPCs que entraron en una zona existente
##   - equipped_weapon      -> el arma equipada del caster (para skills de "empuñadura"/"lanzar arma")
##   - env_object_aoe       -> todos los EnvironmentObject en radio
##   - env_object_nearest   -> el EnvironmentObject más cercano en rango
##   - weapon_nearest       -> el arma (WeaponResource-equipable) más cercana
class_name TargetResolver
extends RefCounted

const NPC_GROUP := "enemies"
const PLAYER_GROUP := "player"
const ENV_OBJECT_GROUP := "env_objects"
const WEAPON_GROUP := "dropped_weapons"


## Resuelve los targets para una skill. Devuelve Array[Node].
## caster: el nodo que castea (CharacterBody3D típicamente).
## skill: el SkillResource.
## params opcionales (dependen del kind).
static func resolve(
	kind: StringName,
	caster: Node,
	params: Dictionary = {},
	projectile_carrier: Node = null
) -> Array[Node]:
	var result: Array[Node] = []
	match kind:
		&"self":
			result.append(caster)
		&"selected_npc":
			var sel := _get_selected_npc(caster, params)
			if sel:
				result.append(sel)
		&"nearest_npc_in_range":
			var nearest := _get_nearest_npc_in_range(caster, params)
			if nearest:
				result.append(nearest)
		&"aoe", &"beam":
			# "beam" es un alias de "aoe" con shape=beam. Permite a los
			# autores de skills escribir kind="beam" directamente sin
			# anidar un shape dentro de aoe.
			var shape := String(params.get("shape", "sphere" if kind == &"aoe" else "beam"))
			if shape == "beam":
				result = _get_npcs_in_beam(caster, params)
			else:
				var center: Vector3 = _resolve_aoe_center(caster, params)
				var radius := float(params.get("radius", 5.0))
				result = _get_npcs_in_radius(center, radius)
		&"self_aoe":
			var r := float(params.get("radius", 5.0))
			result = _get_npcs_in_radius(caster.global_position, r)
		&"chain":
			var max_hops := int(params.get("max_hops", 3))
			result = _get_chain(caster, max_hops)
		&"projectile_carrier":
			if projectile_carrier and is_instance_valid(projectile_carrier):
				result.append(projectile_carrier)
		&"zone_entered":
			# Placeholder: el executor maneja el trigger on_enter separadamente.
			pass
		&"equipped_weapon":
			# Devuelve el arma equipada del caster (como un nodo-fantasma envuelto
			# en un WeaponTarget wrapper si no hay nodo físico).
			var wep := _get_equipped_weapon(caster)
			if wep != null:
				result.append(wep)
		&"env_object_aoe":
			var center_e: Vector3 = _resolve_aoe_center(caster, params)
			var r_e: float = float(params.get("radius", 5.0))
			result = _get_env_objects_in_radius(center_e, r_e)
		&"env_object_nearest":
			var env_obj := _get_nearest_env_object_in_range(caster, params)
			if env_obj:
				result.append(env_obj)
		&"weapon_nearest":
			var wpn := _get_nearest_weapon_in_range(caster, params)
			if wpn != null:
				result.append(wpn)
		&"player":
			# Para boss AI: el caster (boss) siempre apunta al player.
			# Devuelve el nodo "Player" del root, sin importar distancia.
			# Los átomos con falloff/range check se encargan de filtrar.
			var pl: Node = null
			if caster and caster.get_tree():
				pl = caster.get_tree().root.find_child("Player", true, false)
			if pl != null:
				result.append(pl)
		&"player_aoe":
			# Boss AoE: devolver TODOS los nodos en PLAYER_GROUP dentro del radio.
			# Útil para bosses con skills de "campo" que no quieren auto-dañarse.
			var center_p: Node3D = null
			if caster is Node3D:
				center_p = caster as Node3D
			elif params.has("position") and params.position is Vector3:
				center_p = params.position
			var r_p: float = float(params.get("radius", 6.0))
			if center_p == null:
				return result
			var r2_p := r_p * r_p
			for n in Engine.get_main_loop().get_nodes_in_group(PLAYER_GROUP) if Engine.get_main_loop() else []:
				if not is_instance_valid(n) or not n is Node3D:
					continue
				if (n as Node3D).global_position.distance_squared_to(center_p.global_position) <= r2_p:
					result.append(n)
	return result


## Devuelve un nodo "virtual" que representa el arma equipada del caster.
## Si el caster tiene un nodo "Weapon" hijo, lo devuelve. Si no, devuelve null
## (el caller puede envolver un WeaponResource en un wrapper ligero si hace falta).
static func _get_equipped_weapon(caster: Node) -> Node:
	if caster == null:
		return null
	var wep: Node = caster.get_node_or_null("Weapon")
	if wep != null:
		return wep
	# Buscar también "Model/Weapon" (la convención del Player actual)
	var model: Node = caster.get_node_or_null("Model")
	if model != null:
		wep = model.get_node_or_null("Weapon")
	return wep


## Devuelve todos los EnvironmentObject en un radio.
static func _get_env_objects_in_radius(center: Vector3, radius: float) -> Array[Node]:
	var result: Array[Node] = []
	var r2 := radius * radius
	var tree := Engine.get_main_loop()
	if tree == null:
		return result
	for n in tree.get_nodes_in_group(ENV_OBJECT_GROUP):
		if not is_instance_valid(n) or not n is Node3D:
			continue
		if (n as Node3D).global_position.distance_squared_to(center) <= r2:
			result.append(n)
	return result


## Devuelve el EnvironmentObject más cercano en rango.
static func _get_nearest_env_object_in_range(caster: Node, params: Dictionary) -> Node:
	if caster == null or not caster is Node3D:
		return null
	var max_distance: float = float(params.get("max_distance", 20.0))
	var c3d: Node3D = caster
	var best: Node = null
	var best_d2 := max_distance * max_distance
	for n in caster.get_tree().get_nodes_in_group(ENV_OBJECT_GROUP):
		if not is_instance_valid(n) or not n is Node3D:
			continue
		var d2 := (n as Node3D).global_position.distance_squared_to(c3d.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best


## Devuelve el arma "suelta" más cercana (escenario: pickup de arma del suelo).
static func _get_nearest_weapon_in_range(caster: Node, params: Dictionary) -> Node:
	if caster == null or not caster is Node3D:
		return null
	var max_distance: float = float(params.get("max_distance", 5.0))
	var c3d: Node3D = caster
	var best: Node = null
	var best_d2 := max_distance * max_distance
	for n in caster.get_tree().get_nodes_in_group(WEAPON_GROUP):
		if not is_instance_valid(n) or not n is Node3D:
			continue
		var d2 := (n as Node3D).global_position.distance_squared_to(c3d.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best


## Resuelve la posición central de un AOE.
## params.position puede ser:
##   - "in_front_of_caster": a distance_forward metros adelante
##   - "selected_npc": en el NPC seleccionado
##   - "at_target": en el target actual
##   - Vector3 literal: posición fija
static func _resolve_aoe_center(caster: Node, params: Dictionary) -> Vector3:
	var pos: Variant = params.get("position", "in_front_of_caster")
	if pos is Vector3:
		return pos
	if not caster is Node3D:
		return Vector3.ZERO
	var c3d := caster as Node3D
	match pos:
		"in_front_of_caster":
			var dist := float(params.get("distance_forward", 5.0))
			return c3d.global_position - c3d.global_transform.basis.z * dist
		"selected_npc":
			var sel := _get_selected_npc(caster, {})
			if sel and sel is Node3D:
				return (sel as Node3D).global_position
			return c3d.global_position
		"at_target":
			# Mismo que selected_npc por ahora
			var t := _get_selected_npc(caster, {})
			if t and t is Node3D:
				return (t as Node3D).global_position
			return c3d.global_position
	return c3d.global_position


## Busca el NPC bajo el retículo. Usa el grupo "selected_target" si existe,
## sino el NPC más cercano en el cono de visión.
static func _get_selected_npc(caster: Node, _params: Dictionary) -> Node:
	if not caster is Node3D:
		return null
	var tree := caster.get_tree()
	if not tree:
		return null
	# Primero, si hay un target explícitamente seleccionado, usarlo
	for n in tree.get_nodes_in_group("selected_target"):
		if is_instance_valid(n):
			return n
	# Fallback: el más cercano en el cono de visión
	var caster3d := caster as Node3D
	var forward := -caster3d.global_transform.basis.z
	var best: Node = null
	var best_dot := 0.95  # ~18° cone
	for n in tree.get_nodes_in_group(NPC_GROUP):
		if not is_instance_valid(n) or not n is Node3D:
			continue
		var npc3d := n as Node3D
		var to_npc := (npc3d.global_position - caster3d.global_position).normalized()
		var d := to_npc.dot(forward)
		if d > best_dot:
			best_dot = d
			best = n
	return best


static func _get_nearest_npc_in_range(caster: Node, params: Dictionary) -> Node:
	if not caster is Node3D:
		return null
	var max_distance := float(params.get("max_distance", 20.0))
	var caster3d := caster as Node3D
	var best: Node = null
	var best_dist := max_distance * max_distance  # squared
	for n in caster.get_tree().get_nodes_in_group(NPC_GROUP):
		if not is_instance_valid(n) or not n is Node3D:
			continue
		var d2 := (n as Node3D).global_position.distance_squared_to(caster3d.global_position)
		if d2 < best_dist:
			best_dist = d2
			best = n
	return best


static func _get_npcs_in_radius(center: Vector3, radius: float) -> Array[Node]:
	var result: Array[Node] = []
	var r2 := radius * radius
	# Buscar tanto en enemies como en player (para AOE que afecte aliados)
	for g in [NPC_GROUP, PLAYER_GROUP]:
		for n in Engine.get_main_loop().get_nodes_in_group(g) if Engine.get_main_loop() else []:
			if not is_instance_valid(n) or not n is Node3D:
				continue
			if (n as Node3D).global_position.distance_squared_to(center) <= r2:
				result.append(n)
	return result

static func _get_npcs_in_beam(caster: Node, params: Dictionary) -> Array[Node]:
	var result: Array[Node] = []
	if not caster is Node3D:
		return result
	var c3d := caster as Node3D
	var start := c3d.global_position + (-c3d.global_transform.basis.z * float(params.get("distance_forward", 1.0)))
	var length := float(params.get("beam_length", 12.0))
	var radius := float(params.get("radius", 1.5))
	var dir := (-c3d.global_transform.basis.z).normalized()
	var r2 := radius * radius
	for g in [NPC_GROUP, PLAYER_GROUP]:
		for n in c3d.get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n) or not n is Node3D:
				continue
			if n == caster:
				continue
			var p := (n as Node3D).global_position
			var along := (p - start).dot(dir)
			if along < 0.0 or along > length:
				continue
			var closest := start + dir * along
			if p.distance_squared_to(closest) <= r2:
				result.append(n)
	return result

## Chain: empieza en el target principal y salta a los más cercanos.
static func _get_chain(caster: Node, max_hops: int) -> Array[Node]:
	var result: Array[Node] = []
	var first := _get_nearest_npc_in_range(caster, { "max_distance": 50.0 })
	if not first or not first is Node3D:
		return result
	result.append(first)
	var current: Node3D = first as Node3D
	var visited: Array[Node] = [first]
	for i in range(1, max_hops):
		var next_best: Node = null
		var next_best_dist := INF
		for n in caster.get_tree().get_nodes_in_group(NPC_GROUP):
			if n in visited or not is_instance_valid(n) or not n is Node3D:
				continue
			var d := (n as Node3D).global_position.distance_squared_to(current.global_position)
			if d < next_best_dist:
				next_best_dist = d
				next_best = n
		if not next_best:
			break
		result.append(next_best)
		visited.append(next_best)
		current = next_best as Node3D
	return result
