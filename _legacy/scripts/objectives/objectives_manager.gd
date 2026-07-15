## objectives_manager.gd — Autoload que gestiona el sistema de Objetivos.
##
## Un "objetivo" es un boss predefinido (data/contracts/bosses.json) que el
## jugador puede retar a través del menú. Al derrotarlo recibe una recompensa
## de skill_points (5-25 según tier del boss).
##
## API:
##   list_objectives()                -> Array[Dictionary] de los 20 bosses
##   get_objective(id)                -> Dictionary
##   start_objective(id)              -> spawns the boss, returns {ok, instance_path}
##   complete_objective(id)           -> grant reward + mark complete
##   is_completed(id)                 -> bool
##   get_completed_objectives()       -> Array[StringName]
##   get_active_boss()                -> BossEnemy node (or null)
##
## Signals:
##   objective_completed(id, reward)
##   objective_started(id, boss_path)
##   objective_failed(id, reason)
extends Node

const BossResource := preload("res://scripts/objectives/boss_resource.gd")
const BossEnemyScript := preload("res://scripts/objectives/boss_enemy.gd")

const BOSS_DATA_PATH := "res://data/contracts/bosses.json"
# Save path: ahora unificado en SaveSystem (user://menu_state.json).
# Este constant se mantiene por backwards-compat pero ya no se usa para
# escribir/ leer objetivos — todo fluye via SaveSystem.

signal objective_completed(id: StringName, reward: int)
signal objective_started(id: StringName, boss_path: String)
signal objective_failed(id: StringName, reason: String)

## Emitido en cada mutación del estado. SaveSystem escucha este signal
## y persiste tras debounce.
signal data_changed

## Cache de los BossResource parseados al boot.
var _bosses: Dictionary = {}  ## id (StringName) -> BossResource
## Set de IDs completados (persiste a disco).
var _completed: Dictionary = {}  ## id (StringName) -> true
## Boss actualmente spawneado (uno solo a la vez).
var _active_boss: Node3D = null
## ID del boss activo.
var _active_boss_id: StringName = &""


# === Load / save (via SaveSystem) ===

func _load_bosses() -> void:
	var f: FileAccess = FileAccess.open(BOSS_DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("[ObjectivesManager] cannot open %s" % BOSS_DATA_PATH)
		return
	var json_text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[ObjectivesManager] invalid JSON in %s" % BOSS_DATA_PATH)
		return
	var bosses_arr: Array = parsed.get("bosses", [])
	for entry in bosses_arr:
		var boss: Resource = _parse_boss_entry(entry)
		if boss != null:
			_bosses[boss.id] = boss
	print("[ObjectivesManager] loaded %d bosses from %s" % [_bosses.size(), BOSS_DATA_PATH])


func _parse_boss_entry(e: Dictionary) -> Resource:
	var b: Resource = BossResource.new()
	b.id = StringName(String(e.get("id", "")))
	b.display_name = String(e.get("display_name", ""))
	b.title = String(e.get("title", ""))
	b.description = String(e.get("description", ""))
	b.inspiration = String(e.get("inspiration", ""))
	b.max_hp = float(e.get("max_hp", 100.0))
	b.tier = int(e.get("tier", 1))
	b.weapon_id = StringName(String(e.get("weapon_id", "")))
	var sids: Array = e.get("skill_ids", [])
	for s in sids:
		b.skill_ids.append(StringName(String(s)))
	var weights: Array = e.get("skill_weights", [])
	for w in weights:
		b.skill_weights.append(float(w))
	b.behavior = String(e.get("behavior", "aggressive"))
	b.aggression = float(e.get("aggression", 0.5))
	b.preferred_range = StringName(String(e.get("preferred_range", "any")))
	b.reaction_time_sec = float(e.get("reaction_time_sec", 0.6))
	b.weakness_element = StringName(String(e.get("weakness_element", "")))
	b.weakness_mult = float(e.get("weakness_mult", 1.5))
	b.resistance_element = StringName(String(e.get("resistance_element", "")))
	b.resistance_mult = float(e.get("resistance_mult", 0.5))
	var custom_mods: Dictionary = e.get("custom_damage_modifiers", {})
	for k in custom_mods:
		b.custom_damage_modifiers[StringName(String(k))] = float(custom_mods[k])
	b.reward_skill_points = int(e.get("reward_skill_points", 5))
	return b


func _ready() -> void:
	_load_bosses()
	_apply_saved_state()
	print("[ObjectivesManager] ready (bosses=%d, completed=%d)" % [_bosses.size(), _completed.size()])


# === Load / save (via SaveSystem) ===

## Restaura el set de completados desde SaveSystem (si hay datos guardados).
## Llamado en _ready() después de _load_bosses.
func _apply_saved_state() -> void:
	var save_sys: Node = Engine.get_main_loop().root.get_node_or_null("SaveSystem")
	if save_sys == null or not save_sys.has_method("consume"):
		return
	var data: Dictionary = save_sys.consume(&"objectives")
	if data.is_empty():
		return
	from_dict(data)


## to_dict() — serializa solo el set de completados.
## Los bosses en sí vienen de bosses.json (datos estáticos del juego).
func to_dict() -> Dictionary:
	var arr: Array = []
	for k in _completed.keys():
		arr.append(String(k))
	return {"completed": arr}


## from_dict(data) — restaura el set de completados.
func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	_completed.clear()
	var arr: Array = data.get("completed", [])
	for id_str in arr:
		_completed[StringName(String(id_str))] = true


# === Public API ===

func list_objectives() -> Array:
	var out: Array = []
	for id in _bosses.keys():
		out.append(get_objective(id))
	return out


func get_objective(id: StringName) -> Dictionary:
	var boss: Resource = _bosses.get(id)
	if boss == null:
		return {"error": "unknown objective: %s" % String(id)}
	return {
		"id": String(boss.id),
		"display_name": boss.display_name,
		"title": boss.title,
		"description": boss.description,
		"inspiration": boss.inspiration,
		"max_hp": boss.max_hp,
		"tier": boss.tier,
		"behavior": boss.behavior,
		"weakness_element": String(boss.weakness_element),
		"weakness_mult": boss.weakness_mult,
		"resistance_element": String(boss.resistance_element),
		"resistance_mult": boss.resistance_mult,
		"skill_ids": _stringname_array_to_strings(boss.skill_ids),
		"reward_skill_points": boss.reward_skill_points,
		"completed": _completed.has(id),
		"is_active": id == _active_boss_id,
	}


func _stringname_array_to_strings(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(String(v))
	return out


func start_objective(id: StringName) -> Dictionary:
	if not _bosses.has(id):
		return {"error": "unknown objective: %s" % String(id)}
	if _active_boss != null and is_instance_valid(_active_boss):
		return {"error": "another boss is already active: %s" % String(_active_boss_id)}
	# Spawn the boss
	var boss_res: Resource = _bosses[id]
	var boss_node: Node3D = _spawn_boss(boss_res)
	if boss_node == null:
		return {"error": "failed to spawn boss"}
	_active_boss = boss_node
	_active_boss_id = id
	# Conectar la señal de muerte para completar el objetivo
	boss_node.boss_killed.connect(_on_boss_killed)
	objective_started.emit(id, boss_node.get_path())
	print("[ObjectivesManager] started objective id=%s" % String(id))
	return {
		"ok": true,
		"objective_id": String(id),
		"boss_path": String(boss_node.get_path()),
		"max_hp": boss_res.max_hp,
		"display_name": boss_res.display_name,
	}


func _spawn_boss(boss_res: Resource) -> Node3D:
	# Buscar un punto de spawn — al lado del player
	var spawn_pos: Vector3 = Vector3(0, 0, 5)
	var player: Node3D = get_tree().root.find_child("Player", true, false)
	if player and player is Node3D:
		spawn_pos = (player as Node3D).global_position + Vector3(0, 0, 5)
	# Crear la instancia del BossEnemy directamente (no swapping scripts).
	# FASE 4: BossEnemy extends EntityCharacter. Antes cargábamos enemy.tscn
	# (CharacterBody3D) y hacíamos set_script(BossEnemyScript) — eso rompía
	# porque BossEnemy ya no es CharacterBody3D nativo. Ahora instanciamos
	# el script directamente y le copiamos las children de enemy.tscn
	# (Model, AttackArea, etc).
	var inst: Node = BossEnemyScript.new()
	inst.boss_data = boss_res
	inst.name = "Boss_%s" % String(boss_res.id)
	(inst as Node3D).global_position = spawn_pos
	# Add to scene tree
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	host.add_child(inst)
	return inst as Node3D


func _on_boss_killed(boss_id: StringName) -> void:
	if boss_id != _active_boss_id:
		return
	# Grant reward
	complete_objective(boss_id)
	# Cleanup
	_active_boss = null
	_active_boss_id = &""


func complete_objective(id: StringName) -> Dictionary:
	if not _bosses.has(id):
		return {"error": "unknown objective: %s" % String(id)}
	var boss: Resource = _bosses[id]
	if _completed.has(id):
		# Already complete — no re-grant
		return {"already_completed": true, "id": String(id)}
	_completed[id] = true
	# Grant reward
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps and "skill_points" in ps:
		ps.skill_points = int(ps.skill_points) + boss.reward_skill_points
		print("[ObjectivesManager] granted %d skill_points (total now %d)" % [boss.reward_skill_points, int(ps.skill_points)])
	objective_completed.emit(id, boss.reward_skill_points)
	data_changed.emit()
	return {
		"ok": true,
		"id": String(id),
		"reward_skill_points": boss.reward_skill_points,
	}


func is_completed(id: StringName) -> bool:
	return _completed.has(id)


func get_completed_objectives() -> Array:
	var out: Array = []
	for k in _completed.keys():
		out.append(String(k))
	return out


func get_active_boss() -> Node3D:
	return _active_boss


func get_active_boss_id() -> StringName:
	return _active_boss_id


func get_boss_count() -> int:
	return _bosses.size()


func get_boss(boss_id: StringName) -> Resource:
	return _bosses.get(boss_id)


# === Test helpers ===

## Reset completion state (for tests).
func reset_for_testing() -> void:
	_completed.clear()
	_active_boss = null
	_active_boss_id = &""
	data_changed.emit()
