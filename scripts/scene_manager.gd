extends Node

const SCENE_PATH := "res://rulebook/scenes/test_world.json"

var _tracked: Dictionary = {}

var _scene_data: Dictionary = {}

var auto_save_interval: float = 5.0
var _save_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_scene()
	call_deferred("_apply_scene")
	print("[SceneManager] initialized: %s" % SCENE_PATH)


func _process(delta: float) -> void:
	if auto_save_interval > 0.0:
		_save_timer += delta
		if _save_timer >= auto_save_interval:
			_save_timer = 0.0
			save_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_scene()



func _load_scene() -> void:
	var file := FileAccess.open(SCENE_PATH, FileAccess.READ)
	if file == null:
		push_warning("[SceneManager] cannot open: %s" % SCENE_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_warning("[SceneManager] JSON parse error: %s" % json.get_error_message())
		return
	_scene_data = json.data
	print("[SceneManager] loaded scene: %s (%d instances)" % [
		_scene_data.get("scene_id", "?"),
		_scene_data.get("instances", []).size()
	])



func _apply_scene() -> void:
	var instances: Array = _scene_data.get("instances", [])
	var root := get_tree().current_scene
	if root == null:
		push_warning("[SceneManager] no current_scene")
		return

	var valid_names: Dictionary = {}
	for inst in instances:
		var nn: String = inst.get("node_name", "")
		if nn != "":
			valid_names[nn] = true

	for inst in instances:
		var id: String = inst.get("id", "")
		var node_name: String = inst.get("node_name", "")
		var pos: Array = inst.get("position", [0, 0, 0])
		var rot: Array = inst.get("rotation_deg", [0, 0, 0])
		var state: Dictionary = inst.get("state", {})

		var node: Node = root.find_child(node_name, true, false) if node_name != "" else null
		if node == null:
			print("[SceneManager] node not found: %s (id=%s)" % [node_name, id])
			continue

		if node is Node3D:
			node.global_position = Vector3(pos[0], pos[1], pos[2])
			node.rotation_degrees = Vector3(rot[0], rot[1], rot[2])

		if node.has_method("take_damage") and node is StaticBody3D:
			if state.has("hp") and float(state["hp"]) > 0:
				if "hp" in node:
					node.hp = float(state["hp"])
			if state.has("weight"):
				if "weight" in node:
					node.weight = float(state["weight"])

		_tracked[id] = {
			"node": node,
			"node_name": node_name,
			"entity_ref": inst.get("entity_ref", ""),
			"object_ref": inst.get("object_ref", ""),
			"state": state.duplicate(),
		}
		print("[SceneManager] applied: %s → %s at %s" % [id, node_name, str(pos)])

	var all_objects: Array = root.find_children("*", "StaticBody3D", true, false)
	for obj in all_objects:
		if obj is GameObject and obj.name not in valid_names:
			print("[SceneManager] freeing destroyed object: %s" % obj.name)
			obj.queue_free()



func report_position(node: Node3D) -> void:
	var id: String = _find_tracked_id(node)
	if id == "":
		return
	_tracked[id]["pos_changed"] = true


func report_object_state(node: Node, hp: float, weight: float) -> void:
	var id: String = _find_tracked_id(node)
	if id == "":
		return
	_tracked[id]["hp"] = hp
	_tracked[id]["weight"] = weight
	_tracked[id]["state_changed"] = true


func _find_tracked_id(node: Node) -> String:
	for id in _tracked:
		if _tracked[id].get("node") == node:
			return id
	return ""


func report_destroyed(node: Node) -> void:
	var id: String = _find_tracked_id(node)
	if id == "":
		return
	var instances: Array = _scene_data.get("instances", [])
	for i in range(instances.size() - 1, -1, -1):
		if instances[i].get("id", "") == id:
			instances.remove_at(i)
			break
	_tracked.erase(id)
	print("[SceneManager] instance removed: %s" % id)
	save_scene()



func save_scene() -> void:
	if _scene_data.is_empty():
		return

	var instances: Array = _scene_data.get("instances", [])
	for inst in instances:
		var id: String = inst.get("id", "")
		if not _tracked.has(id):
			continue
		var tracked: Dictionary = _tracked[id]
		var node: Node = tracked.get("node", null)
		if node == null or not is_instance_valid(node):
			continue

		if node is Node3D:
			var p: Vector3 = node.global_position
			inst["position"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
			var r: Vector3 = node.rotation_degrees
			inst["rotation_deg"] = [snappedf(r.x, 0.01), snappedf(r.y, 0.01), snappedf(r.z, 0.01)]

		if tracked.get("state_changed", false):
			if tracked.has("hp"):
				inst["state"]["hp"] = tracked["hp"]
			if tracked.has("weight"):
				inst["state"]["weight"] = tracked["weight"]

	var json_str: String = JSON.stringify(_scene_data, "\t")
	var file := FileAccess.open(SCENE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[SceneManager] cannot write: %s" % SCENE_PATH)
		return
	file.store_string(json_str)
	file.close()
	print("[SceneManager] saved scene (%d instances)" % instances.size())
