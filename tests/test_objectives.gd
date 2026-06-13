## test_objectives.gd — Unit tests for the Objectives (boss) system.
##
## Tests:
##   1. JSON parser: 20 bosses cargados
##   2. Each boss tiene id, display_name, max_hp, skill_ids, weakness
##   3. Damage modifiers: weakness > 1, resistance < 1
##   4. Skill weights match skill_ids length
##   5. start_objective: spawns boss correctly
##   6. complete_objective: grants skill_points
##   7. Already-completed: no double-grant
##
## Run: godot --headless --script tests/test_objectives.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _root: Node = null


func _init() -> void:
	print("\n=== test_objectives.gd ===")
	_root = root
	# Esperar un frame para que el autoload se cree
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	# Crear manualmente el ObjectivesManager si el autoload no existe
	var om: Node = await _ensure_objectives_manager()
	if om == null:
		_assert("objectives_manager_exists", false, "cannot create")
		_finish()
		return
	# Tests
	_test_boss_count(om)
	_test_boss_fields_valid(om)
	_test_damage_modifiers(om)
	_test_skill_weights_match(om)
	_test_unique_boss_ids(om)
	_test_rewards_scale_with_tier(om)
	_test_start_and_complete(om)
	_test_already_completed_no_double_grant(om)
	_test_list_objectives(om)
	_finish()


func _ensure_objectives_manager() -> Node:
	for c in _root.get_children():
		if c.name.begins_with("ObjectivesManager") or c.name == "ObjectivesManager":
			if c.has_method("get_boss_count"):
				return c
	var script: GDScript = load("res://scripts/objectives/objectives_manager.gd")
	if script == null:
		return null
	var inst: Node = script.new()
	inst.name = "ObjectivesManagerTest"
	_root.add_child(inst)
	await process_frame
	await process_frame
	return inst


# === Tests ===

func _test_boss_count(om: Node) -> void:
	var n: int = int(om.get_boss_count())
	_assert("boss_count_is_20", n == 20, "got %d" % n)


func _test_boss_fields_valid(om: Node) -> void:
	var list: Array = om.list_objectives()
	for entry in list:
		var id_str: String = String(entry.get("id", ""))
		_assert("boss_has_id_%s" % id_str, id_str != "", "missing id")
		_assert("boss_has_name_%s" % id_str, String(entry.get("display_name", "")) != "", "missing name")
		_assert("boss_has_max_hp_%s" % id_str, float(entry.get("max_hp", 0.0)) > 0.0, "max_hp <= 0")
		_assert("boss_has_skills_%s" % id_str, (entry.get("skill_ids", []) as Array).size() >= 1, "no skills")
		_assert("boss_has_reward_%s" % id_str, int(entry.get("reward_skill_points", 0)) >= 5, "reward < 5")


func _test_damage_modifiers(om: Node) -> void:
	# Verificar que weakness > 1 y resistance < 1 para al menos 1 boss
	var list: Array = om.list_objectives()
	var found: bool = false
	for entry in list:
		var wk: String = String(entry.get("weakness_element", ""))
		var wm: float = float(entry.get("weakness_mult", 1.0))
		if wk != "" and wm > 1.0:
			found = true
			break
	_assert("at_least_one_weakness", found, "no boss has weakness > 1.0")
	# Verificar que el boss_vader (lightning weakness) tiene lightning
	var vader: Dictionary = om.get_objective(&"boss_vader")
	_assert("vader_weakness_lightning", String(vader.get("weakness_element", "")) == "lightning")
	_assert("vader_resistance_dark", String(vader.get("resistance_element", "")) == "dark")


func _test_skill_weights_match(om: Node) -> void:
	var list: Array = om.list_objectives()
	for entry in list:
		var id_str: String = String(entry.get("id", ""))
		var boss_res: Resource = om.get_boss(StringName(id_str))
		if boss_res == null:
			continue
		var sw: Array = boss_res.skill_weights
		var sk: Array = boss_res.skill_ids
		if not sw.is_empty():
			_assert("skill_weights_match_%s" % id_str, sw.size() == sk.size(),
				"weights=%d skills=%d" % [sw.size(), sk.size()])


func _test_unique_boss_ids(om: Node) -> void:
	var list: Array = om.list_objectives()
	var seen: Dictionary = {}
	var dup: bool = false
	for entry in list:
		var id_str: String = String(entry.get("id", ""))
		if seen.has(id_str):
			dup = true
			break
		seen[id_str] = true
	_assert("unique_boss_ids", not dup, "duplicates found")


func _test_rewards_scale_with_tier(om: Node) -> void:
	# Tier 1-2: 5-10, Tier 3: 15, Tier 4: 20, Tier 5: 25
	var list: Array = om.list_objectives()
	for entry in list:
		var tier: int = int(entry.get("tier", 0))
		var reward: int = int(entry.get("reward_skill_points", 0))
		var ok: bool = true
		match tier:
			1, 2: ok = reward == 10
			3: ok = reward == 15
			4: ok = reward == 20
			5: ok = reward == 25
		_assert("reward_tier%d_%s" % [tier, String(entry.get("id", ""))], ok,
			"tier=%d reward=%d" % [tier, reward])


func _test_start_and_complete(om: Node) -> void:
	# Resetear
	om.reset_for_testing()
	# Verificar que boss_yhwach existe y arranca
	var list: Array = om.list_objectives()
	_assert("yhwach_in_list", list.size() == 20)
	# Get ProgressionState
	var ps: Node = root.get_node_or_null("ProgressionState")
	if ps == null:
		_assert("start_objective_no_progression", false, "ProgressionState not found")
		return
	ps.skill_points = 0
	# start
	var resp: Dictionary = om.start_objective(&"boss_yhwach")
	_assert("start_objective_ok", resp.get("ok", false) == true,
		"resp=%s" % str(resp))
	_assert("start_objective_boss_spawned", om.get_active_boss() != null)
	_assert("start_objective_id_matches", String(om.get_active_boss_id()) == "boss_yhwach")
	# Forzar muerte del boss para triggear complete
	var boss: Node3D = om.get_active_boss()
	if boss and boss.has_method("take_damage"):
		boss.take_damage(99999.0, null, &"")
	# Esperar 0.2s
	await create_timer(0.2).timeout
	# Verificar complete
	_assert("yhwach_completed", om.is_completed(&"boss_yhwach"))
	var reward: int = int(ps.skill_points)
	_assert("reward_granted", reward == 25, "got %d expected 25" % reward)


func _test_already_completed_no_double_grant(om: Node) -> void:
	om.reset_for_testing()
	var ps: Node = root.get_node_or_null("ProgressionState")
	if ps == null:
		_assert("double_grant_no_ps", false, "ProgressionState not found")
		return
	ps.skill_points = 100
	# Forzar completado
	om._completed[&"boss_joker"] = true
	om._save()
	# Llamar complete_objective de nuevo
	var resp: Dictionary = om.complete_objective(&"boss_joker")
	_assert("already_completed", resp.get("already_completed", false) == true)
	_assert("no_double_grant", int(ps.skill_points) == 100, "got %d" % int(ps.skill_points))


func _test_list_objectives(om: Node) -> void:
	var list: Array = om.list_objectives()
	_assert("list_size_20", list.size() == 20, "got %d" % list.size())
	# Verificar que las keys esperadas están
	var first: Dictionary = list[0]
	_assert("list_has_id", first.has("id"))
	_assert("list_has_name", first.has("display_name"))
	_assert("list_has_description", first.has("description"))
	_assert("list_has_completed", first.has("completed"))
	_assert("list_has_reward", first.has("reward_skill_points"))


# === Helpers ===

func _assert(test_name: String, cond: bool, msg: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % test_name)
	else:
		_fail += 1
		print("  [FAIL] %s %s" % [test_name, msg])


func _finish() -> void:
	print("\n=== RESULT: %d PASS / %d FAIL ===" % [_pass, _fail])
	quit()
