## test_mission.gd — Unit tests for the mission system.
##
## Tests:
##   1. MissionValidator: valid spec passes, invalid fails
##   2. MissionBalance: compute_config returns expected values per difficulty
##   3. MissionResource: state machine transitions
##
## Run with:
##   godot --headless --script tests/test_mission.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []


func _init() -> void:
	print("=== test_mission.gd ===")
	_test_validator_valid()
	_test_validator_invalid_purpose()
	_test_validator_invalid_target()
	_test_validator_invalid_mission_type()
	_test_balance_difficulty_1()
	_test_balance_difficulty_5()
	_test_balance_damage_modifiers_teach_skill()
	_test_balance_damage_modifiers_teach_weapon()
	_test_balance_mission_type_overrides()
	_test_resource_state_machine()
	_test_mission_type_objective_text()
	# Seed mission flow (uses MissionManager)
	_test_seed_mission_create()
	_test_difficulty_assignment()
	_test_full_mission_flow()
	# Report
	print("\n=== RESULT: %d PASS / %d FAIL ===" % [_pass, _fail])
	if _fail > 0:
		for r in _results:
			if not r.ok:
				print("  FAIL: %s" % r.name)
	quit(0 if _fail == 0 else 1)


func _assert(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		_results.append({"name": name, "ok": true})
		print("  [PASS] %s" % name)
	else:
		_fail += 1
		_results.append({"name": name, "ok": false})
		print("  [FAIL] %s %s" % [name, detail])


# === Validator ===

func _test_validator_valid() -> void:
	var v: Dictionary = preload("res://scripts/missions/mission_validator.gd").validate({
		"purpose": "teach_skill",
		"target_id": "kamehameha_001",
		"mission_type": "defeat_enemies",
		"title": "Aprende Kamehameha",
	})
	_assert("validator_valid", bool(v.get("valid", false)) and v.get("errors", []).is_empty(), "errors=%s" % str(v.get("errors", [])))


func _test_validator_invalid_purpose() -> void:
	var v: Dictionary = preload("res://scripts/missions/mission_validator.gd").validate({
		"purpose": "explode_everything",
		"target_id": "kamehameha_001",
		"mission_type": "defeat_enemies",
	})
	_assert("validator_invalid_purpose", not bool(v.get("valid", false)) and (v.get("errors", []) as Array).size() > 0)


func _test_validator_invalid_target() -> void:
	var v: Dictionary = preload("res://scripts/missions/mission_validator.gd").validate({
		"purpose": "teach_skill",
		"target_id": "nonexistent_skill_xyz",
		"mission_type": "defeat_enemies",
	})
	_assert("validator_invalid_target", not bool(v.get("valid", false)))


func _test_validator_invalid_mission_type() -> void:
	var v: Dictionary = preload("res://scripts/missions/mission_validator.gd").validate({
		"purpose": "teach_skill",
		"target_id": "kamehameha_001",
		"mission_type": "explosive_disco",
	})
	_assert("validator_invalid_mission_type", not bool(v.get("valid", false)))


# === Balance ===

func _test_balance_difficulty_1() -> void:
	preload("res://scripts/missions/mission_balance.gd").reset_cache()
	var cfg: Dictionary = preload("res://scripts/missions/mission_balance.gd").compute_config(
		&"kamehameha_001", &"teach_skill", 1, &"defeat_enemies"
	)
	_assert("balance_d1_count", int(cfg.get("enemy_count", 0)) == 1)
	_assert("balance_d1_hp_mult", absf(float(cfg.get("enemy_hp_mult", 0.0)) - 0.7) < 0.01)
	_assert("balance_d1_rewards", int((cfg.get("rewards", {}) as Dictionary).get("skill_points", 0)) == 2)


func _test_balance_difficulty_5() -> void:
	preload("res://scripts/missions/mission_balance.gd").reset_cache()
	var cfg: Dictionary = preload("res://scripts/missions/mission_balance.gd").compute_config(
		&"kamehameha_001", &"teach_skill", 5, &"defeat_enemies"
	)
	_assert("balance_d5_count", int(cfg.get("enemy_count", 0)) == 5)
	_assert("balance_d5_hp_mult", absf(float(cfg.get("enemy_hp_mult", 0.0)) - 1.8) < 0.01)
	_assert("balance_d5_rewards", int((cfg.get("rewards", {}) as Dictionary).get("skill_points", 0)) == 10)
	_assert("balance_d5_time_limit", float(cfg.get("time_limit_sec", 0.0)) == 120.0)


func _test_balance_damage_modifiers_teach_skill() -> void:
	preload("res://scripts/missions/mission_balance.gd").reset_cache()
	# teach_skill(uraraka=earth): earth vulnerable, others resistant
	var cfg: Dictionary = preload("res://scripts/missions/mission_balance.gd").compute_config(
		&"uraraka_zero_gravity_001", &"teach_skill", 3, &"defeat_enemies"
	)
	var mods: Dictionary = cfg.get("damage_modifiers", {})
	_assert("balance_mods_target_vulnerable", float(mods.get(&"earth", 1.0)) > 1.0,
		"earth was %s" % str(mods.get(&"earth", 1.0)))
	_assert("balance_mods_fire_resistant", float(mods.get(&"fire", 1.0)) < 1.0)
	_assert("balance_mods_physical_resistant", float(mods.get(&"physical", 1.0)) < 1.0,
		"physical was %s" % str(mods.get(&"physical", 1.0)))


func _test_balance_damage_modifiers_teach_weapon() -> void:
	preload("res://scripts/missions/mission_balance.gd").reset_cache()
	# teach_weapon(short_sword=physical): physical vulnerable, elements resistant
	var cfg: Dictionary = preload("res://scripts/missions/mission_balance.gd").compute_config(
		&"short_sword", &"teach_weapon", 3, &"defeat_enemies"
	)
	var mods: Dictionary = cfg.get("damage_modifiers", {})
	_assert("balance_mods_weapon_phys_vulnerable", float(mods.get(&"physical", 1.0)) > 1.0)
	_assert("balance_mods_weapon_fire_resistant", float(mods.get(&"fire", 1.0)) < 1.0)


func _test_balance_mission_type_overrides() -> void:
	preload("res://scripts/missions/mission_balance.gd").reset_cache()
	# 1v1 should always be 1 enemy
	var cfg1: Dictionary = preload("res://scripts/missions/mission_balance.gd").compute_config(
		&"kamehameha_001", &"teach_skill", 5, &"1v1"
	)
	_assert("balance_1v1_count_is_1", int(cfg1.get("enemy_count", 0)) == 1)
	# Invalid difficulty returns {}
	var cfg2: Dictionary = preload("res://scripts/missions/mission_balance.gd").compute_config(
		&"kamehameha_001", &"teach_skill", 99, &"defeat_enemies"
	)
	_assert("balance_invalid_difficulty_empty", cfg2.is_empty())


# === Resource state machine ===

func _test_resource_state_machine() -> void:
	var r: Resource = preload("res://scripts/missions/mission_resource.gd").new()
	_assert("resource_initial_state", String(r.state) == "AVAILABLE")
	_assert("resource_initial_difficulty", r.difficulty == 0)
	_assert("resource_is_terminal_false", not r.is_terminal())
	r.state = &"ACTIVE"
	_assert("resource_can_start_false_when_active", not r.can_start())
	r.state = &"READY"
	_assert("resource_can_start_true_when_ready", r.can_start())
	r.state = &"COMPLETED"
	_assert("resource_is_terminal_true", r.is_terminal())


func _test_mission_type_objective_text() -> void:
	var r: Resource = preload("res://scripts/missions/mission_resource.gd").new()
	r.mission_type = &"defeat_enemies"
	r.enemy_count = 3
	r.enemy_type = &"saibaman"
	var txt: String = r.get_objective_text()
	_assert("objective_contains_count", txt.find("3") != -1)
	_assert("objective_contains_type", txt.find("saibaman") != -1 or txt.find("Derrota") != -1)
	# 1v1
	r.mission_type = &"1v1"
	r.enemy_count = 1
	txt = r.get_objective_text()
	_assert("objective_1v1", txt.find("1v1") != -1 or txt.find("duelo") != -1)
	# survive
	r.mission_type = &"survive"
	r.time_limit_sec = 60.0
	txt = r.get_objective_text()
	_assert("objective_survive_60s", txt.find("60") != -1)


# === MissionManager flow (uses the running tree) ===

func _test_seed_mission_create() -> void:
	# MissionManager is an autoload — but running as --script doesn't load
	# autoloads. Manually add a MissionManager for testing.
	var mm: Node = await _ensure_mission_manager()
	if mm == null:
		_assert("seed_mission_create", false, "MissionManager could not be instantiated")
		return
	var missions: Array = mm.list_missions()
	_assert("seed_mission_create", missions.size() >= 3, "got %d" % missions.size())


func _ensure_mission_manager() -> Node:
	# Para los tests, crear SIEMPRE un MissionManager nuevo con seed conocido
	# (no usamos el autoload porque su _ready puede no haber corrido aún).
	var script: GDScript = load("res://scripts/missions/mission_manager.gd")
	if script == null:
		return null
	var inst: Node = script.new()
	inst.name = "MissionManagerTest"
	root.add_child(inst)
	# Esperar DOS frames para que _ready + call_deferred("_seed_default_missions") corran
	await process_frame
	await process_frame
	return inst


func _test_difficulty_assignment() -> void:
	var mm: Node = await _ensure_mission_manager()
	if mm == null:
		_assert("difficulty_assignment", false, "no MissionManager")
		return
	var all: Array = mm.list_missions()
	# Get first AVAILABLE mission
	var found: Resource = null
	for m in all:
		if String(m.state) == "AVAILABLE":
			found = m
			break
	if found == null:
		_assert("difficulty_assignment", false, "no AVAILABLE mission")
		return
	# Set difficulty
	var updated: Resource = mm.set_difficulty(StringName(String(found.id)), 3)
	_assert("difficulty_assignment_returns", updated != null)
	_assert("difficulty_assignment_state", String(updated.state) == "READY")
	_assert("difficulty_assignment_value", int(updated.difficulty) == 3)
	_assert("difficulty_assignment_count", int(updated.enemy_count) == 3)
	_assert("difficulty_assignment_has_mods", not (updated.damage_modifiers as Dictionary).is_empty())


func _test_full_mission_flow() -> void:
	var mm: Node = await _ensure_mission_manager()
	if mm == null:
		_assert("full_mission_flow", false, "no MissionManager")
		return
	# Get a fresh AVAILABLE mission (or reset one)
	var found: Resource = null
	for m in mm.list_missions():
		if String(m.state) in ["AVAILABLE", "ABANDONED", "COMPLETED", "FAILED"]:
			found = m
			break
	if found == null:
		_assert("full_mission_flow", false, "no mission available to test")
		return
	var mid: StringName = StringName(String(found.id))
	# Set difficulty → READY
	mm.set_difficulty(mid, 1)
	# Start → ACTIVE
	var start_resp: Dictionary = mm.start_mission(mid)
	_assert("flow_start_returns", not start_resp.has("error"), "start_err=%s" % str(start_resp.get("error", "")))
	_assert("flow_start_enemies", int(start_resp.get("enemies_spawned", 0)) >= 1)
	# Get state
	var state_resp: Dictionary = mm.get_state_snapshot(mid)
	_assert("flow_state_is_active", String(state_resp.get("state", "")) == "ACTIVE")
	# Abandon
	var ab: Dictionary = mm.abandon_mission(mid)
	_assert("flow_abandon_ok", not ab.has("error"))
	var state_after: Dictionary = mm.get_state_snapshot(mid)
	_assert("flow_state_is_abandoned", String(state_after.get("state", "")) == "ABANDONED")
	# Retry → ACTIVE again
	var rt: Dictionary = mm.retry_mission(mid)
	_assert("flow_retry_ok", not rt.has("error"))
	var state_retry: Dictionary = mm.get_state_snapshot(mid)
	_assert("flow_state_is_active_after_retry", String(state_retry.get("state", "")) == "ACTIVE")
	# Edit → AVAILABLE → READY
	var ed: Dictionary = mm.edit_mission(mid, 2)
	_assert("flow_edit_ok", not ed.has("error"))
	var state_edit: Dictionary = mm.get_state_snapshot(mid)
	_assert("flow_state_is_ready_after_edit", String(state_edit.get("state", "")) == "READY")
	_assert("flow_difficulty_changed_to_2", int(state_edit.get("difficulty", 0)) == 2)
	# Cleanup: abandon
	mm.abandon_mission(mid)
