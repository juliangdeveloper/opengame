class_name MissionValidator
extends RefCounted

const VALID_PURPOSES := [&"teach_skill", &"teach_weapon"]
const VALID_MISSION_TYPES := [&"defeat_enemies", &"1v1", &"timed", &"reach_destination", &"survive", &"cast_skill_n"]


static func validate(spec: Dictionary) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var purpose: StringName = StringName(String(spec.get("purpose", "")))
	if purpose == &"":
		errors.append("purpose is required")
	elif purpose not in VALID_PURPOSES:
		errors.append("purpose must be one of %s" % str(VALID_PURPOSES))
	var target_id: StringName = StringName(String(spec.get("target_id", "")))
	if target_id == &"":
		errors.append("target_id is required")
	else:
		var exists := _target_exists(target_id, purpose)
		if not exists:
			errors.append("target_id '%s' not found in data/%s/" % [target_id, "skills" if purpose == &"teach_skill" else "weapons"])
	var mission_type: StringName = StringName(String(spec.get("mission_type", "defeat_enemies")))
	if mission_type not in VALID_MISSION_TYPES:
		errors.append("mission_type must be one of %s" % str(VALID_MISSION_TYPES))
	var title: String = String(spec.get("title", ""))
	if title.length() > 80:
		warnings.append("title exceeds 80 chars, will be truncated")
	if purpose == &"teach_weapon" and mission_type == &"cast_skill_n":
		warnings.append("cast_skill_n mission for teach_weapon is unusual (weapon skills don't have an element)")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"target_kind": &"skill" if purpose == &"teach_skill" else &"weapon" if purpose == &"teach_weapon" else &"",
	}


static func _target_exists(target_id: StringName, purpose: StringName) -> bool:
	var dir_path: String = "res://data/skills" if purpose == &"teach_skill" else "res://data/weapons"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res: Resource = load("%s/%s" % [dir_path, fname])
			if res != null and "id" in res and String(res.id) == String(target_id):
				return true
		fname = dir.get_next()
	dir.list_dir_end()
	return false
