## SkillExecutor — Nodo que ejecuta un SkillResource sobre un caster.
##
## Responsabilidades:
## 1. Recibe un SkillResource y un caster (CharacterBody3D).
## 2. Resuelve los targets vía TargetResolver.
## 3. Aplica cada átomo en orden vía EffectLibrary.
## 4. Maneja triggers (delay, on_hit, combo) y los invoca cuando corresponde.
## 5. Calcula el costo efectivo (stamina, cooldown, charge_time) vía Balance.
##
## Lifecycle:
##   var ex = SkillExecutor.new()
##   ex.skill = my_skill
##   ex.caster = player_node
##   add_child(ex)
##   ex.cast()
##
## Usa preloads en vez de class_name para que funcione tanto en modo
## normal (escena) como en --script (test headless).
extends Node

const SkillResource := preload("res://scripts/skill/skill_resource.gd")
const EffectLibrary := preload("res://scripts/skill/effect_library.gd")
const TargetResolver := preload("res://scripts/skill/target_resolver.gd")
const Balance := preload("res://scripts/skill/balance.gd")

signal skill_started(skill)
signal skill_finished(skill)
signal atom_applied(atom_type: StringName, target_count: int)
signal combo_triggered(then_skill_id: StringName)

## La skill que se está ejecutando (asignada antes de cast()).
var skill = null

## El nodo que castea (CharacterBody3D típicamente).
var caster: Node = null

## ProgressionState (para consultar allocations/proficiency).
## Asignado opcionalmente; si es null, usa defaults.
var progression: Node = null

## Estado interno
var _is_casting: bool = false
var _active_triggers: Array[Dictionary] = []
var _combo_triggers: Array[Dictionary] = []

## Último proyectil spawneado (para combo chain / carrier targets).
var last_projectile: Area3D = null


## Llama esto desde el owner (player.gd) cuando quiere castear la skill.
## Devuelve true si la skill se empezó, false si falló (no stamina, etc).
func cast() -> bool:
	if skill == null or caster == null:
		push_warning("[SkillExecutor] missing skill or caster")
		return false
	if _is_casting:
		return false

	# Verifica y consume el costo efectivo
	if not _can_cast():
		return false
	_consume_cost()

	_is_casting = true
	skill_started.emit(skill)
	print("[SkillExecutor] cast skill=%s" % skill.name)

	# Aplica cada átomo en orden
	for atom in skill.atoms:
		var atom_type := StringName(atom.get("type", ""))
		# Triggers con when=delay se manejan async vía EffectLibrary
		# Otros átomos se aplican directamente
		if atom_type == &"trigger":
			EffectLibrary.apply_atom(self, atom, resolve_targets())
		else:
			var targets := resolve_targets_for_atom(atom)
			EffectLibrary.apply_atom(self, atom, targets)
			atom_applied.emit(atom_type, targets.size())

	# Auto-destruir después de un breve delay (los DoTs ya están trackeados
	# en componentes, los triggers quedan registrados aquí).
	# Pero si hay triggers con delay, necesitamos esperar. Por simplicidad:
	# destruimos 0.1s después de aplicar átomos instantáneos.
	await get_tree().create_timer(0.1).timeout
	_is_casting = false
	skill_finished.emit(skill)
	return true


## Resuelve targets globales (sin atom específico). Usado por triggers.
func resolve_targets() -> Array[Node]:
	if skill == null:
		return []
	var kind_str := String(skill.target_resolver.get("kind", "self"))
	var params: Dictionary = skill.target_resolver.get("params", {})
	return TargetResolver.resolve(StringName(kind_str), caster, params, last_projectile)


## Resuelve targets específicos para un átomo. Si el átomo tiene
## applies_to_target="all_in_aoe" y el target_resolver es AOE, devuelve todos.
## Si es "primary", devuelve solo el primer target.
func resolve_targets_for_atom(atom: Dictionary) -> Array[Node]:
	var all := resolve_targets()
	var applies := String(atom.get("applies_to_target", "primary"))
	match applies:
		"all_in_aoe":
			return all
		"chain_target":
			return all  # TargetResolver ya devuelve la cadena
		"carrier":
			if last_projectile and is_instance_valid(last_projectile):
				return [last_projectile]
			return []
		_:
			# primary: primer target o self si no hay
			if all.is_empty():
				return [caster]
			return [all[0]]


## Costo efectivo para stats (lee de progression si está disponible).
func get_effective_stat(stat_name: String, params: Dictionary) -> float:
	# El "value" del átomo está en params[stat_name] o stats análogos.
	var designed: float = 0.0
	if params.has(stat_name):
		designed = float(params[stat_name])
	elif params.has("value"):
		designed = float(params["value"])
	if designed == 0.0:
		return 0.0

	# Si tenemos progression, calculamos el effective
	if progression and progression.has_method("get_effective_stat_for_skill"):
		var skill_id_v: StringName = skill.id if skill else &""
		return progression.call("get_effective_stat_for_skill", skill_id_v, stat_name, designed)
	# Sin progression: devolver el designed (lvl1 weakness NO se aplica)
	return designed


## Verifica si el caster tiene recursos para castear.
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


## Costo efectivo de un stat de costo (stamina, cooldown, charge_time).
func get_effective_cost(cost_name: String) -> float:
	if skill == null:
		return 0.0
	var designed: float = float(skill.costs.get(cost_name, 0.0))
	if designed <= 0.0:
		return 0.0
	# Para stamina, calculamos el costo efectivo basado en el daño efectivo
	# (más daño = más stamina). Para cooldown/charge_time también.
	var balance_mult: float = 1.0
	if progression and progression.has_method("get_skill_power_ratio"):
		var skill_id_v: StringName = skill.id if skill else &""
		balance_mult = progression.call("get_skill_power_ratio", skill_id_v)
	# Cost scaling: a bajo poder, costo bajo; a alto poder, costo total
	if Balance.is_inverted(StringName(cost_name)):
		# Inverted (menor = mejor): costo = diseñado * (1 - power_ratio)^0.5 con floor
		var cost_min: float = designed * Balance.DEFAULT_COST_MIN_RATIO
		var scaled: float = designed * pow(1.0 - balance_mult, Balance.DEFAULT_COST_INVERSE_EXPONENT)
		return max(cost_min, scaled)
	# Normal: costo escala con poder
	var cost_min2: float = designed * Balance.DEFAULT_COST_MIN_RATIO
	return lerpf(cost_min2, designed, balance_mult)


# === Triggers ===

func register_trigger(when: String, params: Dictionary, atom: Dictionary) -> void:
	_active_triggers.append({
		"when": when,
		"params": params,
		"atom": atom,
	})
	# Conectarse a las señales del caster si es player
	if when == "on_take_damage" and caster and caster.has_signal("damaged"):
		caster.damaged.connect(_on_caster_damaged.bind(when))
	elif when == "on_health_below":
		# Polling vía _physics_process
		set_physics_process(true)


func register_combo_trigger(then_skill_id: String, params: Dictionary, atom: Dictionary) -> void:
	_combo_triggers.append({
		"then_skill_id": then_skill_id,
		"params": params,
		"atom": atom,
	})


## Llamado cuando se cumple una condición de trigger.
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
