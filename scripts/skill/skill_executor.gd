extends Node

const SkillResource := preload("res://scripts/skill/skill_resource.gd")
const EffectLibrary := preload("res://scripts/skill/effect_library.gd")
const TargetResolver := preload("res://scripts/skill/target_resolver.gd")
const Balance := preload("res://scripts/skill/balance.gd")

signal skill_started(skill)
signal skill_finished(skill)
signal atom_applied(atom_type: StringName, target_count: int)
signal combo_triggered(then_skill_id: StringName)

var skill = null

var caster: Node = null

var progression: Node = null

var _is_casting: bool = false
var _active_triggers: Array[Dictionary] = []
var _combo_triggers: Array[Dictionary] = []

var last_projectile: Area3D = null


func cast() -> bool:
	if skill == null or caster == null:
		push_warning("[SkillExecutor] missing skill or caster")
		return false
	if _is_casting:
		return false

	if not _can_cast():
		return false
	_consume_cost()

	_is_casting = true
	skill_started.emit(skill)
	print("[SkillExecutor] cast skill=%s" % skill.name)
	var cl: Node = Engine.get_main_loop().root.get_node_or_null("CombatLog")
	if cl and cl.has_method("log_event"):
		var caster_id: String = String(caster.name) if caster else "?"
		var caster_meta: Dictionary = {
			"caster": caster_id,
			"skill_id": String(skill.id),
			"skill_name": String(skill.name),
			"category": String(skill.category),
			"type": String(skill.type),
		}
		if caster and "boss_data" in caster and caster.boss_data != null:
			caster_meta["boss_id"] = String(caster.boss_data.id)
			caster_meta["behavior"] = String(caster.boss_data.behavior)
		cl.log_event("skill_cast", caster_meta)

	for atom in skill.atoms:
		var atom_type := StringName(atom.get("type", ""))
		if atom_type == &"trigger":
			EffectLibrary.apply_atom(self, atom, resolve_targets())
		else:
			var targets := resolve_targets_for_atom(atom)
			EffectLibrary.apply_atom(self, atom, targets)
			atom_applied.emit(atom_type, targets.size())

	await get_tree().create_timer(0.1).timeout
	_is_casting = false
	skill_finished.emit(skill)
	return true


func resolve_targets() -> Array[Node]:
	if skill == null:
		return []
	var kind_str := String(skill.target_resolver.get("kind", "self"))
	var params: Dictionary = skill.target_resolver.get("params", {})
	return TargetResolver.resolve(StringName(kind_str), caster, params, last_projectile)


func resolve_targets_for_atom(atom: Dictionary) -> Array[Node]:
	var all := resolve_targets()
	var applies := String(atom.get("applies_to_target", "primary"))
	match applies:
		"all_in_aoe":
			return all
		"chain_target":
			return all
		"carrier":
			if last_projectile and is_instance_valid(last_projectile):
				return [last_projectile]
			return []
		_:
			if all.is_empty():
				return [caster]
			return [all[0]]


func get_effective_stat(stat_name: String, params: Dictionary) -> float:
	var designed: float = 0.0
	if params.has(stat_name):
		designed = float(params[stat_name])
	elif params.has("value"):
		designed = float(params["value"])
	if designed == 0.0:
		return 0.0

	if progression and progression.has_method("get_effective_stat_for_skill"):
		var skill_id_v: StringName = skill.id if skill else &""
		return progression.call("get_effective_stat_for_skill", skill_id_v, stat_name, designed)
	return designed


func _can_cast() -> bool:
	if not caster:
		return true
	var stamina_cost: float = get_effective_cost("stamina")
	if stamina_cost > 0.0 and "stamina" in caster:
		if float(caster.stamina) < stamina_cost:
			print("[SkillExecutor] not enough stamina (%.1f < %.1f)" % [caster.stamina, stamina_cost])
			return false
	return true


func _consume_cost() -> void:
	if not caster:
		return
	var stamina_cost: float = get_effective_cost("stamina")
	if stamina_cost > 0.0 and "stamina" in caster:
		caster.stamina = max(0.0, float(caster.stamina) - stamina_cost)


func get_effective_cost(cost_name: String) -> float:
	if skill == null:
		return 0.0
	var designed: float = float(skill.costs.get(cost_name, 0.0))
	if designed <= 0.0:
		return 0.0
	var balance_mult: float = 1.0
	if progression and progression.has_method("get_skill_power_ratio"):
		var skill_id_v: StringName = skill.id if skill else &""
		balance_mult = progression.call("get_skill_power_ratio", skill_id_v)
	if Balance.is_inverted(StringName(cost_name)):
		var cost_min: float = designed * Balance.DEFAULT_COST_MIN_RATIO
		var scaled: float = designed * pow(1.0 - balance_mult, Balance.DEFAULT_COST_INVERSE_EXPONENT)
		return max(cost_min, scaled)
	var cost_min2: float = designed * Balance.DEFAULT_COST_MIN_RATIO
	return lerpf(cost_min2, designed, balance_mult)



func register_trigger(when: String, params: Dictionary, atom: Dictionary) -> void:
	_active_triggers.append({
		"when": when,
		"params": params,
		"atom": atom,
	})
	if when == "on_take_damage" and caster and caster.has_signal("damaged"):
		caster.damaged.connect(_on_caster_damaged.bind(when))
	elif when == "on_health_below":
		set_physics_process(true)


func register_combo_trigger(then_skill_id: String, params: Dictionary, atom: Dictionary) -> void:
	_combo_triggers.append({
		"then_skill_id": then_skill_id,
		"params": params,
		"atom": atom,
	})


func notify_event(event_name: String, _context: Dictionary = {}) -> void:
	for trig in _active_triggers:
		if trig.when == event_name:
			_execute_then_effect(trig.params, trig.atom)
	for ct in _combo_triggers:
		if ct.params.get("when", "") == event_name:
			_fire_combo(StringName(ct.then_skill_id), ct.params, ct.atom)


func _execute_then_effect(params: Dictionary, atom: Dictionary) -> void:
	var then_eff: String = String(params.get("then_effect", ""))
	if then_eff == "":
		return
	for a in skill.atoms:
		if a.get("id", "") == then_eff or String(a.get("type", "")) == then_eff:
			EffectLibrary.apply_atom(self, a, resolve_targets())
			return


func _fire_combo(then_skill_id: StringName, _params: Dictionary, _atom: Dictionary) -> void:
	if not progression:
		return
	combo_triggered.emit(then_skill_id)
	if progression.has_method("trigger_skill"):
		progression.call("trigger_skill", then_skill_id, caster)


func _on_caster_damaged(_amount: float, _final: float, _blocked: bool, when: String) -> void:
	notify_event(when)


func _physics_process(_delta: float) -> void:
	if not caster:
		return
	if "hp" not in caster or "max_hp" not in caster:
		return
	var hp: float = float(caster.hp)
	var max_hp: float = float(caster.max_hp)
	var ratio: float = hp / max_hp if max_hp > 0 else 1.0
	for trig in _active_triggers:
		if trig.when == "on_health_below":
			var threshold_str: String = String(trig.params.get("condition", "0.3"))
			var threshold: float = float(threshold_str) if threshold_str.is_valid_float() else 0.3
			if ratio < threshold:
				_execute_then_effect(trig.params, trig.atom)
