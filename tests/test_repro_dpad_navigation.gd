extends SceneTree

func _find_master_menu() -> Node:
	var n: Node = root.find_child("Menu", true, false)
	if n == null:
		n = _find_master_menu()
	return n

# Reproduce: user opens skill book with Share, presses D-pad, presses Share again.
# Also tests: does pressing Share while book is open close it?

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/menu.tscn")


func _initialize() -> void:
	print("=== REPRO: D-pad navigation + Share toggle ===")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var player: Node = root.find_child("Player", true, false)
	var ps: Node = root.find_child("ProgressionState", true, false)
	if not (player and ps):
		print("FAIL: player or ps missing")
		quit()
		return

	# 1) Open skill book via toggle (simulating Share)
	player._toggle_skill_book()
	await process_frame
	await process_frame
	var sb: Node = _find_master_menu()
	print("[1] After 1st Share: sb.visible=%s, paused=%s" % [sb != null and sb.visible, paused])

	# 2) Check what has focus
	if sb and sb.skill_list:
		var list: ItemList = sb.skill_list
		print("[2] skill_list: item_count=%d, has_focus=%s" % [list.item_count, list.has_focus()])
		# Print the focused control
		var focused_node: Node = root.gui_get_focus_owner()
		print("    focused control: %s" % (focused_node.name if focused_node else "<none>"))

	# 3) Try to press D-pad up (button 11) via the SKILL BOOK's _input
	#    by calling it directly with a synthetic event
	if sb:
		var ev_up := InputEventJoypadButton.new()
		ev_up.button_index = 11  # D-pad up
		ev_up.pressed = true
		sb._input(ev_up)
		await process_frame
		var focused2: Node = root.gui_get_focus_owner()
		print("[3] After D-pad up: focused control = %s" % (focused2.name if focused2 else "<none>"))

	# 4) Press Share (button 4) again to close
	var ev_share := InputEventJoypadButton.new()
	ev_share.button_index = 4
	ev_share.pressed = true
	# Send it to the player
	player._input(ev_share)
	await process_frame
	await process_frame
	print("[4] After 2nd Share: sb.visible=%s, paused=%s" % [sb != null and sb.visible, paused])
	if sb and sb.visible:
		print("    BUG: Share did NOT close the book!")

	# 5) Check the toggle function behavior directly
	if sb and sb.visible:
		print("[5] Calling _toggle_skill_book() directly...")
		player._toggle_skill_book()
		await process_frame
		print("[5] After direct toggle: sb.visible=%s, paused=%s" % [sb != null and sb.visible, paused])

	quit()
