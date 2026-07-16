## scene_manager.gd — RuleBook scene state manager (autoload singleton).
##
## Reads scene JSON on load, applies positions/state to scene tree nodes.
## Tracks changes and writes back to JSON to keep RuleBook in sync.
##
## Contract:
##   on_load  → read JSON, apply position/rotation/state to each instance
##   on_change → nodes call report_position/report_state when they change
##   on_save  → serialize all tracked state back to JSON
extends Node

const SCENE_PATH := "res://rulebook/scenes/test_world.json"

## Tracked instances: instance_id → { node, last_pos, last_rot }
var _tracked: Dictionary = {}

## Current scene data (loaded from JSON)
var _scene_data: Dictionary = {}

## Auto-save interval in seconds (0 = save only on exit)
var auto_save_interval: float = 5.0
var _save_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_scene()
	# Wait one frame for all nodes to be ready, then apply
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


## ============================================================
## LOAD — read JSON from rulebook/scenes/
## ============================================================

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


## ============================================================
## APPLY — set positions/rotation/state from JSON to scene tree
## ============================================================

func _apply_scene() -> void:
	var instances: Array = _scene_data.get("instances", [])
	var root := get_tree().current_scene
	if root == null:
		push_warning("[SceneManager] no current_scene")
		return

	# Build set of valid node_names from JSON
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

		# Find node by name in current scene tree
		var node: Node = root.find_child(node_name, true, false) if node_name != "" else null
		if node == null:
			print("[SceneManager] node not found: %s (id=%s)" % [node_name, id])
			continue

		# Apply transform
		if node is Node3D:
			node.global_position = Vector3(pos[0], pos[1], pos[2])
			node.rotation_degrees = Vector3(rot[0], rot[1], rot[2])

		# Apply state to game objects
		if node.has_method("take_damage") and node is StaticBody3D:
			if state.has("hp") and float(state["hp"]) > 0:
				# Set HP directly (max_hp is set by the object's own data)
				if "hp" in node:
					node.hp = float(state["hp"])
			if state.has("weight"):
				if "weight" in node:
					node.weight = float(state["weight"])

		# Track for future saves
		_tracked[id] = {
			"node": node,
			"node_name": node_name,
			"entity_ref": inst.get("entity_ref", ""),
			"object_ref": inst.get("object_ref", ""),
			"state": state.duplicate(),
		}
		print("[SceneManager] applied: %s → %s at %s" % [id, node_name, str(pos)])

	# Free GameObjects that exist in scene but NOT in JSON (were destroyed)
	var all_objects: Array = root.find_children("*", "StaticBody3D", true, false)
	for obj in all_objects:
		if obj is GameObject and obj.name not in valid_names:
			print("[SceneManager] freeing destroyed object: %s" % obj.name)
			obj.queue_free()


## ============================================================
## REPORT — called by game nodes when position/state changes
## ============================================================

## Called by Player.gd after move_and_slide
func report_position(node: Node3D) -> void:
	var id: String = _find_tracked_id(node)
	if id == "":
		return
	_tracked[id]["pos_changed"] = true


## Called by GameObject.gd after push or damage
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


## Called when a tracked object is destroyed (from game_object.gd _destroy)
func report_destroyed(node: Node) -> void:
	var id: String = _find_tracked_id(node)
	if id == "":
		return
	# Remove from scene data entirely
	var instances: Array = _scene_data.get("instances", [])
	for i in range(instances.size() - 1, -1, -1):
		if instances[i].get("id", "") == id:
			instances.remove_at(i)
			break
	# Remove from tracking
	_tracked.erase(id)
	print("[SceneManager] instance removed: %s" % id)
	# Save immediately so next load doesn't have it
	save_scene()


## ============================================================
## SAVE — serialize current state back to JSON
## ============================================================

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

		# Update position from live node
		if node is Node3D:
			var p: Vector3 = node.global_position
			inst["position"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
			var r: Vector3 = node.rotation_degrees
			inst["rotation_deg"] = [snappedf(r.x, 0.01), snappedf(r.y, 0.01), snappedf(r.z, 0.01)]

		# Update state from tracked changes
		if tracked.get("state_changed", false):
			if tracked.has("hp"):
				inst["state"]["hp"] = tracked["hp"]
			if tracked.has("weight"):
				inst["state"]["weight"] = tracked["weight"]

	# Write to file
	var json_str: String = JSON.stringify(_scene_data, "\t")
	var file := FileAccess.open(SCENE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[SceneManager] cannot write: %s" % SCENE_PATH)
		return
	file.store_string(json_str)
	file.close()
	print("[SceneManager] saved scene (%d instances)" % instances.size())
