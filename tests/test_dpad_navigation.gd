extends SceneTree

# Test: D-pad navigation in skill book.
# Verifies that pressing D-pad up/down/left/right moves focus to the right controls.

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/skill_book.tscn")


func _simulate_joy_button(btn: int) -> void:
	# Parse a synthetic InputEventJoypadButton through Godot's event system.
	var ev_press := InputEventJoypadButton.new()
	ev_press.button_index = btn
	ev_press.pressed = true
	Input.parse_input_event(ev_press)
	var ev_release := InputEventJoypadButton.new()
	ev_release.button_index = btn
	ev_release.pressed = false
	Input.parse_input_event(ev_release)


func _initialize() -> void:
	print("=== TEST: D-pad focus navigation in Skill Book ===")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	# Open skill book
	var sb: Node = SKILL_BOOK_SCENE.instantiate()
	sb.name = "SkillBook"
	var layer: Node = root.find_child("SkillBookContainer", true, false)
	layer.add_child(sb)
	await process_frame
	sb.open()
	await process_frame
	print("[setup] skill book open: visible=%s" % sb.visible)

	# 1) Initial focus should be on ItemList (because focus_skill_list was called)
	var focused: Control = root.gui_get_focus_owner()
	print("[1] Initial focus: %s" % (focused.name if focused else "<none>"))
	if not focused or focused.name != "ItemList":
		print("    FAIL: expected ItemList as initial focus")

	# 2) Press D-pad up (button 11) → ui_focus_prev
	_simulate_joy_button(11)
	await process_frame
	await process_frame
	var focused2: Control = root.gui_get_focus_owner()
	print("[2] After D-pad up (btn 11): %s" % (focused2.name if focused2 else "<none>"))
	if focused2 and focused2.name == "PrevTabButton":
		print("    PASS: D-pad up moved focus to PrevTabButton")
	else:
		print("    FAIL: D-pad up did not move focus correctly (got %s)" % (focused2.name if focused2 else "none"))

	# 3) Press D-pad right (button 14) from PrevTabButton → NextTabButton
	_simulate_joy_button(14)
	await process_frame
	await process_frame
	var focused3: Control = root.gui_get_focus_owner()
	print("[3] After D-pad right (btn 14): %s" % (focused3.name if focused3 else "<none>"))
	if focused3 and focused3.name == "NextTabButton":
		print("    PASS: D-pad right moved focus to NextTabButton")
	else:
		print("    FAIL: D-pad right did not move focus correctly (got %s)" % (focused3.name if focused3 else "none"))

	# 4) Press D-pad right again → CloseButton
	_simulate_joy_button(14)
	await process_frame
	await process_frame
	var focused4: Control = root.gui_get_focus_owner()
	print("[4] After D-pad right x2: %s" % (focused4.name if focused4 else "<none>"))
	if focused4 and focused4.name == "CloseButton":
		print("    PASS: D-pad right moved focus to CloseButton")
	else:
		print("    FAIL: D-pad right did not move focus correctly (got %s)" % (focused4.name if focused4 else "none"))

	# 5) Press D-pad down (button 12) → BindingButton
	_simulate_joy_button(12)
	await process_frame
	await process_frame
	var focused5: Control = root.gui_get_focus_owner()
	print("[5] After D-pad down (btn 12): %s" % (focused5.name if focused5 else "<none>"))
	if focused5 and focused5.name == "BindingButton":
		print("    PASS: D-pad down moved focus to BindingButton")
	else:
		print("    FAIL: D-pad down did not move focus correctly (got %s)" % (focused5.name if focused5 else "none"))

	# 6) Press D-pad left (button 13) → ItemList
	_simulate_joy_button(13)
	await process_frame
	await process_frame
	var focused6: Control = root.gui_get_focus_owner()
	print("[6] After D-pad left (btn 13): %s" % (focused6.name if focused6 else "<none>"))
	if focused6 and focused6.name == "ItemList":
		print("    PASS: D-pad left moved focus to ItemList")
	else:
		print("    FAIL: D-pad left did not move focus correctly (got %s)" % (focused6.name if focused6 else "none"))

	print("\n=== TEST COMPLETE ===")
	quit()
