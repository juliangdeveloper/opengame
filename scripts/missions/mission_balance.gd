## MissionBalance — calcula config de misión (enemigos, rewards, modifiers).
##
## Toma el target_id, purpose y difficulty; devuelve un dict con todo lo
## computado por el juego. El LLM no participa en este cálculo.
##
## Tabla de dificultad: data/contracts/mission_balance.json
## Damage modifiers:
##   - teach_skill: enemy vulnerable al element de la skill, resistente a todo lo demás (incluso physical)
##   - teach_weapon: enemy vulnerable a physical, resistente a todos los elementos
##
## Esto FUERZA al jugador a usar el skill/arma siendo enseñada, porque
## todo lo demás hace daño ínfimo.
class_name MissionBalance
extends RefCounted

const BalanceConfigPath := "res://data/contracts/mission_balance.json"
const Elements := preload("res://scripts/skill/elements.gd")

## Cache del JSON
static var _config_cache: Dictionary = {}


## Carga el JSON de balance.
static func _load_config() -> Dictionary:
	if not _config_cache.is_empty():
		return _config_cache
	var f: FileAccess = FileAccess.open(BalanceConfigPath, FileAccess.READ)
	if f == null:
		push_error("[MissionBalance] cannot open %s" % BalanceConfigPath)
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		push_error("[MissionBalance] invalid JSON in %s" % BalanceConfigPath)
		return {}
	_config_cache = parsed
	return _config_cache


## Resetea el cache (útil en tests).
static func reset_cache() -> void:
	_config_cache.clear()


## Devuelve la fila de dificultad (1..5) o {} si inválida.
static func get_difficulty_row(difficulty: int) -> Dictionary:
	var cfg: Dictionary = _load_config()
	var diffs: Dictionary = cfg.get("difficulty", {})
	var key := str(difficulty)
	if not diffs.has(key):
		return {}
	return diffs[key]


## Devuelve el skill resource para un skill_id (o null).
static func _find_skill(skill_id: StringName) -> Resource:
	var dir: DirAccess = DirAccess.open("res://data/skills")
	if dir == null:
		return null
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res: Resource = load("res://data/skills/%s" % fname)
			if res != null and "id" in res and String(res.id) == String(skill_id):
				return res
		fname = dir.get_next()
	dir.list_dir_end()
	return null


## Devuelve el weapon resource para un weapon_id (o null).
static func _find_weapon(weapon_id: StringName) -> Resource:
	var dir: DirAccess = DirAccess.open("res://data/weapons")
	if dir == null:
		return null
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res: Resource = load("res://data/weapons/%s" % fname)
			if res != null and "id" in res and String(res.id) == String(weapon_id):
				return res
		fname = dir.get_next()
	dir.list_dir_end()
	return null


## Determina el "elemento objetivo" de la skill — el que el enemigo será
## vulnerable. Inspecciona los atoms y devuelve el primer element presente.
## Default: "physical" para skills sin element explícito.
##
## Busca en:
##   - atom.params.element
##   - atom.params.damage_type
##   - atom.params.then_params.element (triggers anidados)
##   - atom.params.then_params.damage_type
static func _infer_skill_element(skill: Resource) -> StringName:
	if skill == null or not "atoms" in skill or skill.atoms == null:
		return &"physical"
	for atom in skill.atoms:
		if not atom is Dictionary:
			continue
		var params: Dictionary = atom.get("params", {})
		var elem: StringName = StringName(String(params.get("element", "")))
		if elem != &"":
			return elem
		var dtype: StringName = StringName(String(params.get("damage_type", "")))
		if dtype != &"" and dtype != &"true":  # "true" es marcador de one-shot kill, no element
			return dtype
		# Trigger anidado: then_params
		var then_params: Dictionary = params.get("then_params", {})
		if not then_params.is_empty():
			var t_elem: StringName = StringName(String(then_params.get("element", "")))
			if t_elem != &"":
				return t_elem
			var t_dtype: StringName = StringName(String(then_params.get("damage_type", "")))
			if t_dtype != &"" and t_dtype != &"true":
				return t_dtype
	return &"physical"


## Computa los damage_modifiers que el enemigo tendrá.
##
## teach_skill(target_elem):  target_elem = vulnerable, todo lo demás (incl. physical) = resistente
## teach_weapon:              physical = vulnerable, todo lo demás (los 9 elementos) = resistente
##
## difficulty escala la strength: a mayor dificultad, más extremo el
## contraste entre vulnerable y resistente.
static func compute_damage_modifiers(purpose: StringName, target_element: StringName, difficulty: int) -> Dictionary:
	var row: Dictionary = get_difficulty_row(difficulty)
	var rs: float = float(row.get("resistance_strength", 0.5))
	# other = 1.0 - 0.8 * rs (cap 0.2)
	var other_mult: float = maxf(0.2, 1.0 - 0.8 * rs)
	# target = 1.5 + 0.5 * rs (max 2.0)
	var target_mult: float = 1.5 + 0.5 * rs
	var mods: Dictionary = {}
	for elem_dict in Elements.ELEMENTS:
		var eid: StringName = StringName(String(elem_dict.get("id", "")))
		if eid == &"":
			continue
		if purpose == &"teach_skill" and eid == target_element:
			mods[eid] = target_mult
		elif purpose == &"teach_weapon" and eid == &"physical":
			mods[eid] = target_mult
		else:
			mods[eid] = other_mult
	return mods


## compute_config(target_id, purpose, difficulty, mission_type) -> Dictionary
##
## Devuelve un dict con TODO lo que una misión necesita para estar READY:
##   - enemy_type, enemy_count, enemy_hp_mult
##   - damage_modifiers {element: mult}
##   - rewards {skill_points, proficiency}
##   - time_limit_sec
##
## Si difficulty < 1, devuelve {}.
static func compute_config(target_id: StringName, purpose: StringName, difficulty: int, mission_type: StringName) -> Dictionary:
	if difficulty < 1 or difficulty > 5:
		return {}
	var row: Dictionary = get_difficulty_row(difficulty)
	if row.is_empty():
		return {}
	var target_element: StringName = &"physical"
	if purpose == &"teach_skill":
		var skill: Resource = _find_skill(target_id)
		if skill == null:
			return {"error": "skill not found: %s" % target_id}
		target_element = _infer_skill_element(skill)
	elif purpose == &"teach_weapon":
		var weapon: Resource = _find_weapon(target_id)
		if weapon == null:
			return {"error": "weapon not found: %s" % target_id}
		target_element = &"physical"  # weapons son physical
	else:
		return {"error": "unknown purpose: %s" % purpose}
	var enemy_count: int = int(row.get("enemy_count", 1))
	# mission_type overrides
	if mission_type == &"1v1":
		enemy_count = 1
	elif mission_type == &"survive":
		enemy_count = int(row.get("enemy_count", 1))  # sobrevive rodeado de enemigos
	elif mission_type == &"reach_destination":
		enemy_count = max(1, int(row.get("enemy_count", 1)) - 1)  # un poco menos para que sea viable llegar
	elif mission_type == &"cast_skill_n":
		enemy_count = 3  # enemy_count se reusa para "veces a castear"
	return {
		"enemy_type": &"saibaman",
		"enemy_count": enemy_count,
		"enemy_hp_mult": float(row.get("enemy_hp_mult", 1.0)),
		"time_limit_sec": float(row.get("time_limit_sec", 0.0)),
		"damage_modifiers": compute_damage_modifiers(purpose, target_element, difficulty),
		"target_element": target_element,
		"rewards": {
			"skill_points": int(row.get("skill_points", 1)),
			"proficiency": int(row.get("proficiency", 0)),
		},
		"difficulty_label": String(row.get("label", "?")),
	}
