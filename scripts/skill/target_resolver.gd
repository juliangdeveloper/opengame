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
class_name TargetResolver
extends RefCounted

const NPC_GROUP := "enemies"
const PLAYER_GROUP := "player"


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
		&"aoe":
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
	return result


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
