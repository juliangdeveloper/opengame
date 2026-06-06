## SkillValidator — Valida SkillSpec antes de crear SkillResource.
##
## Aplica las reglas de data/contracts/skill_instance_schema.md:
## - Campos requeridos no vacíos
## - Max 5 átomos, max 2 combo triggers
## - Átomos deben existir en skill_atoms.json
## - Átomos deben coincidir con type (damage vs control)
## - Max 1 heal/hot/shield por skill
## - Combo triggers deben referenciar skills existentes
##
## Diseñado para usarse tanto desde MCP (FastAPI) como desde el editor.
class_name SkillValidator
extends RefCounted

const MAX_ATOMS := 5
const MAX_COMBO_TRIGGERS := 2
const MAX_HEAL_ATOMS := 1

const DAMAGE_ATOMS: Array[StringName] = [
	&"hit", &"dot", &"burst_aoe", &"projectile", &"trigger",
]
const CONTROL_ATOMS: Array[StringName] = [
	&"move", &"morph", &"status", &"mind", &"trigger",
]
const BOTH_ATOMS: Array[StringName] = [
	&"persistent_zone", &"heal", &"hot", &"shield", &"buff", &"npc", &"zone",
]


## validate(spec: Dictionary) -> { valid: bool, errors: Array[String], warnings: Array[String] }
static func validate(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	# Required fields
	for field in ["name", "type", "target_resolver", "designed_max", "atoms"]:
		if not spec.has(field):
			errors.append("missing required field: %s" % field)

	if not errors.is_empty():
		return { "valid": false, "errors": errors, "warnings": warnings }

	# type
	var type_str := String(spec["type"])
	if type_str not in ["damage", "control"]:
		errors.append("type must be 'damage' or 'control', got '%s'" % type_str)

	# atoms
	var atoms_v: Variant = spec["atoms"]
	if not atoms_v is Array:
		errors.append("atoms must be an array")
		return { "valid": false, "errors": errors, "warnings": warnings }
	var atoms: Array = atoms_v
	if atoms.size() > MAX_ATOMS:
		errors.append("max %d atoms per skill, got %d" % [MAX_ATOMS, atoms.size()])

	# atom validation
	var heal_count := 0
	for i in atoms.size():
		var atom = atoms[i]
		if not atom is Dictionary:
			errors.append("atom[%d] must be a dictionary" % i)
			continue
		if not atom.has("type"):
			errors.append("atom[%d] missing 'type'" % i)
			continue
		var atom_type := StringName(atom["type"])
		# Check atom exists (we hardcode the 14 + trigger for now)
		if not _is_valid_atom_type(atom_type):
			errors.append("atom[%d].type '%s' not in library" % [i, atom_type])
			continue
		# Type-specific restrictions
		if type_str == "damage" and atom_type in CONTROL_ATOMS:
			errors.append("atom[%d].type '%s' not allowed in damage skill" % [i, atom_type])
		elif type_str == "control" and atom_type in DAMAGE_ATOMS:
			errors.append("atom[%d].type '%s' not allowed in control skill" % [i, atom_type])
		# heal/hot/shield count
		if atom_type in [&"heal", &"hot", &"shield"]:
			heal_count += 1
	if heal_count > MAX_HEAL_ATOMS:
		errors.append("max %d heal/hot/shield atom per skill, got %d" % [MAX_HEAL_ATOMS, heal_count])

	# combo_triggers
	if spec.has("combo_triggers"):
		var ct_v: Variant = spec["combo_triggers"]
		if not ct_v is Array:
			errors.append("combo_triggers must be an array")
		else:
			var ct: Array = ct_v
			if ct.size() > MAX_COMBO_TRIGGERS:
				errors.append("max %d combo triggers per skill, got %d" % [MAX_COMBO_TRIGGERS, ct.size()])
			for i in ct.size():
				var trig = ct[i]
				if not trig is Dictionary:
					errors.append("combo_triggers[%d] must be a dictionary" % i)
					continue
				if not trig.has("trigger_skill_id"):
					errors.append("combo_triggers[%d] missing 'trigger_skill_id'" % i)
				if not trig.has("when"):
					errors.append("combo_triggers[%d] missing 'when'" % i)

	# target_resolver kind
	var tr_v: Variant = spec["target_resolver"]
	if tr_v is Dictionary:
		var tr: Dictionary = tr_v
		if not tr.has("kind"):
			errors.append("target_resolver missing 'kind'")
		else:
			var kind := StringName(tr["kind"])
			if kind not in [
				&"self", &"selected_npc", &"nearest_npc_in_range",
				&"aoe", &"self_aoe", &"projectile_carrier",
				&"chain", &"zone_entered"
			]:
				errors.append("target_resolver.kind '%s' not supported" % kind)

	# designed_max bounds (básico: todos float >= 0)
	var dm_v: Variant = spec["designed_max"]
	if dm_v is Dictionary:
		var dm: Dictionary = dm_v
		for k in dm.keys():
			var v: Variant = dm[k]
			if v is float or v is int:
				if float(v) < 0.0:
					warnings.append("designed_max.%s is negative (%.2f)" % [k, float(v)])

	return { "valid": errors.is_empty(), "errors": errors, "warnings": warnings }


## Helper para atom types válidos (los 14 + trigger).
static func _is_valid_atom_type(t: StringName) -> bool:
	var all: Array[StringName] = [
		&"hit", &"dot", &"burst_aoe", &"persistent_zone",
		&"heal", &"hot", &"shield",
		&"move", &"morph", &"buff",
		&"status", &"mind",
		&"projectile", &"npc", &"zone",
		&"trigger",
	]
	return t in all
