extends SceneTree
## Test: pressing Share (PS4 button 4) should TOGGLE the menu open/close.
## We simulate real InputEventJoypadButton events (button_index=4)
## via Viewport.push_input, not direct _toggle_skill_book() calls,
## because the bug is in the input handler, not the toggle logic.

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/menu.tscn")

func _find_master_menu() -> Node:
	var n: Node = root.find_child("Menu", true, false)
	if n == null:
		n = root.find_child("SkillBook", true, false)
	return n

func _find_menu_container() -> Node:
	var n: Node = root.find_child("MenuContainer", true, false)
	if n == null:
		n = root.find_child("MenuLayer", true, false)
	if n == null:
		n = root.find_child("SkillBookContainer", true, false)
	return n


func _initialize() -> void:
	print("=== Share button TOGGLE (real input event) ===\n")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var player: Node = root.find_child("Player", true, false)
	if player == null:
		print("FAIL: Player not found")
		quit(1)
		return
	var failures := 0

	# Wait for menu to be fully initialized
	await process_frame

	# === 1) First Share press → menu opens ===
	_push_share(true)
	await process_frame
	await process_frame
	await process_frame
	var sb1: Node = _find_master_menu()
	if sb1 == null:
		print("  [1] FAIL: Menu not created after first Share press")
		failures += 1
	elif not sb1.visible:
		print("  [1] FAIL: Menu not visible after first Share press")
		failures += 1
	elif not self.paused:
		print("  [1] FAIL: Game not paused after first Share press")
		failures += 1
	else:
		print("  [1] PASS: 1st Share press → menu opens, paused")

	# === 2) Second Share press → menu closes ===
	_push_share(false)  # release first
	await process_frame
	_push_share(true)  # press again
	await process_frame
	await process_frame
	await process_frame
	if sb1 == null or not is_instance_valid(sb1):
		# After close, master may be removed if slave handles reopen
		# Re-find it
		sb1 = _find_master_menu()
	if sb1 == null:
		print("  [2] FAIL: Master menu reference lost after close")
		failures += 1
	elif sb1.visible:
		print("  [2] FAIL: Menu STILL visible after 2nd Share press (should close!)")
		failures += 1
	elif self.paused:
		print("  [2] FAIL: Game STILL paused after 2nd Share press")
		failures += 1
	else:
		print("  [2] PASS: 2nd Share press → menu closes, unpaused")

	# === 3) Third Share press → menu reopens ===
	_push_share(false)
	await process_frame
	_push_share(true)
	await process_frame
	await process_frame
	await process_frame
	if sb1 == null or not is_instance_valid(sb1):
		sb1 = _find_master_menu()
	if sb1 == null:
		print("  [3] FAIL: Menu not found after 3rd Share press")
		failures += 1
	elif not sb1.visible:
		print("  [3] FAIL: Menu not visible after 3rd Share press")
		failures += 1
	else:
		print("  [3] PASS: 3rd Share press → menu reopens")

	# === 4) Fourth Share press → menu closes again ===
	_push_share(false)
	await process_frame
	_push_share(true)
	await process_frame
	await process_frame
	await process_frame
	if sb1 == null or not is_instance_valid(sb1):
		sb1 = _find_master_menu()
	if sb1 == null:
		print("  [4] FAIL: Menu reference lost")
		failures += 1
	elif sb1.visible:
		print("  [4] FAIL: Menu STILL visible after 4th Share press")
		failures += 1
	elif self.paused:
		print("  [4] FAIL: Game STILL paused after 4th Share press")
		failures += 1
	else:
		print("  [4] PASS: 4th Share press → menu closes again")

	var result: String = "ALL PASS" if failures == 0 else "BUG REPRODUCED"
	print("\n=== %s (%d failures) ===" % [result, failures])
	quit(1 if failures > 0 else 0)


## Simulate a Share button press (button 4) with full press/release cycle.
func _push_share(pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = 4  # PS4 Share / Xbox Back
	ev.pressed = pressed
	root.push_input(ev)
	# Also trigger the action
	if pressed:
		Input.action_press("open_skill_book", 1.0)
	else:
		Input.action_release("open_skill_book")
	print("  [share sim] pushed ev.pressed=%s, action_pressed=%s" % [
		pressed,
		Input.is_action_pressed("open_skill_book")
	])
