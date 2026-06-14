extends SceneTree

# test_skill_power_bilateral.gd
# Verifica el modelo bilateral de _compute_skill_power (Fase 0).
#
# El modelo bilateral:
#   - _compute_skill_power aplica: caster.attack_power × caster.crit × caster.attack_speed
#     × weapon_contribution × (1 si el target no esquiva)
#   - _apply_hit aplica DESPUÉS: element_matrix × target.phys_res × target.ele_res
#
# Verifica que los ATRIBUTOS de AMBAS instancias influyen en la fórmula
# final, no solo del caster. Y que los status effects (burn, stun) se
# resuelven comparando SOLO la potency y resistance del MISMO status
# (burn_res con burn_res), sin interferencia de phys_dmg/strength.

const EffectLib := preload("res://scripts/skill/effect_library.gd")
const AttributeCompScript := preload("res://scripts/attribute_component.gd")

var _passes: int = 0
var _fails: int = 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var ps: Node = root.get_node_or_null("ProgressionState")
	if ps == null:
		_print_fail("ProgressionState autoload not found")
		quit(1)
		return

	# Caster y target con AttributeComponent
	var caster: Node3D = Node3D.new()
	caster.name = "TestCaster"
	caster.add_to_group("player")
	root.add_child(caster)
	var caster_ac: Node = AttributeCompScript.new()
	caster_ac.name = "AttributeComponent"
	caster.add_child(caster_ac)
	caster_ac.refresh_from_progression_state()

	var target: Node3D = Node3D.new()
	target.name = "TestTarget"
	target.add_to_group("enemies")
	root.add_child(target)
	var target_ac: Node = AttributeCompScript.new()
	target_ac.name = "AttributeComponent"
	target.add_child(target_ac)
	target_ac.refresh_from_progression_state()

	# Reset
	ps.attribute_allocations = {}
	ps.equipped_weapon = null
	caster_ac.set("_allocations", {})
	caster_ac.call("_refresh")
	target_ac.set("_allocations", {})
	target_ac.call("_refresh")

	var atom: Dictionary = {
		"type": "hit",
		"params": {"amount": 50.0, "dmg_type": "physical", "knockback": 1.0},
		"element": &"physical",
	}
	# Constante: el caster tiene un offset temporal dexterity=-2.5
	# (para forzar crit=0 y dodge=0 deterministicamente). Esto reduce
	# attack_speed a 1 + 0.05*(-2.5) = 0.875.
	const ATK_SPEED: float = 0.875
	const BASE: float = 50.0

	# =========================================================================
	# GRUPO 1: caster.attack_power (afecta SOLO el daño físico)
	# =========================================================================

	# 1) Baseline: 0 puntos → attack_power = 1.0 → dmg = 50 * 0.875 = 43.75
	_set_attr(caster_ac, &"strength", 0)
	_set_attr(caster_ac, &"phys_dmg", 0)
	_set_attr(caster_ac, &"ele_dmg", 0)
	_set_temp_offset(caster_ac, &"dexterity", -2.5)  # crit=0, dodge=0
	_test_dmg(caster, target, atom, BASE * 1.0 * ATK_SPEED, "1. baseline → 50*0.875 = 43.75 dmg", 0.5)

	# 2) Caster +5 strength → attack_power = 1.5 → dmg = 50 * 1.5 * 0.875 = 65.625
	_set_attr(caster_ac, &"strength", 5)
	_test_dmg(caster, target, atom, BASE * 1.5 * ATK_SPEED, "2. +5 str → 65.625 dmg (1.5x)", 0.5)

	# 3) Caster +5 phys_dmg → attack_power = 1.25 → dmg = 50 * 1.25 * 0.875 = 54.69
	_set_attr(caster_ac, &"strength", 0)
	_set_attr(caster_ac, &"phys_dmg", 5)
	_test_dmg(caster, target, atom, BASE * 1.25 * ATK_SPEED, "3. +5 phys_dmg → 54.69 dmg (1.25x)", 0.5)

	# 4) Caster +5 ele_dmg → attack_power = 1.25 (ele_dmg cuenta para dmg físico) → 54.69
	_set_attr(caster_ac, &"phys_dmg", 0)
	_set_attr(caster_ac, &"ele_dmg", 5)
	_test_dmg(caster, target, atom, BASE * 1.25 * ATK_SPEED, "4. +5 ele_dmg → 54.69 dmg (1.25x, ele_dmg cuenta)", 0.5)

	# 5) +5 str + +5 phys_dmg → 50 * 1.75 * 0.875 = 76.56
	_set_attr(caster_ac, &"ele_dmg", 0)
	_set_attr(caster_ac, &"phys_dmg", 5)
	_set_attr(caster_ac, &"strength", 5)
	_test_dmg(caster, target, atom, BASE * 1.75 * ATK_SPEED, "5. +5 str/+5 phys_dmg → 76.56 dmg (1.75x)", 0.5)

	# =========================================================================
	# GRUPO 2: target.dodge (afecta SOLO la probabilidad de hit)
	# =========================================================================
	_set_attr(caster_ac, &"strength", 5)
	_set_attr(caster_ac, &"phys_dmg", 0)
	# Resetear target
	_set_attr(target_ac, &"dexterity", 0)
	_set_attr(target_ac, &"phys_res", 0)
	# Forzar dodge=0 con offset negativo
	_set_temp_offset(target_ac, &"dexterity", -2.5)

	# 6) Target sin dodge → siempre hit, dmg = 50 * 1.5 * 0.875 = 65.625
	_test_dmg(caster, target, atom, BASE * 1.5 * ATK_SPEED, "6. target sin dodge → 65.625 dmg (siempre hit)", 0.5)

	# 7) Target con 100% dodge (via +99.5 offset) → 100% miss
	_set_temp_offset(target_ac, &"dexterity", 50.0)  # cap a 1.0
	var power_dodge: Dictionary = EffectLib._compute_skill_power(caster, atom, 50.0, 1.0, target)
	_assert(power_dodge.get("dodged", false) == true,
		"7. target con 100% dodge → dodged=true")
	_assert_eq(float(power_dodge.get("final_amount", 1.0)), 0.0,
		"7b. dodged → final_amount = 0")
	_set_temp_offset(target_ac, &"dexterity", -2.5)  # restore

	# 8) Target con 50% dodge (via +22.5 dexterity = 0.45 + 0.05 = 0.50)
	#    20 trials: al menos 1 hit, al menos 1 dodge esperados
	_set_temp_offset(target_ac, &"dexterity", 22.5)  # base 0.05 + 22.5*0.02 = 0.50
	var hits: int = 0
	var dodges: int = 0
	for i in 20:
		var p: Dictionary = EffectLib._compute_skill_power(caster, atom, 50.0, 1.0, target)
		if bool(p.get("dodged", false)):
			dodges += 1
		else:
			hits += 1
	_assert(hits > 0 and dodges > 0,
		"8. 20 trials con 50% dodge: hits=%d, dodges=%d" % [hits, dodges])
	_set_temp_offset(target_ac, &"dexterity", -2.5)

	# =========================================================================
	# GRUPO 3: Simetría bilateral (NPC→player)
	# =========================================================================
	var npc: Node3D = Node3D.new()
	npc.name = "TestNPC"
	npc.add_to_group("enemies")
	root.add_child(npc)
	var npc_ac: Node = AttributeCompScript.new()
	npc_ac.name = "AttributeComponent"
	npc.add_child(npc_ac)
	npc_ac.refresh_from_progression_state()
	_set_attr(npc_ac, &"strength", 5)
	_set_temp_offset(npc_ac, &"dexterity", -2.5)
	_set_attr(target_ac, &"phys_res", 0)

	_test_dmg(npc, target, atom, BASE * 1.5 * ATK_SPEED,
		"9. NPC +5 str → target 65.625 dmg (mismo modelo que player→NPC)", 0.5)

	# Invertir: target ataca npc
	_set_attr(npc_ac, &"strength", 0)
	_set_attr(target_ac, &"strength", 5)
	_set_temp_offset(target_ac, &"dexterity", -2.5)
	_test_dmg(target, npc, atom, BASE * 1.5 * ATK_SPEED,
		"10. target +5 str → NPC 65.625 dmg (simetría)", 0.5)
	_set_temp_offset(target_ac, &"dexterity", -2.5)

	# =========================================================================
	# GRUPO 4: Status effects (burn) — solo burn_potency vs burn_resistance
	# =========================================================================
	_set_attr(caster_ac, &"strength", 0)
	_set_attr(caster_ac, &"phys_dmg", 0)
	_set_attr(caster_ac, &"ele_dmg", 0)
	_set_attr(target_ac, &"strength", 0)
	_set_attr(caster_ac, &"burn_res", 5)
	_set_attr(target_ac, &"burn_res", 5)

	var potency: float = caster_ac.get_status_potency(&"burn")
	var resistance: float = target_ac.get_status_resistance(&"burn")
	_assert_eq(potency, 1.5, "11a. caster +5 burn_res → burn_potency=1.5")
	_assert_eq(resistance, 0.5, "11b. target +5 burn_res → burn_resistance=0.5")

	# 12) phys_dmg/strength/ele_dmg NO afectan burn potency (independencia de stats)
	_set_attr(caster_ac, &"phys_dmg", 10)
	_set_attr(caster_ac, &"ele_dmg", 10)
	_set_attr(caster_ac, &"strength", 10)
	_set_attr(target_ac, &"ele_res", 10)
	var potency2: float = caster_ac.get_status_potency(&"burn")
	_assert_eq(potency2, 1.5,
		"12. phys_dmg/ele_dmg/strength NO afectan burn_potency (sigue 1.5)")

	# 13) Comparación del MISMO status
	#     burn_potency solo se compara con burn_resistance, no con
	#     stun_resistance, freeze_resistance, etc.
	_set_attr(caster_ac, &"burn_res", 5)
	_set_attr(caster_ac, &"stun_res", 10)
	_set_attr(target_ac, &"burn_res", 5)
	_set_attr(target_ac, &"freeze_res", 10)
	var burn_pot: float = caster_ac.get_status_potency(&"burn")
	var burn_res: float = target_ac.get_status_resistance(&"burn")
	_assert_eq(burn_pot, 1.5, "13a. burn_potency solo influenciado por burn_res")
	_assert_eq(burn_res, 0.5, "13b. burn_resistance solo influenciado por burn_res")
	# Y stun NO influye en burn
	_assert_eq(caster_ac.get_status_potency(&"stun"), 2.0,
		"13c. stun_potency = 1 + 0.10*10 = 2.0 (de stun_res=10)")
	# freeze_potency del target — el target TIENE freeze_res=10,
	# así que su freeze_potency es 2.0 (esto es el MISMO atributo visto
	# desde el lado del caster, que es lo que confirma "los atributos que
	# generan efectos secundarios solo se comparan entre sí" del mismo tipo).
	_assert_eq(target_ac.get_status_potency(&"freeze"), 2.0,
		"13d. target.get_status_potency(freeze) = 2.0 (de freeze_res=10)")

	print("\n=== TOTAL: %d/%d passed ===" % [_passes, _passes + _fails])
	quit(0 if _fails == 0 else 1)


func _test_dmg(
	caster: Node, target: Node, atom: Dictionary,
	expected: float, label: String, tolerance: float = 1.0
) -> void:
	var power: Dictionary = EffectLib._compute_skill_power(caster, atom, 50.0, 1.0, target)
	var actual: float = float(power.get("final_amount", 0.0))
	if absf(actual - expected) <= tolerance:
		_pass(label + " (%.2f)" % actual)
	else:
		_fail(label + " → expected %.2f, got %.2f (notes=%s)" % [
			expected, actual, str(power.get("notes"))
		])


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass(label)
	else:
		_fail(label)


func _assert_eq(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) < 0.01:
		_pass(label + " (got %.2f)" % actual)
	else:
		_fail(label + " → expected %.2f, got %.2f" % [expected, actual])


func _set_attr(ac: Node, attr_id: StringName, pts: int) -> void:
	# _allocations es privado. MERGE con el dict actual para no perder
	# atributos que se setean en tests anteriores (e.g. setear phys_dmg
	# después de burn_res no debe borrar burn_res).
	var d: Dictionary = {}
	if ac.get("_allocations") != null:
		d = (ac.get("_allocations") as Dictionary).duplicate()
	d[String(attr_id)] = pts
	ac.set("_allocations", d)
	ac.call("_refresh")


## Setea un offset temporal en el attribute component (SETTER puro, no aditivo).
## A diferencia de apply_temp_offset/remove_temp_offset que son aditivos,
## esta función reemplaza el valor total del offset.
func _set_temp_offset(ac: Node, attr_id: StringName, offset: float) -> void:
	var d: Dictionary = {}
	if ac.get("_temp_offsets") != null:
		d = (ac.get("_temp_offsets") as Dictionary).duplicate()
	d[String(attr_id)] = offset
	ac.set("_temp_offsets", d)
	ac.call("_refresh")


func _pass(label: String) -> void:
	_passes += 1
	print("  [PASS] %s" % label)


func _fail(label: String) -> void:
	_fails += 1
	print("  [FAIL] %s" % label)


func _print_fail(label: String) -> void:
	_fails += 1
	print("  [FAIL] %s" % label)
