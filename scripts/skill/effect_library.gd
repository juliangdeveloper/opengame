## EffectLibrary — Implementaciones de los 14 átomos del sistema.
##
## Cada átomo es una función pura que toma:
##   - executor: el SkillExecutor (acceso a caster, balance, etc.)
##   - atom: el Dictionary del átomo (params + applies_to_target)
##   - targets: Array[Node] ya resueltos por TargetResolver
##
## Aplica el efecto a los targets. Maneja DOT, burst AOE, projectiles, etc.
##
## Estado (DoT, HoT, shields, morphs, status effects) se trackea en el
## caster/target vía componentes BuffComponent / DoTComponent (ver helpers).
##
## No usa class_name para que funcione tanto en --script como en escenas.
extends RefCounted

const DEBUG := true
const TargetResolver := preload("res://scripts/skill/target_resolver.gd")
const Elements := preload("res://scripts/skill/elements.gd")
# Componentes que se añaden a targets para trackear efectos en curso.
# Cada componente es un nodo ligero (Node) que tiene un timer interno.
#
# SISTEMA ELEMENTAL (2026-06-08):
# - Cada átomo puede tener `element` (fire/water/earth/air/lightning/light/dark/arcane)
# - Cada átomo puede tener `applies_status` con `status_chance` y `status_duration`
# - Cada átomo puede tener `applies_resistance_to_caster` (resistencia temporal)
# - El daño se multiplica por la elemental_matrix (Pokémon-style) y por la
#   resistencia del defensor (de ProgressionState.element_allocations + temporales)

# === Aplica el átomo ===
# atom format: { "type": "...", "params": {...}, "hitbox": {...} (opcional), "applies_to_target": "..." }
# - params = lógica (daño, radio, falloff, etc.)
# - hitbox = visual (shape, size, color, lifetime, etc.) — totalmente data-driven
# El handler _apply_X recibe el atom completo para poder leer params y hitbox.
static func apply_atom(
	executor: Node,
	atom: Dictionary,
	targets: Array[Node]
) -> void:
	var atom_type_text := String(atom.get("type", ""))
	if targets.is_empty() and atom_type_text != "trigger" and atom_type_text != "burst_aoe" and atom_type_text != "persistent_zone":
		# Algunos átomos solo hacen sentido con target; AOE/telegráfos pueden mostrarse sin targets
		return
	var atom_type := StringName(atom.get("type", ""))
	var params: Dictionary = atom.get("params", {})
	var applies := String(atom.get("applies_to_target", "primary"))
	match atom_type:
		&"hit":
			_apply_hit(executor, atom, targets)
		&"dot":
			_apply_dot(executor, atom, targets)
		&"burst_aoe":
			_apply_burst_aoe(executor, atom, targets, applies)
		&"persistent_zone":
			_apply_persistent_zone(executor, params, targets, applies)
		&"heal":
			_apply_heal(executor, params, targets)
		&"hot":
			_apply_hot(executor, params, targets)
		&"shield":
			_apply_shield(executor, params, targets)
		&"move":
			_apply_move(executor, params, targets)
		&"morph":
			_apply_morph(executor, params, targets)
		&"buff":
			_apply_buff(executor, params, targets)
		&"status":
			_apply_status(executor, atom, targets)
		&"mind":
			_apply_mind(executor, params, targets)
		&"projectile":
			_apply_projectile(executor, params, targets)
		&"npc":
			_apply_npc(executor, params, targets)
		&"zone":
			_apply_zone(executor, params, targets)
		&"trigger":
			_apply_trigger(executor, atom)
		_:
			push_warning("[EffectLibrary] unknown atom type: %s" % atom_type)


# === damage ===

# === _compute_skill_power (ATRIBUTOS bilaterales: caster + target) ===
## Calcula la "potencia" efectiva de un skill considerando los ATRIBUTOS de
## AMBAS instancias (caster y target), NO el weapon directamente.
##
## FASE 0 (2026-06-14): refactor del sistema viejo. Antes:
##   final = base + weapon.dmg × (1 + str*scale) × weapon.speed × crit × class
##
## Ahora:
##   final = base
##         × caster.attack_power          # phys_dmg + ele_dmg + strength
##         × crit multiplier (2x si crit) # caster.crit_chance
##         × (1 si el target falla dodge)  # target.dodge_chance
##         × (1 - target.phys_res)        # ya existente (lo aplica _apply_hit)
##         × elemental_matrix             # ya existente
##
## El weapon se mantiene como contribuidor ADITIVO en dmg (lo eliminaremos
## en Fase 1 cuando refactoremos weapons a "temp_offsets puros"). También
## añade crit/speed/class_dmg_mult vía offsets.
##
## El resultado es SIMÉTRICO: el mismo código sirve para player→NPC,
## NPC→player, NPC→NPC, etc. La clave es que ambos lados tienen
## AttributeComponent (player y NPC pueden tenerlo).
##
## Devuelve un Dictionary con:
##   - final_amount: dmg base escalado (antes de resistencias del target)
##   - final_knockback: knockback escalado
##   - crit: bool — si el golpe es crítico
##   - dodged: bool — si el target esquivó (final_amount=0 si true)
##   - notes: Array[String] — para debug/log
static func _compute_skill_power(
	executor: Node,
	atom: Dictionary,
	amount: float,
	knockback: float,
	target: Node
) -> Dictionary:
	var notes: Array = []
	# Aceptar tanto un SkillExecutor (con .caster) como el caster mismo.
	var caster: Node = null
	if executor and "caster" in executor and executor.caster != null:
		caster = executor.caster
	elif executor:
		caster = executor  # El test pasa el player directo

	# Determinar tipo de daño (del atom o de la última acción del caster)
	var dmg_type: String = "physical"
	if "last_damage_type" in executor and executor.last_damage_type != null:
		dmg_type = String(executor.last_damage_type)
	elif "dmg_type" in atom:
		dmg_type = String(atom["dmg_type"])

	var crit: bool = false
	var dodged: bool = false
	var final_amount: float = amount
	var final_knockback: float = knockback

	# 1) APLICAR ATRIBUTOS DEL CASTER (ofensivo)
	var caster_ac: Node = _get_attribute_component(caster)
	if caster_ac != null and is_instance_valid(caster_ac):
		# 1a) Attack power (fuerza del caster para este dmg_type)
		var attack_power: float = float(caster_ac.call("get_attack_power", dmg_type))
		final_amount *= attack_power
		notes.append("caster.attack_power(%s)=%.2f" % [dmg_type, attack_power])

		# 1b) Crit del caster
		var crit_chance: float = float(caster_ac.call("get_crit_chance"))
		if randf() < crit_chance:
			crit = true
			final_amount *= 2.0
			notes.append("CRIT! (chance=%.2f)" % crit_chance)

		# 1c) Attack speed del caster (afecta el escalado de dmg, no el
		# "cooldown" del skill — eso lo controla el sistema de cooldowns)
		var atk_speed: float = float(caster_ac.call("get_attack_speed"))
		final_amount *= atk_speed
		notes.append("caster.attack_speed=%.2f" % atk_speed)
	else:
		notes.append("caster has no AttributeComponent (NPC? use defaults)")

	## FASE 1 (2026-06-14): el weapon YA NO contribuye dmg/speed/crit
	## directamente. En su lugar, al equiparse aplica `attribute_modifiers`
	## como temp_offsets al caster, y `_compute_skill_power` los lee desde
	## caster.AttributeComponent (lo cual ya hace arriba).
	##
	## Mantenemos `class_dmg_mult` por ahora — el bonus de "effective
	## against X" sigue siendo un modificador contextual del arma contra
	## el target, no del caster contra sí mismo. En Fase 3 esto se
	## refactorizará como "skill matchup" si hace falta.
	var weapon: Resource = _get_equipped_weapon_resource(caster)
	if weapon != null and target != null and target.is_in_group("enemies"):
		if target.has_method("get_weapon_family_name"):
			var target_family: String = String(target.call("get_weapon_family_name"))
			var class_mult: float = float(weapon.class_dmg_mult.get(target_family, 1.0))
			if class_mult != 1.0:
				final_amount *= class_mult
				notes.append("weapon.class_mult(%s)=%.2f" % [target_family, class_mult])

	# 3) APLICAR ATRIBUTOS DEL TARGET (defensivo)
	var target_ac: Node = _get_attribute_component(target)
	if target_ac != null and is_instance_valid(target_ac):
		# 3a) Dodge del target (probabilidad de esquivar)
		var dodge_chance: float = float(target_ac.call("get_dodge_chance"))
		if randf() < dodge_chance:
			dodged = true
			final_amount = 0.0
			notes.append("DODGED (chance=%.2f)" % dodge_chance)
		# NOTA: phys_res y ele_res los aplica _apply_hit por separado
		# (vía get_phys_res_multiplier / get_ele_res_multiplier) — no
		# duplicar aquí.
	else:
		notes.append("target has no AttributeComponent (env_object?)")

	# 4) Si el target es un EnvironmentObject, su "resist" puede reducir el efecto
	if target != null and target.has_method("resist"):
		var resist: Dictionary = target.resist(final_amount)
		var resisted_by: float = float(resist.get("resisted_by", 0.0))
		final_amount = float(resist.get("effective", final_amount))
		notes.append("env_resist=%.2f → effective=%.1f" % [resisted_by, final_amount])

	return {
		"final_amount": final_amount,
		"final_knockback": final_knockback,
		"crit": crit,
		"dodged": dodged,
		"notes": notes,
	}


## Helper: busca el AttributeComponent en un nodo (caster o target).
## Devuelve null si no lo tiene (NPCs/objetos sin atributos se tratan como
## "neutrales" — sin bonus ni penalty).
static func _get_attribute_component(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if node.has_node("AttributeComponent"):
		return node.get_node("AttributeComponent")
	return null


## Devuelve el WeaponResource actualmente equipado del caster, o null.
## El caster lo expone como propiedad `equipped_weapon` o como nodo hijo
## "WeaponResource" con un .resource.
static func _get_equipped_weapon_resource(caster: Node) -> Resource:
	if caster == null:
		return null
	# Forma 1: propiedad directa en el script
	if "equipped_weapon" in caster and caster.equipped_weapon != null:
		return caster.equipped_weapon
	# Forma 2: ProgressionState.equipped_weapon (singleton)
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps and "equipped_weapon" in ps and ps.equipped_weapon != null:
		return ps.equipped_weapon
	return null


static func _apply_hit(executor: Node, atom: Dictionary, targets: Array[Node]) -> void:
	var params: Dictionary = atom.get("params", {})
	var hitbox_config: Dictionary = atom.get("hitbox", {})
	var amount := float(executor.get_effective_stat("amount", params))
	var dmg_type := String(params.get("damage_type", "physical"))
	var knockback := float(executor.get_effective_stat("knockback", params))
	# Sistema elemental: este átomo puede tener un element (fire/water/etc.)
	# y la cantidad se multiplica por la elemental_matrix + resistances.
	var element: StringName = StringName(String(params.get("element", "physical")))
	var status_to_apply: String = String(params.get("applies_status", ""))
	var status_chance: float = float(params.get("status_chance", 0.0))
	var status_duration: float = float(params.get("status_duration", 0.0))
	# Resistencias temporales que este átomo aplica AL CASTER.
	# Útil para skills de "fire shield" o "magic barrier".
	var applies_resistance_to_caster: String = String(params.get("applies_resistance_to_caster", ""))
	var resistance_duration: float = float(params.get("resistance_duration", 0.0))
	var resistance_multiplier: float = float(params.get("resistance_multiplier", 0.5))
	# Boost elemental del caster (de ProgressionState.element_allocations).
	# Cada punto en element sube amount un 10%.
	var elemental_boost: float = 1.0
	if element != &"physical" and element != &"" and executor.progression:
		if executor.progression.has_method("get_element_attack_multiplier"):
			elemental_boost = float(executor.progression.call("get_element_attack_multiplier", element))
	amount *= elemental_boost
	for t in targets:
		if not is_instance_valid(t):
			continue
		var dmg := amount
		# === Potencia de skill con arma + stats del caster + resistencia del target ===
		var power: Dictionary = _compute_skill_power(executor, atom, amount, knockback, t)
		dmg = float(power.get("final_amount", amount))
		# Notas a log (solo la primera vez por skill_id, para no spamear)
		if power.get("notes") != null and (power["notes"] as Array).size() > 0 and not (atom.get("_logged", false) if atom else false):
			print("[EffectLibrary] power: %s" % " | ".join(power["notes"]))
			atom["_logged"] = true
		# Multiplicador elemental entre atacante y defensor (Pokémon-style)
		var defender_element := _get_actor_element(t)
		var elemental_mult := Elements.get_elemental_multiplier(element, defender_element)
		# Multiplicador de resistencia del defensor
		var res_mult := _get_actor_resistance(t, element)
		# Total: elemental * resistance
		var final_mult := elemental_mult * res_mult
		_deal_damage_to(t, dmg, dmg_type, executor.caster, knockback, final_mult)
		# Log: skill_hit (after damage is dealt so final amount is correct)
		var cl: Node = Engine.get_main_loop().root.get_node_or_null("CombatLog")
		if cl and cl.has_method("log_event"):
			var caster_id2: String = String(executor.caster.name) if executor.caster and is_instance_valid(executor.caster) else "?"
			var target_id: String = String(t.name) if t and is_instance_valid(t) else "?"
			var hit_data: Dictionary = {
				"caster": caster_id2,
				"target": target_id,
				"skill_id": String(executor.skill.id) if executor.skill and "id" in executor.skill else "",
				"amount": dmg,
				"final_mult": final_mult,
				"element": String(element),
				"dmg_type": dmg_type,
				"target_hp": float(t.hp) if t and "hp" in t else 0.0,
			}
			if executor.caster and "boss_data" in executor.caster and executor.caster.boss_data != null:
				hit_data["caster_boss_id"] = String(executor.caster.boss_data.id)
			if t and "boss_data" in t and t.boss_data != null:
				hit_data["target_boss_id"] = String(t.boss_data.id)
			cl.log_event("skill_hit", hit_data)
		# Aplicar status elemental al target
		if status_to_apply != "" and status_duration > 0.0:
			if status_chance <= 0.0 or randf() < status_chance:
				_apply_status_to(t, status_to_apply, status_duration, executor.caster)
	# Aplicar resistencia temporal al caster (si está configurado)
	if applies_resistance_to_caster != "" and resistance_duration > 0.0:
		_apply_temporary_resistance(executor.caster, applies_resistance_to_caster, resistance_multiplier, resistance_duration)
	# Hitbox visual en la posición del target — SOLO si NO es el caster.
	for t in targets:
		if t != executor.caster and not hitbox_config.is_empty() and t is Node3D:
			spawn_hitbox(executor, hitbox_config, [t])


static func _apply_dot(executor: Node, atom: Dictionary, targets: Array[Node]) -> void:
	var params: Dictionary = atom.get("params", {})
	var hitbox_config: Dictionary = atom.get("hitbox", {})
	var dpt := float(executor.get_effective_stat("dpt", params))
	var duration := float(executor.get_effective_stat("duration", params))
	var tick_interval := float(params.get("tick_interval", 1.0))
	# Sistema elemental
	var element: StringName = StringName(String(params.get("element", "physical")))
	var status_to_apply: String = String(params.get("applies_status", ""))
	var status_chance: float = float(params.get("status_chance", 0.0))
	var status_duration: float = float(params.get("status_duration", 0.0))
	var applies_resistance_to_caster: String = String(params.get("applies_resistance_to_caster", ""))
	var resistance_duration: float = float(params.get("resistance_duration", 0.0))
	var resistance_multiplier: float = float(params.get("resistance_multiplier", 0.5))
	# CORRECCIÓN: filtrar al caster. Antes, cuando no había target,
	# resolve_targets_for_atom caía a [caster] (self-fallback) y el DoT
	# se aplicaba al player (ej. uraraka_zero_gravity sin enemigo cerca
	# → player recibía root+DoT a sí mismo).
	var real_targets: Array[Node] = []
	for t in targets:
		if is_instance_valid(t) and t != executor.caster:
			real_targets.append(t)
	# Aplicar status al inicio (independiente del DoT component)
	for t in real_targets:
		if status_to_apply != "" and status_duration > 0.0:
			if status_chance <= 0.0 or randf() < status_chance:
				_apply_status_to(t, status_to_apply, status_duration, executor.caster)
	# Aplicar resistencia temporal al caster
	if applies_resistance_to_caster != "" and resistance_duration > 0.0:
		_apply_temporary_resistance(executor.caster, applies_resistance_to_caster, resistance_multiplier, resistance_duration)
	for t in real_targets:
		_attach_dot(t, dpt, duration, tick_interval, executor.caster)
	# Hitbox visual: el "cast" inicial del DoT. Solo si hay targets reales.
	for t in real_targets:
		if not hitbox_config.is_empty() and t is Node3D:
			spawn_hitbox(executor, hitbox_config, [t])


static func _apply_burst_aoe(
	executor: Node,
	atom: Dictionary,
	targets: Array[Node],
	applies: String
) -> void:
	# Refactor: el visual del hitbox ahora viene del sub-dict atom.hitbox
	# (data-driven). El atom.params sigue conteniendo la LÓGICA (radius,
	# amount, falloff, damage_type).
	var params: Dictionary = atom.get("params", {})
	var hitbox_config: Dictionary = atom.get("hitbox", {})
	# Sistema elemental (mismo que _apply_hit)
	var element: StringName = StringName(String(params.get("element", "physical")))
	var status_to_apply: String = String(params.get("applies_status", ""))
	var status_chance: float = float(params.get("status_chance", 0.0))
	var status_duration: float = float(params.get("status_duration", 0.0))
	var applies_resistance_to_caster: String = String(params.get("applies_resistance_to_caster", ""))
	var resistance_duration: float = float(params.get("resistance_duration", 0.0))
	var resistance_multiplier: float = float(params.get("resistance_multiplier", 0.5))
	var radius := float(executor.get_effective_stat("radius", params))
	var amount := float(executor.get_effective_stat("amount", params))
	var dmg_type := String(params.get("damage_type", "energy"))
	var falloff := String(params.get("falloff", "linear"))
	var caster3d := executor.caster as Node3D if executor.caster is Node3D else null
	# Boost elemental del caster
	var elemental_boost: float = 1.0
	if element != &"physical" and element != &"" and executor.progression:
		if executor.progression.has_method("get_element_attack_multiplier"):
			elemental_boost = float(executor.progression.call("get_element_attack_multiplier", element))
	amount *= elemental_boost
	# Aplicar daño a todos los targets en rango
	for t in targets:
		if not is_instance_valid(t) or t == executor.caster or not t is Node3D:
			continue
		var t3d := t as Node3D
		var d := t3d.global_position.distance_to(caster3d.global_position) if caster3d else 0.0
		var dmg_amount := amount
		if falloff == "linear" and radius > 0:
			dmg_amount = amount * max(0.0, 1.0 - d / radius)
		elif falloff == "inverse_square" and d > 0.01:
			dmg_amount = amount / (1.0 + d * d)
		# === Potencia con arma + stats del caster + resistencia del target ===
		var power_b: Dictionary = _compute_skill_power(executor, atom, dmg_amount, float(executor.get_effective_stat("knockback", params)), t)
		dmg_amount = float(power_b.get("final_amount", dmg_amount))
		# Multiplicador elemental + resistencia
		var defender_element := _get_actor_element(t)
		var elemental_mult := Elements.get_elemental_multiplier(element, defender_element)
		var res_mult := _get_actor_resistance(t, element)
		var final_mult := elemental_mult * res_mult
		_deal_damage_to(t, dmg_amount, dmg_type, executor.caster, float(executor.get_effective_stat("knockback", params)), final_mult)
		# Aplicar status elemental
		if status_to_apply != "" and status_duration > 0.0:
			if status_chance <= 0.0 or randf() < status_chance:
				_apply_status_to(t, status_to_apply, status_duration, executor.caster)
	# Resistencia temporal al caster
	if applies_resistance_to_caster != "" and resistance_duration > 0.0:
		_apply_temporary_resistance(executor.caster, applies_resistance_to_caster, resistance_multiplier, resistance_duration)
	# Spawn hitbox visual desde atom.hitbox (data-driven).
	if not hitbox_config.is_empty():
		spawn_hitbox(executor, hitbox_config, targets)

static func _apply_persistent_zone(
	executor: Node,
	params: Dictionary,
	targets: Array[Node],
	applies: String
) -> void:
	var radius := float(executor.get_effective_stat("radius", params))
	var duration := float(executor.get_effective_stat("duration", params))
	var dpt := float(executor.get_effective_stat("dpt", params))
	var tick_interval := float(params.get("tick_interval", 1.0))
	var slow_inside := float(params.get("slow_inside", 0.0))
	# Para persistent_zone, los targets son el centro (primary).
	# El ejecutor creará un nodo PersistentZone que vive `duration` segundos.
	var center_target: Node3D = null
	for t in targets:
		if is_instance_valid(t) and t is Node3D:
			center_target = t as Node3D
			break
	if not center_target:
		return
	_spawn_persistent_zone(executor, center_target.global_position, radius, duration, dpt, tick_interval, slow_inside)

# === heal ===
static func _apply_heal(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var amount := float(executor.get_effective_stat("amount", params))
	for t in targets:
		if not is_instance_valid(t) or not t.has_method("heal"):
			continue
		t.call("heal", amount)

static func _apply_hot(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var apt := float(executor.get_effective_stat("hot_per_tick", params))
	var duration := float(executor.get_effective_stat("duration", params))
	var tick_interval := float(params.get("tick_interval", 1.0))
	for t in targets:
		if not is_instance_valid(t):
			continue
		_attach_hot(t, apt, duration, tick_interval)

static func _apply_shield(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var amount := float(executor.get_effective_stat("shield_amount", params))
	var duration := float(executor.get_effective_stat("duration", params))
	for t in targets:
		if not is_instance_valid(t):
			continue
		_attach_shield(t, amount, duration)

# === motion ===

static func _apply_move(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var kind := String(params.get("kind", "dash"))
	var distance := float(executor.get_effective_stat("distance", params))
	var duration := float(executor.get_effective_stat("duration", params))
	var rel := String(params.get("target_relative", "forward"))
	# Flags especiales para movimientos del caster (esquivar, dash, etc.)
	var i_frames: bool = bool(params.get("i_frames", false))
	var blink: bool = bool(params.get("blink", false))
	var stamina_drain: float = float(params.get("stamina_drain", 0.0))
	for t in targets:
		if not is_instance_valid(t) or not t is Node3D:
			continue
		# Si el target es un EnvironmentObject, primero verificar peso
		# (el skill "mover piedra" no funciona si la piedra pesa demasiado).
		if t.has_method("resist") and t.has_method("is_too_heavy_to_move"):
			var resist_info: Dictionary = t.resist(distance * 10.0)  # skill_power proxy
			if t.is_too_heavy_to_move(distance):
				print("[EffectLibrary] move: target %s too heavy (weight=%.1f, power=%.1f)" % [t.name, float(t.weight), distance])
				continue
		# Consumir stamina si el skill lo declara (ej: esquivar gasta 12)
		if stamina_drain > 0.0 and t.has_method("spend_stamina"):
			t.call("spend_stamina", stamina_drain)
		# i-frames: bajar collision_layer y subir blink visualmente
		if i_frames and t.has_method("set_iframes"):
			t.call("set_iframes", duration)
		if blink and t.has_method("start_dodge_blink"):
			t.call("start_dodge_blink", duration)
		_apply_motion(t as Node3D, kind, distance, duration, rel, executor.caster)


static func _apply_motion(
	node: Node3D,
	kind: String,
	distance: float,
	duration: float,
	relative: String,
	caster: Node
) -> void:
	if duration <= 0.0:
		duration = 0.05  # Snap
	var dir := Vector3.ZERO
	match relative:
		"forward":
			dir = -node.global_transform.basis.z
		"backward":
			dir = node.global_transform.basis.z
		"away_from_caster":
			if caster and caster is Node3D:
				dir = (node.global_position - (caster as Node3D).global_position).normalized()
		"toward_caster":
			if caster and caster is Node3D:
				dir = ((caster as Node3D).global_position - node.global_position).normalized()
		"self", "selected_npc":
			dir = -node.global_transform.basis.z  # default forward
	# Para teleport, mover instantáneamente
	if kind == "teleport" or duration <= 0.05:
		node.global_position += dir * distance
		return
	# Dash/knockback/pull/launch: mover a lo largo de duration
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = dir * (distance / duration)
	# Para launch, no se asigna velocity; lo maneja una tween simple
	if kind == "launch":
		var tween := node.create_tween()
		tween.tween_property(node, "global_position", node.global_position + dir * distance, duration)
	# FASE 2: "jump" — salto vertical. distance = velocidad hacia arriba.
	# Se respeta velocity horizontal existente (el jugador puede saltar
	# en movimiento).
	if kind == "jump":
		if node is CharacterBody3D:
			var v: Vector3 = (node as CharacterBody3D).velocity
			v.y = maxf(v.y, distance)  # NO decrementar si ya iba hacia arriba
			(node as CharacterBody3D).velocity = v
		return
	# FASE 2: "speed_boost" — buff de velocidad. distance = multiplicador
	# adicional (e.g., 0.5 = +50% velocidad). El efecto buff atom hace
	# la mayor parte del trabajo vía temp_offset en move_speed.
	if kind == "speed_boost":
		# (no-op here — el buff atom aplica el offset al AttributeComponent
		# del target, y el player lee move_speed de ahí en _physics_process)
		return
	# (knockback en CharacterBody3D se completa naturalmente en physics frames)


# === transform ===

static func _apply_morph(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var kind := String(params.get("kind", "polymorph"))
	var duration := float(executor.get_effective_stat("duration", params))
	for t in targets:
		if not is_instance_valid(t):
			continue
		# Para scale: aplica scale multiplier temporal
		if kind == "scale" and t is Node3D:
			var t3d := t as Node3D
			var mult := float(params.get("scale_multiplier", 1.5))
			var original := t3d.scale
			t3d.scale = original * mult
			await executor.get_tree().create_timer(duration).timeout
			if is_instance_valid(t3d):
				t3d.scale = original
		elif kind == "polymorph":
			# Placeholder: solo log
			if DEBUG:
				print("[EffectLibrary] polymorph %s for %.1fs (not implemented visually yet)" % [t.name, duration])
		elif kind == "possess":
			if DEBUG:
				print("[EffectLibrary] possess %s for %.1fs (not implemented yet)" % [t.name, duration])


# === control ===

static func _apply_status(executor: Node, atom: Dictionary, targets: Array[Node]) -> void:
	var params: Dictionary = atom.get("params", {})
	var hitbox_config: Dictionary = atom.get("hitbox", {})
	var kind := String(params.get("kind", "stun"))
	var duration := float(executor.get_effective_stat("duration", params))
	var magnitude := float(executor.get_effective_stat("magnitude", params))
	# Sistema elemental: status adicional (ej. "burn" además de "root")
	var extra_status: String = String(params.get("applies_status", ""))
	var extra_status_chance: float = float(params.get("status_chance", 0.0))
	var extra_status_duration: float = float(params.get("status_duration", 0.0))
	# Resistencia temporal que se aplica AL CASTER.
	var applies_resistance_to_caster: String = String(params.get("applies_resistance_to_caster", ""))
	var resistance_duration: float = float(params.get("resistance_duration", 0.0))
	var resistance_multiplier: float = float(params.get("resistance_multiplier", 0.5))
	# Filtrar caster: si no hay target real, no aplicamos el status
	# (igual que _apply_hit y _apply_dot).
	var real_targets: Array[Node] = []
	for t in targets:
		if is_instance_valid(t) and t != executor.caster:
			real_targets.append(t)
	for t in real_targets:
		_attach_status(t, kind, duration, magnitude)
		# Status elemental extra (ej. poison encima de root)
		if extra_status != "" and extra_status_duration > 0.0:
			if extra_status_chance <= 0.0 or randf() < extra_status_chance:
				_apply_status_to(t, extra_status, extra_status_duration, executor.caster)
	# Resistencia temporal al caster (independiente de si hay targets)
	if applies_resistance_to_caster != "" and resistance_duration > 0.0:
		_apply_temporary_resistance(executor.caster, applies_resistance_to_caster, resistance_multiplier, resistance_duration)
	# Hitbox visual: campo de control alrededor del target.
	for t in real_targets:
		if not hitbox_config.is_empty() and t is Node3D:
			spawn_hitbox(executor, hitbox_config, [t])


static func _apply_mind(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var kind := String(params.get("kind", "charm"))
	var duration := float(executor.get_effective_stat("duration", params))
	for t in targets:
		if not is_instance_valid(t):
			continue
		# Placeholder: solo log
		if DEBUG:
			print("[EffectLibrary] mind %s on %s for %.1fs (not implemented AI-wise yet)" % [kind, t.name, duration])


# === summon ===

static func _apply_buff(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var stat := String(params.get("stat", "damage_mult"))
	var value := float(params.get("value", 1.0))
	var kind := String(params.get("kind", "multiply"))
	var duration := float(executor.get_effective_stat("duration", params))
	for t in targets:
		if not is_instance_valid(t):
			continue
		_attach_buff(t, stat, value, kind, duration)


static func _apply_projectile(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var speed := float(executor.get_effective_stat("speed", params))
	var hitbox_radius := float(executor.get_effective_stat("hitbox_radius", params))
	var lifetime := float(executor.get_effective_stat("lifetime", params))
	var on_hit_effect := String(params.get("on_hit_effect", ""))
	var friendly := bool(params.get("friendly", false))
	# Crea un Area3D que se mueve desde el caster hacia el target
	if not executor.caster or not executor.caster is Node3D:
		return
	var caster3d := executor.caster as Node3D
	var dir := -caster3d.global_transform.basis.z  # forward
	if targets.size() > 0 and targets[0] is Node3D:
		dir = ((targets[0] as Node3D).global_position - caster3d.global_position).normalized()
	var scene := executor.get_tree().current_scene
	if not scene:
		return
	# Nodo proyectil básico: Area3D + CollisionShape3D + MeshInstance3D visible
	var proj := Area3D.new()
	proj.name = "SkillProjectile"
	proj.global_position = caster3d.global_position + dir * 0.5
	proj.collision_layer = 1  # world
	proj.collision_mask = 4   # enemies
	# Collision shape
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = hitbox_radius
	col.shape = sphere
	proj.add_child(col)
	# Mesh visible (esfera debug)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = hitbox_radius
	sm.height = hitbox_radius * 2
	mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 1.0)
	mesh.material_override = mat
	proj.add_child(mesh)
	scene.add_child(proj)
	# Mover
	var vel := dir * speed
	if DEBUG:
		print("[EffectLibrary] projectile spawned speed=%.1f lifetime=%.1f friendly=%s" % [speed, lifetime, friendly])
	# Hook de impacto
	if on_hit_effect != "":
		proj.body_entered.connect(func(b: Node):
			if b.has_method("take_damage"):
				b.call("take_damage", 5.0, proj)  # placeholder; full damage via on_hit_effect chain
		)
	# Tween de movimiento + lifetime
	var tween := executor.get_tree().create_tween().set_parallel(true)
	tween.tween_property(proj, "global_position", proj.global_position + dir * speed * lifetime, lifetime)
	tween.tween_property(proj, "scale", Vector3(0.1, 0.1, 0.1), lifetime).from(Vector3.ONE)
	# Auto-destruir
	executor.get_tree().create_timer(lifetime).timeout.connect(func():
		if is_instance_valid(proj):
			proj.queue_free()
	)
	# Guardar referencia para combo chain / carrier targets
	executor.last_projectile = proj


static func _apply_npc(executor: Node, params: Dictionary, _targets: Array[Node]) -> void:
	# Placeholder: la integración con NPC templates viene en fase 5.
	if DEBUG:
		print("[EffectLibrary] npc atom placeholder template=%s" % params.get("template", "unknown"))

# === hitbox system (data-driven) ===

## Spawn un hitbox visual a partir de un config dict. ESTA es la única
## función que crea visuales de hitbox. Todo lo demás se lee del dict.
##
## Config keys (todas opcionales, con defaults razonables):
##   shape:            "sphere" | "box" | "beam" | "capsule"
##   size:             Vector3 o [x, y, z] — para sphere se unifica a (r, r, r)
##   position:         "in_front_of_caster" | "at_caster" | "at_target" | "world"
##   distance_forward: float (offset para "in_front_of_caster")
##   world_position:   Vector3 (para position="world")
##   color:            Color o [r, g, b, a]  (default: naranja)
##   emission:         float  (default 8.0)
##   blend_mode:       int (0=mix, 1=add)  (default 1 = add)
##   duration:         float (segundos, default 1.0)
##   fade_out:         bool (alpha + emission -> 0 al final, default true)
##   wireframe:        bool (default false)
##
## Devuelve el Node3D creado (o null si no se pudo).
static func spawn_hitbox(executor: Node, config: Dictionary, targets: Array[Node] = []) -> Node3D:
	if config == null or config.is_empty():
		return null
	if not executor or not executor.get_tree():
		return null
	var scene := executor.get_tree().current_scene
	if not scene:
		return null
	var caster := executor.caster as Node3D if executor.caster is Node3D else null
	if not caster or not is_instance_valid(caster) or not caster.is_inside_tree():
		# El caster fue liberado (parent freed, scene change, etc.).
		# No podemos spawn un visual posicionado correctamente.
		return null
	# --- Parse shape + size ---
	var shape: String = String(config.get("shape", "sphere"))
	var size_raw = config.get("size", [1.0, 1.0, 1.0])
	var size: Vector3
	if size_raw is Vector3:
		size = size_raw
	elif size_raw is Array and size_raw.size() >= 3:
		size = Vector3(float(size_raw[0]), float(size_raw[1]), float(size_raw[2]))
	else:
		size = Vector3(1, 1, 1)
	if shape == "sphere":
		# Sphere usa el primer componente como radio, lo unificamos
		size = Vector3(size.x, size.x, size.x)
	# --- Parse position ---
	var position_mode: String = String(config.get("position", "in_front_of_caster"))
	var dist_forward: float = float(config.get("distance_forward", 1.0))
	var pos := Vector3.ZERO
	var dir := -caster.global_transform.basis.z
	match position_mode:
		"in_front_of_caster":
			pos = caster.global_position + dir * dist_forward
		"at_caster":
			pos = caster.global_position
		"at_target":
			if targets.size() > 0 and is_instance_valid(targets[0]) and targets[0] is Node3D:
				pos = (targets[0] as Node3D).global_position
			else:
				pos = caster.global_position
		"world":
			var wp_raw = config.get("world_position", Vector3.ZERO)
			pos = wp_raw if wp_raw is Vector3 else caster.global_position
		_:
			pos = caster.global_position
	# --- Parse color ---
	var color_raw = config.get("color", [1.0, 0.5, 0.05, 0.9])
	var color: Color
	if color_raw is Color:
		color = color_raw
	elif color_raw is Array and color_raw.size() >= 3:
		var a: float = 1.0 if color_raw.size() < 4 else float(color_raw[3])
		color = Color(float(color_raw[0]), float(color_raw[1]), float(color_raw[2]), a)
	else:
		color = Color(1.0, 0.5, 0.05, 0.9)
	var emission: float = float(config.get("emission", 8.0))
	var blend_mode: int = int(config.get("blend_mode", 1))
	var duration: float = float(config.get("duration", 1.0))
	var fade_out: bool = bool(config.get("fade_out", true))
	# wireframe removido: StandardMaterial3D no tiene esa propiedad en Godot 4
	# (solo se puede activar vía RenderingServer.set_debug_generate_wireframes)
	var _wireframe_unused := bool(config.get("wireframe", false))
	# --- Build node ---
	# CORRECCIÓN: añadir al árbol ANTES de look_at (look_at requiere nodo
	# dentro del árbol). La posición global se puede setear antes, pero
	# la orientación necesita el árbol.
	var node := Node3D.new()
	node.name = "Hitbox"
	# Posición inicial: usamos la global directamente. NO intentamos
	# convertir a local (la escena root puede ser un Node plain sin
	# global_position — eso causaba "Invalid access to property or key
	# 'global_position' on a base object of type 'Node'").
	scene.add_child(node)
	node.global_position = pos
	# Para shapes con dirección (box/beam/capsule), orientar el nodo
	# para que el eje -Z local apunte en la dirección del caster (forward).
	# Así el box se extiende "hacia adelante" desde el origen.
	if shape == "box" or shape == "beam" or shape == "capsule":
		if dir != Vector3.ZERO:
			node.look_at(pos + dir.normalized(), Vector3.UP)
	# --- Build mesh ---
	var mesh := MeshInstance3D.new()
	var m: Mesh
	match shape:
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = size.x * 0.5
			sm.height = size.x
			m = sm
		"box", "beam":
			var bm := BoxMesh.new()
			bm.size = size
			m = bm
		"capsule":
			var cm := CapsuleMesh.new()
			cm.radius = size.x * 0.5
			cm.height = size.y
			m = cm
		_:
			# Fallback: box
			var bm2 := BoxMesh.new()
			bm2.size = size
			m = bm2
	mesh.mesh = m
	# Offset para que la geometría se extienda "hacia adelante" (-Z local) desde el nodo.
	# Así si el nodo está en el caster y la "size.z" es el largo del beam, el
	# beam se extiende delante del caster, no centrado en él.
	if shape == "box" or shape == "beam" or shape == "capsule":
		mesh.position = Vector3(0, 0, -size.z * 0.5)
	# --- Material ---
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission
	mat.transparency = 1  # ALPHA
	mat.shading_mode = 0  # UNSHADED
	mat.cull_mode = 2     # DISABLED (se ve desde ambos lados)
	mat.blend_mode = blend_mode
	# wireframe desactivado (ver nota arriba)
	mesh.material_override = mat
	node.add_child(mesh)
	# --- Fade out ---
	if fade_out and duration > 0.0:
		var tween := node.create_tween()
		tween.tween_property(mat, "albedo_color:a", 0.0, duration).from(color.a)
		tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, duration).from(emission)
	# --- Auto-free ---
	if executor and executor.get_tree():
		executor.get_tree().create_timer(duration + 0.05).timeout.connect(func() -> void:
			if is_instance_valid(node):
				node.queue_free()
		)
	if DEBUG:
		print("[EffectLibrary] hitbox spawn shape=%s size=%s pos=%s duration=%.2f" % [shape, str(size), str(pos), duration])
	return node


## Wrapper legacy: sphere debug con params sueltos. Mantenido por
## compatibilidad, pero el nuevo código debería usar spawn_hitbox.
static func _spawn_debug_aoe(executor: Node, center: Vector3, radius: float) -> void:
	spawn_hitbox(executor, {
		"shape": "sphere",
		"size": [radius * 2.4, radius * 2.4, radius * 2.4],
		"position": "world",
		"world_position": center,
		"color": [1.0, 0.05, 0.0, 0.92],
		"emission": 8.0,
		"blend_mode": 1,
		"duration": 1.0,
		"fade_out": true,
	}, [])


## Wrapper legacy: beam debug con params sueltos. Mantenido por compatibilidad.
static func _spawn_debug_beam(executor: Node, origin: Vector3, dir: Vector3, radius: float, length: float) -> void:
	# Estimamos la posición "delante" del caster. Si la dirección apunta
	# hacia atrás (caster facing -Z), el beam se extiende en esa dirección.
	# Pasamos position=world con world_position=origin para forzar posición absoluta.
	spawn_hitbox(executor, {
		"shape": "beam",
		"size": [radius * 2.0, radius * 2.0, length],
		"position": "world",
		"world_position": origin,
		"color": [1.0, 0.6, 0.1, 0.95],
		"emission": 8.0,
		"blend_mode": 1,
		"duration": 1.5,
		"fade_out": true,
	}, [])


static func _apply_zone(executor: Node, params: Dictionary, _targets: Array[Node]) -> void:
	# Placeholder para zonas persistentes con kind=damage|slow|stun|reveal|heal|shield
	if DEBUG:
		print("[EffectLibrary] zone atom placeholder kind=%s" % params.get("kind", "damage"))


# === trigger ===

static func _apply_trigger(executor: Node, atom: Dictionary) -> void:
	var params: Dictionary = atom.get("params", {})
	var when := String(params.get("when", "delay"))
	var delay := float(params.get("delay", 0.0))
	match when:
		"delay":
			if delay > 0.0:
				# CORRECCIÓN: capturar solo refs débiles (WeakRef) o re-bind
				# al árbol para evitar "Lambda capture freed" cuando el
				# executor o su parent son liberados durante el delay.
				# Truco: conectar con Callable.bind() y validar dentro.
				# IMPORTANTE: tipar explícitamente como WeakRef (no Variant)
				# porque el proyecto trata los warnings como errores.
				var weak_executor: WeakRef = weakref(executor)
				executor.get_tree().create_timer(delay).timeout.connect(func() -> void:
					var ex: Node = weak_executor.get_ref()
					if not ex or not is_instance_valid(ex) or not ex.is_inside_tree():
						# El executor (o el caster) ya no existe → abortar.
						return
					_execute_then_effect(ex, params, atom)
				)
			else:
				_execute_then_effect(executor, params, atom)
		"on_hit", "on_kill", "on_take_damage", "on_health_below", "on_status_applied":
			# Registra el trigger; SkillExecutor lo invocará cuando se cumpla la condición
			executor.register_trigger(when, params, atom)
		"on_skill_used":
			# Combo: si then_skill_id está set, requiere que caster la tenga
			var sid := String(params.get("then_skill_id", ""))
			if sid != "":
				executor.register_combo_trigger(sid, params, atom)


## Ejecuta el "then_effect" del trigger.
## Nueva lógica: el trigger puede llevar `then_params` (lógica) y `then_hitbox`
## (visual) DENTRO de su propio params dict. Construimos un átomo sintético y
## lo pasamos por apply_atom para reutilizar TODO el pipeline (incluyendo
## spawn_hitbox data-driven).
## Fallback: si no hay then_params, busca un átomo con el mismo tipo en la skill.
static func _execute_then_effect(executor: Node, params: Dictionary, atom: Dictionary) -> void:
	var then_eff := String(params.get("then_effect", ""))
	if then_eff == "":
		return
	# Camino nuevo: then_params + then_hitbox en el trigger
	var then_params: Dictionary = params.get("then_params", {})
	var then_hitbox: Dictionary = params.get("then_hitbox", {})
	if not then_params.is_empty() or not then_hitbox.is_empty():
		var synthetic_atom := {
			"type": then_eff,
			"params": then_params,
			"hitbox": then_hitbox,
			"applies_to_target": String(atom.get("applies_to_target", "primary")),
		}
		apply_atom(executor, synthetic_atom, executor.resolve_targets())
		return
	# Camino legacy: buscar un átomo de la skill con type==then_eff
	for a in executor.skill.atoms:
		if a.get("id", "") == then_eff or String(a.get("type", "")) == then_eff:
			apply_atom(executor, a, executor.resolve_targets())
			return
	if DEBUG:
		print("[EffectLibrary] trigger then_effect '%s' not found in skill atoms" % then_eff)


# === helpers (componentes para trackear efectos en curso) ===

static func _deal_damage_to(target: Node, amount: float, dmg_type: String, source: Node, knockback: float, mult: float = 1.0) -> void:
	# CRÍTICO: nunca dañar al caster. Sin este check, el fallback "primary"
	# de resolve_targets_for_atom devuelve [caster] cuando no hay target, y
	# el player se golpea a sí mismo con sus propias skills (ej. gomu_gomu_pistol
	# sin enemigo cerca → player se daña a sí mismo).
	if target == source:
		return
	if not target.has_method("take_damage"):
		return
	# Calcular final con multipliers:
	#   base * mult (elemental_matrix + status_resistance del target)
	#   * attribute_dmg_source (phys_dmg/ele_dmg del caster)
	# NOTA: la resistencia plana phys_res/ele_res del target se aplica
	# dentro de target.take_damage (ver player.gd / npc.gd) para no
	# duplicar la mitigación.
	var final_amount: float = amount * mult
	if source and source.has_node("AttributeComponent"):
		var src_attr: Node = source.get_node("AttributeComponent")
		if dmg_type == "physical":
			final_amount *= float(src_attr.call("get_phys_dmg_multiplier"))
		else:
			final_amount *= float(src_attr.call("get_ele_dmg_multiplier"))
	# Seteamos last_damage_type en el source para que target.take_damage
	# sepa si aplicar phys_res o ele_res.
	if source:
		source.set("last_damage_type", dmg_type)
	# Pasamos el element (dmg_type) para que el target pueda aplicar
	# mission damage_modifiers (ver enemy.gd::take_damage).
	var elem_name := StringName(dmg_type)
	target.call("take_damage", final_amount, source, elem_name)
	if DEBUG:
		print("[EffectLibrary] hit %s amount=%.1f (base %.1f x mult %.2f) type=%s" % [target.name, final_amount, amount, mult, dmg_type])
	# Knockback
	if knockback > 0.0 and target is Node3D and source is Node3D:
		var t3d := target as Node3D
		var s3d := source as Node3D
		var dir := (t3d.global_position - s3d.global_position).normalized()
		if t3d is CharacterBody3D:
			(t3d as CharacterBody3D).velocity += dir * knockback
		else:
			t3d.global_position += dir * knockback


## Devuelve el "element" del actor (para elemental_matrix).
## Busca en metadata, en una propiedad "element" del script, o devuelve physical.
static func _get_actor_element(actor: Node) -> StringName:
	if actor == null or not is_instance_valid(actor):
		return &"physical"
	if actor.has_meta("element"):
		return StringName(String(actor.get_meta("element")))
	if "element" in actor:
		return StringName(String(actor.element))
	return &"physical"


## Devuelve el multiplicador de resistencia del actor a un elemento.
## Busca el ResistanceComponent, o devuelve 1.0 (neutral).
static func _get_actor_resistance(actor: Node, element: StringName) -> float:
	if actor == null or not is_instance_valid(actor):
		return 1.0
	if actor.has_node("ResistanceComponent"):
		var rc: Node = actor.get_node("ResistanceComponent")
		if rc.has_method("get_resistance"):
			return float(rc.call("get_resistance", element))
	return 1.0


## Aplica un status elemental a un actor (burn, freeze, etc.).
## Crea/usa el StatusComponent del actor.
## Aplica:
##   - Status potency del caster (AttributeComponent.get_status_potency)
##   - Status resistance del target (AttributeComponent.get_status_resistance)
## para que invertir puntos en el atributo homónimo potencie tu propio
## status Y reduzca la duración del que recibes.
static func _apply_status_to(target: Node, status_id: String, duration: float, source: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	# Calcular duración efectiva:
	# effective = base_duration * caster_potency * (1 - target_resistance)
	var effective_duration: float = duration
	if source and source.has_node("AttributeComponent"):
		var caster_attr: Node = source.get_node("AttributeComponent")
		var potency: float = float(caster_attr.call("get_status_potency", StringName(status_id)))
		effective_duration *= potency
	if target.has_node("AttributeComponent"):
		var target_attr: Node = target.get_node("AttributeComponent")
		var res: float = float(target_attr.call("get_status_resistance", StringName(status_id)))
		effective_duration *= (1.0 - res)

	# Si la duración efectiva es <= 0, el target es inmune
	if effective_duration <= 0.01:
		print("[EffectLibrary] status %s resisted by target (effective=%.2f)" % [status_id, effective_duration])
		return

	# Si no tiene StatusComponent, añadir uno
	var sc: Node = null
	if target.has_node("StatusComponent"):
		sc = target.get_node("StatusComponent")
	else:
		const StatusCompScript := preload("res://scripts/skill/components/StatusComponent.gd")
		sc = StatusCompScript.new()
		sc.name = "StatusComponent"
		target.add_child(sc)
	# Llamar start_elemental_status (manejamos tanto elementales como clásicos)
	var kind: StringName = StringName(status_id)
	if sc.has_method("start_elemental_status"):
		sc.call("start_elemental_status", kind, effective_duration, source)
	elif sc.has_method("start_status"):
		sc.call("start_status", status_id, effective_duration, 1.0)


## Aplica una resistencia temporal al caster.
## Útil para skills de "fire shield" o "ice armor".
static func _apply_temporary_resistance(actor: Node, element: String, multiplier: float, duration: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if not actor.has_node("ResistanceComponent"):
		const ResistanceCompScript := preload("res://scripts/skill/components/ResistanceComponent.gd")
		var rc: Node = ResistanceCompScript.new()
		rc.name = "ResistanceComponent"
		actor.add_child(rc)
	var rc2: Node = actor.get_node("ResistanceComponent")
	if rc2.has_method("add_temporary_resistance"):
		rc2.call("add_temporary_resistance", StringName(element), multiplier, duration)


## Sphere debug en la posición del target. Usado por _apply_hit cuando
## show_hitbox=true (para que el jugador vea dónde aterrizan los hits
## individuales, no solo AOE/triggers).
static func _spawn_debug_hit_sphere(executor: Node, center: Vector3, radius: float, lifetime: float) -> void:
	var scene := executor.get_tree().current_scene if executor and executor.get_tree() else null
	if not scene:
		return
	var sphere := Node3D.new()
	sphere.name = "DebugHit"
	sphere.global_position = center
	scene.add_child(sphere)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.0)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = 1
	mat.shading_mode = 0
	mat.cull_mode = 2
	mat.blend_mode = 1  # ADD
	mesh.material_override = mat
	sphere.add_child(mesh)
	# Tween de fade out
	var tween := sphere.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, lifetime).from(0.9)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, lifetime).from(8.0)
	executor.get_tree().create_timer(lifetime).timeout.connect(func():
		if is_instance_valid(sphere):
			sphere.queue_free()
	)


static func _attach_dot(target: Node, dpt: float, duration: float, tick_interval: float, source: Node) -> void:
	var comp := _get_or_create_component(target, "DoTComponent")
	if comp.has_method("start_dot"):
		comp.call("start_dot", dpt, duration, tick_interval, source)


static func _attach_hot(target: Node, apt: float, duration: float, tick_interval: float) -> void:
	var comp := _get_or_create_component(target, "HoTComponent")
	if comp.has_method("start_hot"):
		comp.call("start_hot", apt, duration, tick_interval)


static func _attach_shield(target: Node, amount: float, duration: float) -> void:
	var comp := _get_or_create_component(target, "ShieldComponent")
	if comp.has_method("start_shield"):
		comp.call("start_shield", amount, duration)


static func _attach_buff(target: Node, stat: String, value: float, kind: String, duration: float) -> void:
	var comp := _get_or_create_component(target, "BuffComponent")
	if comp.has_method("start_buff"):
		comp.call("start_buff", stat, value, kind, duration)


static func _attach_status(target: Node, kind: String, duration: float, magnitude: float) -> void:
	var comp := _get_or_create_component(target, "StatusComponent")
	if comp.has_method("start_status"):
		comp.call("start_status", kind, duration, magnitude)


static func _spawn_persistent_zone(
	executor: Node,
	center: Vector3,
	radius: float,
	duration: float,
	dpt: float,
	tick_interval: float,
	slow_inside: float
) -> void:
	# Crea un nodo PersistentZone que vive duration segundos
	var scene := executor.get_tree().current_scene
	if not scene:
		return
	var zone := Area3D.new()
	zone.name = "PersistentZone"
	zone.global_position = center
	zone.collision_layer = 1
	zone.collision_mask = 4
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	col.shape = sphere
	zone.add_child(col)
	# Visual
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2
	mesh.mesh = sm
	mesh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.3, 0.3, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.1, 0.0)
	mesh.material_override = mat
	zone.add_child(mesh)
	scene.add_child(zone)
	# Tick DoT a NPCs en zona
	var t := 0.0
	var timer := executor.get_tree().create_timer(tick_interval)
	timer.timeout.connect(func():
		# Recolecta NPCs en la zona y aplica tick
		for n in zone.get_overlapping_bodies() + zone.get_overlapping_areas():
			if n and n.has_method("take_damage") and is_instance_valid(n):
				n.call("take_damage", dpt * tick_interval, zone)
			if n and slow_inside > 0.0 and n.has_method("set_slow"):
				n.call("set_slow", slow_inside)
		# Programar próximo tick
		executor.get_tree().create_timer(tick_interval).timeout.connect(func():
			if is_instance_valid(zone):
				# Re-registrar el cuerpo siguiente (placeholder simple)
				pass
		)
	)
	# Auto-destruir
	executor.get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(zone):
			zone.queue_free()
	)
	if DEBUG:
		print("[EffectLibrary] persistent_zone at %s radius=%.1f duration=%.1f" % [center, radius, duration])


## Crea o reutiliza un nodo componente con el nombre dado.
static func _get_or_create_component(target: Node, component_name: String) -> Node:
	for child in target.get_children():
		if child.name == component_name:
			return child
	var comp_script = load("res://scripts/skill/components/" + component_name + ".gd")
	if not comp_script:
		# Si no hay script, crea un nodo genérico (placeholder).
		var n := Node.new()
		n.name = component_name
		n.set_meta("placeholder", true)
		target.add_child(n)
		return n
	var comp = comp_script.new()
	comp.name = component_name
	target.add_child(comp)
	return comp
