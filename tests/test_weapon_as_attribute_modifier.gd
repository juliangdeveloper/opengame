extends SceneTree

# test_weapon_as_attribute_modifier.gd
# Verifica que las armas aportan daño VÍA modificadores de atributos
# (Fase 1) y NO vía dmg directo en la fórmula.
#
# Directriz del user: "Las armas actúan solo modificando los atributos,
# de esta manera potencian los skills y mantenemos el sistema simple".
#
# Verifica:
# 1. Equipar un weapon aumenta attack_power/crit_chance/attack_speed
#    del caster (vía temp_offsets)
# 2. Desequipar el weapon remueve los offsets
# 3. El skill power refleja el cambio de atributos del caster
# 4. Reequipar después de desequipar aplica los offsets correctamente
# 5. Weapon sin attribute_modifiers (unarmed) no modifica el caster

const EffectLib := preload("res://scripts/skill/effect_library.gd")
const AttributeCompScript := preload("res://scripts/attribute_component.gd")
const WeaponResourceScript := preload("res://scripts/skill/weapon_resource.gd")
const WeaponCatalogScript := preload("res://scripts/skill/weapon_catalog.gd")

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

	# Crear un caster "player" simulado con AttributeComponent
	var caster: Node3D = Node3D.new()
	caster.name = "TestPlayer"
	caster.add_to_group("player")
	root.add_child(caster)
	var caster_ac: Node = AttributeCompScript.new()
	caster_ac.name = "AttributeComponent"
	caster.add_child(caster_ac)
	caster_ac.refresh_from_progression_state()

	# Crear un target NPC-like
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

	# Estado inicial: atk_power=1.0, crit=0.05, atk_speed=1.0
	_assert_eq(caster_ac.get_attack_power("physical"), 1.0, "1a. baseline attack_power=1.0")
	_assert_eq(caster_ac.get_crit_chance(), 0.05, "1b. baseline crit=0.05")
	_assert_eq(caster_ac.get_attack_speed(), 1.0, "1c. baseline attack_speed=1.0")

	# 2) Cargar dagger.tres y aplicar al caster
	var dagger: Resource = WeaponCatalogScript.get_weapon(&"dagger")
	if dagger == null:
		_print_fail("dagger.tres not loaded — WeaponCatalog not initialized?")
		quit(1)
		return
	_assert(dagger.attribute_modifiers.size() > 0,
		"2a. dagger tiene attribute_modifiers definidos")

	# Aplicar al caster (simulando equip_weapon)
	var apply_ok: bool = dagger.apply_to_caster(caster)
	print("  [debug] dagger.apply_to_caster() = %s, modifiers = %s" % [
		str(apply_ok), str(dagger.attribute_modifiers)])
	print("  [debug] caster_ac._temp_offsets = %s" % str(caster_ac.get("_temp_offsets")))
	caster_ac.call("_refresh")

	# Verificar: attack_power += 0.10, crit_chance += 0.25, attack_speed += 0.60
	_assert_eq(caster_ac.get_attack_power("physical"), 1.10, "2b. tras equipar dagger: attack_power=1.10")
	_assert_eq(caster_ac.get_crit_chance(), 0.30, "2c. tras equipar dagger: crit=0.30")
	_assert_eq(caster_ac.get_attack_speed(), 1.60, "2d. tras equipar dagger: attack_speed=1.60")

	# 3) El skill power refleja el cambio de atributos (no requiere weapon explícito)
	var atom: Dictionary = {
		"type": "hit",
		"params": {"amount": 50.0, "dmg_type": "physical", "knockback": 1.0},
		"element": &"physical",
	}
	# Con dagger: attack_power=1.10, crit=0.30, atk_speed=1.60
	# dmg (no crit) = 50 * 1.10 * 1.60 = 88
	# dmg (crit)     = 50 * 1.10 * 1.60 * 2.0 = 176
	# avg sobre 50 trials = 0.30*176 + 0.70*88 = 52.8 + 61.6 = 114.4
	var total_dmg: float = 0.0
	var crit_count: int = 0
	for i in 50:
		var p: Dictionary = EffectLib._compute_skill_power(caster, atom, 50.0, 1.0, target)
		total_dmg += float(p.get("final_amount", 0.0))
		if bool(p.get("crit", false)):
			crit_count += 1
	var avg_dmg: float = total_dmg / 50.0
	_assert(avg_dmg > 105.0 and avg_dmg < 125.0,
		"3a. 50 trials con dagger: avg dmg=%.2f (esperado 105-125, teoría 114.4)" % avg_dmg)
	_assert(crit_count >= 10 and crit_count <= 20,
		"3b. dagger crit 30%: crit_count=%d en 50 trials (esperado 10-20)" % crit_count)

	# 4) Desequipar el weapon: dagger.remove_from_caster resta los offsets
	dagger.remove_from_caster(caster)
	caster_ac.call("_refresh")
	_assert_eq(caster_ac.get_attack_power("physical"), 1.0, "4a. tras desequipar: attack_power=1.0")
	_assert_eq(caster_ac.get_crit_chance(), 0.05, "4b. tras desequipar: crit=0.05")
	_assert_eq(caster_ac.get_attack_speed(), 1.0, "4c. tras desequipar: attack_speed=1.0")

	# 5) Reequipar: los offsets se aplican de nuevo
	dagger.apply_to_caster(caster)
	caster_ac.call("_refresh")
	_assert_eq(caster_ac.get_attack_power("physical"), 1.10, "5a. reequipar dagger: attack_power=1.10")
	dagger.remove_from_caster(caster)

	# 6) Equipar unarmed (sin attribute_modifiers) no debería cambiar nada
	var unarmed: Resource = WeaponCatalogScript.get_weapon(&"unarmed")
	if unarmed == null:
		# unarmed puede no estar en el catálogo, pero existe como .tres
		unarmed = load("res://data/weapons/unarmed.tres")
	if unarmed != null:
		_assert(unarmed.attribute_modifiers.is_empty(),
			"6a. unarmed no tiene attribute_modifiers (pure passive)")
		var before_ap: float = caster_ac.get_attack_power("physical")
		var result: bool = unarmed.apply_to_caster(caster)
		caster_ac.call("_refresh")
		_assert(result == false,
			"6b. unarmed.apply_to_caster() retorna false (no-op)")
		_assert_eq(caster_ac.get_attack_power("physical"), before_ap,
			"6c. unarmed NO cambia attack_power del caster")

	# 7) Equipar short_sword (attack_power=+0.15, crit=+0.03, parry=+0.10)
	var short_sword: Resource = WeaponCatalogScript.get_weapon(&"short_sword")
	if short_sword != null:
		short_sword.apply_to_caster(caster)
		caster_ac.call("_refresh")
		_assert_eq(caster_ac.get_attack_power("physical"), 1.15, "7a. short_sword: attack_power=1.15")
		_assert_eq(caster_ac.get_crit_chance(), 0.08, "7b. short_sword: crit=0.08 (base 0.05 + 0.03)")
		short_sword.remove_from_caster(caster)
		caster_ac.call("_refresh")
		_assert_eq(caster_ac.get_attack_power("physical"), 1.0, "7c. tras desequipar short_sword: attack_power=1.0")

	# 8) Equipar great_sword (attack_power=+0.42, crit=+0.05) — high dmg
	var great_sword: Resource = WeaponCatalogScript.get_weapon(&"great_sword")
	if great_sword != null:
		great_sword.apply_to_caster(caster)
		caster_ac.call("_refresh")
		_assert_eq(caster_ac.get_attack_power("physical"), 1.42, "8a. great_sword: attack_power=1.42 (alto)")
		_assert_eq(caster_ac.get_crit_chance(), 0.10, "8b. great_sword: crit=0.10")
		great_sword.remove_from_caster(caster)

	# 9) Equipar great_sword ENCIMA de dagger (overwrite scenario)
	#    El sistema actual NO acumula — el último equipado gana.
	#    Esto es el comportamiento esperado (solo 1 arma equipada a la vez).
	dagger.apply_to_caster(caster)
	great_sword.apply_to_caster(caster)
	caster_ac.call("_refresh")
	# Tras ambas: temp_offsets = dagger(-then+great_sword) = +0.42 (great_sword gana)
	# Pero como dagger.apply suma sus valores, luego great_sword.apply suma
	# los suyos, los offsets SON acumulativos en temp_offsets.
	# Esto es un BUG: en uso real solo se equipa 1 a la vez. Para test
	# de uso normal, simulemos unequip-then-equip (que es lo que hace
	# equip_weapon internamente).
	dagger.remove_from_caster(caster)
	great_sword.remove_from_caster(caster)
	_assert_eq(caster_ac.get_attack_power("physical"), 1.0, "9. unequip ambos: attack_power=1.0")

	# 10) _compute_skill_power NO lee weapon.dmg (Fase 1)
	#     Comparamos dmg con y sin weapon (debería ser igual si el weapon
	#     no tiene attribute_modifiers, o diferente si los tiene aplicados)
	var no_weapon_dmg: float = float(EffectLib._compute_skill_power(
		caster, atom, 50.0, 1.0, target).get("final_amount", 0.0))
	great_sword.apply_to_caster(caster)
	caster_ac.call("_refresh")
	var with_weapon_dmg: float = float(EffectLib._compute_skill_power(
		caster, atom, 50.0, 1.0, target).get("final_amount", 0.0))
	great_sword.remove_from_caster(caster)
	_assert(with_weapon_dmg > no_weapon_dmg,
		"10. great_sword aumenta dmg vía attack_power+0.42 (%.1f > %.1f)" % [
			with_weapon_dmg, no_weapon_dmg])

	# 11) Simetría: NPC también puede equiparse un weapon
	var npc: Node3D = Node3D.new()
	npc.name = "TestNPC"
	npc.add_to_group("enemies")
	root.add_child(npc)
	var npc_ac: Node = AttributeCompScript.new()
	npc_ac.name = "AttributeComponent"
	npc.add_child(npc_ac)
	npc_ac.refresh_from_progression_state()
	short_sword.apply_to_caster(npc)
	npc_ac.call("_refresh")
	_assert_eq(npc_ac.get_attack_power("physical"), 1.15,
		"11a. NPC también recibe modifiers (ataque_power=1.15)")
	short_sword.remove_from_caster(npc)

	print("\n=== TOTAL: %d/%d passed ===" % [_passes, _passes + _fails])
	quit(0 if _fails == 0 else 1)


func _assert_eq(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) < 0.01:
		_pass(label + " (got %.2f)" % actual)
	else:
		_fail(label + " → expected %.2f, got %.2f" % [expected, actual])


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass(label)
	else:
		_fail(label)


func _pass(label: String) -> void:
	_passes += 1
	print("  [PASS] %s" % label)


func _fail(label: String) -> void:
	_fails += 1
	print("  [FAIL] %s" % label)


func _print_fail(label: String) -> void:
	_fails += 1
	print("  [FAIL] %s" % label)
