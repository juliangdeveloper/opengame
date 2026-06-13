extends SceneTree

# Comprehensive test: D-pad navigation, L1/R1 tab change, Share toggle.

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/skill_book.tscn")


func _simulate_joy(btn: int, pressed: bool = true) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _initialize() -> void:
	print("=== COMPREHENSIVE: D-pad + L1/R1 + Share ===")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var player: Node = root.find_child("Player", true, false)
	if not player:
		print("FAIL: player missing")
		quit()
		return

	var failures := 0
	var layer: Node = root.find_child("SkillBookContainer", true, false)

	# === 1) Open via Share (button 4) ===
	_simulate_joy(4, true)
	await process_frame
	await process_frame
	_simulate_joy(4, false)
	await process_frame
	await process_frame
	var sb: Node = root.find_child("SkillBook", true, false)
	var ok1: bool = sb != null and sb.visible and paused
	print("[1] Open via Share: %s (sb.visible=%s, paused=%s)" % ["PASS" if ok1 else "FAIL", sb.visible, paused])
	if not ok1: failures += 1

	# === 2) D-pad up from ItemList → PrevTabButton ===
	_simulate_joy(11, true)
	await process_frame
	await process_frame
	_simulate_joy(11, false)
	await process_frame
	var f2: Control = root.gui_get_focus_owner()
	var ok2: bool = f2 != null and f2.name == "PrevTabButton"
	print("[2] D-pad up → PrevTabButton: %s (got %s)" % ["PASS" if ok2 else "FAIL", f2.name if f2 else "none"])
	if not ok2: failures += 1

	# === 3) L1 (button 9) → tab change (L1 = prev, so from skills idx=0 → idx=3=armas) ===
	_simulate_joy(9, true)
	await process_frame
	await process_frame
	_simulate_joy(9, false)
	await process_frame
	var wa: Node = layer.get_node_or_null("WeaponAllocator")
	var ok3: bool = wa != null and wa.visible
	print("[3] L1 → armas (idx 0→3): %s (wa=%s)" % ["PASS" if ok3 else "FAIL", "visible" if (wa and wa.visible) else "missing/hidden"])
	if not ok3: failures += 1

	# === 4) R1 (button 10) → tab change (R1 = next, from armas idx=3 → idx=0=skills) ===
	_simulate_joy(10, true)
	await process_frame
	await process_frame
	_simulate_joy(10, false)
	await process_frame
	var ok4: bool = sb != null and sb.visible and (wa == null or not wa.visible)
	print("[4] R1 → skills (idx 3→0): %s (sb=%s, wa=%s)" % ["PASS" if ok4 else "FAIL", sb.visible, wa.visible if wa else "n/a"])
	if not ok4: failures += 1

	# === 5) Navigate: D-pad up from ItemList → PrevTabButton, then right → NextTabButton → CloseButton ===
	_simulate_joy(11, true)
	await process_frame
	await process_frame
	_simulate_joy(11, false)
	await process_frame
	_simulate_joy(14, true)
	await process_frame
	await process_frame
	_simulate_joy(14, false)
	await process_frame
	_simulate_joy(14, true)
	await process_frame
	await process_frame
	_simulate_joy(14, false)
	await process_frame
	var f5: Control = root.gui_get_focus_owner()
	var ok5: bool = f5 != null and f5.name == "CloseButton"
	print("[5] Nav ItemList→up→right→right = CloseButton: %s (got %s)" % ["PASS" if ok5 else "FAIL", f5.name if f5 else "none"])
	if not ok5: failures += 1

	# === 6) Press Share (button 4) to close the book ===
	_simulate_joy(4, true)
	await process_frame
	await process_frame
	_simulate_joy(4, false)
	await process_frame
	await process_frame
	# Refresh sb reference (in case it changed)
	sb = root.find_child("SkillBook", true, false)
	var ok6: bool = sb != null and not sb.visible and not paused
	print("[6] Share from master → close: %s (sb=%s, paused=%s)" % ["PASS" if ok6 else "FAIL", sb.visible if sb else "missing", paused])
	if not ok6:
		print("    DEBUG: sb=%s, paused=%s, _skill_book_instance=%s" % [
			sb, paused, player._skill_book_instance
		])
		if sb:
			print("    DEBUG: sb.visible=%s, sb in tree=%s" % [sb.visible, sb.is_inside_tree()])
		failures += 1

	print("\n=== RESULT: %d/%d PASS ===" % [6 - failures, 6])
	quit(1 if failures > 0 else 0)
