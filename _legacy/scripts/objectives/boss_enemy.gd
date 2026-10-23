extends EntityCharacter
class_name BossEnemy

const SkillResource := preload("res://scripts/skill/skill_resource.gd")
const SkillExecutorScript := preload("res://scripts/skill/skill_executor.gd")
const EffectLibrary := preload("res://scripts/skill/effect_library.gd")
const TargetResolver := preload("res://scripts/skill/target_resolver.gd")

@export var boss_data: Resource = null




var _state_debug_timer: float = 999.0


var player: Node3D = null

const MAX_STAMINA: float = 100.0
const STAMINA_REGEN: float = 22.0

signal boss_damaged(amount: float, hp_left: float)

var reaction_time: float = 0.6
var skill_cast_time: float = 0.55
var skill_recover_time: float = 1.0

signal boss_killed(boss_id: StringName)
signal boss_dodged(enemy: Node)
signal boss_parried(enemy: Node)
signal boss_blocked(enemy: Node)


func _ready() -> void:
	add_to_group("bosses")
	if data == null and boss_data != null:
		data = boss_data
	super._ready()
	_inject_defensive_skills()
	player = get_tree().root.find_child("Player", true, false)
	target = target_override if target_override else player
	print("[boss] %s ready id=%s hp=%.0f skills=%d behavior=%s target=%s" % [
		name, String(boss_data.id) if boss_data else "(none)", hp, skill_ids.size(),
		String(boss_data.behavior) if boss_data else "n/a",
		String(target.name) if target else "none"
	])


func _apply_boss_data() -> void:
	if boss_data == null:
		push_warning("[boss] no boss_data assigned, using defaults")
		return
	if "reaction_time_sec" in boss_data:
		reaction_time = float(boss_data.reaction_time_sec)
	var title_hash: int = hash(String(boss_data.display_name))
	var hue: float = float(title_hash % 360) / 360.0
	base_color = Color.from_hsv(hue, 0.7, 0.85)
	if "weakness_element" in boss_data and boss_data.weakness_element == &"light":
		base_color = Color(0.6, 0.0, 0.7)
	elif "weakness_element" in boss_data and boss_data.weakness_element == &"fire":
		base_color = Color(0.3, 0.5, 0.9)
	if data != null:
		data.base_color = base_color


func _inject_defensive_skills() -> void:
	if boss_data == null:
		return
	var behavior: String = String(boss_data.behavior)
	var w_defend: float
	var w_dodge: float
	var w_parry: float
	match behavior:
		"defensive", "tactical":
			w_defend = 1.2
			w_dodge = 1.0
			w_parry = 1.4
		"evasive", "trickster":
			w_defend = 0.4
			w_dodge = 1.6
			w_parry = 0.5
		"berserker", "aggressive":
			w_defend = 0.2
			w_dodge = 0.3
			w_parry = 0.1
		"summoner", "caster":
			w_defend = 0.7
			w_dodge = 1.0
			w_parry = 0.5
		_:
			w_defend = 0.6
			w_dodge = 0.7
			w_parry = 0.5
	var inject: Array = [
		[&"defenderse_001", w_defend],
		[&"esquivar_001", w_dodge],
		[&"parry_riposte_001", w_parry],
	]
	for entry in inject:
		var sid: StringName = entry[0]
		var w: float = entry[1]
		if sid in skill_ids:
			var idx: int = skill_ids.find(sid)
			skill_weights[idx] = max(skill_weights[idx], w)
		else:
			skill_ids.append(sid)
			skill_weights.append(w)


func _setup_visuals() -> void:
	if model and mesh_instance:
		_base_mat = StandardMaterial3D.new()
		_base_mat.albedo_color = base_color
		mesh_instance.material_override = _base_mat
		model.scale = Vector3(1.3, 1.3, 1.3)
	if attack_area and hit_collision:
		_hitbox_mat = StandardMaterial3D.new()
		_hitbox_mat.transparency = 1
		_hitbox_mat.shading_mode = 0
		_hitbox_mat.cull_mode = 2
		_hitbox_mat.albedo_color = HITBOX_WINDUP
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd:
			hd.material_override = _hitbox_mat
			hd.visible = false
		attack_area.monitoring = false
	if label_hp:
		label_hp.text = "%d/%d" % [int(hp), int(max_hp)]


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		target = target_override if target_override else get_tree().root.find_child("Player", true, false)
	if state == State.DEAD:
		return
	parry_cooldown = max(0.0, parry_cooldown - delta)
	dodge_cooldown = max(0.0, dodge_cooldown - delta)
	defend_cooldown = max(0.0, defend_cooldown - delta)
	stamina = min(MAX_STAMINA, stamina + STAMINA_REGEN * delta)
	state_timer -= delta
	match state:
		State.IDLE: _state_idle()
		State.CHASE: _state_chase(delta)
		State.CHOOSE_SKILL: _state_choose_skill()
		State.WINDUP: _state_windup()
		State.ACTIVE: _state_active()
		State.RECOVER: _state_recover()
	if _state_debug_timer < 1.0:
		_state_debug_timer -= delta
		if _state_debug_timer <= 0.0:
			_state_debug_timer = 0.5
			print("[boss-debug] %s state=%s timer=%.2f hp=%.0f d=%.1f current_skill=%s" % [
				name, State.keys()[state], state_timer, hp,
				_dist_to_target(), String(current_skill_id)
			])
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y < 0:
		velocity.y = 0
	move_and_slide()
	_update_hp_label()
	if global_position.y < -10.0 and not is_dying:
		_die()



func _state_idle() -> void:
	velocity.x *= 0.5
	velocity.z *= 0.5
	if _dist_to_target() < 12.0:
		_enter_chase()


func _state_chase(delta: float) -> void:
	var d := _dist_to_target()
	if d > 18.0:
		_enter_idle()
		return
	if d <= 8.0:
		_enter_choose_skill()
		return
	if target == null:
		return
	var to := (target.global_position - global_position)
	to.y = 0
	if to.length() > 0.01:
		to = to.normalized()
		var target_yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 6.0 * delta)
		velocity.x = to.x * 2.6
		velocity.z = to.z * 2.6


func _state_choose_skill() -> void:
	current_skill_id = _decide_action()
	if current_skill_id == &"":
		_enter_recover()
		return
	_enter_windup()


func _decide_action() -> StringName:
	var hp_ratio: float = hp / max_hp if max_hp > 0.0 else 1.0
	var tgt_state: int = -1
	if target and is_instance_valid(target) and "state" in target:
		tgt_state = int(target.state)
	var d: float = _dist_to_target()
	var target_casting: bool = (tgt_state == 2 or tgt_state == 3)
	var parry_ready: bool = parry_cooldown <= 0.0 and stamina >= 12.0
	var dodge_ready: bool = dodge_cooldown <= 0.0 and stamina >= 18.0
	var defend_ready: bool = defend_cooldown <= 0.0 and stamina >= 12.0
	var behavior: String = String(boss_data.behavior) if boss_data else "aggressive"
	var p_parry: float = 0.0
	var p_dodge: float = 0.0
	var p_defend: float = 0.0
	var low_hp_mult: float = 2.0 if hp_ratio < 0.3 else 1.0
	match behavior:
		"defensive", "tactical":
			p_parry = 0.10 * low_hp_mult
			p_dodge = 0.08 * low_hp_mult
			p_defend = 0.06 * low_hp_mult
		"evasive", "trickster":
			p_parry = 0.04 * low_hp_mult
			p_dodge = 0.12 * low_hp_mult
			p_defend = 0.03 * low_hp_mult
		"berserker", "aggressive":
			p_parry = 0.02
			p_dodge = 0.02
			p_defend = 0.01
		"summoner", "caster":
			p_parry = 0.05
			p_dodge = 0.10 * low_hp_mult
			p_defend = 0.04
		_:
			p_parry = 0.05 * low_hp_mult
			p_dodge = 0.06 * low_hp_mult
			p_defend = 0.03
	if target_casting:
		p_parry += 0.25
		p_dodge += 0.15
	if d > 10.0:
		p_parry *= 0.1
		p_dodge *= 0.1
		p_defend *= 0.1
	if not parry_ready: p_parry = 0.0
	if not dodge_ready: p_dodge = 0.0
	if not defend_ready: p_defend = 0.0
	var p_total_def: float = p_parry + p_dodge + p_defend
	if p_total_def > 0.5:
		var scale: float = 0.5 / p_total_def
		p_parry *= scale
		p_dodge *= scale
		p_defend *= scale
	var r: float = randf()
	var chosen: StringName = &""
	var decision_kind: String = "ATTACK"
	if r < p_parry:
		chosen = &"parry_riposte_001"
		decision_kind = "PARRY"
	elif r < p_parry + p_dodge:
		chosen = &"esquivar_001"
		decision_kind = "DODGE"
	elif r < p_parry + p_dodge + p_defend:
		chosen = &"defenderse_001"
		decision_kind = "DEFEND"
	if log_ai_decisions:
		var cl: Node = Engine.get_main_loop().root.get_node_or_null("CombatLog")
		if cl and cl.has_method("log_event"):
			cl.log_event("ai_decision", {
				"boss_id": String(boss_data.id) if boss_data else "?",
				"decision": decision_kind,
				"chosen_skill": String(chosen),
				"hp_ratio": hp_ratio,
				"target_state": tgt_state,
				"target_casting": target_casting,
				"distance": d,
				"p_parry": p_parry,
				"p_dodge": p_dodge,
				"p_defend": p_defend,
				"stamina": stamina,
			})
	if chosen == &"":
		chosen = _pick_attack_skill()
	return chosen


func _pick_attack_skill() -> StringName:
	var DEFENSIVE: Array[StringName] = [&"defenderse_001", &"esquivar_001"]
	var attack_ids: Array[StringName] = []
	var attack_weights: Array[float] = []
	for i in skill_ids.size():
		if skill_ids[i] in DEFENSIVE:
			continue
		attack_ids.append(skill_ids[i])
		attack_weights.append(skill_weights[i])
	if attack_ids.is_empty():
		for i in skill_ids.size():
			attack_ids.append(skill_ids[i])
			attack_weights.append(skill_weights[i])
	for i in attack_ids.size():
		var cnt: int = _recent_skill_uses.count(attack_ids[i])
		if cnt > 0:
			attack_weights[i] *= 1.0 / (1.0 + float(cnt) * 0.6)
	var total: float = 0.0
	for w in attack_weights:
		total += w
	if total <= 0.0:
		return attack_ids[0] if not attack_ids.is_empty() else &""
	var roll: float = randf() * total
	var acc: float = 0.0
	for i in attack_ids.size():
		acc += attack_weights[i]
		if roll <= acc:
			return attack_ids[i]
	return attack_ids[attack_ids.size() - 1]


func _state_windup() -> void:
	velocity.x *= 0.7
	velocity.z *= 0.7
	if state_timer <= 0.0:
		_enter_active()


func _state_active() -> void:
	velocity.x = 0
	velocity.z = 0
	if state_timer <= 0.0 or current_skill_id == &"":
		_enter_recover()
		return


func _state_recover() -> void:
	velocity.x *= 0.5
	velocity.z *= 0.5
	if state_timer <= 0.0:
		if _dist_to_target() < 12.0:
			_enter_choose_skill()
		else:
			_enter_chase()


func _enter_idle() -> void: state = State.IDLE
func _enter_chase() -> void: state = State.CHASE

func _enter_choose_skill() -> void:
	state = State.CHOOSE_SKILL
	state_timer = reaction_time
	if attack_area and hit_collision:
		hit_collision.disabled = true
	if attack_area:
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd: hd.visible = false

func _enter_windup() -> void:
	state = State.WINDUP
	state_timer = skill_cast_time * 0.6
	var is_defensive: bool = _is_defensive_skill(current_skill_id)
	if attack_area:
		attack_area.monitoring = false
		if hit_collision: hit_collision.disabled = true
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd:
			if is_defensive:
				hd.material_override.albedo_color = Color(0.4, 0.7, 1.0, 0.4)
			else:
				hd.material_override.albedo_color = HITBOX_WINDUP
			hd.visible = true
	_recent_skill_uses.append(current_skill_id)
	if _recent_skill_uses.size() > ANTI_STREAK_DEPTH:
		_recent_skill_uses.pop_front()
	print("[boss] %s windup skill=%s defensive=%s" % [name, String(current_skill_id), is_defensive])

func _enter_active() -> void:
	state = State.ACTIVE
	state_timer = skill_cast_time * 0.4
	_cast_skill(current_skill_id)
	if current_skill_id == &"parry_riposte_001":
		parry_cooldown = 1.5
	elif current_skill_id == &"esquivar_001":
		dodge_cooldown = 1.0
	elif current_skill_id == &"defenderse_001":
		defend_cooldown = 1.2
	if attack_area:
		attack_area.monitoring = true
		if hit_collision: hit_collision.disabled = false
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd:
			hd.material_override.albedo_color = HITBOX_ACTIVE
			hd.visible = true
	print("[boss] %s active skill=%s" % [name, String(current_skill_id)])

func _enter_recover() -> void:
	state = State.RECOVER
	state_timer = skill_recover_time
	if attack_area:
		attack_area.monitoring = false
		if hit_collision: hit_collision.disabled = true
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd: hd.visible = false


func _is_defensive_skill(sid: StringName) -> bool:
	return sid == &"defenderse_001" or sid == &"esquivar_001"



func _cast_skill(skill_id: StringName) -> void:
	if skill_id == &"":
		return
	if not use_skills:
		return
	var skill_path := "res://data/skills/%s.tres" % String(skill_id)
	var skill: Resource = load(skill_path)
	if skill == null:
		push_warning("[boss] %s skill %s not found" % [name, skill_path])
		return
	var original_resolver: Dictionary = skill.target_resolver
	var patched: Dictionary = original_resolver.duplicate(true)
	if _is_defensive_skill(skill_id):
		patched["kind"] = "self"
	elif String(patched.get("kind", "")) in ["aoe", "beam", "self_aoe", "nearest_npc_in_range"]:
		patched["kind"] = "boss_aoe"
		if not patched.has("params"):
			patched["params"] = {}
		if not (patched["params"] as Dictionary).has("position"):
			(patched["params"] as Dictionary)["position"] = "in_front_of_caster"
	else:
		patched["kind"] = "boss"
	_cast_atoms_directly(skill, patched)


func _cast_atoms_directly(skill: Resource, resolver: Dictionary) -> void:
	var targets: Array[Node] = []
	var kind_str: String = String(resolver.get("kind", "self"))
	if kind_str == "self":
		targets.append(self)
	elif kind_str == "boss":
		if is_instance_valid(target):
			targets.append(target)
	elif kind_str == "boss_aoe":
		var radius: float = float(resolver.get("params", {}).get("radius", 6.0))
		var center: Vector3 = target.global_position if is_instance_valid(target) else global_position
		var r2 := radius * radius
		for n in get_tree().get_nodes_in_group("bosses"):
			if not is_instance_valid(n) or not n is Node3D:
				continue
			if n == self:
				continue
			if (n as Node3D).global_position.distance_squared_to(center) <= r2:
				if n not in targets:
					targets.append(n)
		for n in get_tree().get_nodes_in_group("player"):
			if not is_instance_valid(n) or not n is Node3D:
				continue
			if (n as Node3D).global_position.distance_squared_to(center) <= r2:
				if n not in targets:
					targets.append(n)
	var ex_script: GDScript = load("res://scripts/skill/skill_executor.gd")
	if ex_script == null:
		push_warning("[boss] SkillExecutor script not found")
		return
	var ex: Node = ex_script.new()
	ex.caster = self
	var patched_skill: Resource = skill.duplicate()
	(patched_skill as Resource).set("target_resolver", resolver)
	ex.skill = patched_skill
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps:
		ex.progression = ps
	ex.set("__forced_targets", targets)
	_cast_with_forced_targets(ex, patched_skill, targets)
	ex.queue_free()


func _cast_with_forced_targets(ex: Node, skill: Resource, targets: Array[Node]) -> void:
	add_child(ex)
	if ex.has_method("_consume_cost"):
		ex._consume_cost()
	var cl_root: Node = Engine.get_main_loop().root.get_node_or_null("CombatLog")
	if cl_root and cl_root.has_method("log_event"):
		var caster_meta: Dictionary = {
			"caster": String(name),
			"skill_id": String(skill.id),
			"skill_name": String(skill.name),
			"category": String(skill.category),
			"type": String(skill.type),
		}
		if boss_data != null:
			caster_meta["boss_id"] = String(boss_data.id)
			caster_meta["behavior"] = String(boss_data.behavior)
		cl_root.log_event("skill_cast", caster_meta)
	if not skill or not "atoms" in skill:
		return
	for atom in skill.atoms:
		var atom_type_text: String = String(atom.get("type", ""))
		if atom_type_text == "trigger":
			EffectLibrary.apply_atom(ex, atom, ex.resolve_targets())
		else:
			EffectLibrary.apply_atom(ex, atom, targets)
	await get_tree().create_timer(0.1).timeout


func _pick_skill() -> StringName:
	return _pick_attack_skill()


func take_damage(amount: float, attacker: Node = null, element: StringName = &"physical") -> float:
	if state == State.DEAD:
		return 0.0
	var before_hp: float = hp
	var mult: float = float(damage_modifiers.get(element, 1.0)) if element in damage_modifiers else 1.0
	var final: float = super.take_damage(amount, attacker, element)
	var cl: Node = Engine.get_main_loop().root.get_node_or_null("CombatLog")
	if cl and cl.has_method("log_event"):
		cl.log_event("damage_taken", {
			"target": String(name),
			"target_boss_id": String(boss_data.id) if boss_data else "?",
			"source": String(attacker.name) if attacker and is_instance_valid(attacker) else "?",
			"amount_raw": float(amount),
			"amount_final": final,
			"element": String(element),
			"mult": mult,
			"hp": hp,
			"max_hp": max_hp,
		})
	print("[boss] %s hit dmg=%.1f (raw=%.1f elem=%s mult=%.2f) hp=%.1f" % [
		name, final, float(amount), element, mult, hp
	])
	boss_damaged.emit(final, hp)
	return final


func _die() -> void:
	if is_dying:
		return
	is_dying = true
	state = State.DEAD
	hp = 0.0
	if attack_area:
		attack_area.monitoring = false
		if hit_collision: hit_collision.disabled = true
		var hd: MeshInstance3D = attack_area.get_node_or_null("HitboxDebug")
		if hd: hd.visible = false
	if model:
		model.visible = false
	collision_layer = 0
	collision_mask = 0
	var boss_id_str: StringName = &""
	if boss_data:
		boss_id_str = boss_data.id
	var cl: Node = Engine.get_main_loop().root.get_node_or_null("CombatLog")
	if cl and cl.has_method("log_event"):
		cl.log_event("death", {
			"actor": String(name),
			"actor_boss_id": String(boss_id_str),
			"killed_by": String(target.name) if target and is_instance_valid(target) else "?",
		})
	print("[boss] %s DEAD id=%s" % [name, String(boss_id_str)])
	boss_killed.emit(boss_id_str)



func _dist_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	return global_position.distance_to(target.global_position)


func _flash() -> void:
	if not _base_mat:
		return
	var orig := _base_mat.albedo_color
	_base_mat.albedo_color = Color(1.0, 0.5, 0.2)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self) and _base_mat:
		_base_mat.albedo_color = orig


func _update_hp_label() -> void:
	if is_instance_valid(label_hp):
		label_hp.text = "%d/%d" % [int(max(0, hp)), int(max_hp)]
		if is_instance_valid(get_viewport().get_camera_3d()):
			var cam := get_viewport().get_camera_3d()
			label_hp.look_at(cam.global_position, Vector3.UP)
			label_hp.rotate_object_local(Vector3.UP, PI)
