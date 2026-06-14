extends SceneTree

func _find_master_menu() -> Node:
	var n: Node = root.find_child("Menu", true, false)
	if n == null:
		n = _find_master_menu()
	return n

# Full E2E: cycle through all 4 tabs and verify each opens correctly.

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/menu.tscn")


func _initialize() -> void:
	print("=== FULL E2E: cycle all 4 tabs ===")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var prog: Node = root.get_node_or_null("ProgressionState")
	prog.grant_skill_points(10)

	# Open skill book
	var sb := SKILL_BOOK_SCENE.instantiate()
	sb.name = "SkillBook"
	var layer: Node = root.find_child("SkillBookContainer", true, false)
	layer.add_child(sb)
	await process_frame
	sb.open()
	await process_frame
	print("[start] skill book: visible=%s, paused=%s" % [sb.visible, paused])

	# Tab cycle: 0=skills → 1=elementos → 2=atributos → 3=armas → 0
	var tab_names := ["skills", "elementos", "atributos", "armas"]
	for cycle in 2:
		for i in tab_names.size():
			if i == 0 and cycle == 0:
				continue  # skip first, we already opened skills
			# Use next_tab to advance
			sb._on_next_tab()
			await process_frame
			await process_frame
			# Inspect what should be visible
			var sb_vis: bool = sb.visible
			var ea: Node = layer.get_node_or_null("ElementAllocator")
			var aa: Node = layer.get_node_or_null("AttributeAllocator")
			var wa: Node = layer.get_node_or_null("WeaponAllocator")
			var tab_id_actual: String = "?"
			var tab_id_expected: String = tab_names[((cycle * tab_names.size()) + i) % tab_names.size()]
			if sb_vis and not (ea and ea.visible) and not (aa and aa.visible) and not (wa and wa.visible):
				tab_id_actual = "skills"
			elif ea and ea.visible:
				tab_id_actual = "elementos"
			elif aa and aa.visible:
				tab_id_actual = "atributos"
			elif wa and wa.visible:
				tab_id_actual = "armas"
			var ok: String = "PASS" if tab_id_actual == tab_id_expected else "FAIL"
			print("[cycle %d, idx %d] expected=%s actual=%s [%s]" % [cycle, i, tab_id_expected, tab_id_actual, ok])
			print("    sb=%s ea=%s aa=%s wa=%s" % [sb_vis, (ea and ea.visible), (aa and aa.visible), (wa and wa.visible)])

	# Now test closing from elementos with X → should go back to skill book
	sb._on_next_tab()  # 0 → 1 (elementos)
	await process_frame
	await process_frame
	var ea: Node = layer.get_node_or_null("ElementAllocator")
	print("\n[close-test] before X: ea.visible=%s, sb.visible=%s" % [ea.visible, sb.visible])
	var close_btn: Button = ea.get_node("Panel/Margin/VBox/TopBar/CloseButton")
	close_btn.pressed.emit()
	await process_frame
	await process_frame
	print("[close-test] after X: ea.visible=%s, sb.visible=%s, paused=%s" % [ea.visible, sb.visible, paused])

	# Now close skill book
	sb._close()
	await process_frame
	print("\n[final] sb.visible=%s, paused=%s" % [sb.visible, paused])
	quit()
