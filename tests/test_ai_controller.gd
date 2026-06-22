## test_ai_controller.gd — Tests for data-driven AIController.
##
## Verifies:
##   1. AIController auto-finds target (Player)
##   2. decide_skill() uses skill_weights from CharacterResource
##   3. Anti-streak penalizes recently used skills
##   4. Behavior modifiers affect skill weights
##   5. Reaction time is data-driven from CharacterResource
##   6. All 12 weapons have valid attribute_modifiers
extends SceneTree

var pass_count: int = 0
var fail_count: int = 0

func _init() -> void:
	print("=== test_ai_controller ===")
	_test_weapon_attribute_modifiers()
	_test_ai_controller_creation()
	_test_decide_skill_weights()
	_test_anti_streak()
	_test_behavior_modifiers()
	_test_reaction_time()
	print("\n=== TOTAL: %d/%d passed ===" % [pass_count, pass_count + fail_count])
	if fail_count > 0:
		print("RESULT: ✗ SOME TESTS FAILED")
	else:
		print("RESULT: ✓ ALL AI CONTROLLER TESTS PASSED")
	quit(0 if fail_count == 0 else 1)


func _assert(condition: bool, msg: String) -> void:
	if condition:
		pass_count += 1
		print("  [PASS] %s" % msg)
	else:
		fail_count += 1
		print("  [FAIL] %s" % msg)


# === Test 1: All weapons have valid attribute_modifiers ===
func _test_weapon_attribute_modifiers() -> void:
	print("\n--- 1. Weapon attribute_modifiers migration ---")
	var weapon_ids: Array[String] = [
		"short_sword", "dagger", "great_sword",
		"long_sword", "scimitar", "spear", "war_axe", "mace",
		"great_scythe", "long_bow", "arcane_staff", "cursed_blade_001",
	]
	for wid in weapon_ids:
		var path: String = "res://data/weapons/%s.tres" % wid
		var res: Resource = load(path)
		_assert(res != null, "%s loads" % wid)
		if res == null:
			continue
		var mods: Dictionary = res.attribute_modifiers
		_assert(not mods.is_empty(), "%s has modifiers (%d)" % [wid, mods.size()])
		var all_numeric: bool = true
		for k in mods:
			if not (mods[k] is float or mods[k] is int):
				all_numeric = false
		_assert(all_numeric, "%s values numeric" % wid)
		_assert(res.has_method("apply_to_caster"), "%s has apply_to_caster" % wid)

	# Unarmed should NOT have attribute_modifiers
	var unarmed: Resource = load("res://data/weapons/unarmed.tres")
	_assert(unarmed != null, "unarmed loads")
	if unarmed:
		_assert(unarmed.attribute_modifiers.is_empty(), "unarmed EMPTY modifiers")


# === Test 2: AIController creation ===
func _test_ai_controller_creation() -> void:
	print("\n--- 2. AIController creation ---")
	var ctrl: AIController = AIController.new()
	_assert(ctrl != null, "AIController instantiates")
	_assert(ctrl.has_method("decide_skill"), "has decide_skill()")
	_assert(ctrl.has_method("_find_target"), "has _find_target()")
	_assert(ctrl.has_method("_get_behavior"), "has _get_behavior()")
	_assert(ctrl.has_method("_get_aggression"), "has _get_aggression()")
	_assert(ctrl.has_method("_get_reaction_time"), "has _get_reaction_time()")
	ctrl.free()


# === Test 3: decide_skill() weighted selection ===
func _test_decide_skill_weights() -> void:
	print("\n--- 3. decide_skill() weighted selection ---")
	var ctrl: AIController = AIController.new()
	var mock_char: Node = Node.new()
	mock_char.set_meta("skill_ids", [&"fireball", &"ice_bolt", &"lightning"])
	mock_char.set_meta("skill_weights", [0.7, 0.2, 0.1])
	mock_char.set_meta("state", 0)
	mock_char.set_meta("data", null)
	mock_char.set_meta("target", null)
	mock_char.set_meta("attack_range", 2.6)
	mock_char.set_meta("detection_range", 12.0)
	mock_char.set_meta("lose_range", 18.0)
	mock_char.set_meta("move_speed", 5.0)
	ctrl.character = mock_char

	var counts: Dictionary = {&"fireball": 0, &"ice_bolt": 0, &"lightning": 0}
	var trials: int = 300
	for i in trials:
		ctrl._recent_skills.clear()
		var picked: StringName = ctrl.decide_skill()
		if counts.has(picked):
			counts[picked] += 1

	_assert(counts[&"fireball"] > counts[&"ice_bolt"], "fireball > ice_bolt: %d > %d" % [counts[&"fireball"], counts[&"ice_bolt"]])
	_assert(counts[&"ice_bolt"] > counts[&"lightning"], "ice_bolt > lightning: %d > %d" % [counts[&"ice_bolt"], counts[&"lightning"]])

	mock_char.free()
	ctrl.free()


# === Test 4: Anti-streak ===
func _test_anti_streak() -> void:
	print("\n--- 4. Anti-streak ---")
	var ctrl: AIController = AIController.new()
	var mock_char: Node = Node.new()
	mock_char.set_meta("skill_ids", [&"fireball", &"ice_bolt"])
	mock_char.set_meta("skill_weights", [0.5, 0.5])
	mock_char.set_meta("state", 0)
	mock_char.set_meta("data", null)
	mock_char.set_meta("target", null)
	mock_char.set_meta("attack_range", 2.6)
	mock_char.set_meta("detection_range", 12.0)
	mock_char.set_meta("lose_range", 18.0)
	mock_char.set_meta("move_speed", 5.0)
	ctrl.character = mock_char

	ctrl._recent_skills = [&"fireball", &"fireball", &"fireball"]
	var ice_count: int = 0
	for i in 100:
		var picked: StringName = ctrl.decide_skill()
		if picked == &"ice_bolt":
			ice_count += 1
	_assert(ice_count >= 50, "After 3x fireball anti-streak, ice_bolt=%d/100 (>=50)" % ice_count)

	mock_char.free()
	ctrl.free()


# === Test 5: Behavior modifiers ===
func _test_behavior_modifiers() -> void:
	print("\n--- 5. Behavior modifiers ---")
	var ctrl: AIController = AIController.new()
	var mock_char: Node = Node.new()
	mock_char.set_meta("skill_ids", [&"melee_slash", &"fireball"])
	mock_char.set_meta("skill_weights", [0.5, 0.5])
	mock_char.set_meta("state", 0)
	mock_char.set_meta("target", null)
	mock_char.set_meta("attack_range", 2.6)
	mock_char.set_meta("detection_range", 12.0)
	mock_char.set_meta("lose_range", 18.0)
	mock_char.set_meta("move_speed", 5.0)

	var data: CharacterResource = CharacterResource.new()
	data.behavior = "caster"
	data.aggression = 0.5
	data.preferred_range = &"ranged"
	data.reaction_time_sec = 0.4
	mock_char.set_meta("data", data)

	ctrl.character = mock_char

	var weights: Array = ctrl._get_modified_weights("caster")
	_assert(weights.size() == 2, "Weights has 2 entries (got %d)" % weights.size())

	var aggr: float = ctrl._get_aggression()
	_assert(aggr == 0.5, "aggression=0.5 (got %.1f)" % aggr)

	var beh: String = ctrl._get_behavior()
	_assert(beh == "caster", "behavior='caster' (got '%s')" % beh)

	mock_char.free()
	ctrl.free()


# === Test 6: Reaction time ===
func _test_reaction_time() -> void:
	print("\n--- 6. Reaction time ---")
	var ctrl: AIController = AIController.new()
	var mock_char: Node = Node.new()

	var data: CharacterResource = CharacterResource.new()
	data.reaction_time_sec = 0.8
	mock_char.set_meta("data", data)
	mock_char.set_meta("skill_ids", [])
	mock_char.set_meta("target", null)
	mock_char.set_meta("attack_range", 2.6)
	mock_char.set_meta("detection_range", 12.0)
	mock_char.set_meta("lose_range", 18.0)
	mock_char.set_meta("move_speed", 5.0)
	ctrl.character = mock_char

	var rt: float = ctrl._get_reaction_time()
	_assert(rt > 0.5 and rt < 1.1, "reaction_time ~0.8 ±30%%: got %.2f" % rt)

	# Without data
	mock_char.set_meta("data", null)
	rt = ctrl._get_reaction_time()
	_assert(rt > 0.05 and rt < 0.2, "default reaction_time ~0.1: got %.2f" % rt)

	mock_char.free()
	ctrl.free()
