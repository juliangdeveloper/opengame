## MissionManager — autoload que gestiona todas las misiones.
##
## Responsabilidades:
##   - Crear misiones (vía LLM/MCP o seed al boot)
##   - Asignar dificultad (jugador) → computar config
##   - Iniciar / abandonar / reintentar / editar misiones
##   - Spawn de enemigos con damage_modifiers del balance
##   - Monitor de progreso (kills, casts, timer, reach, survival)
##   - Otorgar recompensas (skill_points) al completar
##   - Notificar al HUD con el objetivo actual
##
## State machine por misión:
##   AVAILABLE → READY → ACTIVE → COMPLETED | FAILED | ABANDONED
##   Desde terminal: RETRY (vuelve a ACTIVE con misma config)
##                  EDIT (cambia dificultad → READY)
extends Node

const MissionResourceScript := preload("res://scripts/missions/mission_resource.gd")
const MissionBalanceScript := preload("res://scripts/missions/mission_balance.gd")
const MissionValidatorScript := preload("res://scripts/missions/mission_validator.gd")

# === Signals ===
signal mission_created(mission_id: StringName)
signal mission_state_changed(mission_id: StringName, new_state: StringName)
signal mission_progress(mission_id: StringName, progress: Dictionary)
signal mission_completed(mission_id: StringName, rewards: Dictionary)
signal mission_failed(mission_id: StringName, reason: String)
signal mission_abandoned(mission_id: StringName)
signal active_mission_changed(mission_id: StringName)

## Emitido en cada mutación del estado. SaveSystem escucha este signal
## y persiste tras debounce.
signal data_changed

# === Storage ===
var _missions: Dictionary = {}  # {StringName: MissionResource}
var _active_mission_id: StringName = &""
var _spawned_enemies: Array = []  # [instance_id, ...]
var _destination_marker: Node3D = null
var _monitor_timer: Timer
var _alive_count: int = 0


func _ready() -> void:
	_monitor_timer = Timer.new()
	_monitor_timer.wait_time = 0.25
	_monitor_timer.timeout.connect(_tick)
	_monitor_timer.autostart = true
	add_child(_monitor_timer)
	# Hook player skill cast signal (for cast_skill_n missions)
	call_deferred("_connect_player_signals")
	# Restaurar estado persistido ANTES del seed (si hay save, no se seedea).
	_apply_saved_state()
	# Seed: 3 misiones de ejemplo si no hay ninguna
	call_deferred("_seed_default_missions")
	print("[MissionManager] ready")


## Restaura misiones/active del SaveSystem (si hay datos guardados).
## Llamado en _ready() ANTES de _seed_default_missions, así que si hay save
## no se sobreescribe con el seed.
func _apply_saved_state() -> void:
	var save_sys: Node = Engine.get_main_loop().root.get_node_or_null("SaveSystem")
	if save_sys == null or not save_sys.has_method("consume"):
		return
	var data: Dictionary = save_sys.consume(&"missions")
	if data.is_empty():
		return
	from_dict(data)


## to_dict() — serializa todas las misiones + el active_mission_id.
func to_dict() -> Dictionary:
	var missions_arr: Array = []
	for id_v in _missions.keys():
		var m: MissionResource = _missions[id_v]
		missions_arr.append({
			"id": String(m.id),
			"title": m.title,
			"purpose": String(m.purpose),
			"target_id": String(m.target_id),
			"target_kind": String(m.target_kind),
			"mission_type": String(m.mission_type),
			"state": String(m.state),
			"difficulty": m.difficulty,
			"enemy_type": String(m.enemy_type),
			"enemy_count": m.enemy_count,
			"enemy_hp_mult": m.enemy_hp_mult,
			"time_limit_sec": m.time_limit_sec,
			"damage_modifiers": m.damage_modifiers.duplicate(true),
			"rewards": m.rewards.duplicate(true),
			"kills": m.kills,
			"casts": m.casts,
			"elapsed_sec": m.elapsed_sec,
			"reached_destination": m.reached_destination,
			"survived": m.survived,
			"created_at": m.created_at,
			"started_at": m.started_at,
			"completed_at": m.completed_at,
		})
	return {
		"active_mission_id": String(_active_mission_id),
		"missions": missions_arr,
	}


## from_dict(data) — restaura misiones y active_mission_id.
## Idempotente: si data está vacío, no-op.
func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	_missions.clear()
	var arr: Array = data.get("missions", [])
	for entry in arr:
		var m: MissionResource = MissionResourceScript.new()
		m.id = StringName(String(entry.get("id", "")))
		m.title = String(entry.get("title", ""))
		m.purpose = StringName(String(entry.get("purpose", "")))
		m.target_id = StringName(String(entry.get("target_id", "")))
		m.target_kind = StringName(String(entry.get("target_kind", "")))
		m.mission_type = StringName(String(entry.get("mission_type", "defeat_enemies")))
		m.state = StringName(String(entry.get("state", "AVAILABLE")))
		m.difficulty = int(entry.get("difficulty", 0))
		m.enemy_type = StringName(String(entry.get("enemy_type", "saibaman")))
		m.enemy_count = int(entry.get("enemy_count", 0))
		m.enemy_hp_mult = float(entry.get("enemy_hp_mult", 1.0))
		m.time_limit_sec = float(entry.get("time_limit_sec", 0.0))
		m.damage_modifiers = (entry.get("damage_modifiers", {}) as Dictionary).duplicate(true)
		m.rewards = (entry.get("rewards", {}) as Dictionary).duplicate(true)
		m.kills = int(entry.get("kills", 0))
		m.casts = int(entry.get("casts", 0))
		m.elapsed_sec = float(entry.get("elapsed_sec", 0.0))
		m.reached_destination = bool(entry.get("reached_destination", false))
		m.survived = bool(entry.get("survived", false))
		m.created_at = int(entry.get("created_at", 0))
		m.started_at = int(entry.get("started_at", 0))
		m.completed_at = int(entry.get("completed_at", 0))
		_missions[m.id] = m
	_active_mission_id = StringName(String(data.get("active_mission_id", "")))


func _connect_player_signals() -> void:
	var player: Node = get_tree().root.find_child("Player", true, false)
	if player == null or not player.has_signal("skill_cast_started"):
		return
	if not player.skill_cast_started.is_connected(_on_player_skill_cast):
		player.skill_cast_started.connect(_on_player_skill_cast)


func _seed_default_missions() -> void:
	if not _missions.is_empty():
		return
	create_mission(&"teach_skill", &"kamehameha_001", &"defeat_enemies", "Aprende Kamehameha")
	create_mission(&"teach_skill", &"serious_punch_001", &"1v1", "Duelo de puños")
	create_mission(&"teach_skill", &"uraraka_zero_gravity_001", &"survive", "Flota y sobrevive")


# ============================================================
# Public API — usado por MCP handlers y por la UI
# ============================================================

func create_mission(purpose: StringName, target_id: StringName, mission_type: StringName = &"defeat_enemies", title: String = "") -> MissionResource:
	var spec := {"purpose": purpose, "target_id": target_id, "mission_type": mission_type, "title": title}
	var v: Dictionary = MissionValidatorScript.validate(spec)
	if not bool(v.get("valid", false)):
		push_error("[MissionManager] create_mission validation failed: %s" % str(v.get("errors", [])))
		return null
	var id := StringName("mission_%d" % Time.get_ticks_msec())
	var m: MissionResource = MissionResourceScript.new()
	m.id = id
	m.title = title if title != "" else _auto_title(purpose, target_id, mission_type)
	m.purpose = purpose
	m.target_id = target_id
	m.target_kind = StringName(String(v.get("target_kind", "")))
	m.mission_type = mission_type
	m.state = &"AVAILABLE"
	m.created_at = Time.get_ticks_msec()
	_missions[id] = m
	mission_created.emit(id)
	print("[MissionManager] created %s purpose=%s target=%s type=%s" % [id, purpose, target_id, mission_type])
	data_changed.emit()
	return m


func set_difficulty(mission_id: StringName, difficulty: int) -> MissionResource:
	if not _missions.has(mission_id):
		return null
	var m: MissionResource = _missions[mission_id]
	if m.state != &"AVAILABLE":
		push_warning("[MissionManager] set_difficulty on non-AVAILABLE mission %s (state=%s)" % [mission_id, m.state])
		return null
	if difficulty < 1 or difficulty > 5:
		return null
	var cfg: Dictionary = MissionBalanceScript.compute_config(m.target_id, m.purpose, difficulty, m.mission_type)
	if cfg.has("error"):
		push_error("[MissionManager] compute_config error: %s" % cfg.get("error"))
		return null
	m.difficulty = difficulty
	m.enemy_type = StringName(String(cfg.get("enemy_type", "saibaman")))
	m.enemy_count = int(cfg.get("enemy_count", 1))
	m.enemy_hp_mult = float(cfg.get("enemy_hp_mult", 1.0))
	m.time_limit_sec = float(cfg.get("time_limit_sec", 0.0))
	m.damage_modifiers = cfg.get("damage_modifiers", {})
	m.rewards = cfg.get("rewards", {})
	_set_state(m, &"READY")
	data_changed.emit()
	return m


func start_mission(mission_id: StringName) -> Dictionary:
	if not _missions.has(mission_id):
		return {"error": "mission not found"}
	var m: MissionResource = _missions[mission_id]
	if m.state != &"READY":
		return {"error": "mission not in READY state (current: %s)" % m.state}
	# If hay una activa, abandonarla primero
	if _active_mission_id != &"" and _missions.has(_active_mission_id):
		abandon_mission(_active_mission_id)
	# Reset tracking
	m.kills = 0
	m.casts = 0
	m.elapsed_sec = 0.0
	m.reached_destination = false
	m.survived = false
	m.started_at = Time.get_ticks_msec()
	# Spawn
	_spawn_enemies_for_mission(m)
	if m.mission_type == &"reach_destination":
		_place_destination_marker(m)
	# HUD
	_set_hud_objective(m.get_objective_text())
	# Active
	_active_mission_id = mission_id
	_set_state(m, &"ACTIVE")
	active_mission_changed.emit(mission_id)
	data_changed.emit()
	return {"started": mission_id, "enemies_spawned": _spawned_enemies.size(), "objective": m.get_objective_text()}


func abandon_mission(mission_id: StringName) -> Dictionary:
	if not _missions.has(mission_id):
		return {"error": "mission not found"}
	var m: MissionResource = _missions[mission_id]
	if m.state not in [&"READY", &"ACTIVE"]:
		return {"error": "cannot abandon in state %s" % m.state}
	_cleanup_mission_runtime(m)
	_set_state(m, &"ABANDONED")
	if _active_mission_id == mission_id:
		_active_mission_id = &""
		active_mission_changed.emit(&"")
	mission_abandoned.emit(mission_id)
	data_changed.emit()
	return {"abandoned": mission_id}


func retry_mission(mission_id: StringName) -> Dictionary:
	if not _missions.has(mission_id):
		return {"error": "mission not found"}
	var m: MissionResource = _missions[mission_id]
	if not m.is_terminal():
		return {"error": "can only retry terminal mission (current: %s)" % m.state}
	_cleanup_mission_runtime(m)
	_set_state(m, &"READY")
	return start_mission(mission_id)


func edit_mission(mission_id: StringName, new_difficulty: int) -> Dictionary:
	if not _missions.has(mission_id):
		return {"error": "mission not found"}
	var m: MissionResource = _missions[mission_id]
	_cleanup_mission_runtime(m)
	m.difficulty = 0
	m.damage_modifiers = {}
	m.rewards = {}
	m.kills = 0
	m.casts = 0
	m.elapsed_sec = 0.0
	m.reached_destination = false
	m.survived = false
	_set_state(m, &"AVAILABLE")
	data_changed.emit()
	return {"edit_ok": true, "mission_id": mission_id, "now": set_difficulty(mission_id, new_difficulty) != null}


func get_mission(mission_id: StringName) -> MissionResource:
	return _missions.get(mission_id, null)


func list_missions() -> Array:
	return _missions.values()


func get_active_mission() -> MissionResource:
	if _active_mission_id == &"":
		return null
	return _missions.get(_active_mission_id, null)


func get_state_snapshot(mission_id: StringName) -> Dictionary:
	var m: MissionResource = get_mission(mission_id)
	if m == null:
		return {"error": "not found"}
	return {
		"id": String(m.id),
		"title": m.title,
		"purpose": String(m.purpose),
		"target_id": String(m.target_id),
		"mission_type": String(m.mission_type),
		"state": String(m.state),
		"difficulty": m.difficulty,
		"enemy_count": m.enemy_count,
		"enemy_type": String(m.enemy_type),
		"time_limit_sec": m.time_limit_sec,
		"rewards": m.rewards,
		"damage_modifiers": m.damage_modifiers,
		"progress": {
			"kills": m.kills,
			"casts": m.casts,
			"elapsed_sec": m.elapsed_sec,
			"reached_destination": m.reached_destination,
		},
	}


# ============================================================
# Internals
# ============================================================

func _tick() -> void:
	if _active_mission_id == &"" or not _missions.has(_active_mission_id):
		return
	var m: MissionResource = _missions[_active_mission_id]
	if m.state != &"ACTIVE":
		return
	m.elapsed_sec += _monitor_timer.wait_time
	# Check player death
	var player: Node = get_tree().root.find_child("Player", true, false)
	if player != null and "hp" in player and float(player.hp) <= 0.0:
		_complete_mission(m, false, "player_death")
		return
	# Time limit
	if m.time_limit_sec > 0.0 and m.elapsed_sec >= m.time_limit_sec:
		var success := false
		match m.mission_type:
			&"survive":
				success = true
			&"cast_skill_n":
				success = m.casts >= m.enemy_count
			_:
				success = m.kills >= m.enemy_count
		_complete_mission(m, success, "time_limit")
		return
	# Type-specific
	match m.mission_type:
		&"defeat_enemies", &"1v1", &"timed":
			_count_alive_enemies()
			m.kills = m.enemy_count - _alive_count
			if m.kills >= m.enemy_count:
				_complete_mission(m, true, "all_defeated")
		&"reach_destination":
			_count_alive_enemies()
			m.kills = m.enemy_count - _alive_count
			if m.kills >= m.enemy_count and m.reached_destination:
				_complete_mission(m, true, "destination_reached")
		&"survive":
			if m.elapsed_sec >= m.time_limit_sec:
				m.survived = true
				_complete_mission(m, true, "survived")
		&"cast_skill_n":
			if m.casts >= m.enemy_count:
				_complete_mission(m, true, "casts_done")
	# Progress emit
	mission_progress.emit(m.id, {
		"kills": m.kills,
		"enemy_count": m.enemy_count,
		"elapsed_sec": m.elapsed_sec,
		"time_limit_sec": m.time_limit_sec,
		"casts": m.casts,
	})


func _count_alive_enemies() -> void:
	_alive_count = 0
	for id_v in _spawned_enemies:
		var node: Node = instance_from_id(id_v)
		if node != null and is_instance_valid(node) and node.is_in_group("enemies"):
			# Enemy que está en DEAD state o que tiene hp <= 0
			if "hp" in node and float(node.hp) > 0.0:
				_alive_count += 1


func _complete_mission(m: MissionResource, success: bool, reason: String) -> void:
	_cleanup_mission_runtime(m)
	if success:
		_grant_rewards(m)
		_set_state(m, &"COMPLETED")
		_set_hud_objective("Misión completada! +%d puntos (+%d proficiency)" % [
			int(m.rewards.get("skill_points", 0)),
			int(m.rewards.get("proficiency", 0))
		])
		mission_completed.emit(m.id, m.rewards)
	else:
		_set_state(m, &"FAILED")
		_set_hud_objective("Misión fallida (%s)" % reason)
		mission_failed.emit(m.id, reason)
	if _active_mission_id == m.id:
		_active_mission_id = &""
		active_mission_changed.emit(&"")
	data_changed.emit()


func _grant_rewards(m: MissionResource) -> void:
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps == null:
		return
	var sp: int = int(m.rewards.get("skill_points", 0))
	if sp > 0:
		ps.grant_skill_points(sp)


func _spawn_enemies_for_mission(m: MissionResource) -> void:
	_clear_spawned_enemies()
	var player: Node = get_tree().root.find_child("Player", true, false)
	if player == null:
		push_warning("[MissionManager] no Player in scene")
		return
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	if scene == null:
		push_warning("[MissionManager] enemy.tscn not loadable")
		return
	var n: int = max(1, m.enemy_count)
	if m.mission_type == &"cast_skill_n":
		# cast_skill_n: no enemies needed; usar 1 dummy opcional
		# Para que el jugador no esté solo, spawneamos 1 enemigo dummy
		n = 1
	var radius: float = 8.0
	for i in range(n):
		var angle: float = TAU * float(i) / float(max(n, 1))
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var pos: Vector3 = player.global_position + offset
		var enemy: Node = scene.instantiate()
		enemy.position = pos
		enemy.add_to_group("mission_enemies")
		enemy.add_to_group("mcp_spawned")
		# HP mult
		if "max_hp" in enemy:
			enemy.max_hp = float(enemy.max_hp) * m.enemy_hp_mult
			enemy.hp = enemy.max_hp
		# Damage modifiers
		if "damage_modifiers" in enemy:
			enemy.damage_modifiers = m.damage_modifiers.duplicate(true)
		get_tree().current_scene.add_child(enemy)
		_spawned_enemies.append(enemy.get_instance_id())
	print("[MissionManager] spawned %d enemies (hp_mult=%.2f, mods=%s)" % [n, m.enemy_hp_mult, m.damage_modifiers])


func _clear_spawned_enemies() -> void:
	for id_v in _spawned_enemies:
		var node: Node = instance_from_id(id_v)
		if node != null and is_instance_valid(node):
			node.queue_free()
	_spawned_enemies.clear()
	# Safety: clear any leftover mission_enemies not in our list
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	# Snapshot the group first (queue_free modifies the tree)
	var leftovers: Array = []
	for n in tree.get_nodes_in_group("mission_enemies"):
		if is_instance_valid(n):
			leftovers.append(n)
	for n in leftovers:
		n.remove_from_group("mission_enemies")
		n.queue_free()


func _cleanup_mission_runtime(m: MissionResource) -> void:
	_clear_spawned_enemies()
	if _destination_marker != null and is_instance_valid(_destination_marker):
		_destination_marker.queue_free()
		_destination_marker = null
	# For non-completed states, clear HUD objective
	if m.state == &"ACTIVE" or m.state == &"READY":
		_set_hud_objective("")


func _place_destination_marker(m: MissionResource) -> void:
	var player: Node = get_tree().root.find_child("Player", true, false)
	if player == null:
		return
	_destination_marker = Node3D.new()
	_destination_marker.name = "MissionDestination"
	_destination_marker.add_to_group("mission_destination")
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	cs.shape = shape
	area.add_child(cs)
	area.body_entered.connect(_on_destination_entered)
	_destination_marker.add_child(area)
	var vis := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.5
	mesh.height = 3.0
	vis.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.3, 0.5)
	mat.transparency = 1
	vis.material_override = mat
	_destination_marker.add_child(vis)
	_destination_marker.position = player.global_position + Vector3(15, 0, 0)
	get_tree().current_scene.add_child(_destination_marker)


func _on_destination_entered(body: Node) -> void:
	if body.name == "Player" and _active_mission_id != &"":
		var m: MissionResource = _missions.get(_active_mission_id, null)
		if m != null:
			m.reached_destination = true
			print("[MissionManager] player reached destination")


func _set_hud_objective(text: String) -> void:
	var hud: Node = get_tree().root.find_child("HUD", true, false)
	if hud != null and hud.has_method("set_objective"):
		hud.set_objective(text)


func _set_state(m: MissionResource, new_state: StringName) -> void:
	m.state = new_state
	if new_state == &"COMPLETED" or new_state == &"FAILED" or new_state == &"ABANDONED":
		m.completed_at = Time.get_ticks_msec()
	mission_state_changed.emit(m.id, new_state)
	print("[MissionManager] %s -> %s" % [m.id, new_state])


func _on_player_skill_cast(skill_id: StringName, _slot: int) -> void:
	if _active_mission_id == &"":
		return
	var m: MissionResource = _missions.get(_active_mission_id, null)
	if m == null or m.mission_type != &"cast_skill_n":
		return
	if skill_id == m.target_id:
		m.casts += 1
		print("[MissionManager] cast_skill_n progress: %d/%d" % [m.casts, m.enemy_count])


func _auto_title(purpose: StringName, target_id: StringName, mission_type: StringName) -> String:
	var prefix := "Aprende" if purpose == &"teach_skill" else "Domina"
	return "%s %s" % [prefix, target_id]


# External hook: called by player.gd (or anyone) when a skill is cast.
# Used for cast_skill_n missions. player.skill_cast_started signal is connected in _connect_player_signals.
func notify_skill_cast(skill_id: StringName) -> void:
	_on_player_skill_cast(skill_id, -1)
