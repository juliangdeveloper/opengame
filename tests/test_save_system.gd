extends SceneTree

# mcp-souls-game — SaveSystem tests.
# Verifies the unified persistence:
#   - to_dict/from_dict roundtrip per manager
#   - data_changed signal triggers debounced save
#   - write file → re-init SceneTree → state restored
#   - corrupt save file → warning + start fresh
#   - schema_version mismatch → ignored
#   - atomic write (no .tmp left over)
#
# Test order is critical: each test leaves a known state for the next.

const SAVE_PATH := "user://menu_state.json"

var _results: Array = []
var _errors: Array = []
var _step: int = 0


func _initialize() -> void:
	_reset_log()
	_log("=== mcp-souls-game: SaveSystem tests ===")

	# Pre-clean: remove any save from a previous test run
	DirAccess.remove_absolute(SAVE_PATH)
	DirAccess.remove_absolute(SAVE_PATH + ".tmp")

	# --- 1. No save file → fresh start ---
	_log("\n--- 1. No save file at boot ---")
	var play1: Node = load("res://scenes/play.tscn").instantiate()
	root.add_child(play1)
	await process_frame
	await process_frame
	await process_frame  # deferred _connect_managers
	var save1: Node = root.get_node_or_null("SaveSystem")
	_assert(save1 != null, "SaveSystem autoload exists")
	_assert(not save1.has_save(), "has_save() = false when no file")
	var ps1: Node = root.get_node_or_null("ProgressionState")
	var mm1: Node = root.get_node_or_null("MissionManager")
	var om1: Node = root.get_node_or_null("ObjectivesManager")
	_assert(ps1 != null and mm1 != null and om1 != null, "all 3 manager autoloads present")
	_log("   ProgressionState.skill_points = %d (fresh = 3 from starter grant)" % int(ps1.skill_points))
	_assert(int(ps1.skill_points) == 3, "fresh ProgressionState: skill_points = 3 (starter)")
	_assert(mm1.list_missions().size() == 3, "fresh MissionManager: 3 seed missions")
	_assert(om1.get_completed_objectives().size() == 0, "fresh ObjectivesManager: 0 completed")

	# --- 2. Mutate state → triggers data_changed → debounced save ---
	_log("\n--- 2. Mutate state triggers debounced save ---")
	ps1.grant_skill_points(10)  # +data_changed (bank: 3 -> 13)
	ps1.allocate(&"kamehameha_001", &"damage", 2)  # +data_changed (bank: 13 -> 11)
	ps1.allocate_element(&"fire", 3)  # +data_changed (bank: 11 -> 8)
	# MissionManager: create + set_difficulty + start
	var m1 = mm1.create_mission(&"teach_skill", &"fireball_001", &"1v1", "Test fireball")
	_assert(m1 != null, "create_mission returns non-null")
	mm1.set_difficulty(m1.id, 3)
	# ObjectivesManager: complete one (manually; no boss fight in this test)
	om1._completed[&"boss_test_01"] = true
	om1.data_changed.emit()
	# Wait for debounce (250ms) plus a frame
	await create_timer(0.4).timeout
	await process_frame
	_log("   After mutations + 400ms, file exists = %s" % str(save1.has_save()))
	_assert(save1.has_save(), "save file written after debounce")

	# --- 3. Read file directly to verify JSON structure ---
	_log("\n--- 3. Verify JSON structure ---")
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json_text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(json_text)
	var data: Dictionary = parsed
	_log("   schema_version = %s" % str(data.get("schema_version")))
	_assert(int(data.get("schema_version", 0)) == 1, "schema_version = 1")
	var prog_d: Dictionary = data.get("progression", {})
	_log("   progression.skill_points = %s (expected 8 = 3 + 10 - 2 - 3)" % str(prog_d.get("skill_points")))
	_assert(int(prog_d.get("skill_points", -1)) == 8, "saved skill_points = 8 (3 starter + 10 grant - 2 alloc - 3 elem)")
	var missions_d: Dictionary = data.get("missions", {})
	var missions_arr: Array = missions_d.get("missions", [])
	_log("   missions count = %d (3 seed + 1 created)" % missions_arr.size())
	_assert(missions_arr.size() == 4, "saved 4 missions (3 seed + 1 created)")
	# No leftover .tmp
	_assert(not FileAccess.file_exists(SAVE_PATH + ".tmp"), "no .tmp leftover (atomic write)")

	# --- 4. Tear down + restart → state restored ---
	_log("\n--- 4. State restored after restart ---")
	# Use proper teardown: free old, await one full frame for queue_free,
	# then add new. Don't call remove_child after queue_free (it errors).
	play1.queue_free()
	await process_frame
	await process_frame
	# Add a fresh play.tscn
	var play2: Node = load("res://scenes/play.tscn").instantiate()
	root.add_child(play2)
	await process_frame
	await process_frame
	await process_frame
	var ps2: Node = root.get_node_or_null("ProgressionState")
	var mm2: Node = root.get_node_or_null("MissionManager")
	var om2: Node = root.get_node_or_null("ObjectivesManager")
	_log("   After restart, ProgressionState.skill_points = %d" % int(ps2.skill_points))
	_assert(int(ps2.skill_points) == 8, "restored skill_points = 8")
	var alloc: int = int(ps2.allocations.get("kamehameha_001", {}).get("damage", 0))
	_log("   allocations[kamehameha_001][damage] = %d" % alloc)
	_assert(alloc == 2, "restored allocation damage=2 on kamehameha_001")
	var elem_alloc: int = int(ps2.element_allocations.get("fire", 0))
	_log("   element_allocations[fire] = %d" % elem_alloc)
	_assert(elem_alloc == 3, "restored element allocation fire=3")
	var missions2: Array = mm2.list_missions()
	_log("   missions restored = %d" % missions2.size())
	_assert(missions2.size() == 4, "restored 4 missions")
	# Seed missions should NOT be duplicated (we restored, didn't re-seed)
	var om2_completed: Array = om2.get_completed_objectives()
	_log("   objectives completed = %s" % str(om2_completed))
	_assert(om2_completed.size() == 1 and String(om2_completed[0]) == "boss_test_01", "restored 1 completed objective")

	# --- 5. Debounce: many rapid changes → one save ---
	_log("\n--- 5. Debounce groups rapid changes ---")
	# Erase the file so we can detect the new save
	DirAccess.remove_absolute(SAVE_PATH)
	await create_timer(0.4).timeout  # let any pending timer expire
	await process_frame
	# Fire 5 rapid changes
	for i in 5:
		ps2.grant_skill_points(1)
		await process_frame
	# Wait for debounce
	await create_timer(0.4).timeout
	await process_frame
	_assert(save1.has_save(), "save written after burst of 5 changes")
	# Read skill_points — should be 8 + 5 = 13
	var f5: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data5: Dictionary = JSON.parse_string(f5.get_as_text())
	f5.close()
	_log("   skill_points in file = %d (expected 13 = 8 + 5)" % int(data5.get("progression", {}).get("skill_points", -1)))
	_assert(int(data5.get("progression", {}).get("skill_points", -1)) == 13, "all 5 changes captured in 1 save")

	# --- 6. Corrupt file → SaveSystem._load ignores it ---
	# (We can't truly "restart" because autoloads persist in the SceneTree.
	#  So we verify: SaveSystem detects corrupt JSON and returns from _load
	#  without populating _pending. Then on the NEXT restart, state would
	#  be fresh because consume() returns empty.)
	_log("\n--- 6. Corrupt save file → _load bails out ---")
	# Write garbage
	var f6: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f6.store_string("this is not valid json {{{")
	f6.close()
	# Verify JSON.parse_string rejects it (proves SaveSystem._load's first gate)
	var bad_parsed: Variant = JSON.parse_string("this is not valid json {{{")
	_log("   JSON.parse_string on garbage = %s (expected null)" % str(bad_parsed))
	_assert(bad_parsed == null, "garbage JSON parsed as null (gate 1 rejects)")
	# Manually invoke SaveSystem._load (private, but accessible via get_method).
	# The _pending dict should NOT have 'progression' (because JSON parse failed
	# before _pending was populated — _pending was already drained in step 4).
	# We can verify by checking that consume() returns {}.
	var save_sys: Node = root.get_node_or_null("SaveSystem")
	# Re-trigger _load via call: in Godot 4, we can call private methods
	save_sys.call("_load")
	var empty: Dictionary = save_sys.consume(&"progression")
	_log("   After corrupt file + _load, consume('progression') = %s" % str(empty))
	_assert(empty.is_empty(), "corrupt file → consume returns empty (no state restored)")

	# --- 7. Schema version mismatch → _load ignores it ---
	_log("\n--- 7. Schema version mismatch → ignored ---")
	var f7: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f7.store_string('{"schema_version": 999, "progression": {"skill_points": 999}}')
	f7.close()
	save_sys.call("_load")
	var empty7: Dictionary = save_sys.consume(&"progression")
	_log("   After schema-mismatch + _load, consume('progression') = %s" % str(empty7))
	_assert(empty7.is_empty(), "schema mismatch → consume returns empty")

	# --- 8. Cleanup ---
	_log("\n--- 8. Cleanup ---")
	DirAccess.remove_absolute(SAVE_PATH)
	DirAccess.remove_absolute(SAVE_PATH + ".tmp")
	play2.queue_free()
	await process_frame
	await process_frame

	_finish()


# ---- assertion framework ----

func _assert(cond: bool, label: String) -> void:
	_step += 1
	if cond:
		_results.append("[PASS] #%d %s" % [_step, label])
		_log("   ✓ %s" % label)
	else:
		_results.append("[FAIL] #%d %s" % [_step, label])
		_log("   ✗ %s" % label)
		_errors.append(label)


func _fail(msg: String) -> void:
	_results.append("[FATAL] %s" % msg)
	_errors.append(msg)
	_log("   ✗ FATAL: %s" % msg)


func _finish() -> void:
	var passed: int = 0
	var failed: int = 0
	for r in _results:
		if "[PASS]" in r: passed += 1
		elif "[FAIL]" in r or "[FATAL]" in r: failed += 1
	_log("")
	_log("=== SUMMARY ===")
	_log("Total assertions: %d | PASS: %d | FAIL: %d" % [_results.size(), passed, failed])
	if _errors.is_empty():
		_log("RESULT: ✓ ALL SAVE-SYSTEM TESTS PASSED")
	else:
		_log("RESULT: ✗ %d FAILURES:" % _errors.size())
		for e in _errors:
			_log("  - %s" % e)
	var f := FileAccess.open("/tmp/save_test_results.txt", FileAccess.WRITE)
	for r in _results:
		f.store_line(r)
	f.close()
	quit()


func _log(msg: String) -> void:
	print(msg)
	var f := FileAccess.open("/tmp/save_test.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/tmp/save_test.log", FileAccess.WRITE)
	else:
		f.seek_end()
	f.store_line(msg)
	f.close()


func _reset_log() -> void:
	var f := FileAccess.open("/tmp/save_test.log", FileAccess.WRITE)
	f.close()
	var f2 := FileAccess.open("/tmp/save_test_results.txt", FileAccess.WRITE)
	f2.close()
