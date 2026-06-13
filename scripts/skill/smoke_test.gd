## SmokeTest — Valida el sistema de skills en headless.
##
## Uso: godot --headless --script scripts/skill/smoke_test.gd
## Imprime PASS/FAIL al final. Exit code 0 si todo OK, 1 si falla.
##
## Nota: usa preloads en vez de class_name porque cuando se ejecuta como
## script suelto el class_name registry no está poblado.
extends SceneTree

const Balance := preload("res://scripts/skill/balance.gd")
const SkillValidator := preload("res://scripts/skill/skill_validator.gd")
const SkillResource := preload("res://scripts/skill/skill_resource.gd")
const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")

var _passes: int = 0
var _fails: int = 0


func _init() -> void:
	# En --script los autoloads se añaden al SceneTree DESPUÉS de _init.
	# Esperamos un frame y luego corremos los tests.
	process_frame.connect(_run_tests, CONNECT_ONE_SHOT)


func _run_tests() -> void:
	print("\n=== Skill System Smoke Test ===\n")
	# ProgressionState es un autoload; lo recuperamos del tree
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


# === Tests ===

func _test_balance_forced_floor() -> void:
	# Lvl1 (0 points, Novice) = lvl1 floor 5% = 5
	# PERO tier Novice cap 10% = 10. El sistema toma el soft_value (5) o el hard_cap (10)?
	# En realidad: value = soft_value + (hard_cap - soft_value) * level_bonus
	# Con 0 points, soft_progress=0, soft_value=lvl1=5
	# hard_cap = 100*0.10 = 10
	# level_bonus en Novice (prof=0) = smoothstep(0,1,0^0.5) = smoothstep(0,1,0) = 0
	# value = 5 + (10-5)*0 = 5
	var v: float = Balance.compute_effective(100.0, 0, 5, 0)
	_check("forced_floor", v >= 4.5 and v <= 6.0, "(got %.2f, expected ~5)" % v)


func _test_balance_soft_cap() -> void:
	# 5 puntos (max), Novice (prof=0): tier_max=10, value clamp a 10
	var v: float = Balance.compute_effective(100.0, 5, 5, 0)
	_check("soft_cap_5pts_novice", v >= 9.5 and v <= 10.5, "(got %.2f, expected ~10)" % v)

	# 5 puntos + Adept (prof=15): tier_max=35
	var v2: float = Balance.compute_effective(100.0, 5, 5, 15)
	# soft=50, points_unlock=1, tier_unlock (Adept, next=30, ratio=0.5, sqrt=0.707)
	# smoothstep(0,1,0.707)=0.793
	# unlock=0.793, value=50+50*0.793=89.65, cap=35 → 35
	_check("soft_cap_5pts_adept", v2 >= 34.0 and v2 <= 36.0, "(got %.2f, expected ~35)" % v2)


func _test_balance_proficiency_tiers() -> void:
	# En Mythic (150 prof), 5 puntos: ~100 (full power)
	var v: float = Balance.compute_effective(100.0, 5, 5, 150)
	_check("proficiency_mythic_5pts", v >= 95.0 and v <= 100.0, "(got %.2f, expected 95-100)" % v)

	# En Novice, 0 puntos: ~5
	var v2: float = Balance.compute_effective(100.0, 0, 5, 0)
	_check("proficiency_novice_0pts", v2 >= 4.0 and v2 <= 6.0, "(got %.2f, expected ~5)" % v2)

	# 0 puntos, Mythic: ~5 (lvl1 floor, no points_unlock)
	var v_mythic_0: float = Balance.compute_effective(100.0, 0, 5, 150)
	_check("proficiency_mythic_0pts", v_mythic_0 >= 4.0 and v_mythic_0 <= 6.0,
		"(got %.2f, expected ~5)" % v_mythic_0)

	# En Master (50 prof), 3 puntos: 0.7 exp, progress = (3/5)^0.7 = 0.697
	# soft_value = 5 + 45*0.697 = 36.4
	# tier_max = 65, points_unlock=0.697, tier_unlock (50, next=75)
	# ratio=50/75=0.667, sqrt=0.816, smoothstep(0,1,0.816)=0.961
	# unlock=0.670, value=36.4+63.6*0.670=79.0, cap=65 → 65
	var v3: float = Balance.compute_effective(100.0, 3, 5, 50)
	_check("proficiency_master_3pts", v3 >= 60.0 and v3 <= 70.0, "(got %.2f, expected ~65)" % v3)


func _test_balance_cost_scaling() -> void:
	var low: float = Balance.cost_effective(50.0, 5.0, 100.0)  # 5% power
	var high: float = Balance.cost_effective(50.0, 100.0, 100.0)  # 100% power
	# power_component = (5/100)^0.5 = 0.224, lerp(0.3, 1.0, 0.224) = 0.3 + 0.7*0.224 = 0.457
	# low = 50 * 0.457 = 22.8
	# high: power_component = 1.0, lerp = 1.0, high = 50
	_check("cost_scaling_low", low >= 18.0 and low <= 30.0, "(got %.2f, expected ~23)" % low)
	_check("cost_scaling_high", high >= 48.0 and high <= 52.0, "(got %.2f, expected ~50)" % high)
	_check("cost_scales_monotonically", low < high, "(low=%.2f, high=%.2f)" % [low, high])


func _test_progression_grant_and_allocate(ps: Node) -> void:
	# Limpia estado
	ps.skill_points = 0
	ps.proficiency = 0
	ps.allocations = {}
	# Tipos correctos: Array[StringName] y Dictionary
	ps.set("owned_skills", [] as Array[StringName])
	ps.skill_catalog = {}

	# Carga skill de prueba
	var skill = load("res://data/skills/kamehameha_001.tres")
	ps.add_skill(skill)

	_check("add_skill", &"kamehameha_001" in ps.owned_skills, "(owned=%s)" % str(ps.owned_skills))

	# Grant 5 puntos
	ps.grant_skill_points(5)
	_check("grant_points", ps.skill_points == 5 and ps.proficiency == 5,
		"(points=%d, prof=%d)" % [ps.skill_points, ps.proficiency])

	# Allocate 3 a amount
	var ok: bool = ps.allocate(&"kamehameha_001", &"amount", 3)
	_check("allocate_3pts", ok, "(returned %s)" % str(ok))
	_check("after_allocate_points_remaining", ps.skill_points == 2, "(points=%d)" % ps.skill_points)
	_check("after_allocate_skill_points_3",
		int(ps.allocations[String(&"kamehameha_001")][&"amount"]) == 3,
		"(alloc=%s)" % str(ps.allocations))

	# Allocate 2 más a radius
	ok = ps.allocate(&"kamehameha_001", &"radius", 2)
	_check("allocate_2pts_radius", ok and ps.skill_points == 0, "(points=%d)" % ps.skill_points)

	# No debe poder allocate más (5 puntos max por stat)
	ps.grant_skill_points(3)
	ok = ps.allocate(&"kamehameha_001", &"amount", 3)  # 3+3=6 > 5
	_check("cannot_exceed_max_points", not ok, "(returned %s)" % str(ok))

	# effective amount
	var designed: float = 100.0
	var eff: float = ps.get_effective_stat_for_skill(&"kamehameha_001", &"amount", designed)
	# proficiency=8 (5+3), Apprentice cap 20%
	# 3 puntos en amount: progress = (3/5)^0.7 = 0.697
	# soft_value = 5 + 45*0.697 = 36.4
	# tier_max = 20, points_unlock=0.697
	# tier_unlock (8, next=15) ratio=0.533, sqrt=0.730, smoothstep(0,1,0.730)=0.821
	# unlock = 0.697*0.821 = 0.572
	# value = 36.4 + 63.6*0.572 = 36.4 + 36.4 = 72.8, cap=20 → 20
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
	# Sin atoms
	var spec1 := {
		"name": "Empty",
		"type": "damage",
		"target_resolver": { "kind": "self" },
		"designed_max": {},
		"atoms": []
	}
	var r1: Dictionary = SkillValidator.validate(spec1)
	_check("validator_empty_atoms_ok", r1.valid, "(errors=%s)" % str(r1.errors))

	# 6 atoms -> fail
	var spec2 := spec1.duplicate(true)
	spec2["atoms"] = []
	for i in 6:
		spec2["atoms"].append({ "type": "hit", "params": { "amount": 1 } })
	var r2: Dictionary = SkillValidator.validate(spec2)
	_check("validator_max_atoms", not r2.valid and r2.errors.size() > 0, "(errors=%s)" % str(r2.errors))

	# damage skill con move atom -> fail
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

	# atom desconocido
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
	# Kamehameha: 2 átomos (1x trigger con then_effect=burst_aoe, 1x buff de carga).
	# Antes eran 3, pero el 3ro (burst_aoe inmediato) causaba doble rayo. Se quitó.
	_check("kamehameha_atoms_count", k.atoms.size() == 2, "(got %d, expected 2: trigger+buff)" % k.atoms.size())
	_check("kamehameha_designed_max",
		float(k.designed_max.get("amount", 0)) == 100.0,
		"(amount=%s)" % k.designed_max.get("amount", "?"))

	var s = load("res://data/skills/serious_punch_001.tres")
	_check("serious_punch_loaded", s != null and s.id == &"serious_punch_001")
	_check("serious_punch_atoms_count", s.atoms.size() == 3, "(got %d)" % s.atoms.size())


func _test_skill_power_ratio(ps: Node) -> void:
	# Reset completo y recargar kamehameha (el test anterior lo eliminó)
	ps.skill_points = 0
	ps.proficiency = 0
	ps.allocations = {}
	ps.set("owned_skills", [] as Array[StringName])
	ps.skill_catalog = {}
	var skill = load("res://data/skills/kamehameha_001.tres")
	ps.add_skill(skill)
	ps.grant_skill_points(5)
	# Kamehameha tiene stat "amount" (no "damage"). Allocamos a amount.
	ps.allocate(&"kamehameha_001", &"amount", 5)
	var ratio: float = ps.get_skill_power_ratio(&"kamehameha_001")
	# 5 puntos en amount con proficiency 5 (Apprentice cap 20%):
	# soft=50, tier_max=20, points_unlock=1, tier_unlock=0
	# unlock=0, value=50+50*0=50, cap=20 → 20
	# amount ratio = 20/100 = 0.20
	# Otros stats (radius, cooldown, etc.) en 0 puntos: ~5% cada uno
	# Promedio: (0.20 + ~0.05*N) / (1+N)
	_check("power_ratio_with_allocations", ratio > 0.0 and ratio < 1.0, "(ratio=%.3f)" % ratio)
