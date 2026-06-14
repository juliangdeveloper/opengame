extends SceneTree
## Stress test: L1 cycle 10 times to see if any tab throws on the wrap.

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
	print("=== L1 cycle stress test ===\n")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var sb: Node = SKILL_BOOK_SCENE.instantiate()
	sb.name = "SkillBook"
	var layer: Node = _find_menu_container()
	layer.add_child(sb)
	await process_frame
	sb.open()
	await process_frame

	# L1 cycle 10 times (more than 2 full loops through 5 tabs)
	for i in 10:
		var ev := InputEventJoypadButton.new()
		ev.button_index = 9  # L1
		ev.pressed = true
		root.push_input(ev)
		await process_frame
		ev.pressed = false
		root.push_input(ev)
		await process_frame
		var tab: int = sb._current_tab
		var tab_id: StringName = sb.TABS[tab]
		print("  L1 #%d → tab #%d = %s" % [i + 1, tab, str(tab_id)])

	# Also test R1 cycle
	print("  --- R1 cycle ---")
	for i in 8:
		var ev := InputEventJoypadButton.new()
		ev.button_index = 10  # R1
		ev.pressed = true
		root.push_input(ev)
		await process_frame
		ev.pressed = false
		root.push_input(ev)
		await process_frame
		var tab: int = sb._current_tab
		var tab_id: StringName = sb.TABS[tab]
		print("  R1 #%d → tab #%d = %s" % [i + 1, tab, str(tab_id)])

	print("\n=== L1 stress test done ===")
	quit()


func _log(msg: String) -> void:
	print(msg)
