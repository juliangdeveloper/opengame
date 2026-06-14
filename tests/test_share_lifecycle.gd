extends SceneTree

func _find_master_menu() -> Node:
	var n: Node = root.find_child("Menu", true, false)
	if n == null:
		n = _find_master_menu()
	return n

# Regression test for Share button lifecycle.
# Calls _toggle_skill_book directly to bypass _input (which doesn't get
# synthetic events in headless mode).

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/menu.tscn")


func _initialize() -> void:
	print("=== Share lifecycle (direct toggle) ===")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var player: Node = root.find_child("Player", true, false)
	var failures := 0

	# 1) Open
	player._toggle_skill_book()
	await process_frame
	await process_frame
	var sb: Node = _find_master_menu()
	var ok1: bool = sb.visible and paused
	print("[1] Open: %s" % ("PASS" if ok1 else "FAIL"))
	if not ok1: failures += 1

	# 2) Close via toggle (simulating Share)
	player._toggle_skill_book()
	await process_frame
	await process_frame
	var ok2: bool = not sb.visible and not paused
	print("[2] Close: %s (sb=%s, paused=%s)" % ["PASS" if ok2 else "FAIL", sb.visible, paused])
	if not ok2: failures += 1

	# 3) Reopen
	player._toggle_skill_book()
	await process_frame
	await process_frame
	var ok3: bool = sb.visible and paused
	print("[3] Reopen: %s" % ("PASS" if ok3 else "FAIL"))
	if not ok3: failures += 1

	# 4) Toggle again to close
	player._toggle_skill_book()
	await process_frame
	await process_frame
	var ok4: bool = not sb.visible and not paused
	print("[4] Close again: %s" % ("PASS" if ok4 else "FAIL"))
	if not ok4: failures += 1

	print("\n=== RESULT: %d/%d PASS ===" % [4 - failures, 4])
	quit(1 if failures > 0 else 0)
