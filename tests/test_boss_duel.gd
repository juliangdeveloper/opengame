## test_boss_duel.gd — Headless 1v1 boss fight.
##
## Uso:
##   BOSS_A=boss_frieza BOSS_B=boss_sauron SIM_DURATION=60 \
##     godot --headless --path . --script tests/test_boss_duel.gd
##
## Output:
##   /tmp/boss_duel_result.txt     — resumen en JSON
##   user://combat_log_<run_id>.jsonl — log completo de eventos
##
## Algoritmo:
##   1. Crea ObjectivesManager + ProgressionState manualmente
##   2. Activa CombatLog
##   3. Spawnea 2 BossEnemy con target_override cruzado
##   4. Correr el juego en --script mode por SIM_DURATION segundos
##   5. Al terminar, escribir resumen JSON con winner, hp_final, dmg_dealt, etc.
extends SceneTree

const BossResource := preload("res://scripts/objectives/boss_resource.gd")
const BossEnemyScript := preload("res://scripts/objectives/boss_enemy.gd")
const ENEMY_SCENE := "res://scenes/enemy.tscn"

var _root: Node = null
var _boss_a: Node3D = null
var _boss_b: Node3D = null
var _t0_ms: int = 0
var _sim_duration: float = 60.0
var _run_id: String = ""
var _boss_a_id: String = ""
var _boss_b_id: String = ""
var _om: Node = null
var _cl: Node = null


func _init() -> void:
	# Lee parámetros de entorno
	_boss_a_id = OS.get_environment("BOSS_A")
	_boss_b_id = OS.get_environment("BOSS_B")
	_sim_duration = float(OS.get_environment("SIM_DURATION")) if OS.get_environment("SIM_DURATION") != "" else 60.0
	_run_id = OS.get_environment("RUN_ID")
	if _run_id == "":
		_run_id = "duel_%s_vs_%s" % [_boss_a_id, _boss_b_id]
	if _boss_a_id == "" or _boss_b_id == "":
		printerr("ERROR: set BOSS_A and BOSS_B env vars")
		write_result({"error": "missing BOSS_A/BOSS_B"})
		quit(1)
		return
	print("\n=== test_boss_duel.gd: %s vs %s ===" % [_boss_a_id, _boss_b_id])
	_root = root
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	# Setup CombatLog (si no existe como autoload en --script, lo creamos)
	await _ensure_combat_log()
	# Setup ObjectivesManager
	_om = await _ensure_objectives_manager()
	if _om == null:
		write_result({"error": "cannot create ObjectivesManager"})
		quit(1)
		return
	# Setup ProgressionState
	await _ensure_progression_state()
	# Crear piso y world environment para que los bosses no se caigan
	_setup_arena()
	# Log sim_start
	_cl.sim_start({
		"type": "boss_duel",
		"boss_a": _boss_a_id,
		"boss_b": _boss_b_id,
		"duration_sec": _sim_duration,
	})
	# Spawn bosses
	var spawn_ok: bool = await _spawn_both_bosses()
	if not spawn_ok:
		write_result({"error": "spawn failed"})
		quit(1)
		return
	# Run sim
	_t0_ms = Time.get_ticks_msec()
	print("[sim] running %.1fs..." % _sim_duration)
	while (Time.get_ticks_msec() - _t0_ms) / 1000.0 < _sim_duration:
		await process_frame
		await physics_frame
	# Wait a bit for final events to settle
	await process_frame
	await process_frame
	await process_frame
	# Evaluar resultados
	await _evaluate_and_finish()


func _ensure_combat_log() -> void:
	_cl = _root.get_node_or_null("CombatLog")
	if _cl == null:
		var script: GDScript = load("res://scripts/combat/combat_log.gd")
		_cl = script.new()
		_cl.name = "CombatLog"
		_root.add_child(_cl)
		await process_frame
	# Activar
	_cl.set_run_id(_run_id)


func _ensure_objectives_manager() -> Node:
	for c in _root.get_children():
		if c.name.begins_with("ObjectivesManager") or c.name == "ObjectivesManager":
			if c.has_method("get_boss_count"):
				return c
	var script: GDScript = load("res://scripts/objectives/objectives_manager.gd")
	var inst: Node = script.new()
	inst.name = "ObjectivesManager"
	_root.add_child(inst)
	await process_frame
	await process_frame
	return inst


func _ensure_progression_state() -> void:
	var ps: Node = _root.get_node_or_null("ProgressionState")
	if ps == null:
		var script: GDScript = load("res://scripts/skill/progression_state.gd")
		ps = script.new()
		ps.name = "ProgressionState"
		_root.add_child(ps)
		await process_frame


## Crea piso + iluminación mínima para que los bosses no caigan al vacío.
func _setup_arena() -> void:
	var floor: StaticBody3D = StaticBody3D.new()
	floor.name = "ArenaFloor"
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(500, 1, 500)
	cs.shape = shape
	floor.add_child(cs)
	floor.position = Vector3(0, -0.5, 0)
	_root.add_child(floor)
	# Visibilidad: mesh simple
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(500, 1, 500)
	mesh_inst.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.32, 0.28, 1)
	mesh_inst.material_override = mat
	floor.add_child(mesh_inst)
	# Luz direccional mínima
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "ArenaLight"
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.light_energy = 1.0
	_root.add_child(light)


func _spawn_both_bosses() -> bool:
	var res_a: Resource = _om.get_boss(StringName(_boss_a_id))
	var res_b: Resource = _om.get_boss(StringName(_boss_b_id))
	if res_a == null or res_b == null:
		printerr("Boss not found: %s or %s" % [_boss_a_id, _boss_b_id])
		return false
	# Spawn en posiciones opuestas
	_boss_a = await _spawn_one_boss(res_a, Vector3(-3, 1.0, 0))
	_boss_b = await _spawn_one_boss(res_b, Vector3(3, 1.0, 0))
	if _boss_a == null or _boss_b == null:
		return false
	# Setear target_override cruzado
	_boss_a.target_override = _boss_b
	_boss_b.target_override = _boss_a
	# Forzar re-resolución de target
	_boss_a.target = _boss_b
	_boss_b.target = _boss_a
	# Cleanup any "Player" in scene tree (we don't want boss AI chasing a ghost)
	for p in _root.get_children():
		if p.name == "Player" or p.name.begins_with("Player_"):
			p.queue_free()
	print("[duel] spawned: A=%s hp=%.0f  B=%s hp=%.0f" % [
		_boss_a_id, _boss_a.hp, _boss_b_id, _boss_b.hp
	])
	return true


func _spawn_one_boss(boss_res: Resource, pos: Vector3) -> Node3D:
	var scene: PackedScene = load(ENEMY_SCENE)
	if scene == null:
		printerr("Cannot load %s" % ENEMY_SCENE)
		return null
	var inst: Node = scene.instantiate()
	inst.set_script(BossEnemyScript)
	inst.boss_data = boss_res
	inst.name = "Boss_%s" % String(boss_res.id)
	# Setear target_override y position ANTES de add_child para que _ready los vea
	inst.set("target_override", null)  # se setea después en _spawn_both_bosses
	# position se setea después de add_child (el nodo necesita estar en el tree)
	_root.add_child(inst)
	# Re-check que el nodo esté en el tree antes de global_position
	if is_instance_valid(inst) and inst.is_inside_tree():
		(inst as Node3D).global_position = pos
	else:
		printerr("[spawn] boss not in tree, can't set position")
	await process_frame  # let _ready fire
	return inst as Node3D


func _evaluate_and_finish() -> void:
	var winner: String = "draw"
	var hp_a: float = _boss_a.hp if is_instance_valid(_boss_a) else 0.0
	var hp_b: float = _boss_b.hp if is_instance_valid(_boss_b) else 0.0
	if hp_a <= 0.0 and hp_b <= 0.0:
		winner = "draw"
	elif hp_a <= 0.0:
		winner = _boss_b_id
	elif hp_b <= 0.0:
		winner = _boss_a_id
	else:
		# Nadie murió — quien tenga menos HP pierde
		if hp_a < hp_b:
			winner = _boss_b_id
		elif hp_b < hp_a:
			winner = _boss_a_id
		else:
			winner = "draw"
	var elapsed: float = (Time.get_ticks_msec() - _t0_ms) / 1000.0
	var summary: Dictionary = {
		"run_id": _run_id,
		"boss_a": _boss_a_id,
		"boss_b": _boss_b_id,
		"duration_sec": _sim_duration,
		"elapsed_sec": elapsed,
		"winner": winner,
		"hp_a_final": hp_a,
		"hp_b_final": hp_b,
		"max_hp_a": _boss_a.max_hp if is_instance_valid(_boss_a) else 0.0,
		"max_hp_b": _boss_b.max_hp if is_instance_valid(_boss_b) else 0.0,
		"events_logged": _cl.get_event_count() if is_instance_valid(_cl) else 0,
		"log_path": _cl.get_output_path() if is_instance_valid(_cl) else "",
	}
	# log sim_end
	_cl.sim_end(summary)
	# Flush and close
	_cl.flush()
	_cl.close()
	# Escribir resultado
	write_result(summary)
	print("[duel] DONE winner=%s hp_a=%.0f hp_b=%.0f events=%d" % [
		winner, hp_a, hp_b, summary.get("events_logged", 0)
	])
	quit(0)


func write_result(data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open("/tmp/boss_duel_result.txt", FileAccess.WRITE)
	if f == null:
		printerr("Cannot write /tmp/boss_duel_result.txt")
		return
	f.store_string(JSON.stringify(data))
	f.close()
