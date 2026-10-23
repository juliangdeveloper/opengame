extends RefCounted

const DEBUG := true
const TargetResolver := preload("res://scripts/skill/target_resolver.gd")
const Elements := preload("res://scripts/skill/elements.gd")

static func apply_atom(
	executor: Node,
	atom: Dictionary,
	targets: Array[Node]
) -> void:
	var atom_type_text := String(atom.get("type", ""))
	if targets.is_empty() and atom_type_text != "trigger" and atom_type_text != "burst_aoe" and atom_type_text != "persistent_zone":
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
		&"camera":
			_apply_camera(executor, params, targets)
		&"guide_commune":
			_apply_guide_commune(executor, params, targets)
		&"interact":
			_apply_interact(executor, params, targets)
		_:
			push_warning("[EffectLibrary] unknown atom type: %s" % atom_type)



static func _compute_skill_power(
	executor: Node,
	atom: Dictionary,
	amount: float,
	knockback: float,
	target: Node
) -> Dictionary:
	var notes: Array = []
	var caster: Node = null
	if executor and "caster" in executor and executor.caster != null:
		caster = executor.caster
	elif executor:
		caster = executor

	var dmg_type: String = "physical"
	if "last_damage_type" in executor and executor.last_damage_type != null:
		dmg_type = String(executor.last_damage_type)
	elif "dmg_type" in atom:
		dmg_type = String(atom["dmg_type"])

	var crit: bool = false
	var dodged: bool = false
	var final_amount: float = amount
	var final_knockback: float = knockback

	var caster_ac: Node = _get_attribute_component(caster)
	if caster_ac != null and is_instance_valid(caster_ac):
		var attack_power: float = float(caster_ac.call("get_attack_power", dmg_type))
		final_amount *= attack_power
		notes.append("caster.attack_power(%s)=%.2f" % [dmg_type, attack_power])

		var crit_chance: float = float(caster_ac.call("get_crit_chance"))
		if randf() < crit_chance:
			crit = true
			final_amount *= 2.0
			notes.append("CRIT! (chance=%.2f)" % crit_chance)

		var atk_speed: float = float(caster_ac.call("get_attack_speed"))
		final_amount *= atk_speed
		notes.append("caster.attack_speed=%.2f" % atk_speed)
	else:
		notes.append("caster has no AttributeComponent (NPC? use defaults)")

	var weapon: Resource = _get_equipped_weapon_resource(caster)
	if weapon != null and target != null and target.is_in_group("enemies"):
		if target.has_method("get_weapon_family_name"):
			var target_family: String = String(target.call("get_weapon_family_name"))
			var class_mult: float = float(weapon.class_dmg_mult.get(target_family, 1.0))
			if class_mult != 1.0:
				final_amount *= class_mult
				notes.append("weapon.class_mult(%s)=%.2f" % [target_family, class_mult])

	var target_ac: Node = _get_attribute_component(target)
	if target_ac != null and is_instance_valid(target_ac):
		var dodge_chance: float = float(target_ac.call("get_dodge_chance"))
		if randf() < dodge_chance:
			dodged = true
			final_amount = 0.0
			notes.append("DODGED (chance=%.2f)" % dodge_chance)
	else:
		notes.append("target has no AttributeComponent (env_object?)")

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


static func _get_attribute_component(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if node.has_node("AttributeComponent"):
		return node.get_node("AttributeComponent")
	return null


static func _get_equipped_weapon_resource(caster: Node) -> Resource:
	if caster == null:
		return null
	if "equipped_weapon" in caster and caster.equipped_weapon != null:
		return caster.equipped_weapon
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
	var element: StringName = StringName(String(params.get("element", "physical")))
	var status_to_apply: String = String(params.get("applies_status", ""))
	var status_chance: float = float(params.get("status_chance", 0.0))
	var status_duration: float = float(params.get("status_duration", 0.0))
	var applies_resistance_to_caster: String = String(params.get("applies_resistance_to_caster", ""))
	var resistance_duration: float = float(params.get("resistance_duration", 0.0))
	var resistance_multiplier: float = float(params.get("resistance_multiplier", 0.5))
	var elemental_boost: float = 1.0
	if element != &"physical" and element != &"" and executor.progression:
		if executor.progression.has_method("get_element_attack_multiplier"):
			elemental_boost = float(executor.progression.call("get_element_attack_multiplier", element))
	amount *= elemental_boost
	for t in targets:
		if not is_instance_valid(t):
			continue
		var dmg := amount
		var power: Dictionary = _compute_skill_power(executor, atom, amount, knockback, t)
		dmg = float(power.get("final_amount", amount))
		if power.get("notes") != null and (power["notes"] as Array).size() > 0 and not (atom.get("_logged", false) if atom else false):
			print("[EffectLibrary] power: %s" % " | ".join(power["notes"]))
			atom["_logged"] = true
		var defender_element := _get_actor_element(t)
		var elemental_mult := Elements.get_elemental_multiplier(element, defender_element)
		var res_mult := _get_actor_resistance(t, element)
		var final_mult := elemental_mult * res_mult
		_deal_damage_to(t, dmg, dmg_type, executor.caster, knockback, final_mult)
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
		if status_to_apply != "" and status_duration > 0.0:
			if status_chance <= 0.0 or randf() < status_chance:
				_apply_status_to(t, status_to_apply, status_duration, executor.caster)
	if applies_resistance_to_caster != "" and resistance_duration > 0.0:
		_apply_temporary_resistance(executor.caster, applies_resistance_to_caster, resistance_multiplier, resistance_duration)
	for t in targets:
		if t != executor.caster and not hitbox_config.is_empty() and t is Node3D:
			spawn_hitbox(executor, hitbox_config, [t])


static func _apply_dot(executor: Node, atom: Dictionary, targets: Array[Node]) -> void:
	var params: Dictionary = atom.get("params", {})
	var hitbox_config: Dictionary = atom.get("hitbox", {})
	var dpt := float(executor.get_effective_stat("dpt", params))
	var duration := float(executor.get_effective_stat("duration", params))
	var tick_interval := float(params.get("tick_interval", 1.0))
	var element: StringName = StringName(String(params.get("element", "physical")))
	var status_to_apply: String = String(params.get("applies_status", ""))
	var status_chance: float = float(params.get("status_chance", 0.0))
	var status_duration: float = float(params.get("status_duration", 0.0))
	var applies_resistance_to_caster: String = String(params.get("applies_resistance_to_caster", ""))
	var resistance_duration: float = float(params.get("resistance_duration", 0.0))
	var resistance_multiplier: float = float(params.get("resistance_multiplier", 0.5))
	var real_targets: Array[Node] = []
	for t in targets:
		if is_instance_valid(t) and t != executor.caster:
			real_targets.append(t)
	for t in real_targets:
		if status_to_apply != "" and status_duration > 0.0:
			if status_chance <= 0.0 or randf() < status_chance:
				_apply_status_to(t, status_to_apply, status_duration, executor.caster)
	if applies_resistance_to_caster != "" and resistance_duration > 0.0:
		_apply_temporary_resistance(executor.caster, applies_resistance_to_caster, resistance_multiplier, resistance_duration)
	for t in real_targets:
		_attach_dot(t, dpt, duration, tick_interval, executor.caster)
	for t in real_targets:
		if not hitbox_config.is_empty() and t is Node3D:
			spawn_hitbox(executor, hitbox_config, [t])


static func _apply_burst_aoe(
	executor: Node,
	atom: Dictionary,
	targets: Array[Node],
	applies: String
) -> void:
	var params: Dictionary = atom.get("params", {})
	var hitbox_config: Dictionary = atom.get("hitbox", {})
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
	var elemental_boost: float = 1.0
	if element != &"physical" and element != &"" and executor.progression:
		if executor.progression.has_method("get_element_attack_multiplier"):
			elemental_boost = float(executor.progression.call("get_element_attack_multiplier", element))
	amount *= elemental_boost
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
		var power_b: Dictionary = _compute_skill_power(executor, atom, dmg_amount, float(executor.get_effective_stat("knockback", params)), t)
		dmg_amount = float(power_b.get("final_amount", dmg_amount))
		var defender_element := _get_actor_element(t)
		var elemental_mult := Elements.get_elemental_multiplier(element, defender_element)
		var res_mult := _get_actor_resistance(t, element)
		var final_mult := elemental_mult * res_mult
		_deal_damage_to(t, dmg_amount, dmg_type, executor.caster, float(executor.get_effective_stat("knockback", params)), final_mult)
		if status_to_apply != "" and status_duration > 0.0:
			if status_chance <= 0.0 or randf() < status_chance:
				_apply_status_to(t, status_to_apply, status_duration, executor.caster)
	if applies_resistance_to_caster != "" and resistance_duration > 0.0:
		_apply_temporary_resistance(executor.caster, applies_resistance_to_caster, resistance_multiplier, resistance_duration)
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
	var center_target: Node3D = null
	for t in targets:
		if is_instance_valid(t) and t is Node3D:
			center_target = t as Node3D
			break
	if not center_target:
		return
	_spawn_persistent_zone(executor, center_target.global_position, radius, duration, dpt, tick_interval, slow_inside)

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


static func _apply_move(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var kind := String(params.get("kind", "dash"))
	var distance := float(executor.get_effective_stat("distance", params))
	var duration := float(executor.get_effective_stat("duration", params))
	var rel := String(params.get("target_relative", "forward"))
	var i_frames: bool = bool(params.get("i_frames", false))
	var blink: bool = bool(params.get("blink", false))
	var stamina_drain: float = float(params.get("stamina_drain", 0.0))
	for t in targets:
		if not is_instance_valid(t) or not t is Node3D:
			continue
		if t.has_method("resist") and t.has_method("is_too_heavy_to_move"):
			var resist_info: Dictionary = t.resist(distance * 10.0)
			if t.is_too_heavy_to_move(distance):
				print("[EffectLibrary] move: target %s too heavy (weight=%.1f, power=%.1f)" % [t.name, float(t.weight), distance])
				continue
		if stamina_drain > 0.0 and t.has_method("spend_stamina"):
			t.call("spend_stamina", stamina_drain)
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
		duration = 0.05
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
			dir = -node.global_transform.basis.z
	if kind == "teleport" or duration <= 0.05:
		node.global_position += dir * distance
		return
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = dir * (distance / duration)
	if kind == "launch":
		var tween := node.create_tween()
		tween.tween_property(node, "global_position", node.global_position + dir * distance, duration)
	if kind == "jump":
		if node is CharacterBody3D:
			var v: Vector3 = (node as CharacterBody3D).velocity
			v.y = maxf(v.y, distance)
			(node as CharacterBody3D).velocity = v
		return
	if kind == "speed_boost":
		return



static func _apply_morph(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var kind := String(params.get("kind", "polymorph"))
	var duration := float(executor.get_effective_stat("duration", params))
	for t in targets:
		if not is_instance_valid(t):
			continue
		if kind == "scale" and t is Node3D:
			var t3d := t as Node3D
			var mult := float(params.get("scale_multiplier", 1.5))
			var original := t3d.scale
			t3d.scale = original * mult
			await executor.get_tree().create_timer(duration).timeout
			if is_instance_valid(t3d):
				t3d.scale = original
		elif kind == "polymorph":
			if DEBUG:
				print("[EffectLibrary] polymorph %s for %.1fs (not implemented visually yet)" % [t.name, duration])
		elif kind == "possess":
			if DEBUG:
				print("[EffectLibrary] possess %s for %.1fs (not implemented yet)" % [t.name, duration])



static func _apply_status(executor: Node, atom: Dictionary, targets: Array[Node]) -> void:
	var params: Dictionary = atom.get("params", {})
	var hitbox_config: Dictionary = atom.get("hitbox", {})
	var kind := String(params.get("kind", "stun"))
	var duration := float(executor.get_effective_stat("duration", params))
	var magnitude := float(executor.get_effective_stat("magnitude", params))
	var extra_status: String = String(params.get("applies_status", ""))
	var extra_status_chance: float = float(params.get("status_chance", 0.0))
	var extra_status_duration: float = float(params.get("status_duration", 0.0))
	var applies_resistance_to_caster: String = String(params.get("applies_resistance_to_caster", ""))
	var resistance_duration: float = float(params.get("resistance_duration", 0.0))
	var resistance_multiplier: float = float(params.get("resistance_multiplier", 0.5))
	var real_targets: Array[Node] = []
	for t in targets:
		if is_instance_valid(t) and t != executor.caster:
			real_targets.append(t)
	for t in real_targets:
		_attach_status(t, kind, duration, magnitude)
		if extra_status != "" and extra_status_duration > 0.0:
			if extra_status_chance <= 0.0 or randf() < extra_status_chance:
				_apply_status_to(t, extra_status, extra_status_duration, executor.caster)
	if applies_resistance_to_caster != "" and resistance_duration > 0.0:
		_apply_temporary_resistance(executor.caster, applies_resistance_to_caster, resistance_multiplier, resistance_duration)
	for t in real_targets:
		if not hitbox_config.is_empty() and t is Node3D:
			spawn_hitbox(executor, hitbox_config, [t])


static func _apply_mind(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var kind := String(params.get("kind", "charm"))
	var duration := float(executor.get_effective_stat("duration", params))
	for t in targets:
		if not is_instance_valid(t):
			continue
		if DEBUG:
			print("[EffectLibrary] mind %s on %s for %.1fs (not implemented AI-wise yet)" % [kind, t.name, duration])



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
	if not executor.caster or not executor.caster is Node3D:
		return
	var caster3d := executor.caster as Node3D
	var dir := -caster3d.global_transform.basis.z
	if targets.size() > 0 and targets[0] is Node3D:
		dir = ((targets[0] as Node3D).global_position - caster3d.global_position).normalized()
	var scene := executor.get_tree().current_scene
	if not scene:
		return
	var proj := Area3D.new()
	proj.name = "SkillProjectile"
	proj.global_position = caster3d.global_position + dir * 0.5
	proj.collision_layer = 1
	proj.collision_mask = 4
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = hitbox_radius
	col.shape = sphere
	proj.add_child(col)
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
	var vel := dir * speed
	if DEBUG:
		print("[EffectLibrary] projectile spawned speed=%.1f lifetime=%.1f friendly=%s" % [speed, lifetime, friendly])
	if on_hit_effect != "":
		proj.body_entered.connect(func(b: Node):
			if b.has_method("take_damage"):
				b.call("take_damage", 5.0, proj)
		)
	var tween := executor.get_tree().create_tween().set_parallel(true)
	tween.tween_property(proj, "global_position", proj.global_position + dir * speed * lifetime, lifetime)
	tween.tween_property(proj, "scale", Vector3(0.1, 0.1, 0.1), lifetime).from(Vector3.ONE)
	executor.get_tree().create_timer(lifetime).timeout.connect(func():
		if is_instance_valid(proj):
			proj.queue_free()
	)
	executor.last_projectile = proj


static func _apply_npc(executor: Node, params: Dictionary, _targets: Array[Node]) -> void:
	if DEBUG:
		print("[EffectLibrary] npc atom placeholder template=%s" % params.get("template", "unknown"))


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
		return null
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
		size = Vector3(size.x, size.x, size.x)
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
	var _wireframe_unused := bool(config.get("wireframe", false))
	var node := Node3D.new()
	node.name = "Hitbox"
	scene.add_child(node)
	node.global_position = pos
	if shape == "box" or shape == "beam" or shape == "capsule":
		if dir != Vector3.ZERO:
			node.look_at(pos + dir.normalized(), Vector3.UP)
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
			var bm2 := BoxMesh.new()
			bm2.size = size
			m = bm2
	mesh.mesh = m
	if shape == "box" or shape == "beam" or shape == "capsule":
		mesh.position = Vector3(0, 0, -size.z * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.blend_mode = blend_mode
	mesh.material_override = mat
	node.add_child(mesh)
	if fade_out and duration > 0.0:
		var tween := node.create_tween()
		tween.tween_property(mat, "albedo_color:a", 0.0, duration).from(color.a)
		tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, duration).from(emission)
	if executor and executor.get_tree():
		executor.get_tree().create_timer(duration + 0.05).timeout.connect(func() -> void:
			if is_instance_valid(node):
				node.queue_free()
		)
	if DEBUG:
		print("[EffectLibrary] hitbox spawn shape=%s size=%s pos=%s duration=%.2f" % [shape, str(size), str(pos), duration])
	return node


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


static func _spawn_debug_beam(executor: Node, origin: Vector3, dir: Vector3, radius: float, length: float) -> void:
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
	if DEBUG:
		print("[EffectLibrary] zone atom placeholder kind=%s" % params.get("kind", "damage"))



static func _apply_trigger(executor: Node, atom: Dictionary) -> void:
	var params: Dictionary = atom.get("params", {})
	var when := String(params.get("when", "delay"))
	var delay := float(params.get("delay", 0.0))
	match when:
		"delay":
			if delay > 0.0:
				var weak_executor: WeakRef = weakref(executor)
				executor.get_tree().create_timer(delay).timeout.connect(func() -> void:
					var ex: Node = weak_executor.get_ref()
					if not ex or not is_instance_valid(ex) or not ex.is_inside_tree():
						return
					_execute_then_effect(ex, params, atom)
				)
			else:
				_execute_then_effect(executor, params, atom)
		"on_hit", "on_kill", "on_take_damage", "on_health_below", "on_status_applied":
			executor.register_trigger(when, params, atom)
		"on_skill_used":
			var sid := String(params.get("then_skill_id", ""))
			if sid != "":
				executor.register_combo_trigger(sid, params, atom)


static func _execute_then_effect(executor: Node, params: Dictionary, atom: Dictionary) -> void:
	var then_eff := String(params.get("then_effect", ""))
	if then_eff == "":
		return
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
	for a in executor.skill.atoms:
		if a.get("id", "") == then_eff or String(a.get("type", "")) == then_eff:
			apply_atom(executor, a, executor.resolve_targets())
			return
	if DEBUG:
		print("[EffectLibrary] trigger then_effect '%s' not found in skill atoms" % then_eff)



static func _deal_damage_to(target: Node, amount: float, dmg_type: String, source: Node, knockback: float, mult: float = 1.0) -> void:
	if target == source:
		return
	if not target.has_method("take_damage"):
		return
	var final_amount: float = amount * mult
	if source and source.has_node("AttributeComponent"):
		var src_attr: Node = source.get_node("AttributeComponent")
		if dmg_type == "physical":
			final_amount *= float(src_attr.call("get_phys_dmg_multiplier"))
		else:
			final_amount *= float(src_attr.call("get_ele_dmg_multiplier"))
	if source:
		source.set("last_damage_type", dmg_type)
	var elem_name := StringName(dmg_type)
	target.call("take_damage", final_amount, source, elem_name)
	if DEBUG:
		print("[EffectLibrary] hit %s amount=%.1f (base %.1f x mult %.2f) type=%s" % [target.name, final_amount, amount, mult, dmg_type])
	if knockback > 0.0 and target is Node3D and source is Node3D:
		var t3d := target as Node3D
		var s3d := source as Node3D
		var dir := (t3d.global_position - s3d.global_position).normalized()
		if t3d is CharacterBody3D:
			(t3d as CharacterBody3D).velocity += dir * knockback
		else:
			t3d.global_position += dir * knockback


static func _get_actor_element(actor: Node) -> StringName:
	if actor == null or not is_instance_valid(actor):
		return &"physical"
	if actor.has_meta("element"):
		return StringName(String(actor.get_meta("element")))
	if "element" in actor:
		return StringName(String(actor.element))
	return &"physical"


static func _get_actor_resistance(actor: Node, element: StringName) -> float:
	if actor == null or not is_instance_valid(actor):
		return 1.0
	if actor.has_node("ResistanceComponent"):
		var rc: Node = actor.get_node("ResistanceComponent")
		if rc.has_method("get_resistance"):
			return float(rc.call("get_resistance", element))
	return 1.0


static func _apply_status_to(target: Node, status_id: String, duration: float, source: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	var effective_duration: float = duration
	if source and source.has_node("AttributeComponent"):
		var caster_attr: Node = source.get_node("AttributeComponent")
		var potency: float = float(caster_attr.call("get_status_potency", StringName(status_id)))
		effective_duration *= potency
	if target.has_node("AttributeComponent"):
		var target_attr: Node = target.get_node("AttributeComponent")
		var res: float = float(target_attr.call("get_status_resistance", StringName(status_id)))
		effective_duration *= (1.0 - res)

	if effective_duration <= 0.01:
		print("[EffectLibrary] status %s resisted by target (effective=%.2f)" % [status_id, effective_duration])
		return

	var sc: Node = null
	if target.has_node("StatusComponent"):
		sc = target.get_node("StatusComponent")
	else:
		const StatusCompScript := preload("res://scripts/skill/components/StatusComponent.gd")
		sc = StatusCompScript.new()
		sc.name = "StatusComponent"
		target.add_child(sc)
	var kind: StringName = StringName(status_id)
	if sc.has_method("start_elemental_status"):
		sc.call("start_elemental_status", kind, effective_duration, source)
	elif sc.has_method("start_status"):
		sc.call("start_status", status_id, effective_duration, 1.0)


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
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.blend_mode = 1
	mesh.material_override = mat
	sphere.add_child(mesh)
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
	var t := 0.0
	var timer := executor.get_tree().create_timer(tick_interval)
	timer.timeout.connect(func():
		for n in zone.get_overlapping_bodies() + zone.get_overlapping_areas():
			if n and n.has_method("take_damage") and is_instance_valid(n):
				n.call("take_damage", dpt * tick_interval, zone)
			if n and slow_inside > 0.0 and n.has_method("set_slow"):
				n.call("set_slow", slow_inside)
		executor.get_tree().create_timer(tick_interval).timeout.connect(func():
			if is_instance_valid(zone):
				pass
		)
	)
	executor.get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(zone):
			zone.queue_free()
	)
	if DEBUG:
		print("[EffectLibrary] persistent_zone at %s radius=%.1f duration=%.1f" % [center, radius, duration])


static func _get_or_create_component(target: Node, component_name: String) -> Node:
	for child in target.get_children():
		if child.name == component_name:
			return child
	var comp_script = load("res://scripts/skill/components/" + component_name + ".gd")
	if not comp_script:
		var n := Node.new()
		n.name = component_name
		n.set_meta("placeholder", true)
		target.add_child(n)
		return n
	var comp = comp_script.new()
	comp.name = component_name
	target.add_child(comp)
	return comp


static func _apply_camera(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	if targets.is_empty():
		return
	for target in targets:
		if not is_instance_valid(target):
			continue
		var axis: String = String(params.get("axis", "yaw"))
		var direction: String = String(params.get("direction", "right"))
		var base_speed: float = float(params.get("base_speed", 2.5))
		var amount: float = float(params.get("amount", 0.0))

		match axis:
			"yaw":
				var sign: float = -1.0 if direction == "right" else 1.0
				if amount != 0.0:
					target.rotate_y(sign * amount)
				else:
					target.rotate_y(sign * base_speed * 0.016)
			"pitch":
				var pivot: Node3D = target.get_node_or_null("CameraPivot")
				if pivot == null:
					continue
				var sign: float = -1.0 if direction == "up" else 1.0
				var clamp_min: float = deg_to_rad(float(params.get("clamp_min", -85.0)))
				var clamp_max: float = deg_to_rad(float(params.get("clamp_max", 85.0)))
				if amount != 0.0:
					pivot.rotate_x(sign * amount)
				else:
					pivot.rotate_x(sign * base_speed * 0.016)
				pivot.rotation.x = clampf(pivot.rotation.x, clamp_min, clamp_max)
			"reset":
				var pivot: Node3D = target.get_node_or_null("CameraPivot")
				if pivot == null:
					continue
				var duration: float = float(params.get("duration", 0.2))
				if duration > 0.0 and target.get_tree():
					var tween: Tween = target.create_tween()
					tween.set_ease(Tween.EASE_OUT)
					tween.set_trans(Tween.TRANS_QUAD)
					tween.tween_property(pivot, "rotation:x", 0.0, duration)
					var cam: Camera3D = pivot.get_node_or_null("Camera3D")
				else:
					pivot.rotation.x = 0.0
			"free_look":
				pass

	if DEBUG:
		print("[EffectLibrary] camera axis=%s dir=%s speed=%.2f" % [String(params.get("axis", "")), String(params.get("direction", "")), float(params.get("base_speed", 0.0))])


static func _apply_guide_commune(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var action: String = String(params.get("action", ""))
	match action:
		"perceive":
			var caster: Node = executor.caster if "caster" in executor else executor
			if caster == null:
				return
			var guide: Node = caster.get_tree().root.find_child("Guide", true, false)
			if guide != null and guide.has_method("reveal"):
				guide.call("reveal", caster)
			if DEBUG:
				print("[EffectLibrary] guide_commune: perceive — Guide revealed to %s" % caster.name)
		"dialogue":
			var caster: Node = executor.caster if "caster" in executor else executor
			if caster != null and caster.has_signal("guide_dialogue_requested"):
				caster.emit_signal("guide_dialogue_requested")
			if DEBUG:
				print("[EffectLibrary] guide_commune: dialogue opened")
		"request_skill":
			if DEBUG:
				print("[EffectLibrary] guide_commune: skill request submitted")
		"grant_skill":
			if DEBUG:
				print("[EffectLibrary] guide_commune: skill granted to target")


static func _apply_interact(executor: Node, params: Dictionary, targets: Array[Node]) -> void:
	var action: String = String(params.get("action", ""))
	var opens_ui: String = String(params.get("opens_ui", ""))

	for target in targets:
		if not is_instance_valid(target):
			continue
		match action:
			"dialogue":
				if target.has_method("start_dialogue"):
					target.call("start_dialogue", executor.caster if "caster" in executor else executor)
			"pick_up":
				if target.has_method("pick_up"):
					target.call("pick_up", executor.caster if "caster" in executor else executor)
			"use":
				if target.has_method("use"):
					target.call("use", executor.caster if "caster" in executor else executor)
			"examine":
				if target.has_method("examine"):
					target.call("examine", executor.caster if "caster" in executor else executor)

	if opens_ui != "" and executor.get_tree():
		var scene: PackedScene = load("res://scenes/ui/%s.tscn" % opens_ui)
		if scene != null:
			var ui: Node = scene.instantiate()
			executor.get_tree().root.add_child(ui)

	if DEBUG:
		print("[EffectLibrary] interact: action=%s targets=%d" % [action, targets.size()])
