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

# Componentes que se añaden a targets para trackear efectos en curso.
# Cada componente es un nodo ligero (Node) que tiene un timer interno.

# === Aplica el átomo ===
static func apply_atom(
	executor: Node,
	atom: Dictionary,
	targets: Array[Node]
) -> void:
	if targets.is_empty() and atom.get("type", "") != "trigger":
		# La mayoría de átomos necesitan al menos un target
		return
	var atom_type := StringName(atom.get("type", ""))
	var params: Dictionary = atom.get("params", {})
	var applies := String(atom.get("applies_to_target", "primary"))
	match atom_type:
		&"hit":
			_apply_hit(executor, params, targets)
		&"dot":
			_apply_dot(executor, params, targets)
		&"burst_aoe":
			_apply_burst_aoe(executor, params, targets, applies)
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
			_apply_status(executor, params, targets)
		&"mind":
			_apply_mind(executor, params, targets)
		&"projectile":
			_apply_projectile(executor, params, targets)
		&"npc":
			_apply_npc(executor, params, targets)
		&"zone":
			_apply_zone(executor, params, targets)
		&"trigger":
			_apply_trigger(executor, params, atom)
		_:
			push_warning("[EffectLibrary] unknown atom type: %s" % atom_type)


# === damage ===

static func _apply_hit(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var amount := float(executor.get_effective_stat("amount", params))
	var dmg_type := String(params.get("damage_type", "physical"))
	var knockback := float(executor.get_effective_stat("knockback", params))
	for t in targets:
		if not is_instance_valid(t):
			continue
		_deal_damage_to(t, amount, dmg_type, executor.caster, knockback)


static func _apply_dot(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var dpt := float(executor.get_effective_stat("dpt", params))
	var duration := float(executor.get_effective_stat("duration", params))
	var tick_interval := float(params.get("tick_interval", 1.0))
	for t in targets:
		if not is_instance_valid(t):
			continue
		_attach_dot(t, dpt, duration, tick_interval, executor.caster)


static func _apply_burst_aoe(
	executor: Node,
	params: Dictionary,
	targets: Array[Node],
	applies: String
) -> void:
	var radius := float(executor.get_effective_stat("radius", params))
	var amount := float(executor.get_effective_stat("amount", params))
	var dmg_type := String(params.get("damage_type", "energy"))
	var falloff := String(params.get("falloff", "linear"))
	# Si applies_to_target es "primary" pero los targets ya vienen del AOE resolver,
	# iteramos todos. Si no, buscamos los targets en el radio.
	if applies == "primary":
		# El executor ya pasó un solo target (el resolver ya aplicó el AOE)
		for t in targets:
			if not is_instance_valid(t):
				continue
			_deal_damage_to(t, amount, dmg_type, executor.caster, 0.0)
		return
	# all_in_aoe: ya targets son la lista del AOE
	for t in targets:
		if not is_instance_valid(t):
			continue
		_deal_damage_to(t, amount, dmg_type, executor.caster, 0.0)


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
	_spawn_persistent_zone(
		executor,
		center_target.global_position,
		radius, duration, dpt, tick_interval, slow_inside
	)


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
	for t in targets:
		if not is_instance_valid(t) or not t is Node3D:
			continue
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

static func _apply_status(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var kind := String(params.get("kind", "stun"))
	var duration := float(executor.get_effective_stat("duration", params))
	var magnitude := float(executor.get_effective_stat("magnitude", params))
	for t in targets:
		if not is_instance_valid(t):
			continue
		_attach_status(t, kind, duration, magnitude)


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


static func _apply_zone(executor: Node, params: Dictionary, _targets: Array[Node]) -> void:
	# Placeholder para zonas persistentes con kind=damage|slow|stun|reveal|heal|shield
	if DEBUG:
		print("[EffectLibrary] zone atom placeholder kind=%s" % params.get("kind", "damage"))


# === trigger ===

static func _apply_trigger(executor: Node, params: Dictionary, atom: Dictionary) -> void:
	var when := String(params.get("when", "delay"))
	var delay := float(params.get("delay", 0.0))
	match when:
		"delay":
			if delay > 0.0:
				executor.get_tree().create_timer(delay).timeout.connect(func():
					_execute_then_effect(executor, params, atom)
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


static func _execute_then_effect(executor: Node, params: Dictionary, atom: Dictionary) -> void:
	var then_eff := String(params.get("then_effect", ""))
	if then_eff == "":
		return
	# Busca el átomo referenciado por then_effect dentro de la skill actual
	for a in executor.skill.atoms:
		if a.get("id", "") == then_eff or String(a.get("type", "")) == then_eff:
			apply_atom(executor, a, executor.resolve_targets())
			return
	if DEBUG:
		print("[EffectLibrary] trigger then_effect '%s' not found in skill atoms" % then_eff)


# === helpers (componentes para trackear efectos en curso) ===

static func _deal_damage_to(target: Node, amount: float, dmg_type: String, source: Node, knockback: float) -> void:
	if not target.has_method("take_damage"):
		return
	target.call("take_damage", amount, source)
	if DEBUG:
		print("[EffectLibrary] hit %s amount=%.1f type=%s" % [target.name, amount, dmg_type])
	# Knockback
	if knockback > 0.0 and target is Node3D and source is Node3D:
		var t3d := target as Node3D
		var s3d := source as Node3D
		var dir := (t3d.global_position - s3d.global_position).normalized()
		if t3d is CharacterBody3D:
			(t3d as CharacterBody3D).velocity += dir * knockback
		else:
			t3d.global_position += dir * knockback


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
