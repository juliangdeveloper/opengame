extends SceneTree

const Balance := preload("res://scripts/skill/balance.gd")
const SkillValidator := preload("res://scripts/skill/skill_validator.gd")
const SkillResource := preload("res://scripts/skill/skill_resource.gd")
const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")

var _passes: int = 0
var _fails: int = 0


func _init() -> void:
	process_frame.connect(_run_tests, CONNECT_ONE_SHOT)


func _run_tests() -> void:
	print("\n=== Skill System Smoke Test ===\n")
	var ps: Node = root.get_node_or_null("ProgressionState")
	if ps == null:
		print("[FATAL] ProgressionState autoload not found")
		quit(1)
		return

	_test_balance_forced_floor()
	_test_balance_soft_cap()
	_test_balance_proficiency_tiers()
	_test_balance_cost_scaling()
	_test_progression_grant_and_allocate(ps)
	_test_progression_deallocate(ps)
	_test_progression_refund_on_remove(ps)
	_test_skill_validator_positive()
	_test_skill_validator_negative()
	_test_skill_resource_load()
	_test_skill_power_ratio(ps)

	print("\n=== Result: %d PASS / %d FAIL ===" % [_passes, _fails])
	quit(0 if _fails == 0 else 1)


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  [PASS] %s %s" % [name, detail])
		_passes += 1
	else:
		print("  [FAIL] %s %s" % [name, detail])
		_fails += 1



func _test_balance_forced_floor() -> void:
	var v: float = Balance.compute_effective(100.0, 0, 5, 0)
	_check("forced_floor", v >= 4.5 and v <= 6.0, "(got %.2f, expected ~5)" % v)


func _test_balance_soft_cap() -> void:
	var v: float = Balance.compute_effective(100.0, 5, 5, 0)
	_check("soft_cap_5pts_novice", v >= 9.5 and v <= 10.5, "(got %.2f, expected ~10)" % v)

	var v2: float = Balance.compute_effective(100.0, 5, 5, 15)
	_check("soft_cap_5pts_adept", v2 >= 34.0 and v2 <= 36.0, "(got %.2f, expected ~35)" % v2)


func _test_balance_proficiency_tiers() -> void:
	var v: float = Balance.compute_effective(100.0, 5, 5, 150)
	_check("proficiency_mythic_5pts", v >= 95.0 and v <= 100.0, "(got %.2f, expected 95-100)" % v)

	var v2: float = Balance.compute_effective(100.0, 0, 5, 0)
	_check("proficiency_novice_0pts", v2 >= 4.0 and v2 <= 6.0, "(got %.2f, expected ~5)" % v2)

	var v_mythic_0: float = Balance.compute_effective(100.0, 0, 5, 150)
	_check("proficiency_mythic_0pts", v_mythic_0 >= 4.0 and v_mythic_0 <= 6.0,
		"(got %.2f, expected ~5)" % v_mythic_0)

	var v3: float = Balance.compute_effective(100.0, 3, 5, 50)
	_check("proficiency_master_3pts", v3 >= 60.0 and v3 <= 70.0, "(got %.2f, expected ~65)" % v3)


func _test_balance_cost_scaling() -> void:
	var low: float = Balance.cost_effective(50.0, 5.0, 100.0)
	var high: float = Balance.cost_effective(50.0, 100.0, 100.0)
	_check("cost_scaling_low", low >= 18.0 and low <= 30.0, "(got %.2f, expected ~23)" % low)
	_check("cost_scaling_high", high >= 48.0 and high <= 52.0, "(got %.2f, expected ~50)" % high)
	_check("cost_scales_monotonically", low < high, "(low=%.2f, high=%.2f)" % [low, high])


func _test_progression_grant_and_allocate(ps: Node) -> void:
	ps.skill_points = 0
	ps.proficiency = 0
	ps.allocations = {}
	ps.set("owned_skills", [] as Array[StringName])
	ps.skill_catalog = {}

	var skill = load("res://data/skills/kamehameha_001.tres")
	ps.add_skill(skill)

	_check("add_skill", &"kamehameha_001" in ps.owned_skills, "(owned=%s)" % str(ps.owned_skills))

	ps.grant_skill_points(5)
	_check("grant_points", ps.skill_points == 5 and ps.proficiency == 5,
		"(points=%d, prof=%d)" % [ps.skill_points, ps.proficiency])

	var ok: bool = ps.allocate(&"kamehameha_001", &"amount", 3)
	_check("allocate_3pts", ok, "(returned %s)" % str(ok))
	_check("after_allocate_points_remaining", ps.skill_points == 2, "(points=%d)" % ps.skill_points)
	_check("after_allocate_skill_points_3",
		int(ps.allocations[String(&"kamehameha_001")][&"amount"]) == 3,
		"(alloc=%s)" % str(ps.allocations))

	ok = ps.allocate(&"kamehameha_001", &"radius", 2)
	_check("allocate_2pts_radius", ok and ps.skill_points == 0, "(points=%d)" % ps.skill_points)

	ps.grant_skill_points(3)
	ok = ps.allocate(&"kamehameha_001", &"amount", 3)
	_check("cannot_exceed_max_points", not ok, "(returned %s)" % str(ok))

	var designed: float = 100.0
	var eff: float = ps.get_effective_stat_for_skill(&"kamehameha_001", &"amount", designed)
	_check("effective_amount_with_allocations", eff >= 18.0 and eff <= 22.0,
		"(got %.2f, expected ~20)" % eff)


func _test_progression_deallocate(ps: Node) -> void:
	ps.skill_points = 0
	ps.allocations = {}
	ps.grant_skill_points(5)
	ps.allocate(&"kamehameha_001", &"amount", 3)
	_check("after_alloc_3pts", ps.skill_points == 2)

	var ok: bool = ps.deallocate(&"kamehameha_001", &"amount", 2)
	_check("deallocate_2pts", ok and ps.skill_points == 4)
	_check("after_dealloc",
		int(ps.allocations[String(&"kamehameha_001")][&"amount"]) == 1,
		"(alloc=%s)" % str(ps.allocations))


func _test_progression_refund_on_remove(ps: Node) -> void:
	ps.skill_points = 0
	ps.allocations = {}
	ps.grant_skill_points(5)
	ps.allocate(&"kamehameha_001", &"amount", 3)
	ps.allocate(&"kamehameha_001", &"radius", 2)
	_check("before_remove", ps.skill_points == 0)

	ps.remove_skill(&"kamehameha_001")
	_check("refund_on_remove", ps.skill_points == 5,
		"(refunded %d points)" % ps.skill_points)
	_check("removed_from_owned", &"kamehameha_001" not in ps.owned_skills)


func _test_skill_validator_positive() -> void:
	var spec := {
		"name": "Test Kamehameha",
		"description": "test",
		"type": "damage",
		"target_resolver": { "kind": "aoe", "params": { "radius": 5 } },
		"designed_max": { "amount": 100, "radius": 5 },
		"atoms": [
			{ "type": "hit", "params": { "amount": 100 } }
		]
	}
	var r: Dictionary = SkillValidator.validate(spec)
	_check("validator_positive", r.valid, "(errors=%s)" % str(r.errors))


func _test_skill_validator_negative() -> void:
	var spec1 := {
		"name": "Empty",
		"type": "damage",
		"target_resolver": { "kind": "self" },
		"designed_max": {},
		"atoms": []
	}
	var r1: Dictionary = SkillValidator.validate(spec1)
	_check("validator_empty_atoms_ok", r1.valid, "(errors=%s)" % str(r1.errors))

	var spec2 := spec1.duplicate(true)
	spec2["atoms"] = []
	for i in 6:
		spec2["atoms"].append({ "type": "hit", "params": { "amount": 1 } })
	var r2: Dictionary = SkillValidator.validate(spec2)
	_check("validator_max_atoms", not r2.valid and r2.errors.size() > 0, "(errors=%s)" % str(r2.errors))

	var spec3 := {
		"name": "Bad",
		"type": "damage",
		"target_resolver": { "kind": "self" },
		"designed_max": {},
		"atoms": [
			{ "type": "move", "params": { "kind": "dash", "distance": 5 } }
		]
	}
	var r3: Dictionary = SkillValidator.validate(spec3)
	_check("validator_damage_no_move", not r3.valid, "(errors=%s)" % str(r3.errors))

	var spec4 := {
		"name": "Bad",
		"type": "damage",
		"target_resolver": { "kind": "self" },
		"designed_max": {},
		"atoms": [
			{ "type": "explode_universe", "params": {} }
		]
	}
	var r4: Dictionary = SkillValidator.validate(spec4)
	_check("validator_unknown_atom", not r4.valid, "(errors=%s)" % str(r4.errors))


func _test_skill_resource_load() -> void:
	var k = load("res://data/skills/kamehameha_001.tres")
	_check("kamehameha_loaded", k != null and k.id == &"kamehameha_001", "(id=%s)" % str(k.id if k else "null"))
	_check("kamehameha_atoms_count", k.atoms.size() == 2, "(got %d, expected 2: trigger+buff)" % k.atoms.size())
	_check("kamehameha_designed_max",
		float(k.designed_max.get("amount", 0)) == 100.0,
		"(amount=%s)" % k.designed_max.get("amount", "?"))

	var s = load("res://data/skills/serious_punch_001.tres")
	_check("serious_punch_loaded", s != null and s.id == &"serious_punch_001")
	_check("serious_punch_atoms_count", s.atoms.size() == 3, "(got %d)" % s.atoms.size())


func _test_skill_power_ratio(ps: Node) -> void:
	ps.skill_points = 0
	ps.proficiency = 0
	ps.allocations = {}
	ps.set("owned_skills", [] as Array[StringName])
	ps.skill_catalog = {}
	var skill = load("res://data/skills/kamehameha_001.tres")
	ps.add_skill(skill)
	ps.grant_skill_points(5)
	ps.allocate(&"kamehameha_001", &"amount", 5)
	var ratio: float = ps.get_skill_power_ratio(&"kamehameha_001")
	_check("power_ratio_with_allocations", ratio > 0.0 and ratio < 1.0, "(ratio=%.3f)" % ratio)
