extends SceneTree

# migrate_bosses_to_character_resource.gd
# Convierte data/contracts/bosses.json a archivos CharacterResource.tres
# individuales en data/characters/bosses/<id>.tres.
#
# Esto es la prueba de que bosses son 100% data-driven — el mismo
# schema que el player, sin código de boss.

const CharacterResourceScript := preload("res://scripts/character_resource.gd")


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var json_path: String = "res://data/contracts/bosses.json"
	var out_dir: String = "res://data/characters/bosses/"

	# Ensure output directory exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open %s" % json_path)
		quit(1)
		return
	var raw: String = file.get_as_text()
	file.close()
	var data: Dictionary = JSON.parse_string(raw)
	if data == null or not data.has("bosses"):
		push_error("Invalid bosses.json")
		quit(1)
		return

	var bosses: Array = data["bosses"]
	print("=== Migrating %d bosses ===" % bosses.size())

	var ok: int = 0
	for b in bosses:
		var res: Resource = _boss_to_resource(b)
		var out_path: String = out_dir + String(b.id) + ".tres"
		var err: int = ResourceSaver.save(res, out_path)
		if err != OK:
			push_error("Failed to save %s (err=%d)" % [out_path, err])
			continue
		# Re-load to verify roundtrip
		var reloaded: Resource = load(out_path)
		if reloaded == null:
			push_error("Failed to reload %s" % out_path)
			continue
		_assert_eq(float(reloaded.max_hp), float(b.max_hp),
			"roundtrip max_hp for %s" % String(b.id))
		_assert_eq(reloaded.ai_controlled, true,
			"boss ai_controlled=true for %s" % String(b.id))
		_assert_eq(reloaded.skill_ids.size(), b.skill_ids.size(),
			"roundtrip skill_ids count for %s" % String(b.id))
		_assert_eq(reloaded.weapon_id, StringName(b.weapon_id),
			"roundtrip weapon_id for %s" % String(b.id))
		_assert_eq(int(reloaded.reward_skill_points), int(b.reward_skill_points),
			"roundtrip reward_skill_points for %s" % String(b.id))
		ok += 1

	print("\n=== Migrated %d/%d bosses to %s ===" % [ok, bosses.size(), out_dir])
	quit(0)


func _boss_to_resource(b: Dictionary) -> Resource:
	var res: Resource = CharacterResourceScript.new()
	res.id = StringName(b.id)
	res.display_name = String(b.display_name)
	res.description = String(b.get("description", ""))
	res.inspiration = String(b.get("inspiration", ""))
	res.ai_controlled = true
	res.max_hp = float(b.max_hp)
	res.max_stamina = 100.0  # default for bosses
	res.move_speed = 2.6
	res.turn_speed = 6.0
	res.detection_range = 12.0
	res.attack_range = 8.0  # bosses castean a rango
	res.lose_range = 18.0
	res.windup_duration = 0.55
	res.active_duration = 0.18
	res.recover_duration = 1.5  # bosses tienen cast más lento
	res.stagger_duration = 1.30
	res.respawn_delay = 999.0  # bosses NO respawnean
	res.weapon_id = StringName(b.weapon_id)
	var skill_ids: Array[StringName] = []
	for s in b.skill_ids:
		skill_ids.append(StringName(s))
	res.skill_ids = skill_ids
	var skill_weights: Array[float] = []
	for w in b.skill_weights:
		skill_weights.append(float(w))
	res.skill_weights = skill_weights
	# Damage modifiers
	var mods: Dictionary = {}
	if b.has("weakness_element") and b.weakness_element != &"":
		mods[StringName(b.weakness_element)] = float(b.weakness_mult)
	if b.has("resistance_element") and b.resistance_element != &"":
		mods[StringName(b.resistance_element)] = float(b.resistance_mult)
	res.damage_modifiers = mods
	res.behavior = String(b.behavior)
	res.aggression = float(b.aggression)
	res.preferred_range = StringName(b.preferred_range)
	res.reaction_time_sec = float(b.reaction_time_sec)
	res.reward_skill_points = int(b.reward_skill_points)
	return res


var _passes: int = 0
var _fails: int = 0

func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passes += 1
		print("  [PASS] %s" % label)
	else:
		_fails += 1
		print("  [FAIL] %s → expected %s, got %s" % [label, str(expected), str(actual)])
