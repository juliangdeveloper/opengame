## MCPReceiver — Autoload TCP server que recibe comandos JSON-RPC del LLM.
##
## Arquitectura:
##   [LLM/MCP] -> [FastAPI bridge] -> [Godot MCPReceiver (este)] -> [acciones]
##
## Escucha en 127.0.0.1:9876 (configurable). Cada conexión es una serie de
## requests JSON-RPC 2.0 (un JSON por línea, newline-delimited).
##
## Métodos expuestos (mapean a mcp_tools.md):
##   - ping
##   - get_player_state
##   - grant_skill_points
##   - grant_skill
##   - spawn_enemy
##   - set_objective
##   - run_skill_test
##
## Respuestas siguen JSON-RPC 2.0:
##   {"jsonrpc": "2.0", "id": N, "result": {...}}  (éxito)
##   {"jsonrpc": "2.0", "id": N, "error": {"code": N, "message": "..."}}  (error)
##
## El autoload se registra en project.godot.
extends Node

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 9876

var _server: TCPServer
var _is_running: bool = false
var _clients: Array = []  # Array[StreamPeerBuffer] activos
var _poll_timer: Timer

# Comandos pendientes de procesar en _process
var _pending_commands: Array = []  # Array[Dictionary] {client_idx, request}

# Challenge tracking
var _challenges: Dictionary = {}
var _challenge_monitors: Array = []  # Array[Timer]


func _ready() -> void:
	_server = TCPServer.new()
	var err: int = _server.listen(DEFAULT_PORT, DEFAULT_HOST)
	if err != OK:
		push_error("[MCPReceiver] failed to listen on %s:%d (err=%d)" % [DEFAULT_HOST, DEFAULT_PORT, err])
		_is_running = false
		return
	_is_running = true
	print("[MCPReceiver] listening on %s:%d" % [DEFAULT_HOST, DEFAULT_PORT])
	# Timer para poll (acepta conexiones + lee clientes)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.05
	_poll_timer.timeout.connect(_poll)
	_poll_timer.autostart = true
	add_child(_poll_timer)


func _process(_delta: float) -> void:
	# Procesa comandos pendientes
	while _pending_commands.size() > 0:
		var cmd: Dictionary = _pending_commands.pop_front()
		_handle_command(cmd)


func _poll() -> void:
	if not _is_running:
		return
	# Acepta nuevas conexiones
	while _server.is_connection_available():
		var conn: StreamPeerTCP = _server.take_connection()
		_clients.append(conn)
	# Lee clientes existentes
	for i in range(_clients.size() - 1, -1, -1):
		var c: StreamPeerTCP = _clients[i]
		c.poll()
		var status: int = c.get_status()
		if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
			_clients.remove_at(i)
			continue
		var avail: int = c.get_available_bytes()
		if avail <= 0:
			continue
		var bytes: PackedByteArray = c.get_data(avail)[1]
		if bytes.size() == 0:
			continue
		var text := bytes.get_string_from_utf8()
		# Cada línea = un JSON request
		for line in text.split("\n", false):
			if line.strip_edges() == "":
				continue
			var req: Dictionary = JSON.parse_string(line)
			if req == null or not req is Dictionary:
				_send_error(c, -1, -32700, "parse error")
				continue
			_pending_commands.append({"client_idx": i, "request": req})


func _handle_command(cmd: Dictionary) -> void:
	var client_idx: int = cmd.client_idx
	var req: Dictionary = cmd.request
	if client_idx < 0 or client_idx >= _clients.size():
		return
	var c: StreamPeerTCP = _clients[client_idx]
	var method: String = String(req.get("method", ""))
	var params: Dictionary = req.get("params", {})
	var id_v: Variant = req.get("id", null)
	# Despacha
	var result: Variant = null
	var error: Dictionary = {}
	match method:
		"ping":
			result = {"pong": true, "ts": Time.get_ticks_msec()}
		"get_player_state":
			result = _cmd_get_player_state()
		"grant_skill_points":
			result = _cmd_grant_skill_points(params)
		"grant_skill":
			result = _cmd_grant_skill(params)
		"spawn_enemy":
			result = _cmd_spawn_enemy(params)
		"set_objective":
			result = _cmd_set_objective(params)
		"run_skill_test":
			result = _cmd_run_skill_test(params)
		"create_skill":
			result = _cmd_create_skill(params)
		"modify_skill":
			result = _cmd_modify_skill(params)
		"spawn_challenge":
			result = _cmd_spawn_challenge(params)
		"allocate_skill_points":
			result = _cmd_allocate_skill_points(params)
		"list_skills":
			result = _cmd_list_skills(params)
		_:
			error = {"code": -32601, "message": "method not found: %s" % method}
	# Responde
	var response: Dictionary = {"jsonrpc": "2.0", "id": id_v}
	if not error.is_empty():
		response["error"] = error
	else:
		response["result"] = result
	var json: String = JSON.stringify(response)
	c.put_data((json + "\n").to_utf8_buffer())


func _send_error(c: StreamPeerTCP, id_v: Variant, code: int, message: String) -> void:
	var response: Dictionary = {
		"jsonrpc": "2.0",
		"id": id_v,
		"error": {"code": code, "message": message}
	}
	c.put_data((JSON.stringify(response) + "\n").to_utf8_buffer())


# -------------------- Comandos --------------------

func _cmd_get_player_state() -> Dictionary:
	var ps: Node = get_tree().root.get_node_or_null("ProgressionState")
	if ps == null:
		return {"error": "ProgressionState not found"}
	return {
		"skill_points": ps.skill_points,
		"proficiency": ps.proficiency,
		"tier": ps.get_tier_name(),
		"owned_skills": Array(ps.owned_skills),
		"allocations": ps.allocations.duplicate(true),
		"scene": get_tree().current_scene.name if get_tree().current_scene else "<none>"
	}


func _cmd_grant_skill_points(params: Dictionary) -> Dictionary:
	var ps: Node = get_tree().root.get_node_or_null("ProgressionState")
	if ps == null:
		return {"error": "ProgressionState not found"}
	var amount: int = int(params.get("amount", 1))
	ps.grant_skill_points(amount)
	return {"granted": amount, "skill_points": ps.skill_points, "proficiency": ps.proficiency}


func _cmd_grant_skill(params: Dictionary) -> Dictionary:
	var ps: Node = get_tree().root.get_node_or_null("ProgressionState")
	if ps == null:
		return {"error": "ProgressionState not found"}
	var skill_id: String = String(params.get("skill_id", ""))
	# Busca el .tres cuyo id field == skill_id
	var skill: Resource = _find_skill_resource(skill_id)
	if skill == null:
		return {"error": "skill not found: %s" % skill_id}
	ps.add_skill(skill)
	return {"granted_skill": skill_id, "owned": Array(ps.owned_skills)}


## Busca un skill resource por su campo "id" en data/skills/*.tres
func _find_skill_resource(skill_id: String) -> Resource:
	var dir: DirAccess = DirAccess.open("res://data/skills")
	if dir == null:
		return null
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var path: String = "res://data/skills/%s" % fname
			var res: Resource = load(path)
			if res != null:
				var res_id: String = String(res.id) if "id" in res else ""
				if res_id == skill_id:
					return res
		fname = dir.get_next()
	dir.list_dir_end()
	return null


func _cmd_spawn_enemy(params: Dictionary) -> Dictionary:
	# Params: scene (string), position (Vector3 dict)
	var scene_path: String = String(params.get("scene", "res://scenes/enemy.tscn"))
	if not ResourceLoader.exists(scene_path):
		return {"error": "scene not found: %s" % scene_path}
	var scene: PackedScene = load(scene_path)
	var instance: Node = scene.instantiate()
	var pos_d: Dictionary = params.get("position", {"x": 0.0, "y": 1.0, "z": 3.0})
	instance.position = Vector3(float(pos_d.get("x", 0.0)), float(pos_d.get("y", 1.0)), float(pos_d.get("z", 3.0)))
	instance.add_to_group("mcp_spawned")
	get_tree().current_scene.add_child(instance)
	return {"spawned": scene_path, "instance_id": instance.get_instance_id(), "position": [pos_d.get("x",0), pos_d.get("y",1), pos_d.get("z",3)]}


func _cmd_set_objective(params: Dictionary) -> Dictionary:
	# Encuentra el HUD y setea el texto
	var hud: Node = get_tree().root.find_child("HUD", true, false)
	if hud == null:
		return {"error": "HUD not found"}
	if hud.has_method("set_objective"):
		hud.set_objective(String(params.get("text", "")))
		return {"objective_set": params.get("text", "")}
	return {"error": "HUD has no set_objective method"}


func _cmd_run_skill_test(params: Dictionary) -> Dictionary:
	# Spawn N enemies around player y los manda a atacar
	var count: int = int(params.get("count", 3))
	var radius: float = float(params.get("radius", 5.0))
	var player: Node = get_tree().root.find_child("Player", true, false)
	if player == null:
		return {"error": "Player not found"}
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	if scene == null:
		return {"error": "enemy scene not loadable"}
	var spawned: Array = []
	for i in range(count):
		var angle: float = TAU * float(i) / float(count)
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var pos: Vector3 = player.global_position + offset
		var enemy: Node = scene.instantiate()
		enemy.position = pos
		enemy.add_to_group("mcp_spawned")
		get_tree().current_scene.add_child(enemy)
		spawned.append({"id": enemy.get_instance_id(), "pos": [pos.x, pos.y, pos.z]})
	return {"spawned": spawned, "count": count}


## create_skill(params) — Crea un nuevo SkillResource .tres desde el LLM.
##
## Params:
##   id: String (required)        -- ej: "fireball_001"
##   name: String                 -- ej: "Fireball"
##   description: String          -- texto libre
##   atoms: Array[Dictionary]     -- [{type, params, applies_to_target}, ...]
##   target_resolver: String      -- ej: "nearest_in_range", "aoe", "self"
##   designed_max: Dictionary     -- {stat_name: float}
##   costs: Dictionary            -- {stamina: 30, cooldown: 5.0, ...}
##   cast: Dictionary             -- {charge_time: 0.0, channel_time: 0.0, ...}
##
## Returns:
##   {created: path, id: id, atoms_count: N}
func _cmd_create_skill(params: Dictionary) -> Dictionary:
	var skill_id: String = String(params.get("id", ""))
	if skill_id == "":
		return {"error": "id is required"}
	# Sanitize filename
	var safe_id: String = skill_id.replace("/", "_").replace("\\", "_")
	var path: String = "res://data/skills/%s.tres" % safe_id
	if ResourceLoader.exists(path):
		return {"error": "skill already exists: %s" % path}
	# Build the resource dict
	var resource_dict: Dictionary = {
		"id": StringName(skill_id),
		"name": String(params.get("name", skill_id)),
		"type": String(params.get("type", "damage")),  # 'damage' or 'control'
		"target_resolver": params.get("target_resolver", "nearest_npc_in_range"),
		"atoms": params.get("atoms", []),
		"designed_max": params.get("designed_max", {}),
		"costs": params.get("costs", {}),
	}
	# Validate atoms against the skill validator
	var validator_script: GDScript = load("res://scripts/skill/skill_validator.gd")
	if validator_script == null:
		return {"error": "validator script not found"}
	# SkillValidator is a class_name; instantiate and call its static method.
	var validator_obj: Object = validator_script.new()
	var vres: Dictionary = validator_obj.validate(resource_dict)
	var errors: Array = vres.get("errors", [])
	var warnings: Array = vres.get("warnings", [])
	if not bool(vres.get("valid", false)):
		return {"error": "validation failed", "errors": errors, "warnings": warnings}
	# Write the .tres
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"error": "cannot write to %s" % path}
	f.store_string(_format_skill_tres(resource_dict))
	f.close()
	# Reload to verify
	var res: Resource = load(path)
	if res == null:
		return {"error": "created but failed to load"}
	print("[MCPReceiver] created skill %s (%d atoms)" % [skill_id, resource_dict["atoms"].size()])
	return {
		"created": path,
		"id": skill_id,
		"atoms_count": resource_dict["atoms"].size(),
	}


## modify_skill(params) — Modifica campos de un skill existente.
## Params: id, plus any of: name, description, atoms, costs, designed_max, etc.
func _cmd_modify_skill(params: Dictionary) -> Dictionary:
	var skill_id: String = String(params.get("id", ""))
	var skill: Resource = _find_skill_resource(skill_id)
	if skill == null:
		return {"error": "skill not found: %s" % skill_id}
	# Update fields
	for key_v in params.keys():
		var key: String = String(key_v)
		if key in ["id", "method", "params", "jsonrpc"]:
			continue
		skill.set(key, params[key_v])
	# Re-validate
	var validator_script: GDScript = load("res://scripts/skill/skill_validator.gd")
	var resource_dict: Dictionary = {
		"name": String(skill.name) if "name" in skill else "",
		"type": String(skill.category) if "category" in skill else "damage",
		"target_resolver": skill.target_resolver if "target_resolver" in skill else "nearest_npc_in_range",
		"atoms": skill.atoms,
		"designed_max": skill.designed_max,
		"costs": skill.costs,
	}
	var validator_obj: Object = validator_script.new()
	var vres: Dictionary = validator_obj.validate(resource_dict)
	var errors: Array = vres.get("errors", [])
	if not bool(vres.get("valid", false)):
		return {"error": "validation failed after modify", "errors": errors}
	# Save back to disk
	var path: String = skill.resource_path
	if path == "" or not path.ends_with(".tres"):
		return {"error": "skill has no .tres path"}
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"error": "cannot write to %s" % path}
	f.store_string(_format_skill_tres(skill))
	f.close()
	print("[MCPReceiver] modified skill %s" % skill_id)
	return {"modified": path, "id": skill_id}


## spawn_challenge(params) — Diseña un challenge: enemies + objective + reward.
##
## Params:
##   enemy_count: int
##   radius: float
##   objective: String
##   reward_skill: String (id de la skill a entregar al completar)
##   reward_points: int
##
## Returns:
##   {challenge_id, enemies_spawned, objective, reward}
func _cmd_spawn_challenge(params: Dictionary) -> Dictionary:
	var enemy_count: int = int(params.get("enemy_count", 3))
	var radius: float = float(params.get("radius", 6.0))
	var objective: String = String(params.get("objective", "Defeat all enemies"))
	var reward_skill: String = String(params.get("reward_skill", ""))
	var reward_points: int = int(params.get("reward_points", 1))
	# Spawn enemies (re-uses run_skill_test logic)
	var player: Node = get_tree().root.find_child("Player", true, false)
	if player == null:
		return {"error": "Player not found"}
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	if scene == null:
		return {"error": "enemy scene not loadable"}
	var spawned: Array = []
	for i in range(enemy_count):
		var angle: float = TAU * float(i) / float(enemy_count)
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var pos: Vector3 = player.global_position + offset
		var enemy: Node = scene.instantiate()
		enemy.position = pos
		enemy.add_to_group("challenge_enemies")
		enemy.add_to_group("mcp_spawned")
		get_tree().current_scene.add_child(enemy)
		spawned.append({"id": enemy.get_instance_id(), "pos": [pos.x, pos.y, pos.z]})
	# Set objective
	var hud: Node = get_tree().root.find_child("HUD", true, false)
	if hud != null and hud.has_method("set_objective"):
		hud.set_objective(objective)
	# Track challenge
	var challenge_id: String = "challenge_%d" % Time.get_ticks_msec()
	_challenges[challenge_id] = {
		"enemies": spawned,
		"reward_skill": reward_skill,
		"reward_points": reward_points,
		"objective": objective,
		"completed": false,
	}
	# Connect a monitor (using a Timer for polling)
	_start_challenge_monitor(challenge_id)
	return {
		"challenge_id": challenge_id,
		"enemies_spawned": spawned.size(),
		"objective": objective,
		"reward": {"skill": reward_skill, "points": reward_points},
	}


func _start_challenge_monitor(challenge_id: String) -> void:
	var t: Timer = Timer.new()
	t.wait_time = 0.5
	t.one_shot = false
	t.autostart = true
	t.timeout.connect(_check_challenge.bind(challenge_id))
	add_child(t)
	_challenge_monitors.append(t)


func _check_challenge(challenge_id: String) -> void:
	if not _challenges.has(challenge_id):
		return
	var c: Dictionary = _challenges[challenge_id]
	if c.get("completed", false):
		return
	# Check if all enemies are dead (no longer in tree or invalid)
	var alive_count: int = 0
	for e in c.get("enemies", []):
		var id: int = int(e.get("id", 0))
		var node: Node = instance_from_id(id)
		if node != null and is_instance_valid(node):
			alive_count += 1
	if alive_count > 0:
		return
	# Challenge complete!
	c["completed"] = true
	_challenges[challenge_id] = c
	print("[MCPReceiver] challenge %s completed!" % challenge_id)
	# Grant reward
	var ps: Node = get_tree().root.get_node_or_null("ProgressionState")
	if ps == null:
		return
	if int(c.get("reward_points", 0)) > 0:
		ps.grant_skill_points(int(c["reward_points"]))
	var reward_skill: String = String(c.get("reward_skill", ""))
	if reward_skill != "":
		var skill: Resource = _find_skill_resource(reward_skill)
		if skill != null and StringName(reward_skill) not in ps.owned_skills:
			ps.add_skill(skill)
	# Notify objective
	var hud: Node = get_tree().root.find_child("HUD", true, false)
	if hud != null and hud.has_method("set_objective"):
		hud.set_objective("Challenge complete! +%d points%s" % [
			int(c.get("reward_points", 0)),
			" + skill: " + reward_skill if reward_skill != "" else ""
		])


## allocate_skill_points(params) — Asigna puntos a un stat de una skill owned.
## Params: skill_id, stat, points
func _cmd_allocate_skill_points(params: Dictionary) -> Dictionary:
	var ps: Node = get_tree().root.get_node_or_null("ProgressionState")
	if ps == null:
		return {"error": "ProgressionState not found"}
	var skill_id_v: StringName = StringName(String(params.get("skill_id", "")))
	var stat_v: StringName = StringName(String(params.get("stat", "")))
	var points: int = int(params.get("points", 1))
	var ok: bool = ps.allocate(skill_id_v, stat_v, points)
	return {"allocated": ok, "skill_id": skill_id_v, "stat": stat_v, "points": points}


## list_skills(params) — Lista todas las skills disponibles en data/skills/.
func _cmd_list_skills(_params: Dictionary) -> Dictionary:
	var dir: DirAccess = DirAccess.open("res://data/skills")
	if dir == null:
		return {"skills": []}
	var skills: Array = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res: Resource = load("res://data/skills/%s" % fname)
			if res != null:
				skills.append({
					"id": String(res.id) if "id" in res else fname,
					"name": String(res.name) if "name" in res else fname,
					"path": "res://data/skills/%s" % fname,
					"atoms_count": res.atoms.size() if "atoms" in res and res.atoms != null else 0,
				})
		fname = dir.get_next()
	dir.list_dir_end()
	return {"skills": skills, "count": skills.size()}


## Format a skill dict as a .tres file. Mimics the existing kamehameha.tres style.
func _format_skill_tres(skill) -> String:
	var data: Dictionary
	if skill is Dictionary:
		data = skill.duplicate(true)
	else:
		# Resource — extract fields
		data = {
			"id": String(skill.id) if "id" in skill else "",
			"name": String(skill.name) if "name" in skill else "",
			"description": String(skill.description) if "description" in skill else "",
			"category": String(skill.category) if "category" in skill else "damage",
			"target_resolver": String(skill.target_resolver) if "target_resolver" in skill else "nearest_npc_in_range",
			"atoms": skill.atoms.duplicate(true) if "atoms" in skill and skill.atoms != null else [],
			"designed_max": skill.designed_max.duplicate(true) if "designed_max" in skill and skill.designed_max != null else {},
			"costs": skill.costs.duplicate(true) if "costs" in skill and skill.costs != null else {},
			"cast": skill.cast.duplicate(true) if "cast" in skill and skill.cast != null else {},
			"vfx": skill.vfx.duplicate(true) if "vfx" in skill and skill.vfx != null else {},
			"tier_requirement": String(skill.tier_requirement) if "tier_requirement" in skill else "Novice",
		}
	var lines: Array = [
		"[gd_resource type=\"Resource\" script_class=\"SkillResource\" load_steps=2 format=3]",
		"",
		"[ext_resource type=\"Script\" path=\"res://scripts/skill/skill_resource.gd\" id=\"1_skill\"]",
		"",
		"[resource]",
		"script = ExtResource(\"1_skill\")",
		"id = &\"%s\"" % data.get("id", ""),
		"name = \"%s\"" % data.get("name", ""),
		"description = \"%s\"" % data.get("description", "").replace("\"", "\\\""),
		"category = \"%s\"" % data.get("category", "damage"),
		"target_resolver = " + _format_tres_value(data.get("target_resolver", {})),
		"tier_requirement = \"%s\"" % data.get("tier_requirement", "Novice"),
		"atoms = " + _format_tres_value(data.get("atoms", [])),
		"designed_max = " + _format_tres_value(data.get("designed_max", {})),
		"costs = " + _format_tres_value(data.get("costs", {})),
		"cast = " + _format_tres_value(data.get("cast", {})),
		"vfx = " + _format_tres_value(data.get("vfx", {})),
	]
	return "\n".join(lines) + "\n"


## Format any value (Dict/Array/String/Number) as a Godot .tres expression.
## Dict/Array → literal block (not JSON-quoted). Strings → quoted. Numbers/bools → literal.
func _format_tres_value(v: Variant, indent: int = 0) -> String:
	var pad: String = "    ".repeat(indent)
	if v == null:
		return "null"
	var t: int = typeof(v)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		if d.is_empty():
			return "{}"
		var lines: Array = ["{"]
		var keys: Array = d.keys()
		var parts: Array = []
		for i in keys.size():
			var k_v: Variant = keys[i]
			var k: String = String(k_v)
			var line_pad: String = "    ".repeat(indent + 1)
			var val_str: String = _format_tres_value(d[k_v], indent + 1)
			parts.append("%s\"%s\": %s" % [line_pad, k, val_str])
		lines.append(",\n".join(parts))
		lines.append("%s}" % pad)
		return "\n".join(lines)
	elif t == TYPE_ARRAY:
		var a: Array = v
		if a.is_empty():
			return "[]"
		var parts2: Array = []
		for i in a.size():
			var line_pad2: String = "    ".repeat(indent + 1)
			var val_str2: String = _format_tres_value(a[i], indent + 1)
			parts2.append("%s%s" % [line_pad2, val_str2])
		return "[\n%s\n%s]" % [",\n".join(parts2), pad]
	elif t == TYPE_STRING or t == TYPE_STRING_NAME:
		var s: String = String(v).replace("\"", "\\\"").replace("\n", "\\n")
		return "\"%s\"" % s
	elif t == TYPE_FLOAT or t == TYPE_INT:
		var n: float = float(v)
		if n == int(n) and abs(n) < 1e15:
			return str(int(n))
		return str(n)
	elif t == TYPE_BOOL:
		return "true" if v else "false"
	else:
		return "\"%s\"" % str(v)
