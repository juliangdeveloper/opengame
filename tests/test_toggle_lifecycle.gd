extends SceneTree

func _initialize() -> void:
	var play_scene := load("res://scenes/play.tscn") as PackedScene
	var inst := play_scene.instantiate()
	root.add_child(inst)
	for i in 5:
		await process_frame

	var player: Node = root.find_child("Player", true, false)
	print("Initial: paused = %s" % paused)
	# Open
	player._toggle_skill_book()
	for i in 3:
		await process_frame
	var sb: Node = null
	for c in root.find_children("*", "", true, false):
		if c.name == "SkillBook":
			sb = c
			break
	print("After 1st toggle: sb.visible = %s, paused = %s" % [sb.visible, paused])
	# Close
	player._toggle_skill_book()
	for i in 3:
		await process_frame
	print("After 2nd toggle (close): sb.visible = %s, paused = %s" % [sb.visible, paused])
	# Open again
	player._toggle_skill_book()
	for i in 3:
		await process_frame
	print("After 3rd toggle (reopen): sb.visible = %s, paused = %s" % [sb.visible, paused])
	# Close again
	player._toggle_skill_book()
	for i in 3:
		await process_frame
	print("After 4th toggle (close): sb.visible = %s, paused = %s" % [sb.visible, paused])

	# Now: open, navigate to elementos, then toggle to close
	player._toggle_skill_book()
	for i in 3:
		await process_frame
	print("5th toggle (open): sb.visible = %s" % sb.visible)
	# Navigate to elementos
	sb._on_next_tab()
	for i in 3:
		await process_frame
	var ea: Node = null
	for c in root.find_children("*", "", true, false):
		if c.name == "ElementAllocator":
			ea = c
			break
	print("After _on_next_tab: ea = %s, ea.visible = %s" % [ea != null, ea.visible if ea else "n/a"])
	# Now toggle should close everything
	player._toggle_skill_book()
	for i in 3:
		await process_frame
	print("After close-from-subtab: sb.visible = %s, ea = %s, paused = %s" % [
		sb.visible, (ea != null and ea.visible) if ea else "n/a", paused
	])

	quit(0)
